extends TestCase
## Noclip review fixes (R6) on the real player.tscn: Coherence cannot fall in a drop or
## the Landing; the fall is clamped and the falling body is on no layer, so no exit takes
## it; a charge ends silently into Landing or Hidden; the open door's header and jambs are
## SOLID; TOO FAR before SOLID; a fallback pass refunds and records nothing; a blocked
## press speaks once; the pass eases sine in-out; one wall plane is one target across
## seams; a dissolve mid-pass snaps free; the far floor height decides the landing step;
## a level's data makes the floor solid; the debug drop arrival notifies a bound HUD.

const PHYSICS_HZ := 60.0
const EXIT_SCENE := "res://scenes/exits/elevator.tscn"
const DOOR_SCENE := "res://scenes/props/shared/door.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const LEVEL_SCENE := "res://scenes/level.tscn"

var _w: Node3D
var _p: Player
var _nt: NoclipTargeting
var _reports: Array = []
var _commits: Array = []


func before_each() -> void:
	PlayerFixture.release_all()
	_w = NoclipFixture.world(self)
	_p = PlayerFixture.spawn_player(_w, Vector3(0, 0.02, 0))
	_nt = _p.noclip_targeting as NoclipTargeting
	_reports.clear()
	_commits.clear()
	_p.noclip_state.connect(func(c: float, t: StringName, v: bool, r: StringName) -> void: _reports.append([c, t, v, r]))
	_p.noclip_committed.connect(func(t: StringName, a: Vector3, b: Vector3) -> void: _commits.append([t, a, b]))
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	if GameState.is_run_active():
		GameState.end_run(&"test")
	var guard := 0
	while get_tree().paused and guard < 200:
		guard += 1
		await get_tree().process_frame
	_w.free()
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_invalid(false)


func _run_frames(n: int) -> void:
	var done := 0
	var guard := 0
	while done < n and guard < n + 400:
		guard += 1
		await get_tree().physics_frame
		if not get_tree().paused:
			done += 1


func _frames_for(seconds: float) -> int:
	return int(ceil(seconds * PHYSICS_HZ))


func _until(cond: Callable, max_frames: int = 400) -> bool:
	var guard := 0
	while not bool(cond.call()) and guard < max_frames:
		guard += 1
		await get_tree().physics_frame
	return bool(cond.call())


func _charge_partly(frames: int = 15) -> void:
	Input.action_press(&"noclip")
	await _run_frames(frames)


func _drop() -> void:
	_p.floor_drop_committed.connect(func() -> void: pass)  # a run flow owns the arrival
	_p.rig.add_pitch(deg_to_rad(-60.0))
	Input.action_press(&"noclip")
	await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.DROPPING), 300)


func _exit() -> Exit:
	var e := (load(EXIT_SCENE) as PackedScene).instantiate() as Exit
	_w.add_child(e)
	e.global_position = Vector3(6, 0, 6)
	return e


# --- 1, 2: drop -------------------------------------------------------------------------------

func test_static_drain_cannot_lower_coherence_during_a_drop_or_the_landing() -> void:
	await _drop()
	assert_true(_p.state_machine.is_in(PlayerStateMachine.DROPPING))
	var after_cost := _p.coherence
	assert_approx(after_cost, 100.0 - Tuning.NOCLIP_FLOOR_COST, 0.0001, "the drop's own cost landed")
	for i in 30:
		_p.apply_coherence(-Tuning.STATIC_DRAIN_PER_S / PHYSICS_HZ, &"static")
		await get_tree().physics_frame
	assert_approx(_p.coherence, after_cost, 0.0001, "Static drain ignored while dropping")
	_p.state_machine.transition_to(PlayerStateMachine.LANDING)
	_p.apply_coherence(-35.0, &"still")
	assert_approx(_p.coherence, after_cost, 0.0001, "no loss in the Landing")
	_p.apply_coherence(Tuning.COHERENCE_GAIN_PROPER_EXIT, &"landing")
	assert_approx(_p.coherence, after_cost + Tuning.COHERENCE_GAIN_PROPER_EXIT, 0.0001, "gains still land")


