extends Node
## Sample playback, buses, reverb per stratum, ducking, occlusion, captions, and the pool of
## 32 AudioStreamPlayer3D (03, 14 §3). No game logic: callers say what sounds, this decides
## how it is mixed. Ids are the manifest's (game/assets/audio/manifest.json).
##
## Mix rules (03 §6): 1 walk steps play at their rendered -14 dB and the Footsteps bus is
## never ducked on its own; 2 the Errors bus is limited at -6 dBFS (AudioBuses); 3 the room
## tone never ducks below -40 dB (-46 dB in Still's silence, -inf in a silence()); 4 fades
## are baked by the synth; 5 one-shots play through AudioStreamRandomizer at +-4% pitch.
## noise_emitted: `step` noises play the footstep for the current surface here (06 §6, a
## noise and its sound are one event); every other kind is played by its emitter.

const STEP_SURFACE: Dictionary = {   # 03 §4 footstep table: the surface a stratum walks on
	&"halls": &"carpet", &"pools": &"tile", &"garage": &"concrete",
	&"offices": &"carpet", &"server": &"raised_floor", &"substrate": &"substrate",
}
const SETTINGS_BUSES: Dictionary = {  # 12 §4 sliders; Player follows Effects
	&"audio_master": [&"Master"], &"audio_effects": [&"World", &"Player"],
	&"audio_ambience": [&"Ambience"], &"audio_music": [&"Music"], &"audio_ui": [&"UI"],
}
const SETTINGS_DEFAULTS: Dictionary = {
	&"audio_master": Tuning.SETTINGS_AUDIO_MASTER_DEFAULT, &"audio_effects": Tuning.SETTINGS_AUDIO_EFFECTS_DEFAULT,
	&"audio_ambience": Tuning.SETTINGS_AUDIO_AMBIENCE_DEFAULT, &"audio_music": Tuning.SETTINGS_AUDIO_MUSIC_DEFAULT,
	&"audio_ui": Tuning.SETTINGS_AUDIO_UI_DEFAULT,
}
const NOCLIP_DUCK_BUSES: Array[StringName] = [&"World", &"Music", &"UI"]  # everything but Player
const DUCK_ERRORS_NEAR := &"errors_near"
const DUCK_STILL := &"still_silence"
const DUCK_NOTE := &"note"

var library: SoundLibrary
var bed: GeneratorLayers
var pool: AudioPool
var _loops3d: Array = []                  # 3D loop players, for occlusion
var _loops_root: Node
var ducker := AudioDucker.new()
var _clock: float = 0.0
var _stratum: StringName = &""
var _reverb_from: Dictionary = {}
var _reverb_to: Dictionary = {}
var _reverb_t: float = 1.0
var _room_tone: AudioLoop
var _fading_tones: Array[AudioLoop] = []
var _near: Dictionary = {}                # error id -> last distance (error_proximity)
var _threat: float = 0.0
var _coherence: float = 100.0
var _heartbeat_wait: float = 0.0
var _occlusion_wait: float = 0.0
var _listener: Node3D
var _step_surface: StringName = &""
var _captions: Dictionary = {}


func _ready() -> void:
	# 11 §4: pulse audio and UI sounds keep playing through hitstop and the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	library = SoundLibrary.new()
	_captions = (load("res://src/core/strings.gd") as GDScript).get_script_constant_map()
	pool = AudioPool.new(self)
	AudioMixGuard.install(self)  # RCA1: engine mix race in headless runs
	_loops_root = Node.new()
	_loops_root.name = "Loops"
	_loops_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_loops_root)
	bed = GeneratorLayers.new()
	bed.name = "GeneratorLayers"
	add_child(bed)
	for key: StringName in SETTINGS_BUSES:
		var v: Variant = SettingsManager.get_value(key)
		ducker.set_slider(SETTINGS_BUSES[key], float(v) if v != null else float(SETTINGS_DEFAULTS[key]))
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.level_entered.connect(_on_level_entered)
	EventBus.level_left.connect(_on_level_left)
	EventBus.run_started.connect(_on_run_started)
	EventBus.noise_emitted.connect(_on_noise_emitted)
	EventBus.error_proximity.connect(_on_error_proximity)
	EventBus.threat_changed.connect(func(t: float) -> void: _threat = t)
	EventBus.note_found.connect(func(_id: StringName) -> void: hold_duck(DUCK_NOTE, &"Music", Tuning.AUDIO_NOTE_DUCK_MUSIC_DB))
	ducker.apply(DUCK_STILL)


