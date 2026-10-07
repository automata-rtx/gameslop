class_name AudioLoop
extends RefCounted
## A handle on one looping sound from AudioManager.loop(): the crank whine, the noclip
## charge, the sprint breath, a fixture hum, Static's hum. The player node is a 3D player
## parented to the emitter (positional) or a plain player under AudioManager (Player, Music,
## Ambience room tones). A handle on a missing sound is valid and silent.
##
##   var whine := AudioManager.loop(&"crank_whine")
##   whine.start(); whine.set_pitch01(charge / 100.0); whine.stop(0.1)
##
## A player's volume_db is always base + fade + occlusion, each kept as node metadata, so
## a fade, a set_volume and the occlusion tween never overwrite one another.

const META_BASE := &"audio_base_db"
const META_FADE := &"audio_fade_db"
const META_OCCLUSION := &"audio_occlusion_db"

var id: StringName
## AudioStreamPlayer or AudioStreamPlayer3D; null when the sound is missing.
var player: Node
var _pitch_min: float = 1.0
var _pitch_max: float = 1.0
var _fade: Tween
## Called when the loop starts from silence (AudioManager emits its caption here).
var on_start: Callable


func _init(sound_id: StringName, node: Node, runtime: Dictionary = {}) -> void:
	id = sound_id
	player = node
	_pitch_min = float(runtime.get("pitch_min", 1.0))
	_pitch_max = float(runtime.get("pitch_max", 1.0))


## volume_db = base + fade + occlusion.
static func refresh_volume(p: Node) -> void:
	var db := float(p.get_meta(META_BASE, 0.0)) + float(p.get_meta(META_FADE, 0.0)) \
		+ float(p.get_meta(META_OCCLUSION, 0.0))
	p.set(&"volume_db", maxf(db, Tuning.AUDIO_SLIDER_MUTE_DB))


static func set_part(p: Node, key: StringName, db: float) -> void:
	p.set_meta(key, db)
	refresh_volume(p)


func is_valid() -> bool:
	return player != null and is_instance_valid(player)


func is_playing() -> bool:
	return is_valid() and bool(player.get(&"playing"))


## Starts (or restarts) the loop, fading in over `fade_s` (the breath's 2 s, 11 §2).
func start(fade_s: float = 0.0) -> AudioLoop:
	if not is_valid():
		return self
	_kill_fade()
	if fade_s > 0.0:
		_fade_to(Tuning.AUDIO_SLIDER_MUTE_DB, 0.0, fade_s)
	else:
		set_part(player, META_FADE, 0.0)
	if not player.get(&"playing"):
		player.call(&"play")
		if on_start.is_valid():
			on_start.call(self)
	return self


## Stops, fading out over `fade_s` (the breath's 1 s). The handle can start again.
func stop(fade_s: float = 0.0) -> void:
	if not is_valid():
		return
	_kill_fade()
	if fade_s > 0.0 and player.get(&"playing"):
		_fade_to(float(player.get_meta(META_FADE, 0.0)), Tuning.AUDIO_SLIDER_MUTE_DB, fade_s)
		_fade.tween_callback(player.stop)
	else:
		player.call(&"stop")


## Exact pitch scale (1.0 = as rendered).
func set_pitch(p: float) -> void:
	if is_valid():
		player.set(&"pitch_scale", maxf(p, 0.01))


func get_pitch() -> float:
	return float(player.get(&"pitch_scale")) if is_valid() else 1.0


## Pitch by a 0..1 value across the manifest's runtime range (crank whine: 200 to 900 Hz;
## noclip charge: 110 to 440 Hz).
func set_pitch01(t: float) -> void:
	set_pitch(lerpf(_pitch_min, _pitch_max, clampf(t, 0.0, 1.0)))


## Loop level in dB relative to its rendered level (Static's band rising inside the field).
func set_volume(db: float) -> void:
	if is_valid():
		set_part(player, META_BASE, db)


func get_volume() -> float:
	return float(player.get_meta(META_BASE, 0.0)) if is_valid() else 0.0


## Stops and frees the player node.
func release() -> void:
	_kill_fade()
	if is_valid():
		player.queue_free()
	player = null


func _fade_to(from_db: float, to_db: float, seconds: float) -> void:
	var p := player
	_fade = p.create_tween()
	_fade.tween_method(func(v: float) -> void: set_part(p, META_FADE, v), from_db, to_db, seconds)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
