class_name AudioFeeds
extends RefCounted
## AudioManager's feeds (M2.14), split out of it: step noises and error proximity
## (moved unchanged), and two per-frame feeds from the renderer:
## - the heartbeat sample, played when CoherenceRenderer.heartbeat_phase() wraps, so the
##   beat and the vignette pulse are one event (14 R3);
## - the Null grid tone (03 §4, 08 §7): the listener's distance and side to g_null_pos
##   drive GeneratorLayers' NullTone; inside the 2 m core World, Player and Music are
##   muted (a held mute: the rule-3 floor lifts) and only the tone remains; captioned
##   `[grid tone, ...]` each time it becomes audible.
## Reads CoherenceRenderer (presentation state) and the listener, never the player.

## Null's core (03 §4): everything but the grid tone is muted. UI stays (menus).
const NULL_CORE_MUTE: Array[StringName] = [&"World", &"Player", &"Music"]
const DUCK_NULL_CORE := "null_core_"
## The tone's stereo side at most (a hint of direction, never hard-panned).
const NULL_PAN_WIDTH := 0.6
const STILL_KEY := &"still_silence"  # AudioManager.DUCK_STILL
const DUCK_ERRORS_NEAR := &"errors_near"
const DUCK_STILL := STILL_KEY

## Heartbeat phase source 0..1 (0 on the beat); default CoherenceRenderer.heartbeat_phase.
var heartbeat_phase_source: Callable
## Heartbeats played (tests, the audio board).
var heartbeats: int = 0
var null_distance: float = INF
var null_audible: bool = false
var null_core: bool = false
## error id -> last distance (error_proximity)
var near: Dictionary = {}
var _am: Node
var _beat_last: float = -1.0


func _init(manager: Node) -> void:
	_am = manager


func tick(threat: float, coherence: float) -> void:
	_tick_null()
	_tick_heartbeat(threat, coherence)


func _renderer() -> Node:
	return _am.get_node_or_null(^"/root/CoherenceRenderer") if _am.is_inside_tree() else null


func _tick_heartbeat(threat: float, coherence: float) -> void:
	var ph := _heartbeat_phase()
	var wrapped := _beat_last >= 0.0 and ph < _beat_last
	_beat_last = ph
	var level := AudioMix.heartbeat_level(threat, coherence)
	if level <= 0.0 or not wrapped or (_am.is_inside_tree() and _am.get_tree().paused):
		return
	_am.call(&"play_2d", &"heartbeat", linear_to_db(level))
	heartbeats += 1


func _heartbeat_phase() -> float:
	if heartbeat_phase_source.is_valid():
		return float(heartbeat_phase_source.call())
	var cr := _renderer()
	return float(cr.call(&"heartbeat_phase")) if cr != null else 0.0


func _tick_null() -> void:
	var cr := _renderer()
	var l: Node3D = _am.call(&"listener_node")
	var d := INF
	var pan := 0.0
	var pos := Vector3.ZERO
	if cr != null and l != null and float(cr.get(&"null_radius")) > 0.0:
		pos = cr.get(&"null_pos")
		d = l.global_position.distance_to(pos)
		var local := l.global_transform.affine_inverse() * pos
		pan = clampf(local.x / maxf(Vector2(local.x, local.z).length(), 1.0), -1.0, 1.0) * NULL_PAN_WIDTH
	null_distance = d
	var bed: GeneratorLayers = _am.get(&"bed")
	var ducker: AudioDucker = _am.get(&"ducker")
	bed.set_null(d, pan)
	bed.set_null_trim(ducker.slider_db(&"Player"))  # the Effects slider; the tone is on Master
	var audible := NullTone.amplitude(d) > 0.0
	if audible and not null_audible:
		_am.call(&"caption_key", "CAPTION_NULL", pos)
	null_audible = audible
	var core := d < Tuning.NULL_CORE_RADIUS
	if core == null_core:
		return
	null_core = core
	for b in NULL_CORE_MUTE:
		var key := StringName(DUCK_NULL_CORE + String(b))
		if core:
			ducker.hold_mute(key, b)
		else:
			ducker.release(key)
	ducker.apply(STILL_KEY)


func _ducker() -> AudioDucker:
	return _am.get(&"ducker")


# --------------------------------------------------------------------------- bus events (moved from AudioManager)

func on_noise_emitted(pos: Vector3, radius: float, kind: StringName) -> void:
	if kind != Tuning.NOISE_KIND_STEP:
		return
	var surface: StringName = _am.call(&"step_surface")
	var walk := Tuning.NOISE_STEP_WATER_RADIUS if surface == &"water" \
		else float(Tuning.NOISE_STEP_RADIUS.get(surface, radius))
	# Sprint, crouch and wading scale the noise radius; the step's level follows it.
	_am.call(&"play_3d", StringName("foot_%s" % surface), pos, &"", linear_to_db(maxf(radius, 0.01) / maxf(walk, 0.01)))


## 03 §3 ducking: Ambience -4 dB with any error within 10 m; 08 Still: -6 dB within 8 m
## (the room goes quiet, captioned `[silence]`).
func on_error_proximity(id: StringName, distance: float) -> void:
	near[id] = distance
	var any_near := false
	for d: float in near.values():
		any_near = any_near or d < Tuning.AUDIO_ERRORS_DUCK_DIST
	if any_near:
		if not _ducker().has(DUCK_ERRORS_NEAR):
			_am.call(&"hold_duck", DUCK_ERRORS_NEAR, &"Ambience", Tuning.AUDIO_ERRORS_DUCK_AMBIENCE_DB)
	else:
		_am.call(&"release_duck", DUCK_ERRORS_NEAR)
	var still_near := id == &"still" and distance < Tuning.STILL_SILENCE_RANGE
	if id == &"still":
		if still_near and not _ducker().has(DUCK_STILL):
			_am.call(&"hold_duck", DUCK_STILL, &"Ambience", Tuning.STILL_SILENCE_DB)
			var l: Node3D = _am.call(&"listener_node")
			var at := l.global_position if l != null else Vector3.ZERO
			EventBus.audio_cue.emit(Strings.CAPTION_STILL_SILENCE, at)
		elif not still_near:
			_am.call(&"release_duck", DUCK_STILL)

