extends TestCase
## RCA1: headless processes hold the audio driver lock across AudioServer.update() so the
## mix thread never reads a bus-details block the main thread frees (engine race; see
## AudioMixGuard). Stress repro: tests/stress/audio_mix_race.gd.


func _guard() -> AudioMixGuard:
	return AudioManager.get_node_or_null(^"AudioMixGuard") as AudioMixGuard


func test_headless_audio_manager_installs_the_guard() -> void:
	assert_eq(DisplayServer.get_name(), "headless", "the gate runs headless")
	var g := _guard()
	assert_not_null(g, "AudioManager carries an AudioMixGuard in headless runs")
	if g == null:
		return
	assert_true(AudioMixGuard.enabled)
	assert_eq(g.mode, AudioMixGuard.Mode.HEADLESS)
	assert_eq(g.process_priority, 2147483647, "it locks last in the process step")
	assert_eq(g.process_mode, Node.PROCESS_MODE_ALWAYS, "and through pause")


func test_guard_covers_every_frame_end_and_releases_at_frame_start() -> void:
	var g := _guard()
	if g == null:
		fail("no guard")
		return
	var before := g.locks
	await await_frames(5)
	assert_true(g.locks - before >= 4, "locked at the end of each frame (%d)" % (g.locks - before))
	# The guard releases on the first frame signal; this test resumes after it.
	await get_tree().process_frame
	assert_false(g.held, "released when the next frame starts")
	await get_tree().physics_frame
	assert_false(g.held, "released when a physics step starts")


func test_the_mixer_still_advances_under_the_guard() -> void:
	# A 50 ms one-shot only finishes when the mix thread mixes it to the end.
	var p := AudioStreamPlayer.new()
	p.stream = _tone(0.05)
	add_child(p)
	var done := [false]
	p.finished.connect(func() -> void: done[0] = true)
	p.play()
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_true(done[0], "the one-shot finished within 3 s of wall time")
	p.queue_free()


func test_exit_releases_a_held_lock() -> void:
	var g := AudioMixGuard.new()
	g.held = false
	AudioServer.lock()
	g.held = true
	g.release()
	assert_false(g.held)
	g.release()  # idempotent: unlocks once
	assert_false(g.held)
	g.free()


## M3.3: with a window the guard holds the lock from frame_post_draw to the next frame
## start, only when nothing in that tail sleeps, and a watchdog turns it off for good after
## repeated long holds or lock waits. Driven by hand here (no draw in headless).
func test_frame_tail_holds_only_when_the_tail_cannot_sleep() -> void:
	var g := AudioMixGuard.new()
	g.mode = AudioMixGuard.Mode.FRAME_TAIL
	var fps := Engine.max_fps
	Engine.max_fps = 0
	assert_true(AudioMixGuard.tail_cannot_sleep(), "uncapped, no low-processor mode")
	g._on_frame_post_draw()
	assert_true(g.held, "locked after the draw")
	assert_eq(g.locks, 1)
	g._on_frame_post_draw()
	assert_eq(g.locks, 1, "once per frame")
	g.release()
	assert_false(g.held)
	assert_lt(g.max_hold_usec, AudioMixGuard.WATCHDOG_BUDGET_USEC, "a short hold")
	Engine.max_fps = 60
	assert_false(AudioMixGuard.tail_cannot_sleep(), "a frame cap sleeps in the tail")
	g._on_frame_post_draw()
	assert_false(g.held, "no lock across a frame-delay sleep")
	Engine.max_fps = 0
	OS.low_processor_usage_mode = true
	assert_false(AudioMixGuard.tail_cannot_sleep(), "low-processor mode sleeps too")
	OS.low_processor_usage_mode = false
	Engine.max_fps = fps
	g.free()


func test_frame_tail_watchdog_trips_after_repeated_long_holds() -> void:
	var g := AudioMixGuard.new()
	g.mode = AudioMixGuard.Mode.FRAME_TAIL
	var fps := Engine.max_fps
	Engine.max_fps = 0
	for i in AudioMixGuard.WATCHDOG_STRIKES - 1:
		g._watch(AudioMixGuard.WATCHDOG_BUDGET_USEC + 1, i % 2 == 0)
	assert_false(g.tripped, "a few long holds are tolerated")
	g._on_frame_post_draw()
	assert_true(g.held)
	OS.delay_usec(AudioMixGuard.WATCHDOG_BUDGET_USEC + 500)  # one more long hold: the last strike
	g.release()
	assert_true(g.tripped, "off for the session")
	g._on_frame_post_draw()
	assert_false(g.held, "no more holds once tripped")
	var h := AudioMixGuard.new()
	h.mode = AudioMixGuard.Mode.FRAME_TAIL
	h._watch(AudioMixGuard.WATCHDOG_HARD_USEC + 1, false)
	assert_true(h.tripped, "one wait near an underrun trips at once")
	h.free()
	Engine.max_fps = fps
	g.free()


func test_headless_mode_ignores_the_watchdog() -> void:
	var g := AudioMixGuard.new()
	g.mode = AudioMixGuard.Mode.HEADLESS
	for i in AudioMixGuard.WATCHDOG_STRIKES * 2:
		g._watch(AudioMixGuard.WATCHDOG_BUDGET_USEC * 10, true)
	assert_false(g.tripped, "headless holds span a whole unthrottled frame by design")
	g._on_frame_post_draw()
	assert_false(g.held, "headless never locks on a draw")
	g.free()


static func _tone(seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(sin(TAU * 220.0 * i / rate) * 8000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s
