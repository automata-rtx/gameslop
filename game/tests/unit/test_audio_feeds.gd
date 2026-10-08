extends TestCase
## M2.14: the Null grid tone (03 §4: amplitude 1 - distance / radius, heard to 60 m, the
## 2 m core mutes everything but the tone), the heartbeat locked to the renderer's beat
## phase, Echo's footsteps with their extra reverb, occlusion decided at play time.

const BLOCK := 4800

var _cues: Array = []
var _scratch: Array[Node] = []
var _phase: float = 0.0


func before_each() -> void:
	_cues.clear()
	EventBus.audio_cue.connect(_on_cue)


func after_each() -> void:
	EventBus.audio_cue.disconnect(_on_cue)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	AudioManager.tick(0.1)
	AudioManager.feeds.heartbeat_phase_source = Callable()
	EventBus.threat_changed.emit(0.0)
	for n in _scratch:
		if is_instance_valid(n):
			n.queue_free()
	_scratch.clear()
	AudioManager.set_listener(null)
	EventBus.level_left.emit(true)
	AudioManager.tick(2.0)
	for p in AudioManager.pool.players_3d:
		p.stop()
	for p in AudioManager.pool.players_2d:
		p.stop()


func _on_cue(text: String, pos: Vector3) -> void:
	_cues.append([text, pos])


func _node3d(pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	_scratch.append(n)
	return n


func _rms(buf: PackedVector2Array, right: bool = false) -> float:
	var acc := 0.0
	for v in buf:
		var x := v.y if right else v.x
		acc += x * x
	return sqrt(acc / maxf(1.0, buf.size()))


func _level(t: NullTone, d: float, pan: float = 0.0) -> float:
	t.distance = d
	t.pan = pan
	t.render(BLOCK)
	var b := t.render(BLOCK)
	return (_rms(b) + _rms(b, true)) * 0.5


func test_null_amplitude_vs_distance() -> void:
	assert_approx(NullTone.amplitude(0.0), 1.0)
	assert_approx(NullTone.amplitude(30.0), 0.5)
	assert_approx(NullTone.amplitude(Tuning.AUDIO_NULL_MAX_DISTANCE), 0.0, 0.0001, "silent at 60 m")
	assert_eq(NullTone.amplitude(80.0), 0.0)
	assert_eq(NullTone.amplitude(INF), 0.0, "no Null, no tone")
	var t := NullTone.new(GeneratorLayers.MIX_RATE)
	var near := _level(t, 2.0)
	var mid := _level(t, 30.0)
	var far := _level(t, 54.0)
	assert_gt(near, 0.05, "loud near the core")
	assert_approx(mid / near, NullTone.amplitude(30.0) / NullTone.amplitude(2.0), 0.08, "rendered level follows 1 - d/60")
	assert_approx(far / near, NullTone.amplitude(54.0) / NullTone.amplitude(2.0), 0.03)
	assert_eq(_level(t, INF), 0.0)
	assert_true(t.is_silent())
	var right := NullTone.new(GeneratorLayers.MIX_RATE)
	right.distance = 5.0
	right.pan = 0.6
	right.render(BLOCK)
	var b := right.render(BLOCK)
	assert_gt(_rms(b, true), _rms(b) * 1.5, "panned toward the side Null is on")


func test_null_tone_spectrum_is_the_grid_chord() -> void:
	# Correlate one second against each partial: 55, 82.5 and 110 Hz carry the energy.
	var t := NullTone.new(GeneratorLayers.MIX_RATE)
	t.distance = 0.0
	t.render(BLOCK)
	var b := t.render(int(GeneratorLayers.MIX_RATE))
	for hz: float in [55.0, 82.5, 110.0, 70.0]:
		var re := 0.0
		var im := 0.0
		for i in b.size():
			var a := TAU * hz * float(i) / GeneratorLayers.MIX_RATE
			re += b[i].x * cos(a)
			im += b[i].x * sin(a)
		var mag := sqrt(re * re + im * im) / b.size()
		if hz == 70.0:
			assert_lt(mag, 0.01, "nothing between the partials")
		else:
			assert_gt(mag, 0.03, "%.1f Hz partial" % hz)


func test_audio_manager_feeds_the_null_tone_and_core_mute() -> void:
	AudioManager.set_listener(_node3d(Vector3.ZERO))
	CoherenceRenderer.set_null(Vector3(0, 0, -20), Tuning.NULL_UNRENDER_RADIUS)
	AudioManager.tick(0.05)
	assert_approx(AudioManager.null_distance(), 20.0, 0.001)
	assert_approx(AudioManager.bed.null_tone.target_gain(), 1.0 - 20.0 / 60.0, 0.001)
	assert_eq(AudioManager.bed.get_node("NullTone").bus, &"Master", "not under World's Substrate high-pass")
	assert_eq(_cues.size(), 1, "captioned once when it becomes audible")
	assert_eq(String(_cues[0][0]), "[grid tone, ahead]")
	AudioManager.tick(0.05)
	assert_eq(_cues.size(), 1)
	assert_false(AudioManager.in_null_core())
	CoherenceRenderer.set_null(Vector3(1, 0, 0), Tuning.NULL_UNRENDER_RADIUS)
	AudioManager.tick(0.05)
	assert_true(AudioManager.in_null_core(), "inside 2 m")
	for bus: StringName in [&"World", &"Player", &"Music"]:
		assert_approx(AudioManager.duck_db(bus), Tuning.AUDIO_SLIDER_MUTE_DB, 0.01, "%s muted in the core" % bus)
	assert_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Ambience")) \
		+ AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"World")), -80.0, 40.0, "room tone gone too")
	assert_approx(AudioManager.bed.null_tone.target_gain(), 1.0 - 1.0 / 60.0, 0.001, "the tone stays")
	CoherenceRenderer.set_null(Vector3(0, 0, -30), Tuning.NULL_UNRENDER_RADIUS)
	AudioManager.tick(0.05)
	assert_false(AudioManager.in_null_core())
	assert_approx(AudioManager.duck_db(&"World"), 0.0, 0.01, "released")
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	AudioManager.tick(0.05)
	assert_eq(AudioManager.null_distance(), INF, "no Null on the level")
	assert_eq(AudioManager.bed.null_tone.target_gain(), 0.0)


func test_heartbeat_locks_to_the_renderer_phase() -> void:
	AudioManager.feeds.heartbeat_phase_source = func() -> float: return _phase
	EventBus.threat_changed.emit(1.0)
	_phase = 0.0
	AudioManager.tick(0.016)
	var start := AudioManager.feeds.heartbeats
	for ph in [0.5, 0.9, 0.97, 0.02, 0.4, 0.8, 0.99, 0.01, 0.2]:
		_phase = ph
		AudioManager.tick(0.016)
	assert_eq(AudioManager.feeds.heartbeats - start, 2, "one beat per phase wrap, never on its own timer")
	EventBus.threat_changed.emit(0.0)
	for ph in [0.5, 0.99, 0.01]:
		_phase = ph
		AudioManager.tick(0.016)
	assert_eq(AudioManager.feeds.heartbeats - start, 2, "no threat, no heartbeat")
	# The default source is CoherenceRenderer.heartbeat_phase().
	AudioManager.feeds.heartbeat_phase_source = Callable()
	assert_approx(AudioManager.feeds._heartbeat_phase(), CoherenceRenderer.heartbeat_phase(), 0.0001)


func test_echo_steps_play_with_their_extra_reverb() -> void:
	AudioManager.set_listener(_node3d(Vector3.ZERO))
	var p := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 3), &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)
	assert_not_null(p)
	assert_eq(p.get_meta(AudioPool.META_ID), &"echo_foot_carpet", "the reverb variant on Errors")
	assert_eq(p.bus, &"Errors")
	assert_eq(_cues.size(), 1)
	assert_eq(String(_cues[0][0]), "[footsteps, behind, late]")
	var own := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 1))
	assert_eq(own.get_meta(AudioPool.META_ID), &"foot_carpet", "the player's own step is dry")
	assert_eq(own.bus, &"Footsteps")
	var e := AudioManager.library.entry(&"echo_foot_carpet")
	var f := AudioManager.library.entry(&"foot_carpet")
	assert_eq((e["files"] as Array).size(), (f["files"] as Array).size(), "the same variants")
	for i in (e["length_s"] as Array).size():
		assert_approx(float(e["length_s"][i]), float(f["length_s"][i]) + 0.3, 0.001, "plus a 0.3 s tail")


