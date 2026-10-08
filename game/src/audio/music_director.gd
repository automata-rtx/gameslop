class_name MusicDirector
extends Node
## The generative drone (03 §5), a child of AudioManager (`AudioManager.music`). No
## composed music: per stratum a three-voice chord of synthesized pads (Tuning.MUSIC_CHORDS)
## whose voices fade in and out on a slow random schedule, each voice cycling its three
## 12 s stem variations with 2 s crossfades so the drone never loops audibly.
##
## Pads are rendered at A1, A2 and A3 (music_pad_a1/a2/a3, manifest runtime.note_hz); each
## voice plays the nearest stem with pitch_scale (at most 6 semitones). The Music bus
## low-pass (AudioBuses.music_lowpass) is the live filter: 600 Hz, 1.8 kHz above
## intensity 0.6.
##
## Rules (03 §5, 10 §2, 10 §6):
## - intensity > 0.6: the low-pass opens and a fourth voice a minor second above the root
##   fades in at -10 dB. Going down, the fourth voice drops out first; the filter closes
##   only once it is gone (so at Relief the fourth leaves first).
## - Peak (a chase): everything drops out for 4 s, then the fourth voice alone returns.
## - Silence is the loudest cue: Still within 8 m holds the drone silent (the room goes
##   quiet, 08 §4) and silence(seconds) cuts it (Flicker's lunge, 1.5 s, via
##   AudioManager.silence). A note pickup ducks the Music bus (AudioManager, 03 §3).
## - Substrate: A1 alone; its 5th joins while the Threshold is in view
##   (set_threshold_in_view). Pursuit holds intensity >= 0.6, so the fourth voice plays.
## - Title: the Halls drone with a 0.2 Hz tremolo. Ending: music_ending (A major) for 40 s.
## Fed by the Director (set_intensity, 10 §6) and EventBus (director_phase, threat_changed
## as a fallback intensity where no Director feeds it, level_entered/left, error_proximity);
## never reads the player.

const STEM_IDS: Array[StringName] = [&"music_pad_a1", &"music_pad_a2", &"music_pad_a3"]
const ENDING_ID := &"music_ending"
const TITLE_SCENE := "res://scenes/title.tscn"
const ENDING_SCENE_SUFFIX := "ending.tscn"
const MODE_OFF := &"off"
const MODE_TITLE := &"title"
const MODE_LEVEL := &"level"
const MODE_ENDING := &"ending"
const ROLE_CHORD := MusicVoice.ROLE_CHORD
const ROLE_FOURTH := MusicVoice.ROLE_FOURTH
const ROLE_FIFTH := MusicVoice.ROLE_FIFTH
## Fades (presentation timing; 03 gives none): a voice change, the fourth voice, the 03 §5
## Peak drop, a silence cut, the return after a cut, and stop().
const VOICE_FADE_S := 4.0
const FOURTH_FADE_S := 2.0
const DROP_FADE_S := 0.3
const CUT_FADE_S := 0.05
const RETURN_FADE_S := 2.0
const LP_SMOOTH_S := 0.5
const TITLE_TREMOLO_DEPTH := 0.35
const ENDING_FADE_IN_S := 4.0
const ENDING_FADE_OUT_S := 6.0
const FLOOR_GAIN := MusicVoice.FLOOR_GAIN

var mode: StringName = MODE_OFF
var stratum: StringName = &""
var intensity: float = 0.0
var phase: StringName = &""
var threshold_in_view: bool = false
var still_near: bool = false
var _fed: bool = false            # set_intensity was called on this level
var _library: SoundLibrary
var _stems: Dictionary = {}       # stem id -> {hz, streams: Array[AudioStream]}
var _voices: Array[MusicVoice] = []
var _on: Array[bool] = []         # chord voices on in the schedule
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _change_left: float = 0.0
var _cut_left: float = 0.0
var _drop_left: float = 0.0
var _return_left: float = 0.0
var _stop_fade: float = 2.0
var _lp_hz: float = Tuning.MUSIC_LP_CLOSED_HZ
var _ending: AudioStreamPlayer
var _ending_t: float = -1.0


func setup(library: SoundLibrary) -> void:
	_library = library
	_stems.clear()
	for id in STEM_IDS:
		var streams := _load_streams(id)
		if not streams.is_empty():
			_stems[id] = {&"hz": float(library.runtime(id).get("note_hz", 0.0)), &"streams": streams}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ending = AudioStreamPlayer.new()
	_ending.name = "Ending"
	_ending.bus = &"Music"
	add_child(_ending)
	EventBus.level_entered.connect(_on_level_entered)
	EventBus.level_left.connect(func(_proper: bool) -> void: stop())
	EventBus.run_ended.connect(func(_cause: StringName, _score: int) -> void: stop())
	EventBus.director_phase.connect(set_phase)
	EventBus.threat_changed.connect(_on_threat)
	EventBus.error_proximity.connect(_on_error_proximity)
	_connect_router.call_deferred()


