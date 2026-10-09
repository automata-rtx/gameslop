extends TestCase
## R15 (M2.17 review) on real runs, headless: B1 the Lightbearer cranks x1.5 (05 §7), S1 the
## Variant B fuse pulled after the throw unpowers the floor and seals the exit, and inserting
## it again re-runs the throw (08 §5), S4 the Cycle 2 Substrate drain reaches run_ended with
## cause `substrate` (06 §9).

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 40.0
const DT := 1.0 / 60.0

var _host: Node
var _prev_host: Node
var _prev_transition: Object
var _meta: MetaState


func before_all() -> void:
	_meta = GameState.meta


func after_all() -> void:
	GameState.meta = _meta


func before_each() -> void:
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	PlayerFixture.release_all()
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "R15TestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	PlayerFixture.release_all()
	for c in _host.get_children():
		c.queue_free()
	await await_frames(3)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()


func _until(cond: Callable, seconds: float = TIMEOUT_S) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _run(overrides: Dictionary = {}) -> Run:
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 0.3
	run.dissolve_time = 0.2
	run.generation_overrides = overrides
	_host.add_child(run)
	SceneRouter.set_host(_host)
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING)
	return run


func _strata(stratum: StringName) -> void:
	var order: Array[StringName] = []
	for i in Tuning.RUN_CYCLE_LENGTH:
		order.append(stratum)
	GameState.run.strata_order = order


# --- B1 -------------------------------------------------------------------------------------

## Cranks from empty with the light off for `frames` physics frames; returns the charge.
func _crank(run: Run, frames: int) -> float:
	var f := run.player.flashlight
	f.set_on(false, true)
	f.set_charge(0.0)
	Input.action_press(&"crank")
	await await_physics_frames(frames)
	Input.action_release(&"crank")
	return f.charge


func test_lightbearer_cranks_one_and_a_half_times_faster() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"lightbearer", 151)
	var run := await _run()
	assert_eq(run.phase, Run.PHASE_PLAYING)
	assert_true(run.player.flashlight.lightbearer, "the loadout reaches the flashlight")
	# 0 to 100 in 100 / 37.5 = 2.67 s.
	assert_lt(await _crank(run, 150), Tuning.FLASH_CHARGE_MAX, "not full at 2.5 s")
	assert_approx(await _crank(run, 162), Tuning.FLASH_CHARGE_MAX, 0.001, "full at 2.7 s")


func test_faller_cranks_at_the_base_rate() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 152)
	var run := await _run()
	assert_false(run.player.flashlight.lightbearer)
	# 0 to 100 in 4 s; 2.7 s gives 67.5.
	assert_approx(await _crank(run, 162), Tuning.CRANK_RATE * 162.0 * DT, 1.0, "25 per second")


# --- S1 -------------------------------------------------------------------------------------

