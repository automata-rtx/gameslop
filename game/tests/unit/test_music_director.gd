extends TestCase
## M2.14: MusicDirector (03 §5): chord palettes per stratum from the pad stems, layers
## follow Director intensity (the fourth voice and the low-pass above 0.6, the fourth
## leaving first), the Peak drop, the silence rules (silence(), Still within 8 m), the slow
## voice schedule, the title tremolo drone and the ending chord.

var _md: MusicDirector


func before_each() -> void:
	_md = MusicDirector.new()
	add_child(_md)
	_md.setup(AudioManager.library)


func after_each() -> void:
	_md.stop(0.01)
	_md.tick(0.1)
	_md.queue_free()
	_md = null
	var lp := AudioBuses.music_lowpass()
	if lp != null:
		lp.cutoff_hz = Tuning.MUSIC_LP_CLOSED_HZ


func _run(seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		_md.tick(step)
		t += step


func _index(role: StringName) -> int:
	for i in _md.voice_count():
		if _md.voice_role(i) == role:
			return i
	return -1


func _chord_gain() -> float:
	var g := 0.0
	for i in _md.voice_count():
		if _md.voice_role(i) == MusicVoice.ROLE_CHORD:
			g += _md.voice_gain(i)
	return g


func test_note_names_and_stems() -> void:
	assert_approx(MusicVoice.note_hz("A4"), 440.0, 0.001)
	assert_approx(MusicVoice.note_hz("A1"), 55.0, 0.001)
	assert_approx(MusicVoice.note_hz("Bb2"), 116.541, 0.01)
	assert_approx(MusicVoice.note_hz("C#4"), 277.183, 0.01)
	var stems := {&"music_pad_a1": {&"hz": 55.0}, &"music_pad_a2": {&"hz": 110.0}, &"music_pad_a3": {&"hz": 220.0}}
	assert_eq(MusicVoice.nearest_stem(MusicVoice.note_hz("G1"), stems), &"music_pad_a1")
	assert_eq(MusicVoice.nearest_stem(MusicVoice.note_hz("F2"), stems), &"music_pad_a2")
	assert_eq(MusicVoice.nearest_stem(MusicVoice.note_hz("B3"), stems), &"music_pad_a3")


func test_every_stratum_has_its_chord_and_a_fourth_voice() -> void:
	for s: StringName in Tuning.MUSIC_CHORDS:
		_md.set_stratum(s)
		var chord: Array = Tuning.MUSIC_CHORDS[s]
		var extra := 2 if s == &"substrate" else 1
		assert_eq(_md.voice_count(), chord.size() + extra, String(s))
		for i in chord.size():
			assert_approx(_md.voice_hz(i), MusicVoice.note_hz(String(chord[i])), 0.01, String(s))
		var root := MusicVoice.note_hz(String(chord[0]))
		assert_approx(_md.voice_hz(_index(MusicVoice.ROLE_FOURTH)), root * pow(2.0, 1.0 / 12.0), 0.01, "minor second above the root")
		for i in _md.voice_count():
			var semis := 12.0 * log(_md.voice_pitch(i)) / log(2.0)
			assert_true(absf(semis) <= 6.01, "%s voice %d pitched %.1f semitones from its stem" % [s, i, semis])
	_md.set_stratum(&"substrate")
	assert_approx(_md.voice_hz(_index(MusicVoice.ROLE_FIFTH)), 55.0 * pow(2.0, 7.0 / 12.0), 0.01, "A1's fifth")


func test_layers_follow_intensity() -> void:
	_md.set_stratum(&"halls")
	_md.set_phase(&"build")
	_md.set_intensity(0.3)
	_run(6.0)
	var fourth := _index(MusicVoice.ROLE_FOURTH)
	assert_approx(_chord_gain(), 3.0, 0.01, "the chord plays")
	assert_true(_md.voice_playing(0), "voices play on the Music bus")
	assert_eq(_md.voice_gain(fourth), 0.0, "no fourth voice below 0.6")
	assert_approx(_md.lowpass_hz(), Tuning.MUSIC_LP_CLOSED_HZ, 5.0, "LP 600 Hz")
	assert_approx(AudioBuses.music_lowpass().cutoff_hz, _md.lowpass_hz(), 1.0, "drives the bus filter")
	_md.set_intensity(0.7)
	_run(4.0)
	assert_approx(_md.voice_gain(fourth), 1.0, 0.001, "fourth voice in above 0.6")
	assert_gt(_md.lowpass_hz(), 1700.0, "LP opens toward 1.8 kHz")
	# Relief: intensity clamped to 0.5; the fourth voice drops out first.
	_md.set_phase(&"relief")
	_md.set_intensity(0.5)
	_run(1.0)
	assert_lt(_md.voice_gain(fourth), 1.0, "fourth fading")
	assert_gt(_md.lowpass_hz(), 1700.0, "the filter waits for the fourth voice")
	_run(6.0)
	assert_eq(_md.voice_gain(fourth), 0.0)
	assert_lt(_md.lowpass_hz(), 700.0, "then closes")
	assert_approx(_chord_gain(), 3.0, 0.01, "chord stays through relief")


func test_peak_drops_out_then_returns_with_the_fourth_only() -> void:
	_md.set_stratum(&"garage")
	_md.set_phase(&"build")
	_run(6.0)
	_md.set_intensity(0.9)
	_md.set_phase(&"peak")
	_run(1.0)
	assert_approx(_md.level(), 0.0, 0.0001, "silence is the loudest cue")
	assert_true(_md.is_cut())
	_run(3.5)
	assert_false(_md.is_cut(), "back after 4 s")
	_run(2.5)
	assert_approx(_md.voice_gain(_index(MusicVoice.ROLE_FOURTH)), 1.0, 0.001, "the fourth voice returns")
	assert_approx(_chord_gain(), 0.0, 0.0001, "alone")


func test_silence_and_still_rules() -> void:
	_md.set_stratum(&"offices")
	_md.set_phase(&"build")
	_run(6.0)
	_md.silence(Tuning.FLICKER_DARK_TIME)
	_run(0.2)
	assert_approx(_md.level(), 0.0, 0.0001, "Flicker lunge: total silence")
	_run(1.5)
	_run(3.0)
	assert_approx(_chord_gain(), 3.0, 0.01, "returns after the silence")
	EventBus.error_proximity.emit(&"still", 5.0)
	_run(0.2)
	assert_approx(_md.level(), 0.0, 0.0001, "Still within 8 m: the drone goes quiet")
	_run(5.0)
	assert_approx(_md.level(), 0.0, 0.0001, "for as long as it is near")
	EventBus.error_proximity.emit(&"still", 12.0)
	_run(3.0)
	assert_approx(_chord_gain(), 3.0, 0.01, "and comes back")
	EventBus.level_left.emit(true)


func test_voices_change_on_a_slow_schedule_and_the_root_holds() -> void:
	_md.set_stratum(&"pools", 3)
	_md.set_phase(&"build")
	var changes := 0
	var last: Array = []
	for i in _md.voice_count():
		last.append(_md.voice_target(i))
	for k in 400:
		_md.tick(0.5)
		assert_eq(_md.voice_target(0), 1.0, "the root holds the key")
		for i in 3:
			if _md.voice_target(i) != last[i]:
				changes += 1
				last[i] = _md.voice_target(i)
	# 200 s at one change every 20 to 45 s.
	assert_true(changes >= 4 and changes <= 10, "%d voice changes in 200 s" % changes)


func test_substrate_fifth_with_the_threshold_in_view() -> void:
	_md.set_stratum(&"substrate")
	_md.set_phase(&"pursuit")
	_run(6.0)
	var fifth := _index(MusicVoice.ROLE_FIFTH)
	assert_eq(_md.voice_gain(fifth), 0.0, "A1 only")
	_md.set_threshold_in_view(true)
	_run(5.0)
	assert_approx(_md.voice_gain(fifth), 1.0, 0.001, "its fifth appears")


func test_title_and_ending() -> void:
	_md.play_title()
	assert_eq(_md.mode, MusicDirector.MODE_TITLE)
	_run(6.0)
	assert_approx(_chord_gain(), 3.0, 0.01, "the Halls drone")
	assert_eq(_md.voice_count(), 4)
	_md.play_ending()
	_run(2.0)
	assert_approx(_md.ending_gain(), 0.5, 0.05, "the A major triad fades in")
	_run(3.0)
	assert_approx(_chord_gain(), 0.0, 0.0001, "the drone is gone")
	_run(36.0, 0.5)
	assert_eq(_md.ending_gain(), 0.0, "40 s, then silence")


func test_director_feeds_the_music_director() -> void:
	assert_true(AudioManager.has_node(^"MusicDirector"), "a child of AudioManager")
	assert_eq(AudioManager.music, AudioManager.get_node(^"MusicDirector"))
	var src := FileAccess.get_file_as_string("res://src/director/director.gd")
	assert_true(src.contains("call(&\"set_intensity\", pacing.intensity)"), "10 §6: the Director calls set_intensity")
	AudioManager.music.set_intensity(0.8)
	assert_approx(AudioManager.music.intensity, 0.8)
	AudioManager.silence(&"World", 0.5)
	assert_true(AudioManager.music.is_cut(), "a total silence() cuts the drone too")
	AudioManager.music.tick(1.0)
	AudioManager.music.stop(0.01)
	AudioManager.tick(1.0)
