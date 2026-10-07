extends TestCase
## M1.11a: AudioManager (03 §3, §6, Interfaces) headless on the dummy audio driver: the bus
## tree, playback by manifest id, the pool of 32, missing ids, ducking and the room-tone
## floor, reverb per stratum on level_entered, loops, occlusion, and captions.

var _cues: Array = []
var _scratch: Array[Node] = []


func before_each() -> void:
	_cues.clear()
	EventBus.audio_cue.connect(_on_cue)


func after_each() -> void:
	EventBus.audio_cue.disconnect(_on_cue)
	for n in _scratch:
		if is_instance_valid(n):
			n.queue_free()
	_scratch.clear()
	AudioManager.set_listener(null)
	EventBus.level_left.emit(true)          # clears holds and proximity
	AudioManager.tick(2.0)                  # expires timed ducks
	for p in AudioManager.pool.players_3d:
		p.stop()
	for p in AudioManager.pool.players_2d:
		p.stop()


func after_all() -> void:
	AudioManager.stop_all()
	AudioManager.set_coherence(100.0)
	await await_frames(3)  # the audio server drops stopped playbacks on its next mix


func _on_cue(text: String, pos: Vector3) -> void:
	_cues.append([text, pos])


func _node3d(pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	_scratch.append(n)
	return n


func test_bus_tree_matches_03() -> void:
	assert_true(AudioBuses.is_complete(), "03 §3 buses and effects")
	for i in Tuning.AUDIO_BUSES.size():
		assert_eq(AudioServer.get_bus_name(i), String(Tuning.AUDIO_BUSES[i]))
	for bus: StringName in AudioBuses.PARENT:
		assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)), AudioBuses.PARENT[bus], "%s send" % bus)
	var master := AudioServer.get_bus_effect(0, AudioBuses.MASTER_LIMITER) as AudioEffectHardLimiter
	assert_approx(master.ceiling_db, -1.0, 0.001, "limiter on Master at -1 dBFS")
	var errors := AudioServer.get_bus_effect(AudioServer.get_bus_index(&"Errors"), 0) as AudioEffectHardLimiter
	assert_approx(errors.ceiling_db, -6.0, 0.001, "rule 2: Errors never above -6 dBFS")
	var shelf := AudioServer.get_bus_effect(AudioServer.get_bus_index(&"Player"), 0) as AudioEffectLowShelfFilter
	assert_approx(shelf.cutoff_hz, 90.0, 0.01)
	assert_approx(linear_to_db(shelf.gain), 2.0, 0.01, "+2 dB low shelf on Player")
	assert_not_null(AudioBuses.reverb(), "one reverb on World")


func test_layout_file_is_the_project_default() -> void:
	assert_eq(ProjectSettings.get_setting("audio/buses/default_bus_layout"), "res://default_bus_layout.tres")
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout, "game/default_bus_layout.tres loads")


func test_plays_known_ids_headless() -> void:
	var p := AudioManager.play_2d(&"ui_confirm")
	assert_not_null(p)
	assert_true(p.playing, "playing on the dummy driver")
	assert_eq(p.bus, &"UI")
	var r := p.stream as AudioStreamRandomizer
	assert_not_null(r, "rule 5: one-shots through AudioStreamRandomizer")
	assert_approx(r.random_pitch, 1.04, 0.0001, "+-4% pitch")
	assert_eq(r.streams_count, 3, "the variation set")
	var p3 := AudioManager.play_3d(&"door_open", Vector3(2, 0, -3))
	assert_not_null(p3)
	assert_true(p3.playing)
	assert_eq(p3.bus, &"Interact", "manifest bus when none is given")
	assert_eq(p3.attenuation_model, AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE)
	assert_eq(p3.doppler_tracking, AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED)
	assert_approx(p3.unit_size, 1.0)
	var echo := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 4), &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)
	assert_eq(echo.bus, &"Errors", "explicit bus wins")
	assert_approx(echo.volume_db, -3.0, 0.001)


