extends TestCase
## 08 §5 Flicker, headless, on the flat floor with the real player and a hand-built LightPool
## (Halls tubes 3 m up, no grid). Groups along +X: A (x 0, 4), B (x 10, 14), C (x 20, 24),
## and D far away (x -30). A-B and B-C are adjacent (6 m between neighbouring tubes); D is
## alone. Covers: habitat and adjacency, dark is safe, chemical light is immune, the lunge
## only after standing in the lit area for the charge time and only through the contact gate,
## draining and the evasion, attach and shed, the attached lunge without push, Lightbearer
## reach, despawn and respawn, the breaker's power wave, the Offices light dilemma with
## Still, only Flicker flickers, and determinism.

const TUBE := "res://scenes/props/halls/fixture_tube.tscn"
const HEIGHT := 3.0
const GROUPS := {0: [0.0, 4.0], 1: [10.0, 14.0], 2: [20.0, 24.0], 3: [-30.0]}

var _world: Node3D
var _p: Player
var _pool: LightPool
var _gate_calls: int = 0


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(-40, 0.05, 20))
	_pool = LightPool.new()
	_world.add_child(_pool)
	_pool.configure(load("res://data/strata/halls.tres") as StratumData)
	for g: int in GROUPS:
		for x: float in GROUPS[g]:
			var f := (load(TUBE) as PackedScene).instantiate() as Fixture
			_world.add_child(f)
			f.global_position = Vector3(x, HEIGHT, 0)
			f.group_id = g
			_pool.register_fixture(f)
	_gate_calls = 0
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()
	await await_physics_frames(1)


func _flicker(group: int = 0, aggression: float = 0.25, seed_value: int = 7) -> ErrorFlicker:
	var c := _pool.group_centroid(group)
	var e := ErrorFixture.spawn(_world, &"flicker", Vector3(c.x, 0, c.z), _p, seed_value) as ErrorFlicker
	e.light_pool = _pool
	e.set_aggression(aggression)
	e.contact_request = func(_e: ErrorBase) -> bool:
		_gate_calls += 1
		return true
	e.wake()
	return e


func _seconds(t: float) -> void:
	await await_physics_frames(int(t * Engine.physics_ticks_per_second))


func _place(pos: Vector3) -> void:
	_p.global_position = Vector3(pos.x, 0.05, pos.z)
	_p.velocity = Vector3.ZERO


## Runs up to `t` seconds; returns the seconds when `cond` first held (INF: never).
func _until(t: float, cond: Callable) -> float:
	var n := int(t * Engine.physics_ticks_per_second)
	for i in n:
		await get_tree().physics_frame
		if bool(cond.call()):
			return (i + 1) / float(Engine.physics_ticks_per_second)
	return INF


# --- habitat ---------------------------------------------------------------------------------

func test_groups_adjacency_and_dark_habitat() -> void:
	assert_eq(_pool.groups_adjacent(0), [1] as Array[int], "A touches B (6 m)")
	assert_eq(_pool.groups_adjacent(1), [0, 2] as Array[int])
	assert_eq(_pool.groups_adjacent(3), [] as Array[int], "D is alone")
	var c := _pool.group_centroid(1)
	assert_approx(c.x, 12.0, 0.001, "centroid")
	assert_true(FlickerHabitat.habitable(_pool, 1))
	_pool.set_group_powered(1, false)
	assert_false(FlickerHabitat.habitable(_pool, 1), "an unpowered group is not habitable")
	assert_eq(FlickerHabitat.habitable_neighbours(_pool, 0), [] as Array[int], "A cannot hop into dark B")
	assert_true(FlickerHabitat.in_lit_area(_pool, 0, Vector3(2, 0, 2)), "within 3 m of a tube")
	assert_false(FlickerHabitat.in_lit_area(_pool, 0, Vector3(2, 0, 6)), "6 m off the tubes")


func test_resident_stutters_its_group_only() -> void:
	var e := _flicker(0)
	await _seconds(0.2)
	assert_eq(e.state, Tuning.ERROR_STATE_RESIDENT)
	for f in _pool.group(0):
		assert_true(f.is_flickering(), "its group stutters (the tell)")
	for g in [1, 2, 3]:
		for f in _pool.group(g):
			assert_false(f.is_flickering(), "group %d is steady" % g)
	assert_approx(_pool.group(0)[0].flicker_rate(), Tuning.FLICKER_STUTTER_MIN_HZ, 0.01, "8 Hz resident")


# --- the counter: darkness ----------------------------------------------------------------------

