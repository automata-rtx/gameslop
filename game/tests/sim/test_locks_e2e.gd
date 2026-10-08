extends TestCase
## M2.9 end to end, headless (07 §6, 09 §5, 05 §4): on a real level of each stratum, every lock
## through run.tscn: Open (walk in), Powered Variant B (fetch the placed fuse, insert it, throw
## the breaker, the power wave opens the exit), Keyed (pick up the placed keycard, swipe at the
## exit's reader), Cycled (the schedule opens the exit) -> enter -> the Landing -> the next
## depth. One run per stratum: its strata order is that stratum six times and each depth's lock
## is forced through Run.generation_overrides. The HUD's exit line is checked at each step.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 60.0
const STRATA: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server"]
const SEQUENCE: Array[StringName] = [Tuning.LOCK_OPEN, Tuning.LOCK_POWERED, Tuning.LOCK_KEYED, Tuning.LOCK_CYCLED]
## The first depth each stratum is played at: its usual depths (05 §2), so grid sizes match.
const START_DEPTH: Dictionary = {&"halls": 1, &"pools": 2, &"garage": 2, &"offices": 2, &"server": 4}
const EXIT_KINDS: Dictionary = {
	&"halls": &"elevator", &"pools": &"drain_hatch", &"garage": &"stairwell_door",
	&"offices": &"elevator", &"server": &"floor_hatch",
}

var _host: Node
var _prev_host: Node
var _prev_transition: Object
var _meta: MetaState


func before_all() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true


func after_all() -> void:
	GameState.meta = _meta


func before_each() -> void:
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "LocksTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
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


func _start(stratum: StringName, run_seed: int, depth: int, first_lock: StringName, levels: int) -> Run:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	var order: Array[StringName] = []
	for i in Tuning.RUN_CYCLE_LENGTH:
		order.append(stratum)
	# The depth after the last one played is pre-generated on the last exit: Halls, which
	# generates at any depth (Server only validates at its own depths).
	order[(depth + levels - 1) % Tuning.RUN_CYCLE_LENGTH] = &"halls"
	GameState.run.strata_order = order
	GameState.run.depth = depth
	GameState.run.max_depth = GameState.run.depth
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 0.3
	run.generation_overrides = {&"lock": first_lock, &"lock_variant": &"b"}
	_host.add_child(run)
	SceneRouter.set_host(_host)
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING)
	return run


