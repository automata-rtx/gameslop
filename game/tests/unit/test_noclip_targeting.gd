extends TestCase
## 06 §8 noclip on the real player.tscn with simulated input: charge timings and costs,
## the cancel paths (release, look-away, contact, stun), the commit's channels (hitstop,
## renderer, sound, noise, FOV, HUD report, counters), the 250 ms pass that never leaves
## the body inside geometry, and the floor drop hook.

const PHYSICS_HZ := 60.0

var _w: Node3D
var _p: Player
var _nt: NoclipTargeting
var _reports: Array = []
var _noises: Array = []
var _drops: int = 0
var _commits: Array = []


func before_each() -> void:
	PlayerFixture.release_all()
	_w = NoclipFixture.world(self)
	_p = PlayerFixture.spawn_player(_w, Vector3(0, 0.02, 0))
	_nt = _p.noclip_targeting as NoclipTargeting
	_reports.clear()
	_noises.clear()
	_commits.clear()
	_drops = 0
	_p.noclip_state.connect(func(c: float, t: StringName, v: bool, r: StringName) -> void: _reports.append([c, t, v, r]))
	_p.noclip_committed.connect(func(t: StringName, a: Vector3, b: Vector3) -> void: _commits.append([t, a, b]))
	EventBus.noise_emitted.connect(_on_noise)
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	EventBus.noise_emitted.disconnect(_on_noise)
	await _await_unpaused()
	_w.free()
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_invalid(false)


func _on_noise(pos: Vector3, radius: float, kind: StringName) -> void:
	_noises.append([pos, radius, kind])


func _await_unpaused() -> void:
	var guard := 0
	while get_tree().paused and guard < 200:
		guard += 1
		await get_tree().process_frame


## Physics frames the player (not paused) actually ran.
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


func _hold() -> void:
	Input.action_press(&"noclip")


func _release() -> void:
	Input.action_release(&"noclip")


func _wall(kind: StringName = &"WALL") -> StaticBody3D:
	var b := NoclipFixture.wall(_w, kind)
	return b


func _overlaps_world(p: Player) -> bool:
	return not NoclipQuery.is_free(p.get_world_3d().direct_space_state, p.global_position,
			p.collision.shape, [p.get_rid()])


func test_wall_charge_takes_0_6_s_and_costs_10() -> void:
	_wall()
	await await_physics_frames(2)
	_hold()
	await _run_frames(_frames_for(Tuning.NOCLIP_WALL_TIME) - 4)
	assert_true(_p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE), "still charging before 0.6 s")
	assert_approx(_p.coherence, 100.0, 0.0001, "no cost while charging")
	assert_gt(_nt.charge_fraction(), 0.8)
	assert_lt(_p.rig.fov_hold_of(CameraRig.HOLD_NOCLIP), -1.0, "FOV pulls in during the charge")
	assert_gt(CoherenceRenderer.noclip_charge, 0.5, "renderer preview fed")
	assert_approx(CoherenceRenderer.noclip_target.z, -0.9, 0.05, "anchored at the aimed surface")
	assert_true(_p.sounds.is_looping(NoclipTargeting.LOOP_CHARGE), "rising sine cluster")
	assert_approx(_p.flashlight.dim, Tuning.FEEDBACK_NOCLIP_FLASHLIGHT_DIM, 0.0001)
	var last: Array = _reports[-1]
	assert_eq(last[1], &"wall")
	assert_true(last[2])
	await _run_frames(6)
	assert_approx(_p.coherence, 100.0 - Tuning.NOCLIP_WALL_COST, 0.0001, "committed by 0.6 s")
	assert_contains(_p.sounds.played, &"noclip_commit")
	assert_eq(_commits.size(), 0, "noclip_committed waits for the pass to end beyond the wall")
	var tear := _noises.filter(func(n: Array) -> bool: return n[2] == Tuning.NOISE_KIND_TEAR)
	assert_eq(tear.size(), 1, "one tear noise")
	assert_approx(tear[0][1], Tuning.NOISE_NOCLIP_COMMIT_RADIUS, 0.0001, "20 m")


func test_soft_wall_charges_in_0_35_s_for_5() -> void:
	_wall(&"SOFT")
	await await_physics_frames(2)
	_hold()
	await _run_frames(_frames_for(Tuning.NOCLIP_SOFT_TIME) - 3)
	assert_approx(_p.coherence, 100.0, 0.0001)
	await _run_frames(5)
	assert_approx(_p.coherence, 100.0 - Tuning.NOCLIP_SOFT_COST, 0.0001)
	await _run_frames(_frames_for(Tuning.NOCLIP_PASS_TIME_MS / 1000.0) + 4)
	assert_contains(_p.sounds.played, &"noclip_pass_soft")