func test_dark_is_safe() -> void:
	_pool.set_group_powered(1, false)
	var e := _flicker(0)
	_place(Vector3(12, 0, 0))   # under B's dark tubes, 2 m from A's lit area edge
	var lost: Array[int] = [0]
	e.lost_player.connect(func() -> void: lost[0] += 1)
	var stalked := await _until(8.0, func() -> bool: return e.state != Tuning.ERROR_STATE_RESIDENT)
	assert_eq(stalked, INF, "standing in an unlit group never starts a Stalk")
	assert_eq(e.lunges, 0)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.001, "no loss")


func test_chemical_light_is_immune() -> void:
	_pool.set_group_powered(1, false)
	var e := _flicker(0)
	var gs := Glowstick.new()
	_world.add_child(gs)
	gs.freeze = true
	gs.global_position = Vector3(12, 0.1, 0)
	_place(Vector3(12, 0, 0))
	_p.flashlight.set_on(false, true)
	var t := await _until(8.0, func() -> bool: return e.state != Tuning.ERROR_STATE_RESIDENT)
	assert_eq(t, INF, "a glowstick's light is never Flicker's light")
	assert_true(Glowstick.is_lit(get_tree(), Vector3(12, 1, 0)), "the glowstick does light the spot (for Still)")
	assert_eq(e.lunges, 0)
	assert_eq(e.attach_time, 0.0, "nothing to attach to")


# --- the rule: stalk and lunge --------------------------------------------------------------------

func test_lunge_only_after_standing_in_its_light_for_the_charge_time() -> void:
	var e := _flicker(0)
	_p.flashlight.set_on(false, true)
	var noticed: Array[int] = [0]
	e.noticed_player.connect(func() -> void: noticed[0] += 1)
	var hit: Array[float] = [0.0]
	e.contacted_player.connect(func(c: float) -> void: hit[0] = c)
	_place(Vector3(2, 0, 1))
	await _seconds(0.1)
	assert_eq(e.state, Tuning.ERROR_STATE_STALK, "in its lit area: Stalk")
	assert_eq(noticed[0], 1, "notice on Stalk")
	var expect := e.charge_time()
	assert_approx(expect, Tuning.FLICKER_CHARGE_TIME * Tuning.FLICKER_LUNGE_CHARGE_MULT_LOW, 0.001, "2.0 s x 1.3 at 0.25")
	var t := await _until(expect + 0.5, func() -> bool: return e.lunges > 0)
	assert_gt(t, expect - 0.2, "no lunge before the charge is full")
	assert_lt(t, expect + 0.2, "the lunge at charge 1.0")
	await _seconds(0.1)
	assert_eq(_gate_calls, 1, "contact asked the gate once")
	assert_approx(hit[0], Tuning.FLICKER_LUNGE_COST, 0.001, "30 on a lunge")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.FLICKER_LUNGE_COST, 0.001)
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED)
	for f in _pool.group(0):
		assert_true(f.is_lunge_dark(), "the group is dark after the lunge")
		assert_true(f.powered, "dark, not unpowered")
	await _seconds(Tuning.FLICKER_DARK_TIME + 0.2)
	assert_eq(e.current_group, 1, "then it hops to an adjacent group")
	for f in _pool.group(0):
		assert_false(f.is_lunge_dark())
		assert_false(f.is_flickering(), "A is steady again")
	_place(Vector3(12, 0, 1))
	await _seconds(2.0)
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED, "no Stalk while Satiated")


func test_refused_contact_does_nothing() -> void:
	var e := _flicker(0)
	e.contact_request = func(_e: ErrorBase) -> bool:
		_gate_calls += 1
		return false
	_place(Vector3(2, 0, 1))
	await _seconds(e.charge_time() + 0.3)
	assert_eq(_gate_calls, 1, "the lunge asked the gate")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.001, "refused: no loss")
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED, "a refused lunge still ends in Satiated")


func test_leaving_the_light_drains_and_is_an_evasion() -> void:
	var e := _flicker(0)
	var lost: Array[int] = [0]
	e.lost_player.connect(func() -> void: lost[0] += 1)
	_place(Vector3(2, 0, 1))
	await _seconds(1.0)
	assert_eq(e.state, Tuning.ERROR_STATE_STALK)
	_place(Vector3(2, 0, 9))
	var t := await _until(1.0, func() -> bool: return e.state == Tuning.ERROR_STATE_RESIDENT)
	assert_lt(t, 0.4, "drains at 2 per second")
	assert_eq(lost[0], 1, "drained without a lunge: an evasion")
	assert_eq(e.lunges, 0)


# --- attach and shed --------------------------------------------------------------------------------