func _process(delta: float) -> void:
	tick(delta)


## Stops every one-shot and non-spatial loop and drops the room tone (the audio board's
## STOP ALL; tests). Positional loops belong to their emitters.
func stop_all() -> void:
	for pl: Array in [pool.players_3d, pool.players_2d, _loops_root.get_children()]:
		for p: Node in pl:
			p.call(&"stop")
	for h in _fading_tones + ([_room_tone] if _room_tone != null else []):
		h.release()
	_fading_tones.clear()
	_room_tone = null
	_stratum = &""


# --------------------------------------------------------------------------- playback

## A non-spatial one-shot (Player and UI buses, stereo sounds). Returns the player or null.
func play_2d(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var s := _one_shot_stream(id)
	if s == null:
		return null
	var p := pool.take_2d()
	p.stream = s
	p.bus = library.bus(id)
	p.pitch_scale = maxf(pitch, 0.01)
	var captioned := pool.start(p, id, volume_db, _clock)
	_after_play(id, _listener_transform().origin, p.bus, captioned)
	return p


## A positional one-shot from the pool of 32. `bus` empty = the manifest's bus (Echo plays
## footsteps with bus &"Errors"). Returns the player or null.
func play_3d(id: StringName, pos: Vector3, bus: StringName = &"", volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var s := _one_shot_stream(id)
	if s == null:
		return null
	var p := pool.take_3d()
	p.stream = s
	p.bus = bus if bus != &"" else library.bus(id)
	p.global_position = pos
	var rt := library.runtime(id)
	p.max_distance = float(rt.get("max_distance", 0.0))
	p.set_meta(AudioOcclusion.META_THROUGH, bool(rt.get("through_walls", false)))
	AudioOcclusion.reset(p)
	if rt.has("pitch_hash"):
		pitch *= AudioMix.hashed_pitch(pos, float(rt["pitch_hash"]))
	p.pitch_scale = maxf(pitch, 0.01)
	var captioned := pool.start(p, id, volume_db, _clock)
	_after_play(id, pos, p.bus, captioned)
	return p


## A loop handle. With `node`, a 3D player parented to it (it moves and frees with the
## emitter); without, a non-spatial player (crank whine, noclip charge, breath, room tone).
func loop(id: StringName, node: Node3D = null) -> AudioLoop:
	var s := library.stream(id)
	if s != null and not library.is_loop(id):
		push_error("AudioManager.loop: %s is a one-shot" % id)
		s = null
	if s == null:
		return AudioLoop.new(id, null)
	var rt := library.runtime(id)
	var p: Node
	if node != null:
		var p3 := AudioStreamPlayer3D.new()
		AudioPool.setup_3d(p3)
		p3.max_distance = float(rt.get("max_distance", 0.0))
		p3.set_meta(AudioOcclusion.META_THROUGH, bool(rt.get("through_walls", false)))
		p3.stream = s
		p3.bus = library.bus(id)
		node.add_child(p3)
		_loops3d.append(p3)
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = s
		p2.bus = library.bus(id)
		_loops_root.add_child(p2)
		p = p2
	p.set_meta(AudioPool.META_ID, id)
	AudioLoop.refresh_volume(p)
	var h := AudioLoop.new(id, p, rt)
	h.on_start = func(lp: AudioLoop) -> void:
		var pos := (lp.player as Node3D).global_position if lp.player is Node3D else _listener_transform().origin
		_caption(id, pos, StringName(lp.player.get(&"bus")))
	return h


## 03 Interfaces: starts a positional loop on `node` and returns its player.
func start_loop(id: StringName, node: Node3D) -> AudioStreamPlayer3D:
	if node == null:
		push_error("AudioManager.start_loop(%s): needs an emitter node; use loop() for non-spatial loops" % id)
		return null
	return loop(id, node).start().player as AudioStreamPlayer3D


func has_sound(id: StringName) -> bool:
	return library.has(id)


# --------------------------------------------------------------------------- mix state

## Swaps the World reverb (1 s crossfade) and the room tone (03 §3).
func set_stratum(stratum: StringName) -> void:
	if stratum == _stratum:
		return
	_stratum = stratum
	_reverb_from = AudioBuses.current_reverb()
	_reverb_to = AudioBuses.reverb_params(stratum)
	_reverb_t = 0.0
	var fade := Tuning.AUDIO_REVERB_CROSSFADE
	if _room_tone != null:
		_room_tone.stop(fade)
		_fading_tones.append(_room_tone)
		_room_tone = null
	var tone := StringName("room_tone_%s" % stratum)
	ducker.room_tone_db = 0.0
	if library.has(tone):
		_room_tone = loop(tone).start(fade)
		ducker.room_tone_db = float(library.runtime(tone).get("level_db", 0.0))


func stratum() -> StringName:
	return _stratum


func reverb_target() -> Dictionary:
	return _reverb_to


## A timed duck (03 §3). Ducks on one bus add up.
func duck(bus: StringName, db: float, seconds: float) -> void:
	ducker.duck(bus, db, seconds)


## A duck held until release_duck(key): the note sheet releases &"note" when it closes.
func hold_duck(key: StringName, bus: StringName, db: float) -> void:
	ducker.hold(key, bus, db)


func release_duck(key: StringName) -> void:
	ducker.release(key)


## Total silence on a bus for `seconds`, past the room-tone floor (Flicker's lunge, 03 §6).
func silence(bus: StringName, seconds: float) -> void:
	ducker.silence(bus, seconds)


## The duck offset applied to `bus` right now, after rule 3.
func duck_db(bus: StringName) -> float:
	return ducker.duck_db(bus, DUCK_STILL)


## Coherence 0..100 from its owner: the static bed and the heartbeat's danger floor.
func set_coherence(v: float) -> void:
	_coherence = clampf(v, 0.0, 100.0)
	bed.set_coherence(_coherence)


## Inside Static's field the bed holds 0.6 drain-equivalent (03 §4 Static).
func set_static_inside(on: bool) -> void:
	bed.set_static_inside(on)


## The surface the player stands on: carpet, tile, water, concrete, raised_floor, substrate.
func set_step_surface(surface: StringName) -> void:
	_step_surface = surface


func step_surface() -> StringName:
	if _step_surface != &"":
		return _step_surface
	return STEP_SURFACE.get(_stratum, &"carpet")


## Captions and occlusion use this node as the listener instead of the active camera.
func set_listener(node: Node3D) -> void:
	_listener = node


## Advances ducks, the reverb crossfade, occlusion and the heartbeat. Called by _process;
## tests drive it directly.
func tick(delta: float) -> void:
	_clock += delta
	ducker.advance(delta)
	ducker.apply(DUCK_STILL)
	if _reverb_t < 1.0:
		_reverb_t = minf(1.0, _reverb_t + delta / Tuning.AUDIO_REVERB_CROSSFADE)
		AudioBuses.blend_reverb(_reverb_from, _reverb_to, _reverb_t)
	for h in _fading_tones.duplicate():
		if not h.is_playing():
			h.release()
			_fading_tones.erase(h)
	_occlusion_wait -= delta
	if _occlusion_wait <= 0.0:
		_occlusion_wait = Tuning.AUDIO_OCCLUSION_INTERVAL
		_loops3d = _loops3d.filter(func(p: Variant) -> bool: return is_instance_valid(p))
		var l := _listener_node()
		if l != null:
			AudioOcclusion.tick(pool.players_3d, l.global_position)
			AudioOcclusion.tick(_loops3d, l.global_position)
	_tick_heartbeat(delta)


# --------------------------------------------------------------------------- internals

func _one_shot_stream(id: StringName) -> AudioStream:
	var s := library.stream(id)
	if s != null and library.is_loop(id):
		push_error("AudioManager: %s is a loop; use loop()" % id)
		return null
	return s


func _after_play(id: StringName, pos: Vector3, bus: StringName, captioned: bool) -> void:
	if id == &"noclip_commit":  # 03 §3: everything but Player ducks 8 dB for 300 ms
		for b in NOCLIP_DUCK_BUSES:
			duck(b, Tuning.AUDIO_NOCLIP_DUCK_DB, Tuning.AUDIO_NOCLIP_DUCK_MS / 1000.0)
	if captioned:
		_caption(id, pos, bus)


## 03 §6 rule 6: captioned sounds (manifest runtime.caption, a Strings constant) and every
## Errors bus event emit EventBus.audio_cue; footsteps on Errors are Echo's.
func _caption(id: StringName, pos: Vector3, bus: StringName) -> void:
	var key := String(library.runtime(id).get("caption", ""))
	if key.is_empty() and bus == &"Errors" and String(id).begins_with("foot_"):
		key = "CAPTION_ECHO_FOOTSTEP"
	if key.is_empty():
		return
	if not _captions.has(key):
		push_error("AudioManager: caption %s for %s is not in Strings" % [key, id])
		return
	EventBus.audio_cue.emit(AudioMix.format_caption(String(_captions[key]), _listener_transform(), pos), pos)


func _listener_node() -> Node3D:
	if _listener != null and is_instance_valid(_listener) and _listener.is_inside_tree():
		return _listener
	return get_viewport().get_camera_3d() if get_viewport() != null else null


func _listener_transform() -> Transform3D:
	var l := _listener_node()
	return l.global_transform if l != null else Transform3D.IDENTITY


func _tick_heartbeat(delta: float) -> void:
	var level := AudioMix.heartbeat_level(_threat, _coherence)
	if level <= 0.0 or get_tree().paused:
		_heartbeat_wait = 0.0
		return
	_heartbeat_wait -= delta
	if _heartbeat_wait <= 0.0:
		play_2d(&"heartbeat", linear_to_db(level))
		_heartbeat_wait = 60.0 / AudioMix.heartbeat_bpm(_threat, _coherence)


# --------------------------------------------------------------------------- bus events

func _on_settings_changed(key: StringName, value: Variant) -> void:
	if SETTINGS_BUSES.has(key):
		ducker.set_slider(SETTINGS_BUSES[key], float(value))
		ducker.apply(DUCK_STILL)


func _on_level_entered(_depth: int, stratum_id: StringName, _arrival: StringName) -> void:
	_clear_level_state()
	set_stratum(stratum_id)


func _on_level_left(_proper: bool) -> void:
	_clear_level_state()


func _on_run_started(_mode: StringName, _seed: int) -> void:
	_clear_level_state()
	_threat = 0.0
	set_coherence(100.0)
	set_static_inside(false)


func _clear_level_state() -> void:
	_near.clear()
	_step_surface = &""
	release_duck(DUCK_ERRORS_NEAR)
	release_duck(DUCK_STILL)
	release_duck(DUCK_NOTE)


func _on_noise_emitted(pos: Vector3, radius: float, kind: StringName) -> void:
	if kind != Tuning.NOISE_KIND_STEP:
		return
	var surface := step_surface()
	var walk := Tuning.NOISE_STEP_WATER_RADIUS if surface == &"water" \
		else float(Tuning.NOISE_STEP_RADIUS.get(surface, radius))
	# Sprint, crouch and wading scale the noise radius; the step's level follows it.
	play_3d(StringName("foot_%s" % surface), pos, &"", linear_to_db(maxf(radius, 0.01) / maxf(walk, 0.01)))


## 03 §3 ducking: Ambience -4 dB with any error within 10 m; 08 Still: -6 dB within 8 m
## (the room goes quiet, captioned `[silence]`).
func _on_error_proximity(id: StringName, distance: float) -> void:
	_near[id] = distance
	var any_near := false
	for d: float in _near.values():
		any_near = any_near or d < Tuning.AUDIO_ERRORS_DUCK_DIST
	if any_near:
		if not ducker.has(DUCK_ERRORS_NEAR):
			hold_duck(DUCK_ERRORS_NEAR, &"Ambience", Tuning.AUDIO_ERRORS_DUCK_AMBIENCE_DB)
	else:
		release_duck(DUCK_ERRORS_NEAR)
	var still_near := id == &"still" and distance < Tuning.STILL_SILENCE_RANGE
	if id == &"still":
		if still_near and not ducker.has(DUCK_STILL):
			hold_duck(DUCK_STILL, &"Ambience", Tuning.STILL_SILENCE_DB)
			var at := _listener_transform().origin
			EventBus.audio_cue.emit(Strings.CAPTION_STILL_SILENCE, at)
		elif not still_near:
			release_duck(DUCK_STILL)

