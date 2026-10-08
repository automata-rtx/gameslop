class_name GeneratorLayers
extends Node
## The runtime AudioStreamGenerator layers of 03 §2. This task builds the Coherence static
## bed: white noise through a one-pole low-pass whose cutoff is lerp(200, 6000, drain) Hz,
## at lerp(-60, -18, drain^1.5) dB, silent at 100 Coherence, on the Player bus. Inside
## Static's field the bed is held at 0.6 drain-equivalent (08 §3, STATIC_FORCED_BED).
## It is fed by setters (set_coherence, set_static_inside) and never reads the player.
## The second layer is the Null grid tone (NullTone), fed by AudioManager with the
## listener's distance to g_null_pos and its side. It plays on Master, not Errors: Errors
## sits under World, whose Substrate high-pass (300 Hz) would erase a 55 Hz tone, and
## Null's core mutes World, Player and Music (03 §4) while the tone stays. Its level
## follows the Effects slider through set_null_trim().

## The bed tops out at a 6 kHz cutoff, so 24 kHz is enough and halves the script cost.
const MIX_RATE := 24000.0
const BUFFER_S := 0.1

var _coherence: float = 100.0
var _static_inside: bool = false
var _gain: float = 0.0          # current linear gain, ramped per block toward the target
var _lp: Vector2 = Vector2.ZERO # one-pole state per channel
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var null_tone := NullTone.new(MIX_RATE)
var _null_player: AudioStreamPlayer
var _null_playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	_rng.seed = 0x5747  # cosmetic noise; fixed so renders are repeatable in tests
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_S
	_player = AudioStreamPlayer.new()
	_player.name = "StaticBed"
	_player.stream = gen
	_player.bus = &"Player"
	add_child(_player)
	var gen2 := AudioStreamGenerator.new()
	gen2.mix_rate = MIX_RATE
	gen2.buffer_length = BUFFER_S
	_null_player = AudioStreamPlayer.new()
	_null_player.name = "NullTone"
	_null_player.stream = gen2
	_null_player.bus = &"Master"
	add_child(_null_player)


func _exit_tree() -> void:
	# Release the playback the audio server holds, so quitting leaks nothing.
	_playback = null
	_null_playback = null
	if _player != null:
		_player.stop()
	if _null_player != null:
		_null_player.stop()


## The generator only runs while the bed is audible or ramping down: at full Coherence it
## costs nothing.
func _process(_delta: float) -> void:
	_process_null()
	if target_gain() <= 0.0 and _gain <= 0.0:
		if _player.playing:
			_player.stop()
			_playback = null
		return
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n > 0:
		_playback.push_buffer(render(n))
	elif target_gain() <= 0.0:
		_gain = 0.0  # nothing queued to ramp through: done


func _process_null() -> void:
	if _null_player == null:
		return
	if null_tone.is_silent():
		if _null_player.playing:
			_null_player.stop()
			_null_playback = null
		return
	if not _null_player.playing:
		_null_player.play()
		_null_playback = _null_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _null_playback == null:
		return
	var n := _null_playback.get_frames_available()
	if n > 0:
		_null_playback.push_buffer(null_tone.render(n))


## The listener's distance to Null (INF when there is none) and its side (-1..1).
func set_null(distance: float, pan: float = 0.0) -> void:
	null_tone.distance = distance
	null_tone.pan = pan


## The Effects slider (and its ducks) in dB, since the tone bypasses World.
func set_null_trim(db: float) -> void:
	if _null_player != null:
		_null_player.volume_db = db


func is_null_running() -> bool:
	return _null_player != null and _null_player.playing


func is_running() -> bool:
	return _player != null and _player.playing


## Coherence 0..100 (the player's value, pushed by whoever owns it).
func set_coherence(v: float) -> void:
	_coherence = clampf(v, 0.0, 100.0)


func set_static_inside(on: bool) -> void:
	_static_inside = on


## The drain the bed plays at: 1 - Coherence/100, floored at 0.6 inside Static.
func drain() -> float:
	var d := AudioMix.drain_from_coherence(_coherence)
	if _static_inside:
		d = maxf(d, Tuning.STATIC_FORCED_BED)
	return d


func target_gain() -> float:
	return AudioMix.bed_gain_linear(drain())


func current_gain() -> float:
	return _gain


## Renders `frames` stereo frames of the bed and advances its state. Public so tests and
## the audio board can measure it without an audio device.
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if frames <= 0:
		return out
	var d := drain()
	var target := AudioMix.bed_gain_linear(d)
	var a := 1.0 - exp(-TAU * AudioMix.bed_cutoff_hz(d) / MIX_RATE)
	var g0 := _gain
	var step := (target - g0) / float(frames)
	if g0 <= 0.0 and target <= 0.0:
		_lp = Vector2.ZERO
		return out
	var lp := _lp
	for i in frames:
		var g := g0 + step * float(i + 1)
		lp.x += a * (_rng.randf_range(-1.0, 1.0) - lp.x)
		lp.y += a * (_rng.randf_range(-1.0, 1.0) - lp.y)
		out[i] = lp * g
	_lp = lp
	_gain = target
	return out