func test_pulse_players_run_through_pause() -> void:
	assert_eq(AudioManager.process_mode, Node.PROCESS_MODE_ALWAYS)
	var p := AudioManager.pool.players_2d[0]
	assert_eq(p.get_parent().process_mode, Node.PROCESS_MODE_ALWAYS, "UI and Player one-shots during pause")
	var w := AudioManager.pool.players_3d[0]
	assert_eq(w.get_parent().process_mode, Node.PROCESS_MODE_PAUSABLE, "world sounds freeze with the world")


func test_pool_reuse_never_exceeds_32() -> void:
	var seen := {}
	for i in 50:
		var p := AudioManager.play_3d(&"foot_tile", Vector3(i, 0, 0))
		assert_not_null(p)
		seen[p.get_instance_id()] = true
	assert_eq(AudioManager.pool.players_3d.size(), 32)
	assert_eq(seen.size(), 32, "50 plays reuse the same 32 players")
	assert_true(AudioManager.pool.active_3d() <= 32)
	var under := AudioManager.get_node("Pool3D").get_child_count()
	assert_eq(under, 32, "no players created beyond the pool")


func test_missing_id_is_silent_and_does_not_crash() -> void:
	assert_null(AudioManager.play_2d(&"no_such_sound"))
	assert_null(AudioManager.play_3d(&"no_such_sound", Vector3.ZERO))
	var h := AudioManager.loop(&"no_such_loop")
	assert_false(h.is_valid())
	h.start()
	h.set_pitch01(0.5)
	h.set_volume(-3.0)
	h.stop(0.5)
	h.release()
	assert_null(AudioManager.start_loop(&"no_such_loop", _node3d()))
	assert_null(AudioManager.play_2d(&"crank_whine"), "a loop is not a one-shot")