func test_occlusion_is_decided_at_play_time() -> void:
	AudioManager.set_listener(_node3d(Vector3.ZERO))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.4)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	_scratch.append(wall)
	wall.global_position = Vector3(0, 0, -5)
	await await_physics_frames(2)
	var p := AudioManager.play_3d(&"door_open", Vector3(0, 0, -10))
	assert_approx(p.attenuation_filter_cutoff_hz, Tuning.AUDIO_OCCLUSION_LOWPASS_HZ, 1.0, "muffled from the first sample")
	assert_approx(p.volume_db, Tuning.AUDIO_OCCLUSION_DB, 0.01)
	var near_wall := AudioManager.play_3d(&"door_close", Vector3(0, 0, -5.1))
	assert_approx(near_wall.attenuation_filter_cutoff_hz, AudioOcclusion.OPEN_CUTOFF_HZ, 1.0,
		"a sound inside its own surface is not occluded by it")
	var own := StaticBody3D.new()
	own.collision_layer = 1
	var s2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(1, 2, 1)
	s2.shape = b2
	own.add_child(s2)
	add_child(own)
	_scratch.append(own)
	own.global_position = Vector3(8, 0, 0)
	await await_physics_frames(2)
	var lp := AudioManager.loop(&"fan_loop", own)
	lp.player.position = Vector3(0.8, 0, 0)
	assert_false(AudioOcclusion.is_occluded(lp.player as AudioStreamPlayer3D, Vector3.ZERO), "its own body never occludes it")
	lp.release()


func test_echo_step_on_errors_bus_is_captioned_after_the_reverb_swap() -> void:
	var cues: Array[String] = []
	var cb := func(text: String, _pos: Vector3) -> void: cues.append(text)
	EventBus.audio_cue.connect(cb)
	AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, -6), &"Errors")
	EventBus.audio_cue.disconnect(cb)
	assert_eq(cues.size(), 1, "Echo's footstep keeps its caption (04 §10)")