func test_attach_then_shed_by_switching_off() -> void:
	var e := _flicker(0)
	var lost: Array[int] = [0]
	e.lost_player.connect(func() -> void: lost[0] += 1)
	_p.flashlight.set_on(true, true)
	_place(Vector3(2, 0, 3.0))   # 3.6 m from both tubes: lit area by the cell rule, beam within 4 m
	var t := await _until(2.0, func() -> bool: return e.is_attached())
	assert_approx(t, Tuning.FLICKER_ATTACH_TIME, 0.1, "attached after 1.5 s with the beam on")
	for f in _pool.group(0):
		assert_false(f.is_flickering(), "the group goes steady")
	var stuttered := false
	for i in 30:
		await get_tree().physics_frame
		stuttered = stuttered or _p.flashlight.stutter < 1.0
	assert_true(stuttered, "the beam stutters")
	_p.flashlight.set_on(false, true)
	await _seconds(0.1)
	assert_false(e.is_attached(), "switching off sheds it")
	assert_eq(e.sheds, 1)
	assert_eq(e.current_group, 0, "to the nearest habitable group within 10 m")
	assert_eq(lost[0], 1, "shed without a lunge: an evasion")
	assert_eq(_p.flashlight.stutter, 1.0, "the beam is steady again")
	assert_eq(e.lunges, 0)


func test_cranking_does_not_shed() -> void:
	var e := _flicker(0)
	_p.flashlight.set_on(true, true)
	_place(Vector3(2, 0, 3.0))
	await _until(2.0, func() -> bool: return e.is_attached())
	assert_true(e.is_attached())
	_p.flashlight.set_cranking(true)
	await _seconds(0.3)
	_p.flashlight.set_cranking(false)
	assert_true(e.is_attached() or e.state == Tuning.ERROR_STATE_LUNGE or e.state == Tuning.ERROR_STATE_SATIATED,
		"cranking kept it on the beam")
	assert_eq(e.sheds, 0)


func test_attached_lunge_lands_anywhere_without_push() -> void:
	var e := _flicker(0)
	_p.flashlight.set_on(true, true)
	_place(Vector3(2, 0, 3.0))
	await _until(2.0, func() -> bool: return e.is_attached())
	# Walk off into the dark with the beam on: the charge builds wherever the player goes.
	_place(Vector3(-15, 0, 12))
	var at := _p.global_position
	var t := await _until(3.0, func() -> bool: return e.lunges > 0)
	assert_lt(t, 3.0, "the attached lunge lands away from any fixture")
	await _seconds(0.3)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.FLICKER_LUNGE_COST, 0.001, "30")
	assert_lt(FlickerHabitat.flat(_p.global_position, at), 0.05, "no push (Flicker has no body)")
	assert_true(_p.is_stunned(), "the stun still applies")
	assert_eq(e.state, Tuning.ERROR_STATE_DORMANT, "no habitable group within 10 m: despawned")
	assert_true(e.despawned)


func test_lightbearer_reach() -> void:
	var e := _flicker(0)
	_p.flashlight.set_on(true, true)
	_place(Vector3(2, 0, 5.5))   # outside the lit area, 5.5 m from the tubes
	await _seconds(2.0)
	assert_false(e.is_attached(), "4 m: too far")
	e.attract_mult_override = Tuning.FLICKER_ATTACH_DIST_LIGHTBEARER / Tuning.FLICKER_ATTACH_DIST
	var t := await _until(2.0, func() -> bool: return e.is_attached())
	assert_lt(t, 1.7, "Lightbearer: 6 m")


func test_run_attract_mult_is_read() -> void:
	var e := _flicker(0)
	assert_approx(e.attach_dist(), Tuning.FLICKER_ATTACH_DIST, 0.001)
	if GameState.run != null and GameState.is_run_active():
		return
	e.attract_mult_override = 1.5
	assert_approx(e.attach_dist(), 6.0, 0.001, "loadout multiplier")


# --- habitat loss, respawn, breaker ----------------------------------------------------------------------

func test_despawns_in_darkness_and_respawns() -> void:
	var e := _flicker(0)
	await _seconds(0.1)
	_pool.set_group_powered(0, false)
	_pool.set_group_powered(1, false)
	await _seconds(0.1)
	assert_true(e.despawned, "no lit group within 10 m: it does not persist in darkness")
	assert_eq(e.state, Tuning.ERROR_STATE_DORMANT)
	for f in _pool.group(0):
		assert_false(f.is_flickering())
	e.wake()
	assert_true(e.is_dormant(), "a wake does not bring it back; only the Director's respawn")
	assert_false(e.respawn_at(1), "not into a dark group")
	assert_true(e.respawn_at(2))
	assert_eq(e.state, Tuning.ERROR_STATE_RESIDENT)
	assert_eq(e.current_group, 2)