func test_missing_file_in_manifest_is_silent() -> void:
	var path := "user://test_audio_manifest.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"sounds": {"ghost": {"bus": "UI", "loop": false,
		"files": ["res://assets/audio/ui/ghost_v01.wav"]}}}))
	f.close()
	var lib := SoundLibrary.new(path)
	assert_true(lib.has(&"ghost"))
	assert_null(lib.stream(&"ghost"), "14 §12: missing file -> silent")
	assert_null(lib.stream(&"ghost"), "asked twice, still null, reported once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_slider_and_duck_math() -> void:
	assert_eq(AudioMix.slider_db(0.0), -80.0)
	assert_approx(AudioMix.slider_db(100.0), 0.0)
	assert_approx(AudioMix.slider_db(50.0), -6.0206, 0.001)
	var ducks := [
		{&"bus": &"Ambience", &"db": -4.0, &"until": INF},
		{&"bus": &"Ambience", &"db": -6.0, &"until": 5.0},
		{&"bus": &"Music", &"db": -6.0, &"until": INF},
	]
	assert_approx(AudioMix.bus_duck_db(ducks, &"Ambience", 1.0), -10.0)
	assert_approx(AudioMix.bus_duck_db(ducks, &"Ambience", 5.0), -4.0, 0.0001, "expired at its time")
	assert_approx(AudioMix.bus_duck_db(ducks, &"Player", 1.0), 0.0)
	# Rule 3 with a room tone rendered at -30 dB: -40 floor, -46 in Still's silence.
	assert_approx(AudioMix.clamp_ambience(-14.0, -30.0, AudioMix.Floor.NORMAL), -10.0)
	assert_approx(AudioMix.clamp_ambience(-14.0, -30.0, AudioMix.Floor.STILL), -14.0)
	assert_approx(AudioMix.clamp_ambience(-20.0, -30.0, AudioMix.Floor.STILL), -16.0)
	assert_approx(AudioMix.clamp_ambience(-80.0, -30.0, AudioMix.Floor.MUTE), -80.0, 0.0001, "Flicker's lunge")
	assert_approx(AudioMix.clamp_ambience(-4.0, -30.0, AudioMix.Floor.NORMAL), -4.0, 0.0001, "above the floor: untouched")


func test_ducker_timing_and_floor_counts_world() -> void:
	var d := AudioDucker.new()
	d.room_tone_db = -30.0
	d.duck(&"World", -8.0, 0.3)
	assert_approx(d.duck_db(&"World"), -8.0)
	d.advance(0.2)
	assert_approx(d.duck_db(&"World"), -8.0, 0.0001, "still inside 300 ms")
	d.hold(&"errors_near", &"Ambience", -4.0)
	# Ambience -4 inside World -8 puts the room tone at -42: clamped to -40 overall.
	assert_approx(d.duck_db(&"Ambience") + d.duck_db(&"World"), -10.0)
	d.hold(&"still", &"Ambience", -6.0)
	assert_approx(d.duck_db(&"Ambience", &"still") + d.duck_db(&"World"), -16.0, 0.0001, "-46 dB floor in the silence")
	d.advance(0.2)
	assert_approx(d.duck_db(&"World"), 0.0, 0.0001, "the noclip duck ended")
	assert_approx(d.duck_db(&"Ambience", &"still"), -10.0)
	d.release(&"still")
	d.release(&"errors_near")
	assert_approx(d.duck_db(&"Ambience"), 0.0)
	d.silence(&"Ambience", 1.5)
	assert_approx(d.duck_db(&"Ambience"), -80.0, 0.0001, "silence passes the floor")
	d.advance(1.6)
	assert_approx(d.duck_db(&"Ambience"), 0.0)


func test_noclip_commit_ducks_everything_but_player_and_captions() -> void:
	AudioManager.play_2d(&"noclip_commit")
	for bus in [&"World", &"Music", &"UI"]:
		assert_approx(AudioManager.duck_db(bus), -8.0, 0.0001, "%s ducked" % bus)
	assert_approx(AudioManager.duck_db(&"Player"), 0.0, 0.0001, "Player is never ducked by its own commit")
	assert_eq(_cues.size(), 1)
	assert_eq(String(_cues[0][0]), Strings.CAPTION_NOCLIP_COMMIT)
	AudioManager.tick(0.31)
	assert_approx(AudioManager.duck_db(&"World"), 0.0, 0.0001, "300 ms")


func test_error_proximity_ducks_ambience_and_still_silence() -> void:
	EventBus.level_entered.emit(1, &"halls", &"start")
	EventBus.error_proximity.emit(&"echo", 9.0)
	assert_approx(AudioManager.duck_db(&"Ambience"), -4.0, 0.0001, "an error within 10 m")
	EventBus.error_proximity.emit(&"still", 5.0)
	assert_approx(AudioManager.duck_db(&"Ambience"), -10.0, 0.0001, "plus Still's -6 dB")
	assert_eq(_cues.size(), 1)
	assert_eq(String(_cues[0][0]), Strings.CAPTION_STILL_SILENCE)
	EventBus.error_proximity.emit(&"still", 5.0)
	assert_eq(_cues.size(), 1, "one caption per silence")
	EventBus.error_proximity.emit(&"still", 12.0)
	EventBus.error_proximity.emit(&"echo", 15.0)
	assert_approx(AudioManager.duck_db(&"Ambience"), 0.0, 0.0001, "released")
	EventBus.note_found.emit(&"H1")
	assert_approx(AudioManager.duck_db(&"Music"), -6.0, 0.0001, "note pickup ducks Music")
	AudioManager.release_duck(AudioManager.DUCK_NOTE)
	assert_approx(AudioManager.duck_db(&"Music"), 0.0)


func test_reverb_switches_on_level_entered() -> void:
	EventBus.level_entered.emit(2, &"pools", &"proper")
	assert_eq(AudioManager.stratum(), &"pools")
	AudioManager.tick(Tuning.AUDIO_REVERB_CROSSFADE + 0.05)
	var r := AudioBuses.reverb()
	assert_approx(r.room_size, 0.9, 0.001)
	assert_approx(r.damping, 0.2, 0.001)
	assert_approx(r.wet, 0.45, 0.001)
	assert_approx(r.predelay_msec, 40.0, 0.01)
	EventBus.level_entered.emit(6, &"substrate", &"drop")
	AudioManager.tick(Tuning.AUDIO_REVERB_CROSSFADE * 0.5)
	assert_approx(r.room_size, 0.95, 0.001, "halfway through the 1 s crossfade")
	AudioManager.tick(Tuning.AUDIO_REVERB_CROSSFADE)
	assert_approx(r.room_size, 1.0, 0.001)
	assert_approx(r.wet, 0.5, 0.001)
	var world := AudioServer.get_bus_index(&"World")
	assert_true(AudioServer.is_bus_effect_enabled(world, AudioBuses.WORLD_HIGHPASS), "Substrate high-pass")
	assert_approx(AudioBuses.highpass().cutoff_hz, 300.0)
	EventBus.level_entered.emit(1, &"halls", &"start")
	AudioManager.tick(Tuning.AUDIO_REVERB_CROSSFADE + 0.05)
	assert_false(AudioServer.is_bus_effect_enabled(world, AudioBuses.WORLD_HIGHPASS))
	assert_approx(r.room_size, 0.5, 0.001)
	assert_approx(r.wet, 0.2, 0.001)


func test_level_entered_starts_the_room_tone() -> void:
	EventBus.level_entered.emit(1, &"garage", &"start")
	EventBus.level_entered.emit(1, &"halls", &"start")
	var found := false
	for p in AudioManager.get_node("Loops").get_children():
		if p.get_meta(AudioPool.META_ID, &"") == &"room_tone_halls" and p.playing:
			found = true
			assert_eq(p.bus, &"Ambience")
	assert_true(found, "Halls room tone plays")


func test_step_noise_plays_the_surface_footstep() -> void:
	EventBus.level_entered.emit(1, &"halls", &"start")
	assert_eq(AudioManager.step_surface(), &"carpet", "Halls walks on carpet")
	AudioManager.set_step_surface(&"tile")
	EventBus.noise_emitted.emit(Vector3(1, 0, 1), 7.0, Tuning.NOISE_KIND_STEP)
	var p := _latest(&"foot_tile")
	assert_not_null(p, "a step noise is its sound")
	assert_approx(p.volume_db, 0.0, 0.001, "rule 1: walk steps at their rendered level")
	EventBus.noise_emitted.emit(Vector3(1, 0, 1), 7.0 * Tuning.NOISE_SPRINT_MULT, Tuning.NOISE_KIND_STEP)
	assert_approx(_latest(&"foot_tile").volume_db, linear_to_db(Tuning.NOISE_SPRINT_MULT), 0.001, "sprint is louder")
	var before := AudioManager.pool.active_3d()
	EventBus.noise_emitted.emit(Vector3.ZERO, 12.0, Tuning.NOISE_KIND_MECH)
	assert_eq(AudioManager.pool.active_3d(), before, "other kinds are played by their emitter")


func _latest(id: StringName) -> AudioStreamPlayer3D:
	var best: AudioStreamPlayer3D = null
	for p in AudioManager.pool.players_3d:
		if p.playing and p.get_meta(AudioPool.META_ID, &"") == id:
			if best == null or float(p.get_meta(AudioPool.META_STARTED)) >= float(best.get_meta(AudioPool.META_STARTED)):
				best = p
	return best


func test_loop_handles() -> void:
	var whine := AudioManager.loop(&"crank_whine")
	assert_true(whine.is_valid())
	whine.start()
	assert_true(whine.is_playing())
	assert_eq(whine.player.get(&"bus"), &"Player")
	whine.set_pitch01(0.0)
	assert_approx(whine.get_pitch(), 0.4444, 0.0001, "200 Hz")
	whine.set_pitch01(1.0)
	assert_approx(whine.get_pitch(), 2.0, 0.0001, "900 Hz")
	whine.set_volume(-6.0)
	assert_approx(float(whine.player.get(&"volume_db")), -6.0, 0.001)
	whine.stop()
	assert_false(whine.is_playing())
	whine.release()
	assert_false(whine.is_valid())


func test_positional_loop_captions_and_hears_through_walls() -> void:
	AudioManager.set_listener(_node3d(Vector3.ZERO))
	var emitter := _node3d(Vector3(10, 0, 0))
	var p := AudioManager.start_loop(&"static_hum", emitter)
	assert_not_null(p)
	assert_true(p.playing)
	assert_eq(p.get_parent(), emitter, "moves with the emitter")
	assert_approx(p.max_distance, 40.0)
	assert_false(AudioOcclusion.wants_check(p), "Static ignores occlusion")
	assert_eq(_cues.size(), 1)
	assert_eq(String(_cues[0][0]), "[hum, right]")


func test_occluded_emitter_is_muffled() -> void:
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
	assert_true(AudioOcclusion.wants_check(p))
	assert_true(AudioOcclusion.is_occluded(p, Vector3.ZERO), "wall between")
	var open := AudioManager.play_3d(&"door_close", Vector3(10, 0, 0))
	assert_false(AudioOcclusion.is_occluded(open, Vector3.ZERO), "clear line")
	AudioOcclusion.set_occluded(p, true)
	await Clock.wall_timer(0.15).timeout
	assert_approx(p.attenuation_filter_cutoff_hz, 800.0, 1.0, "low-pass 800 Hz")
	assert_approx(p.volume_db, -6.0, 0.01, "-6 dB")


func test_captions_follow_the_listener() -> void:
	var l := Transform3D.IDENTITY  # at the origin, facing -Z
	assert_eq(AudioMix.format_caption(Strings.CAPTION_DOOR_SLAM, l, Vector3(0, 0, -10)), "[door slams, ahead]")
	assert_eq(AudioMix.format_caption(Strings.CAPTION_DOOR_SLAM, l, Vector3(30, 0, 0)), "[door slams, right, far]")
	assert_eq(AudioMix.format_caption(Strings.CAPTION_STATIC, l, Vector3(0, 0, 3)), "[hum, behind, near]")
	assert_eq(AudioMix.format_caption(Strings.CAPTION_STATIC, l, Vector3(-8, 0, -8)), "[hum, ahead left]")
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)  # facing -X
	assert_eq(AudioMix.format_caption(Strings.CAPTION_NULL, turned, Vector3(-10, 0, 0)), "[grid tone, ahead]")