func test_fall_is_clamped_and_the_falling_body_is_on_no_layer() -> void:
	var floor_y := _p.global_position.y
	await _drop()
	assert_eq(_p.collision_layer, 0, "collision_layer 0 while dropping")
	await _run_frames(_frames_for(Tuning.NOCLIP_FLOOR_FALL_TIME * 2.0))
	assert_true(_p.state_machine.is_in(PlayerStateMachine.DROPPING), "the hooked run flow owns the arrival")
	assert_gt(_p.global_position.y, floor_y - Tuning.NOCLIP_FALL_CLAMP_BELOW - 0.001, "clamped about 2 m below")
	assert_lt(_p.global_position.y, floor_y - Tuning.NOCLIP_FALL_CLAMP_BELOW + 0.05, "it did fall that far")
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)
	assert_eq(_p.collision_layer, PlayerLayers.PLAYER_MASK, "layer restored when the drop ends")


func test_a_drop_never_counts_as_a_proper_exit() -> void:
	var exit := _exit()
	await await_physics_frames(2)
	var entered: Array = []
	exit.entering.connect(func(who: Node3D) -> void: entered.append(who))
	assert_true(exit.is_open())
	await _drop()
	assert_false(exit.try_enter(_p), "the exit refuses a dropping player")
	# Fall straight through the trigger volume: nothing takes the body (layer 0).
	_p.global_position = exit.to_global(Vector3(0.0, 0.1, -0.45))
	await _run_frames(10)
	assert_eq(entered.size(), 0, "no proper exit during a drop")
	assert_false(exit.is_entering)


# --- 3: charge ends silently into Landing and Hidden -------------------------------------------

func test_walking_into_an_open_exit_while_charging() -> void:
	NoclipFixture.wall(_w, &"WALL")
	var exit := _exit()
	await await_physics_frames(2)
	# As the run flow does on `entering`: the player goes straight to Landing.
	exit.entering.connect(func(_who: Node3D) -> void:
		assert_true(_p.state_machine.transition_to(PlayerStateMachine.LANDING), "NoclipCharge -> Landing"))
	await _charge_partly()
	assert_true(_nt.is_charging())
	_p.sounds.played.clear()
	assert_true(exit.try_enter(_p), "a charging player walks in")
	assert_true(_p.state_machine.is_in(PlayerStateMachine.LANDING))
	assert_false(_nt.is_charging(), "the charge ended")
	assert_false(_p.sounds.played.has(&"noclip_cancel"), "silently")
	assert_false(_p.sounds.is_looping(NoclipTargeting.LOOP_CHARGE))
	assert_approx(_p.coherence, 100.0, 0.0001, "no cost")
	await _run_frames(40)
	assert_approx(_p.coherence, 100.0, 0.0001, "holding on in the Landing commits nothing")


func test_hiding_while_charging() -> void:
	NoclipFixture.wall(_w, &"WALL")
	var locker := (load(PlayerFixture.LOCKER_SCENE) as PackedScene).instantiate() as HideSpot
	_w.add_child(locker)
	locker.global_position = Vector3(3, 0, 1)
	await await_physics_frames(2)
	await _charge_partly()
	assert_true(_nt.is_charging())
	assert_true(_p.can_hide(), "a hide spot takes a charging player")
	_p.sounds.played.clear()
	_p.enter_hide(locker)
	assert_true(_p.is_hidden())
	assert_false(_nt.is_charging())
	assert_false(_p.sounds.played.has(&"noclip_cancel"), "the charge ends silently")
	await get_tree().create_timer(Tuning.FEEDBACK_NOCLIP_CANCEL_FOV_MS / 1000.0 + 0.1).timeout
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_NOCLIP), 0.0, 0.01, "pull-in released over 150 ms")
	_p.leave_hide()
	await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.1).timeout
	await _run_frames(5)
	assert_false(_nt.is_charging(), "still holding after leaving: a new charge needs a fresh press")


# --- 6, 7: door frame, reason order -------------------------------------------------------------