func test_group_losing_power_moves_it_to_a_lit_neighbour() -> void:
	var e := _flicker(0)
	await _seconds(0.1)
	_pool.set_group_powered(0, false)
	await _seconds(0.1)
	assert_eq(e.current_group, 1, "the nearest lit group within 10 m")
	assert_false(e.despawned)


func test_breaker_wave_opens_the_floor() -> void:
	_pool.set_group_powered(1, false)
	_pool.set_group_powered(2, false)
	var e := _flicker(0, 0.75)
	await _seconds(15.0)
	assert_eq(e.hops, 0, "no lit neighbour: it stays")
	_pool.power_wave(Vector3(30, 0, 0))
	await _seconds(2.0)
	assert_true(FlickerHabitat.habitable(_pool, 1), "the wave powered B")
	await _until(20.0, func() -> bool: return e.hops > 0)
	assert_gt(e.hops, 0, "its habitat grew with the power")


# --- Director link ------------------------------------------------------------------------------------

func test_immediate_hint_hops_toward_it() -> void:
	var e := _flicker(0)
	await _seconds(0.1)
	e.hint(Vector3(30, 0, 0), true)
	await _seconds(0.1)
	assert_eq(e.current_group, 1, "one hop toward the hint now")
	assert_true(e.has_hint())


func test_retreat_while_attached_sheds_without_evasion() -> void:
	var e := _flicker(0)
	var lost: Array[int] = [0]
	e.lost_player.connect(func() -> void: lost[0] += 1)
	_p.flashlight.set_on(true, true)
	_place(Vector3(2, 0, 3.0))
	await _until(2.0, func() -> bool: return e.is_attached())
	e.retreat(5.0)
	await _seconds(0.1)
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED)
	assert_ge_group(e)
	assert_eq(lost[0], 0, "the Director sent it away: not an evasion")
	assert_eq(_p.flashlight.stutter, 1.0)


func assert_ge_group(e: ErrorFlicker) -> void:
	assert_true(e.current_group >= 0, "back in a group")


# --- the Offices light dilemma ------------------------------------------------------------------------

## 08 §5: with a glowstick in a dark area the player observes Still while Flicker, in a lit
## group nearby, has nothing to lunge from or attach to.
func test_glowstick_watches_still_safe_from_flicker() -> void:
	_pool.set_group_powered(1, false)
	var fl := _flicker(0)
	var still := ErrorFixture.spawn(_world, &"still", Vector3(12, 0, -3.0), _p) as ErrorStill
	still.wake()
	var gs := Glowstick.new()
	_world.add_child(gs)
	gs.freeze = true
	gs.global_position = Vector3(12, 0.1, -1.5)
	_p.flashlight.set_on(false, true)
	_place(Vector3(12, 0, 2))
	_p.rotation = Vector3.ZERO   # facing -Z, toward Still
	await _seconds(0.2)
	var start := still.body_position()
	var observed_all := true
	for i in 240:
		await get_tree().physics_frame
		observed_all = observed_all and _p.is_observing(still)
	assert_true(observed_all, "the glowstick lights Still for observation")
	assert_lt(still.body_position().distance_to(start), 0.05, "Still holds")
	assert_eq(fl.state, Tuning.ERROR_STATE_RESIDENT, "Flicker never stalks a player in chemical light")
	assert_eq(fl.lunges, 0)


# --- only Flicker flickers ----------------------------------------------------------------------------------

func test_only_flicker_drives_fixture_flicker() -> void:
	var offenders: Array[String] = []
	_scan("res://src", offenders)
	assert_eq(offenders, [] as Array[String], "set_flicker / set_group_flicker callers outside Flicker")


func _scan(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var path := dir.path_join(f)
		var text := FileAccess.get_file_as_string(path)
		var allowed := path.ends_with("light_pool.gd") and text.contains("f.set_flicker(") \
			or path.ends_with("error_flicker.gd") or path.ends_with("fixture.gd")
		if (text.contains(".set_flicker(") or text.contains("set_group_flicker(")) and not allowed:
			out.append(path)
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


# --- determinism ----------------------------------------------------------------------------------------------

func test_hops_are_deterministic_per_seed() -> void:
	var a := await _hop_trace(11)
	var b := await _hop_trace(11)
	assert_eq(a, b, "same seed, same hops")
	assert_gt(a.size(), 2)


func _hop_trace(seed_value: int) -> Array[int]:
	var e := _flicker(1, 0.75, seed_value)
	var out: Array[int] = []
	var last := e.current_group
	for i in int(20.0 * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if e.current_group != last:
			last = e.current_group
			out.append(last)
	e.free()
	for g in _pool.group_ids():
		_pool.set_group_flicker(g, false)
	return out
