extends TestCase
## M1.13 slice review (R9), headless on the flat navigable floor: Relief's immediate
## hint-away (10 §2: Wander and Search re-target at once), Static's one notice per
## engagement (08 §2, re-armed after 5 s outside or an evasion), and errors that stop
## ticking against a freed player without a single engine error.

var _world: Node3D
var _p: Player


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(3)


func after_each() -> void:
	Engine.time_scale = 1.0
	_world.free()
	await await_physics_frames(1)


## An unobserved Still (flat world: no light; sight and hearing off).
func _still(pos: Vector3) -> ErrorStill:
	var s := ErrorFixture.spawn(_world, &"still", pos, _p) as ErrorStill
	s.set_aggression(0.25)
	s.senses.sight_range = 0.0
	s.senses.hearing_mult = 0.0
	return s


func _seconds(t: float) -> void:
	await await_physics_frames(int(t * Engine.physics_ticks_per_second))


# ------------------------------------------------------------- 4. immediate hints

func test_still_wander_retargets_at_once_on_an_immediate_hint() -> void:
	var s := _still(Vector3(0, 0, -20))
	var a := Vector3(12, 0, -20)
	var b := Vector3(-12, 0, -20)
	# A fresh navigation map can answer the zero vector for its first queries (see
	# ErrorFixture.make_world): let the server settle before the first snap.
	await await_physics_frames(5)
	NavigationServer3D.map_force_update(s.agent.get_navigation_map())
	s.hint(a)
	s.wake()
	await _seconds(0.5)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER)
	assert_lt(ErrorFixture.flat(s._target, a), 0.5, "walking to the first hint")
	s.hint(b, true)
	assert_lt(ErrorFixture.flat(s._target, b), 0.5, "an immediate hint re-targets now")
	assert_false(s.has_hint(), "consumed")
	var x0 := s.body_position().x
	await _seconds(1.0)
	assert_lt(s.body_position().x, x0 - 0.5, "walking toward the hint")


func test_still_search_retargets_at_once_on_an_immediate_hint() -> void:
	var s := _still(Vector3(0, 0, -20))
	s.wake()
	s.start_search(Vector3(12, 0, -20))
	await _seconds(0.3)
	assert_eq(s.state, Tuning.ERROR_STATE_SEARCH)
	var b := Vector3(-12, 0, -20)
	s.hint(b, true)
	assert_eq(s.state, Tuning.ERROR_STATE_SEARCH, "still searching")
	assert_lt(ErrorFixture.flat(s._target, b), 0.5, "searching the hinted point now")
	var x0 := s.body_position().x
	await _seconds(1.0)
	assert_lt(s.body_position().x, x0 - 0.5, "walking toward the hint")


func test_immediate_hint_is_only_stored_outside_wander_and_search() -> void:
	var s := _still(Vector3(0, 0, -20))
	s.wake()
	s.retreat(20.0)
	var target := s._target
	s.hint(Vector3(-12, 0, -20), true)
	assert_eq(s._target, target, "Satiated keeps its retreat")
	assert_true(s.has_hint(), "the hint is kept for later")


func test_static_retargets_at_once_and_cuts_its_dwell() -> void:
	var s := ErrorFixture.spawn(_world, &"static", Vector3(20, 0, 20), _p) as ErrorStatic
	s.set_aggression(0.25)
	s.hint(s.global_position)
	s.wake()
	await _seconds(0.5)
	var here := s.global_position
	var far := Vector3(20, 0, -10)
	s.hint(far)
	await _seconds(0.5)
	assert_lt(ErrorFixture.flat(s.global_position, here), 0.01, "a plain hint waits for the dwell")
	s.hint(far, true)
	await _seconds(1.0)
	assert_gt(ErrorFixture.flat(s.global_position, here), 0.4, "drifting to the hint at once")
	assert_lt(s.global_position.z, here.z, "toward it")


func test_static_nudge_holds_over_an_immediate_hint() -> void:
	var s := ErrorFixture.spawn(_world, &"static", Vector3(20, 0, 20), _p) as ErrorStatic
	s.wake()
	s.nudge(Vector3(-10, 0, 20))
	s.hint(Vector3(20, 0, -10), true)
	assert_true(s.is_nudged())
	await _seconds(1.0)
	assert_lt(s.global_position.x, 19.0, "still on the nudge")


# ------------------------------------------------------------- 6. one Static notice

func test_static_short_entries_record_one_notice() -> void:
	var s := ErrorFixture.spawn(_world, &"static", Vector3(0, 0, -20), _p) as ErrorStatic
	s.set_aggression(0.25)
	s.hint(s.global_position)
	var counts := {"notice": 0, "lost": 0}
	s.noticed_player.connect(func() -> void: counts["notice"] += 1)
	s.lost_player.connect(func() -> void: counts["lost"] += 1)
	var before: int = int(GameState.run.encounters.get(&"static", 0)) if GameState.run != null else 0
	s.wake()
	for i in 6:
		_p.global_position = s.global_position + Vector3(0, 0.05, 0)
		await _seconds(0.5)
		assert_true(s.inside, "inside on entry %d" % i)
		_p.global_position = s.global_position + Vector3(15, 0.05, 0)
		await _seconds(1.0)
		assert_false(s.inside)
	assert_eq(counts["notice"], 1, "six short entries: one notice")
	assert_eq(counts["lost"], 0, "none lasted 2 s: no evasion")
	if GameState.run != null:
		assert_eq(int(GameState.run.encounters.get(&"static", 0)), before + 1, "one encounter recorded")
	await _seconds(Tuning.STATIC_NOTICE_REARM_TIME + 0.2)
	assert_false(s.is_engaged(), "5 s outside ends the engagement")
	_p.global_position = s.global_position + Vector3(0, 0.05, 0)
	await _seconds(0.2)
	assert_eq(counts["notice"], 2, "re-armed after 5 s outside")


# ------------------------------------------------------------- 16. freed player

class _Catcher extends Logger:
	var lines: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("[%d] %s (%s:%d %s) %s" % [error_type, code, file, line, function, rationale])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func test_freeing_the_player_mid_run_raises_no_errors() -> void:
	var still := ErrorFixture.spawn(_world, &"still", Vector3(0, 0, -22), _p) as ErrorStill
	still.set_aggression(1.0)
	still.wake()
	var st := ErrorFixture.spawn(_world, &"static", Vector3(0, 0, 0), _p) as ErrorStatic
	st.hint(st.global_position)
	st.wake()
	await _seconds(2.0)
	assert_true(st.inside, "the field holds the player")
	assert_eq(still.state, Tuning.ERROR_STATE_CHASE, "Still saw the player")
	var catcher := _Catcher.new()
	OS.add_logger(catcher)
	_p.queue_free()
	await _seconds(1.5)
	still.hint(Vector3(5, 0, -5), true)
	st.hint(Vector3(5, 0, 5), true)
	await await_physics_frames(10)
	OS.remove_logger(catcher)
	assert_eq(catcher.lines.size(), 0, "no engine errors: %s" % "\n".join(catcher.lines))
	assert_false(still.has_player())
	assert_null(still.live_player())
	assert_false(st.inside, "the field let go")
	assert_eq(st.distance_to_player(), INF)