func _door(open: bool) -> Door:
	var d := (load(DOOR_SCENE) as PackedScene).instantiate() as Door
	d.start_open = open
	_w.add_child(d)
	d.global_position = Vector3(0, 0, NoclipFixture.WALL_Z)
	d.set_edge_meta({&"cell": Vector2i(0, 0), &"dir": LevelGrid.N, &"wall_type": LevelGrid.DOOR,
		&"wall_kind": &"DOOR", &"thickness": 0.2, &"other_cell": Vector2i(0, -1),
		&"walkable": true, &"other_walkable": true})
	return d


## The builder's header box above a DOOR edge (BuildCollision: no `closed` state).
func _header() -> StaticBody3D:
	var h := NoclipFixture.wall(_w, &"DOOR", Vector3(0, 2.55, NoclipFixture.WALL_Z), Vector3(2.2, 0.9, 0.2))
	var table: Dictionary = h.get_meta(&"shape_meta")
	for k in table:
		(table[k] as Dictionary).erase(&"closed")
	return h


func test_open_door_header_and_jambs_are_solid() -> void:
	var door := _door(true)
	_header()
	await await_physics_frames(3)
	var jamb_eye := NoclipFixture.EYE + Vector3(0.7, 0, 0)
	var a := NoclipFixture.aim(_w, NoclipFixture.FORWARD, 100.0, false, jamb_eye)
	assert_eq(a[&"target"], NoclipQuery.TARGET_WALL)
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID, "an open door's jamb")
	var up := Vector3(0, 0.85, -0.9).normalized()
	assert_eq(NoclipFixture.aim(_w, up)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "the header over an open door")
	door.close()
	await get_tree().create_timer(Tuning.DOOR_SWING_TIME + 0.1).timeout
	await await_physics_frames(2)
	var closed := NoclipFixture.aim(_w, NoclipFixture.FORWARD, 100.0, false, jamb_eye)
	assert_true(closed[&"valid"], "a closed door's jamb is part of a passable door (reason %s)" % closed[&"reason"])
	assert_true(NoclipFixture.aim(_w)[&"valid"], "the closed leaf")
	assert_eq(NoclipFixture.aim(_w, up)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "the header is always SOLID")


func test_too_far_before_solid_except_ceilings() -> void:
	NoclipFixture.wall(_w, &"SOLID", Vector3(0, 1.35, -4.0))
	await await_physics_frames(2)
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_TOO_FAR, "a far SOLID wall reads TOO FAR")
	PlayerFixture.box(_w, Vector3(20, 0.2, 20), Vector3(0, 6.0, 0)).set_meta(&"wall_kind", &"WALL")
	await await_physics_frames(2)
	var a := NoclipFixture.aim(_w, Vector3(0, 1, -0.3).normalized())
	assert_gt(a[&"distance"], Tuning.NOCLIP_RANGE)
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID, "a ceiling is SOLID at any distance")


# --- 5: fallback refunds, records nothing; relocation ------------------------------------------

func test_fallback_pass_refunds_and_records_nothing() -> void:
	NoclipFixture.wall(_w, &"WALL")
	await await_physics_frames(2)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 11)
	var spent := GameState.run.coherence_spent
	var start := _p.global_position
	Input.action_press(&"noclip")
	assert_true(await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS)))
	assert_approx(_p.coherence, 100.0 - Tuning.NOCLIP_WALL_COST, 0.0001, "the cost landed at commit")
	PlayerFixture.box(_w, Vector3(1.5, 2.5, 4.0), _nt.motion.to + Vector3(0, 1.25, -1.0))
	_p.sounds.played.clear()
	var gain_age := CoherenceRenderer.pulse_age(&"coherence_gain")
	await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.IDLE))
	assert_approx(_p.global_position.distance_to(start), 0.0, 0.05, "back at the start")
	assert_approx(_p.coherence, 100.0, 0.0001, "the cost is refunded")
	assert_false(_p.sounds.played.has(&"coherence_gain"), "a refund is not a gain (no chord)")
	assert_true(CoherenceRenderer.pulse_age(&"coherence_gain") >= gain_age, "no gain pulse")
	assert_eq(GameState.run.walls_passed, 0, "no wall pass recorded")
	assert_approx(GameState.run.coherence_spent, spent, 0.0001, "no spend recorded")
	assert_eq(_commits.size(), 0, "noclip_committed never fired")


