extends TestCase
## Clock (14 §3, 11 §4): hitstop through the tree pause, no stacking, menu pause
## precedence, wall timers that survive pause, and the run timer.

var _real_now: Callable


func before_each() -> void:
	_real_now = Clock.now_usec
	_reset()


func after_each() -> void:
	Clock.now_usec = _real_now
	_reset()


func _reset() -> void:
	Clock.set_menu_pause(false)
	if Clock.is_hitstopping():
		Clock._end_hitstop()
	get_tree().paused = false


func _fake(fc: FakeClock) -> void:
	Clock.now_usec = func() -> int: return int(round(fc.time_s * 1_000_000.0))


## Waits up to `limit_ms` of real time for the tree to unpause; returns elapsed ms.
func _await_unpause(limit_ms: int) -> int:
	var t0 := Time.get_ticks_msec()
	while get_tree().paused and Time.get_ticks_msec() - t0 < limit_ms:
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0


func test_clock_and_router_run_while_paused() -> void:
	assert_eq(Clock.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(SceneRouter.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(CoherenceRenderer.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_hitstop_pauses_then_unpauses_after_duration() -> void:
	var t0 := Time.get_ticks_msec()
	Clock.hitstop(40)
	assert_true(get_tree().paused, "tree paused immediately")
	assert_true(Clock.is_hitstopping())
	await get_tree().process_frame
	var elapsed := Time.get_ticks_msec() - t0
	if elapsed < 40:
		assert_true(get_tree().paused, "still paused before the duration")
	await _await_unpause(2000)
	assert_false(get_tree().paused, "unpaused after the duration")
	assert_false(Clock.is_hitstopping())
	assert_true(Time.get_ticks_msec() - t0 >= 40, "held for at least the duration")


func test_pausable_node_freezes_during_hitstop() -> void:
	var counter := _FrameCounter.new()
	add_child(counter)
	await get_tree().process_frame
	Clock.hitstop(60)
	var frozen_at := counter.frames
	await get_tree().process_frame
	await get_tree().process_frame
	if Clock.is_hitstopping():
		assert_eq(counter.frames, frozen_at, "pausable node does not process during hitstop")
	await _await_unpause(2000)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(counter.frames, frozen_at, "processes again after hitstop")
	counter.free()


func test_hitstops_do_not_stack() -> void:
	var fc := fake_clock(10.0)
	_fake(fc)
	Clock.hitstop(80)
	fc.advance(0.050)
	Clock.hitstop(60)  # ends at 110 ms, not 140 ms
	assert_approx(Clock.hitstop_remaining_ms(), 60.0, 0.01, "extends to the later end")
	Clock.hitstop(10)  # shorter than what remains: no change
	assert_approx(Clock.hitstop_remaining_ms(), 60.0, 0.01, "a shorter hitstop does not shorten or add")
	fc.advance(0.059)
	await get_tree().process_frame
	assert_true(get_tree().paused, "still paused 1 ms before the end")
	fc.advance(0.002)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(get_tree().paused, "unpaused at the later end")


func test_hitstop_refused_while_menu_paused() -> void:
	Clock.set_menu_pause(true)
	Clock.hitstop(80)
	assert_false(Clock.is_hitstopping())
	assert_true(get_tree().paused, "menu keeps the pause")
	Clock.set_menu_pause(false)
	assert_false(get_tree().paused)


func test_menu_open_ends_hitstop_and_keeps_pause() -> void:
	var fc := fake_clock(1.0)
	_fake(fc)
	Clock.hitstop(80)
	Clock.set_menu_pause(true)
	assert_false(Clock.is_hitstopping(), "menu ends the hitstop (11 §4)")
	fc.advance(1.0)
	await get_tree().process_frame
	assert_true(get_tree().paused, "the expired hitstop never unpauses the menu")
	Clock.set_menu_pause(false)
	assert_false(get_tree().paused)


func test_hitstop_ignores_non_positive() -> void:
	Clock.hitstop(0)
	Clock.hitstop(-5)
	assert_false(get_tree().paused)


func test_wall_timer_survives_pause() -> void:
	get_tree().paused = true
	var t0 := Time.get_ticks_usec()
	await Clock.wall_timer(0.03).timeout
	assert_true(Time.get_ticks_usec() - t0 >= 30_000, "waited the full wall-clock duration")
	assert_true(get_tree().paused, "fired while the tree was paused")
	get_tree().paused = false


func test_run_timer_excludes_menu_pause() -> void:
	var fc := fake_clock(100.0)
	_fake(fc)
	Clock.start_run_timer()
	fc.advance(10.0)
	assert_approx(Clock.run_seconds(), 10.0, 0.001)
	Clock.set_menu_pause(true)
	fc.advance(5.0)
	assert_approx(Clock.run_seconds(), 10.0, 0.001, "menu time not counted")
	Clock.set_menu_pause(false)
	fc.advance(2.0)
	assert_approx(Clock.run_seconds(), 12.0, 0.001)
	Clock.stop_run_timer()
	fc.advance(50.0)
	assert_approx(Clock.run_seconds(), 12.0, 0.001, "stopped timer holds")


func test_run_timer_follows_run_lifecycle_signals() -> void:
	var fc := fake_clock(0.0)
	_fake(fc)
	EventBus.run_started.emit(&"descent", 1)
	assert_true(Clock.is_run_timer_running())
	fc.advance(3.0)
	EventBus.run_ended.emit(&"still", 0)
	assert_false(Clock.is_run_timer_running())
	assert_approx(Clock.run_seconds(), 3.0, 0.001)


class _FrameCounter extends Node:
	var frames: int = 0

	func _process(_delta: float) -> void:
		frames += 1
