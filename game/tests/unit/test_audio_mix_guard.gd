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