func test_blocked_spot_is_found_again_in_the_landing_cell() -> void:
	NoclipFixture.wall(_w, &"WALL")
	await await_physics_frames(2)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 12)
	Input.action_press(&"noclip")
	assert_true(await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS)))
	var planned := _nt.motion.to
	PlayerFixture.box(_w, Vector3(1.5, 2.5, 1.5), planned + Vector3(0, 1.25, 0))
	await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.IDLE))
	assert_lt(_p.global_position.z, planned.z - 0.5, "further along the aim, beyond the obstacle")
	assert_eq(NoclipQuery.cell_at(_p.global_position), Vector2i(0, -1), "still in the far cell")
	assert_true(NoclipQuery.is_free(_p.get_world_3d().direct_space_state, _p.global_position,
			_p.collision.shape, [_p.get_rid()]))
	assert_eq(GameState.run.walls_passed, 1)
	assert_eq(_commits.size(), 1)
	assert_approx((_commits[0][2] as Vector3).distance_to(_p.global_position), 0.0, 0.01, "`to` is where it landed")


# --- 8: blocked press -------------------------------------------------------------------------

func test_press_during_cooldown_tones_once_and_dims_the_arc() -> void:
	NoclipFixture.wall(_w, &"WALL")
	NoclipFixture.wall(_w, &"WALL", Vector3(0, 1.35, -3.0))
	await await_physics_frames(2)
	Input.action_press(&"noclip")
	await _until(func() -> bool: return _commits.size() == 1)
	assert_eq(_p.sounds.played.count(&"noclip_fail"), 0, "holding through the pass is quiet")
	Input.action_release(&"noclip")
	await _run_frames(2)
	assert_gt(_nt.cooldown, 0.0)
	_p.sounds.played.clear()
	Input.action_press(&"noclip")
	await _run_frames(5)
	assert_false(_nt.is_charging(), "no charge during the cooldown")
	assert_eq(_p.sounds.played.count(&"noclip_fail"), 1, "a dull tone once")
	assert_eq(_reports[-1], [Tuning.NOCLIP_INVALID_PREVIEW, &"wall", false, &""], "dimmed arc, no reason word")
	assert_true(CoherenceRenderer.noclip_invalid, "dashed preview")
	Input.action_release(&"noclip")
	await _run_frames(2)
	assert_eq(_reports[-1], [0.0, &"", true, &""], "arc shutters out on release")


# --- 9, 10, 11 ---------------------------------------------------------------------------------

func test_pass_eases_sine_in_out() -> void:
	assert_approx(NoclipMotion.ease_pass(0.0), 0.0, 0.0001)
	assert_approx(NoclipMotion.ease_pass(0.5), 0.5, 0.0001, "the crossing lands mid-pass")
	assert_approx(NoclipMotion.ease_pass(1.0), 1.0, 0.0001)
	assert_lt(NoclipMotion.ease_pass(0.1), 0.05, "slow out of the start")


func test_strafing_along_one_wall_keeps_the_charge_across_a_seam() -> void:
	# Two segments of one wall plane, each its own collider, meeting at x = 0.
	NoclipFixture.wall(_w, &"WALL", Vector3(-0.5, 1.35, NoclipFixture.WALL_Z), Vector3(1.0, 2.7, 0.2))
	NoclipFixture.wall(_w, &"WALL", Vector3(0.5, 1.35, NoclipFixture.WALL_Z), Vector3(1.0, 2.7, 0.2))
	_p.global_position = Vector3(-0.3, 0.02, 0)
	await await_physics_frames(3)
	Input.action_press(&"noclip")
	await _run_frames(5)
	assert_true(_nt.is_charging())
	for i in 6:
		_p.global_position.x += 0.1
		await get_tree().physics_frame
	assert_gt(_p.global_position.x, 0.1, "the aim crossed the seam")
	assert_true(_nt.is_charging() or _commits.size() > 0 or _p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS),
			"the charge kept across the seam")
	await _until(func() -> bool: return _commits.size() == 1)
	assert_approx(_p.coherence, 100.0 - Tuning.NOCLIP_WALL_COST, 0.0001)