func test_commit_hitstops_pulses_and_passes_through_without_overlap() -> void:
	_wall()
	await await_physics_frames(2)
	_hold()
	var hit_hitstop := false
	var saw_pass := false
	var mask_off := false
	for i in 120:
		await get_tree().physics_frame
		hit_hitstop = hit_hitstop or Clock.is_hitstopping()
		if _p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS):
			saw_pass = true
			mask_off = mask_off or (_p.collision_mask & PlayerLayers.WORLD_MASK) == 0
		if saw_pass and _p.state_machine.is_in(PlayerStateMachine.IDLE):
			break
	assert_true(hit_hitstop, "80 ms hitstop")
	assert_true(saw_pass, "NoclipPass entered")
	assert_true(mask_off, "world collision off during the pass")
	assert_lt(CoherenceRenderer.pulse_age(&"noclip_commit"), 2.0, "commit pulse fired")
	assert_true(_p.state_machine.is_in(PlayerStateMachine.IDLE))
	assert_lt(_p.global_position.z, -1.1 - Tuning.PLAYER_CAPSULE_RADIUS + 0.001, "through the wall")
	assert_false(_overlaps_world(_p), "the pass never leaves the player inside geometry")
	assert_ne(_p.collision_mask & PlayerLayers.WORLD_MASK, 0, "collision restored")
	assert_approx(_nt.cooldown, Tuning.NOCLIP_COOLDOWN, 0.1, "1 s cooldown")
	assert_contains(_p.sounds.played, &"noclip_pass_wall")
	assert_eq(_commits[0][0], &"wall")


func test_blocked_landing_falls_back_to_the_start() -> void:
	_wall()
	await await_physics_frames(2)
	var start := _p.global_position
	_hold()
	while not _p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS):
		await get_tree().physics_frame
	# Something fills the whole far side during the hitstop: the pass must not end inside
	# it, and with no spot left in the landing cell it falls back to the start.
	var to: Vector3 = _nt.motion.to
	PlayerFixture.box(_w, Vector3(1.5, 2.5, 4.0), to + Vector3(0, 1.25, -1.0))
	await _run_frames(_frames_for(Tuning.NOCLIP_PASS_TIME_MS / 1000.0) + 3)
	assert_true(_p.state_machine.is_in(PlayerStateMachine.IDLE))
	assert_false(_overlaps_world(_p), "not inside geometry")
	assert_approx(_p.global_position.distance_to(start), 0.0, 0.05, "back where it stood")


func test_release_cancels_at_no_cost() -> void:
	_wall()
	await await_physics_frames(2)
	_hold()
	await _run_frames(15)
	assert_true(_nt.is_charging())
	_release()
	await _run_frames(2)
	assert_false(_nt.is_charging())
	assert_false(_p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE))
	assert_approx(_p.coherence, 100.0)
	assert_contains(_p.sounds.played, &"noclip_cancel")
	assert_false(_p.sounds.is_looping(NoclipTargeting.LOOP_CHARGE))
	assert_eq(_reports[-1], [0.0, &"", true, &""], "arc shutters out")
	await _run_frames(10)
	assert_approx(CoherenceRenderer.noclip_charge, 0.0, 0.0001, "preview collapsed")
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_NOCLIP), 0.0, 0.01, "FOV returned")


func test_looking_away_cancels() -> void:
	_wall()
	await await_physics_frames(2)
	_hold()
	await _run_frames(15)
	_p.rotate_y(PI * 0.5)
	await _run_frames(2)
	assert_false(_nt.is_charging())
	assert_approx(_p.coherence, 100.0)


func test_contact_cancels_and_stun_blocks() -> void:
	_wall()
	await await_physics_frames(2)
	_hold()
	await _run_frames(15)
	var e := Node3D.new()
	e.set(&"error_id", &"still")
	_w.add_child(e)
	e.global_position = Vector3(0, 0, 2)
	assert_true(_p.contact(e, 35.0))
	assert_false(_nt.is_charging(), "contact cancels the charge")
	await _await_unpaused()
	await _run_frames(30)
	assert_false(_nt.is_charging(), "no noclip while stunned")
	assert_approx(_p.coherence, 65.0, 0.0001, "only the contact cost")


func test_invalid_reports_reason_dashes_and_tones_once() -> void:
	_wall(&"SOLID")
	await await_physics_frames(2)
	_hold()
	await _run_frames(20)
	assert_false(_nt.is_charging())
	assert_eq(_reports[-1], [0.0, &"wall", false, Tuning.NOCLIP_REASON_SOLID])
	assert_true(CoherenceRenderer.noclip_invalid, "dashed preview")
	assert_approx(CoherenceRenderer.noclip_charge, Tuning.NOCLIP_INVALID_PREVIEW, 0.0001)
	assert_eq(_p.sounds.played.count(&"noclip_fail"), 1, "dull tone once")
	_release()
	await _run_frames(2)
	assert_false(CoherenceRenderer.noclip_invalid)
	assert_eq(_reports[-1], [0.0, &"", true, &""])