func _connect_router() -> void:
	var router := get_node_or_null(^"/root/SceneRouter")
	if router != null and router.has_signal(&"scene_changed"):
		router.connect(&"scene_changed", _on_scene_changed)


func _process(delta: float) -> void:
	tick(delta)


# --------------------------------------------------------------------------- interface

## 03 Interfaces: Director intensity 0..1 (10 §6, called at 10 Hz).
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	_fed = true


## 03 Interfaces: the chord palette for a stratum; starts the level drone.
func set_stratum(s: StringName, seed_value: int = 0) -> void:
	stratum = s
	mode = MODE_LEVEL
	_build_voices(s, Tuning.MUSIC_CHORDS.get(s, Tuning.MUSIC_CHORDS[&"halls"]))
	_rng.seed = hash(String(s)) ^ seed_value
	_change_left = _next_change()
	_stop_ending()


## 03 Interfaces: total silence for `seconds` (Flicker's lunge), then a 2 s return.
func silence(seconds: float) -> void:
	_cut_left = maxf(_cut_left, seconds)


func set_phase(p: StringName) -> void:
	if p == phase:
		return
	if p == &"peak":
		_drop_left = Tuning.MUSIC_PEAK_SILENCE_TIME
	phase = p


func set_still_near(on: bool) -> void:
	still_near = on


## Substrate: A1's fifth joins while the Threshold is in view (03 §5).
func set_threshold_in_view(on: bool) -> void:
	threshold_in_view = on


## The title drone: Halls with a 0.2 Hz tremolo.
func play_title() -> void:
	set_stratum(&"halls")
	mode = MODE_TITLE
	phase = &""
	intensity = 0.0


## The ending corridor: the A major triad for 40 s, the drone fades out.
func play_ending() -> void:
	mode = MODE_ENDING
	_stop_fade = RETURN_FADE_S
	var s := _load_streams(ENDING_ID) if _library != null else []
	if s.is_empty():
		return
	_ending.stream = s[0]
	_ending.volume_db = linear_to_db(FLOOR_GAIN)
	_ending.play()
	_ending_t = 0.0


## Fades everything out over `fade_s`.
func stop(fade_s: float = 2.0) -> void:
	mode = MODE_OFF
	_stop_fade = maxf(fade_s, 0.01)
	threshold_in_view = false
	still_near = false


# --------------------------------------------------------------------------- readouts

func voice_count() -> int:
	return _voices.size()


func voice_role(i: int) -> StringName:
	return _voices[i].role


func voice_hz(i: int) -> float:
	return _voices[i].hz


func voice_pitch(i: int) -> float:
	return _voices[i].pitch


func voice_gain(i: int) -> float:
	return _voices[i].gain


func voice_target(i: int) -> float:
	return _voices[i].target


func voice_playing(i: int) -> bool:
	return _voices[i].is_playing()


## Sum of voice gains (0 = the drone is silent).
func level() -> float:
	var t := 0.0
	for v in _voices:
		t += v.gain
	return t


func lowpass_hz() -> float:
	return _lp_hz


func ending_gain() -> float:
	return db_to_linear(_ending.volume_db) if _ending != null and _ending.playing else 0.0


func is_cut() -> bool:
	return _cut_left > 0.0 or _drop_left > 0.0 or (still_near and mode == MODE_LEVEL)


# --------------------------------------------------------------------------- tick

## Advances fades, the schedule, the crossfades and the filter. _process calls it; tests
## drive it directly.
func tick(delta: float) -> void:
	_clock += delta
	var was_cut := is_cut()
	_cut_left = maxf(0.0, _cut_left - delta)
	_drop_left = maxf(0.0, _drop_left - delta)
	if was_cut and not is_cut():
		_return_left = RETURN_FADE_S
	_return_left = maxf(0.0, _return_left - delta)
	_schedule(delta)
	var bright := mode == MODE_LEVEL and intensity > Tuning.MUSIC_INTENSITY_OPEN
	var fourth_gain := 0.0
	var trem := 1.0
	if mode == MODE_TITLE:
		trem = 1.0 - TITLE_TREMOLO_DEPTH * (0.5 + 0.5 * sin(TAU * Tuning.MUSIC_TITLE_TREMOLO_HZ * _clock))
	for v in _voices:
		v.target = _target_for(v, bright)
		var fade := _fade_for(v)
		var step := delta / maxf(fade, 0.001)
		v.gain = move_toward(v.gain, v.target, step)
		if v.role == ROLE_FOURTH:
			fourth_gain = v.gain
		v.drive(delta, _rng, trem)
	var open := bright or fourth_gain > 0.05
	var lp_target := Tuning.MUSIC_LP_OPEN_HZ if open else Tuning.MUSIC_LP_CLOSED_HZ
	var k := 1.0 - exp(-delta / LP_SMOOTH_S)
	_lp_hz = exp(lerpf(log(_lp_hz), log(lp_target), k))
	var lp := AudioBuses.music_lowpass()
	if lp != null and absf(lp.cutoff_hz - _lp_hz) > 0.5:
		lp.cutoff_hz = _lp_hz
	_tick_ending(delta)