func test_a_different_wall_kind_on_the_same_plane_is_a_different_target() -> void:
	var a := {&"target": &"wall", &"wall_kind": &"WALL", &"normal": Vector3(0, 0, 1), &"plane": -0.9}
	var b := a.duplicate()
	b[&"wall_kind"] = &"PARTITION"
	assert_false(NoclipQuery.same_target(a, b))
	var c := a.duplicate()
	c[&"plane"] = -0.9 + Tuning.NOCLIP_PLANE_TOLERANCE * 0.5
	assert_true(NoclipQuery.same_target(a, c), "within the plane tolerance")
	c[&"plane"] = -1.1
	assert_false(NoclipQuery.same_target(a, c), "the far face of the wall is another plane")


func test_dissolving_mid_pass_snaps_out_of_the_wall() -> void:
	NoclipFixture.wall(_w, &"WALL")
	await await_physics_frames(2)
	var start := _p.global_position
	_p.apply_coherence(-80.0, &"static")
	Input.action_press(&"noclip")
	assert_true(await _until(func() -> bool: return _nt.pass_time() >= NoclipMotion.PASS_TIME * 0.4))
	var end := _nt.motion.to
	_p.apply_coherence(-20.0, &"static")
	assert_true(_p.is_dissolving())
	var at := _p.global_position
	assert_true(at.distance_to(end) < 0.01 or at.distance_to(start) < 0.01, "snapped to the end or the start")
	assert_true(NoclipQuery.is_free(_p.get_world_3d().direct_space_state, at, _p.collision.shape, [_p.get_rid()]))
	assert_ne(_p.collision_mask & PlayerLayers.WORLD_MASK, 0, "collision back on")


# --- 14, 15, 17 ---------------------------------------------------------------------------------

func test_landing_uses_the_far_cell_floor_height() -> void:
	var wall := NoclipFixture.wall(_w, &"WALL")
	# The far cell is a raised floor 0.5 m up: more than a step from the body's floor.
	NoclipFixture.floor_slab(_w, Vector3(4, 0.5, 3.0), Vector3(0, 0.25, -2.6))
	await await_physics_frames(2)
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE, "without the far floor height")
	var table: Dictionary = wall.get_meta(&"shape_meta")
	for k in table:
		(table[k] as Dictionary)[&"other_floor_y"] = 0.5
	var a := NoclipFixture.aim(_w)
	assert_true(a[&"valid"], "reason %s" % a[&"reason"])
	assert_approx((a[&"landing"] as Vector3).y, 0.5 + Tuning.NOCLIP_LANDING_LIFT, 0.01, "on the far cell's floor")


func test_a_level_marked_final_has_a_solid_floor_without_a_run() -> void:
	assert_false(GameState.is_run_active())
	assert_false(_nt.is_floor_solid())
	var level := (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	level.data = LevelData.new()
	level.data.floor_solid = true
	_w.add_child(level)
	assert_true(_nt.is_floor_solid(), "direct launch --depth 6: the level data says SOLID")
	level.data.floor_solid = false
	assert_false(_nt.is_floor_solid())
	level.free()


func test_debug_drop_arrival_notifies_a_bound_hud() -> void:
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.bind_player(_p)
	_p.rig.add_pitch(deg_to_rad(-60.0))
	Input.action_press(&"noclip")
	await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.DROPPING), 300)
	Input.action_release(&"noclip")
	await _until(func() -> bool: return _p.state_machine.is_in(PlayerStateMachine.IDLE), 200)
	assert_contains(hud.notifications.lines(), Strings.MSG_DROPPED)
	hud.free()