func _in_level(run: Run, group: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(group):
		if run.level != null and run.level.is_ancestor_of(n):
			out.append(n)
	return out


## Unlocks the current level's exit the way its lock asks. Returns false (after failing) when
## something is missing.
func _unlock(run: Run, tag: String) -> bool:
	var exit := run.exit
	var p := run.player
	match exit.lock:
		Tuning.LOCK_OPEN:
			assert_true(exit.is_open(), tag + ": Open is open")
		Tuning.LOCK_POWERED:
			assert_eq(run.data.lock_variant, &"b", tag)
			assert_not_null(run.breaker, tag + ": breaker placed")
			if run.breaker == null:
				return false
			assert_eq(run.breaker.variant, Breaker.VARIANT_B, tag)
			assert_false(run.breaker.throw_breaker(), tag + ": no lever without the fuse")
			var fuse: ItemPickup = null
			for n in _in_level(run, ItemPickup.GROUP):
				if n is ItemPickup and (n as ItemPickup).kind == &"fuse":
					fuse = n
			assert_not_null(fuse, tag + ": the guaranteed fuse is in the level")
			if fuse == null:
				return false
			var cell := run.data.grid.cell_of(fuse.global_position)
			var path := run.data.grid.distance_field(run.data.spawn_cell)
			assert_true(path[run.data.grid.idx(cell)] >= 0, tag + ": the fuse is reachable on foot")
			p.global_position = fuse.global_position
			assert_true(fuse.take(p), tag + ": fuse picked up")
			assert_true(p.inventory.has(&"fuse"))
			p.global_position = run.breaker.global_position + run.breaker.global_transform.basis.z * -1.0
			run.breaker.interactable.interact(p)
			assert_true(run.breaker.fuse_in, tag + ": fuse inserted at the breaker")
			assert_false(p.inventory.has(&"fuse"))
			run.breaker.interactable.interact(p)
			assert_true(run.breaker.is_thrown, tag + ": lever thrown")
			assert_true(await _until(func() -> bool: return exit.is_open(), 20.0), tag + ": the power wave opens the exit")
		Tuning.LOCK_KEYED:
			assert_not_null(exit.reader, tag + ": the exit has its reader")
			var cards := _in_level(run, ItemPickup.GROUP).filter(func(n: Node) -> bool: return n is KeycardPickup)
			assert_eq(cards.size(), 1, tag + ": one keycard in the level")
			if cards.is_empty() or exit.reader == null:
				return false
			var card := cards[0] as KeycardPickup
			var cell := run.data.grid.cell_of(card.global_position)
			assert_true(run.data.grid.distance_field(run.data.spawn_cell)[run.data.grid.idx(cell)] >= 0,
				tag + ": the keycard is reachable on foot")
			assert_false(exit.reader.swipe(p), tag + ": NO CARD")
			assert_false(exit.is_open())
			p.global_position = card.global_position
			assert_true(card.take(p), tag + ": card picked up")
			exit.reader.interactable.interact(p)
			assert_true(exit.is_open(), tag + ": the swipe opens the exit")
		Tuning.LOCK_CYCLED:
			assert_eq(exit.status, Tuning.EXIT_STATUS_SEALED)
			assert_true(exit.cycle_running, tag + ": the clock started on arrival")
			assert_false(exit.try_enter(p), tag + ": sealed")
			assert_eq(run.hud.depth.exit_text(), "EXIT: SEALED %s" % HudDepth.format_time(exit.cycle_left), tag)
			# Wait for the cycle: skip most of the 70 s, then let real frames open it.
			exit.advance_cycle(exit.cycle_left - 0.3)
			assert_true(await _until(func() -> bool: return exit.is_open(), 5.0), tag + ": the cycle opens the exit")
			assert_true(run.hud.depth.exit_text().begins_with("EXIT: OPEN 00:"), tag + ": " + run.hud.depth.exit_text())
			return true
	assert_eq(run.hud.depth.exit_text(), "EXIT: OPEN", tag)
	return true


func _play_stratum(stratum: StringName, run_seed: int, locks: Array[StringName] = SEQUENCE,
		depth: int = -1) -> void:
	var run := await _start(stratum, run_seed, depth if depth > 0 else START_DEPTH[stratum], locks[0], locks.size())
	assert_eq(run.phase, Run.PHASE_PLAYING, "%s arrived" % stratum)
	for i in locks.size():
		var lock := locks[i]
		var tag := "%s depth %d %s" % [stratum, GameState.run.depth, lock]
		assert_eq(run.data.stratum, stratum, tag)
		assert_eq(run.data.exit_lock, lock, tag)
		var exit := run.exit
		assert_not_null(exit, tag + ": exit prefab")
		if exit == null:
			return
		assert_eq(exit.exit_kind, EXIT_KINDS[stratum], tag + ": the stratum's own prefab")
		assert_eq(exit.lock, lock, tag)
		assert_eq(run.hud.depth.exit_text(), "EXIT: UNKNOWN", tag + ": unknown until seen")
		exit.mark_seen()
		var expect := {Tuning.LOCK_OPEN: "EXIT: OPEN", Tuning.LOCK_POWERED: "EXIT: POWERED",
			Tuning.LOCK_KEYED: "EXIT: KEYED"}
		if expect.has(lock):
			assert_eq(run.hud.depth.exit_text(), expect[lock], tag + ": seen status")
		if not await _unlock(run, tag):
			return
		if i + 1 < locks.size():
			run.generation_overrides = {&"lock": locks[i + 1], &"lock_variant": &"b"}
		var before := GameState.run.depth
		run.player.global_position = exit.walk_in_point()
		assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_LANDING, 10.0), tag + ": entered, Landing")
		assert_eq(GameState.run.depth, before + 1, tag + ": descend(true)")
		assert_true(await _until(func() -> bool:
			return run.phase == Run.PHASE_PLAYING and run.arrival == Tuning.RUN_ARRIVE_PROPER), tag + ": next depth arrived")
	assert_eq(GameState.run.proper_exits, locks.size(), "%s: a proper exit per lock" % stratum)
	run.queue_free()
	await await_frames(3)


func test_locks_halls() -> void:
	await _play_stratum(&"halls", 901)


func test_locks_pools() -> void:
	await _play_stratum(&"pools", 902)


func test_locks_garage() -> void:
	await _play_stratum(&"garage", 903)


func test_locks_offices() -> void:
	await _play_stratum(&"offices", 904)


## Server generates only at its own depths (4 and 5, 05 §2), so its four locks take two runs.
func test_locks_server() -> void:
	await _play_stratum(&"server", 905, [Tuning.LOCK_OPEN, Tuning.LOCK_POWERED] as Array[StringName], 4)
	await _play_stratum(&"server", 906, [Tuning.LOCK_KEYED, Tuning.LOCK_CYCLED] as Array[StringName], 4)