func _in_level(run: Run, group: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(group):
		if run.level != null and run.level.is_ancestor_of(n):
			out.append(n)
	return out


func _unpowered(run: Run) -> Array[Fixture]:
	var out: Array[Fixture] = []
	for f in run.level.light_pool.fixtures():
		if not f.powered:
			out.append(f)
	return out


func _habitable_groups(run: Run) -> int:
	var n := 0
	for g: int in run.level.light_pool.group_ids():
		if FlickerHabitat.habitable(run.level.light_pool, g):
			n += 1
	return n


func test_offices_fuse_pulled_after_the_throw_cuts_the_power() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 1517)
	_strata(&"offices")
	GameState.run.depth = 2
	GameState.run.max_depth = 2
	var run := await _run({&"lock": Tuning.LOCK_POWERED, &"lock_variant": &"b"})
	assert_eq(run.data.stratum, &"offices")
	var exit := run.exit
	var b := run.breaker
	assert_not_null(b, "breaker placed")
	if b == null or exit == null:
		return
	assert_eq(b.variant, Breaker.VARIANT_B)
	var p := run.player
	var dark_before := _unpowered(run)
	assert_gt(dark_before.size(), 0, "a Powered exit room starts dark")
	var habitable_before := _habitable_groups(run)
	p.inventory.add(&"fuse")
	p.global_position = b.global_position + b.global_transform.basis.z * -1.0
	assert_true(b.insert_fuse(p))
	assert_true(b.throw_breaker())
	assert_true(await _until(func() -> bool: return exit.is_open(), 20.0), "the wave opens the exit")
	assert_true(await _until(func() -> bool: return _unpowered(run).is_empty(), 10.0), "the whole floor is powered")
	assert_gt(_habitable_groups(run), habitable_before, "Flicker's habitat grows with the power")
	# Pull: dark and a dead exit.
	assert_true(b.socket_interactable.can_interact(p), "PULL FUSE offered after the throw")
	assert_true(b.pull_fuse(p))
	assert_true(p.inventory.has(&"fuse"))
	assert_false(exit.is_open(), "the exit seals")
	assert_eq(exit.status, Tuning.EXIT_STATUS_POWERED, "EXIT: POWERED again")
	assert_false(exit.try_enter(p), "a dead exit refuses the player")
	var dark_after := _unpowered(run)
	assert_eq(dark_after.size(), dark_before.size(), "exactly the fixtures the wave lit go dark")
	for f in dark_before:
		assert_true(f in dark_after)
	assert_eq(_habitable_groups(run), habitable_before, "Flicker's habitat shrinks back")
	# Re-insert: the throw again (the wave, the exit).
	var thrown := []
	var cb := func(pos: Vector3) -> void: thrown.append(pos)
	EventBus.breaker_thrown.connect(cb)
	assert_true(b.insert_fuse(p))
	EventBus.breaker_thrown.disconnect(cb)
	assert_eq(thrown.size(), 1, "re-inserting re-runs the throw")
	assert_true(await _until(func() -> bool: return exit.is_open(), 20.0), "the wave opens the exit again")
	assert_true(await _until(func() -> bool: return _unpowered(run).is_empty(), 10.0), "the floor is lit again")


func test_pull_during_the_wave_cancels_it() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 1518)
	_strata(&"offices")
	GameState.run.depth = 2
	GameState.run.max_depth = 2
	var run := await _run({&"lock": Tuning.LOCK_POWERED, &"lock_variant": &"b"})
	var b := run.breaker
	var exit := run.exit
	if b == null or exit == null:
		assert_not_null(b)
		return
	var p := run.player
	var dark_before := _unpowered(run).size()
	p.inventory.add(&"fuse")
	b.insert_fuse(p)
	b.throw_breaker()
	await await_physics_frames(2)
	assert_true(b.pull_fuse(p), "pulled while the wave travels")
	await get_tree().create_timer(4.0).timeout
	assert_false(exit.is_open(), "the cancelled wave never opens the exit")
	assert_eq(_unpowered(run).size(), dark_before, "no fixture lights after the pull")


# --- S4 -------------------------------------------------------------------------------------

func test_cycle_2_substrate_dissolves_with_cause_substrate() -> void:
	GameState.start_run(Tuning.MODE_ENDLESS, &"faller", 1519)
	_strata(Tuning.STRATUM_SUBSTRATE)
	GameState.run.depth = 12
	GameState.run.max_depth = 12
	GameState.run.coherence = 0.3
	var ended := []
	var cb := func(cause: StringName, _score: int) -> void: ended.append(cause)
	EventBus.run_ended.connect(cb)
	var run := await _run()
	assert_eq(run.data.stratum, Tuning.STRATUM_SUBSTRATE)
	assert_true(await _until(func() -> bool: return not ended.is_empty(), 10.0), "the drain dissolves the player")
	EventBus.run_ended.disconnect(cb)
	assert_eq(ended, [Player.CAUSE_SUBSTRATE], "run_ended(&\"substrate\", ...)")