func test_too_thin_never_spends() -> void:
	_wall()
	_p.apply_coherence(-90.0, &"static")
	await await_physics_frames(2)
	_hold()
	await _run_frames(60)
	assert_approx(_p.coherence, 10.0, 0.0001)
	assert_eq(_reports[-1][3], Tuning.NOCLIP_REASON_TOO_THIN)


func test_new_charge_needs_a_fresh_press_after_commit() -> void:
	_wall()
	NoclipFixture.wall(_w, &"WALL", Vector3(0, 1.35, -3.0))
	await await_physics_frames(2)
	_hold()
	await _run_frames(_frames_for(0.6 + 0.25 + Tuning.NOCLIP_COOLDOWN) + 30)
	assert_approx(_p.coherence, 90.0, 0.0001, "holding through does not chain a second pass")
	_release()
	await _run_frames(2)
	_hold()
	await _run_frames(_frames_for(0.6) + 3)
	assert_approx(_p.coherence, 80.0, 0.0001, "a new press passes the second wall")


func test_floor_drop_emits_hook_and_debug_respawns() -> void:
	await await_physics_frames(2)
	_p.rig.add_pitch(deg_to_rad(-60.0))
	var home := _p.global_position
	_hold()
	await _run_frames(_frames_for(Tuning.NOCLIP_FLOOR_TIME) - 5)
	assert_true(_nt.is_charging())
	assert_approx(_p.coherence, 100.0)
	await _run_frames(8)
	assert_true(_p.state_machine.is_in(PlayerStateMachine.DROPPING))
	assert_approx(_p.coherence, 100.0 - Tuning.NOCLIP_FLOOR_COST, 0.0001)
	assert_contains(_p.sounds.played, &"noclip_fall")
	assert_eq(_commits[-1][0], &"floor")
	assert_false(_p.contact(null, 35.0), "no contact during the drop")
	await _run_frames(_frames_for(Tuning.NOCLIP_FLOOR_FALL_TIME) + 4)
	assert_true(_p.state_machine.is_in(PlayerStateMachine.IDLE), "debug arrival without a run flow")
	assert_approx(_p.global_position.distance_to(home), 0.0, 0.05)
	assert_contains(_p.sounds.played, &"drop_arrival")
	assert_ne(_p.collision_mask & PlayerLayers.WORLD_MASK, 0)


func test_floor_drop_hook_hands_over_to_the_run_flow() -> void:
	await await_physics_frames(2)
	_p.floor_drop_committed.connect(func() -> void: _drops += 1)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 7)
	var spent_before := GameState.run.coherence_spent
	_p.rig.add_pitch(deg_to_rad(-60.0))
	_hold()
	await _run_frames(_frames_for(Tuning.NOCLIP_FLOOR_TIME) + 3)
	assert_eq(_drops, 1, "floor_drop_committed once")
	assert_eq(GameState.run.drops_total, 1)
	assert_approx(GameState.run.coherence_spent - spent_before, Tuning.NOCLIP_FLOOR_COST, 0.0001)
	await _run_frames(_frames_for(Tuning.NOCLIP_FLOOR_FALL_TIME) + 10)
	assert_true(_p.state_machine.is_in(PlayerStateMachine.DROPPING), "the run flow owns the arrival")
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)
	assert_ne(_p.collision_mask & PlayerLayers.WORLD_MASK, 0, "collision back when the run flow ends the drop")
	GameState.end_run(&"test")


func test_wall_pass_counts_in_the_run() -> void:
	_wall()
	await await_physics_frames(2)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 8)
	_hold()
	await _run_frames(_frames_for(0.6) + 3)
	assert_eq(GameState.run.walls_passed, 0, "counted only when the pass ends beyond the wall")
	await _run_frames(_frames_for(Tuning.NOCLIP_PASS_TIME_MS / 1000.0) + 3)
	assert_eq(GameState.run.walls_passed, 1)
	assert_approx(GameState.run.coherence_spent, Tuning.NOCLIP_WALL_COST, 0.0001)
	GameState.end_run(&"test")


func test_final_depth_floor_is_solid() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 9)
	GameState.run.depth = Tuning.RUN_FINAL_DEPTH
	assert_true(_nt.is_floor_solid())
	GameState.run.mode = Tuning.MODE_ENDLESS
	assert_false(_nt.is_floor_solid(), "never solid in Endless")
	GameState.end_run(&"test")