func _target_for(v: MusicVoice, bright: bool) -> float:
	match mode:
		MODE_TITLE:
			return 1.0 if v.role == ROLE_CHORD else 0.0
		MODE_LEVEL:
			if is_cut():
				return 0.0
			if phase == &"peak":
				return 1.0 if v.role == ROLE_FOURTH else 0.0
			match v.role:
				ROLE_FOURTH:
					return 1.0 if bright else 0.0
				ROLE_FIFTH:
					return 1.0 if threshold_in_view else 0.0
				_:
					var i := _voices.find(v)
					return 1.0 if i < _on.size() and _on[i] else 0.0
	return 0.0


func _fade_for(v: MusicVoice) -> float:
	if mode == MODE_OFF or mode == MODE_ENDING:
		return _stop_fade
	if mode == MODE_LEVEL and is_cut():
		return CUT_FADE_S if _cut_left > 0.0 or still_near else DROP_FADE_S
	if _return_left > 0.0:
		return RETURN_FADE_S
	return FOURTH_FADE_S if v.role == ROLE_FOURTH else VOICE_FADE_S


## 03 §5: one voice change every 20 to 45 s; the root always holds the key.
func _schedule(delta: float) -> void:
	if mode != MODE_LEVEL or _on.size() < 2:
		return
	_change_left -= delta
	if _change_left > 0.0:
		return
	_change_left = _next_change()
	var i := _rng.randi_range(1, _on.size() - 1)
	_on[i] = not _on[i]


func _next_change() -> float:
	return _rng.randf_range(Tuning.MUSIC_VOICE_CHANGE_MIN, Tuning.MUSIC_VOICE_CHANGE_MAX)


func _tick_ending(delta: float) -> void:
	if _ending_t < 0.0:
		return
	_ending_t += delta
	var total := Tuning.MUSIC_ENDING_TIME
	if _ending_t >= total or mode != MODE_ENDING:
		_stop_ending()
		return
	var g := minf(1.0, _ending_t / ENDING_FADE_IN_S) * minf(1.0, (total - _ending_t) / ENDING_FADE_OUT_S)
	_ending.volume_db = linear_to_db(maxf(g, FLOOR_GAIN))


func _stop_ending() -> void:
	_ending_t = -1.0
	if _ending != null and _ending.playing:
		_ending.stop()


# --------------------------------------------------------------------------- voices

func _build_voices(s: StringName, chord: Array) -> void:
	_clear_voices()
	var root := MusicVoice.note_hz(String(chord[0]))
	for n: Variant in chord:
		_add_voice(MusicVoice.note_hz(String(n)), ROLE_CHORD, 0.0)
	_on.clear()
	for i in chord.size():
		_on.append(true)
	if s == &"substrate":
		_add_voice(root * pow(2.0, 7.0 / 12.0), ROLE_FIFTH, 0.0)
	_add_voice(root * pow(2.0, 1.0 / 12.0), ROLE_FOURTH, Tuning.MUSIC_FOURTH_VOICE_DB)


func _add_voice(hz: float, role: StringName, db: float) -> void:
	_voices.append(MusicVoice.create(self, hz, role, db, _stems))


func _clear_voices() -> void:
	for v in _voices:
		v.free_players()
	_voices.clear()
	_on.clear()


func _load_streams(id: StringName) -> Array:
	var out: Array = []
	if _library == null or not _library.has(id):
		return out
	for f: Variant in _library.entry(id).get("files", []):
		var path := String(f)
		if ResourceLoader.exists(path):
			var res := load(path) as AudioStream
			if res != null:
				out.append(res)
	return out


# --------------------------------------------------------------------------- events

func _on_level_entered(depth: int, s: StringName, _arrival: StringName) -> void:
	_fed = false
	intensity = 0.0
	phase = &"calm"
	threshold_in_view = false
	still_near = false
	_cut_left = 0.0
	_drop_left = 0.0
	set_stratum(s, depth)


func _on_threat(t: float) -> void:
	if not _fed:
		intensity = clampf(t, 0.0, 1.0)


func _on_error_proximity(id: StringName, distance: float) -> void:
	if id == &"still":
		set_still_near(distance < Tuning.STILL_SILENCE_RANGE)


func _on_scene_changed(path: String) -> void:
	if path == TITLE_SCENE:
		play_title()
	elif path.ends_with(ENDING_SCENE_SUFFIX):
		play_ending()