func test_power_wave_is_one_caption_with_hashed_pitch() -> void:
	for i in 4:
		AudioManager.play_3d(&"power_wave_ignite", Vector3(i * 4.0, 2.8, 0))
	assert_eq(_cues.size(), 1, "one [lights waking] per wave")
	assert_eq(String(_cues[0][0]), Strings.CAPTION_POWER_WAVE)
	var a := AudioMix.hashed_pitch(Vector3(4, 2.8, 0), 0.05)
	assert_eq(a, AudioMix.hashed_pitch(Vector3(4, 2.8, 0), 0.05), "deterministic")
	assert_true(a >= 0.95 and a <= 1.05, "+-5%")


func test_settings_slider_sets_bus_volume() -> void:
	EventBus.settings_changed.emit(&"audio_music", 50)
	var i := AudioServer.get_bus_index(&"Music")
	assert_approx(AudioServer.get_bus_volume_db(i), -6.0206, 0.01)
	EventBus.settings_changed.emit(&"audio_effects", 0)
	assert_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Player")), -80.0, 0.01, "Player follows Effects")
	EventBus.settings_changed.emit(&"audio_music", Tuning.SETTINGS_AUDIO_MUSIC_DEFAULT)
	EventBus.settings_changed.emit(&"audio_effects", Tuning.SETTINGS_AUDIO_EFFECTS_DEFAULT)


func test_heartbeat_rate() -> void:
	assert_approx(AudioMix.heartbeat_bpm(0.0, 100.0), 60.0)
	assert_approx(AudioMix.heartbeat_bpm(1.0, 100.0), 140.0)
	assert_approx(AudioMix.heartbeat_bpm(0.0, 20.0), 90.0, 0.0001, "danger floor")
	assert_eq(AudioMix.heartbeat_level(0.0, 100.0), 0.0, "no threat, no heartbeat")
