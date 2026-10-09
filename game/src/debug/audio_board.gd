class_name AudioBoard
extends Node
## The audio test scene of 03 §7: a button per manifest id, grouped by bus, played through
## AudioManager exactly as the game plays it (one-shots via play_2d / play_3d, loops as
## handles), with a 3D test listener and an emitter whose distance and bearing can be
## moved. Controls for the stratum (reverb and room tone), Coherence (the static bed),
## threat (the heartbeat), the Still silence and the noclip duck. Debug-only text: these
## labels are for review, not player text, so they do not live in strings.gd.
## M3.3 (the cp-12 listen check, docs/qa/listen_check.md): ECHO PAIR plays the player's own
## step under the listener then Echo's copy at the emitter 800 ms later; WALL drops a wall
## between listener and emitter (occlusion); the meter line shows each bus's peak.

const NON_SPATIAL_BUSES: Array[StringName] = [&"Player", &"Music", &"UI"]

var _loops: Dictionary = {}           # id -> AudioLoop
var _buttons: Dictionary = {}         # id -> BaseButton
var _dist: float = 5.0
var _bearing_deg: float = 30.0
var _wall: StaticBody3D
var _meter: Label

@onready var _listener: Camera3D = %Listener
@onready var _emitter: Marker3D = %Emitter
@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	AudioManager.set_listener(_listener)
	_build_controls()
	var by_bus := {}
	for id in AudioManager.library.ids():
		var bus := AudioManager.library.bus(id)
		if not by_bus.has(bus):
			by_bus[bus] = []
		(by_bus[bus] as Array).append(id)
	for bus: StringName in Tuning.AUDIO_BUSES:
		if not by_bus.has(bus):
			continue
		var ids: Array = by_bus[bus]
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		_add_section(bus, ids)


func _exit_tree() -> void:
	for h: AudioLoop in _loops.values():
		h.release()
	_loops.clear()
	AudioManager.set_listener(null)


## Every manifest id has exactly one control; the test counts them.
func button_count() -> int:
	return _buttons.size()


func has_button(id: StringName) -> bool:
	return _buttons.has(id)


func _build_controls() -> void:
	var title := Label.new()
	title.text = "AUDIO BOARD · %d SOUNDS" % AudioManager.library.ids().size()
	title.theme_type_variation = &"MenuHeading"
	_content.add_child(title)
	var row := HFlowContainer.new()
	_content.add_child(row)
	var strata := OptionButton.new()
	for s in DataRegistry.STRATUM_ORDER:
		strata.add_item(String(s).to_upper())
	strata.item_selected.connect(func(i: int) -> void:
		EventBus.level_entered.emit(1, DataRegistry.STRATUM_ORDER[i], &"start"))
	row.add_child(strata)
	_slider(row, "COHERENCE", 0.0, 100.0, 100.0, func(v: float) -> void: AudioManager.set_coherence(v))
	_slider(row, "THREAT", 0.0, 1.0, 0.0, func(v: float) -> void: EventBus.threat_changed.emit(v))
	_slider(row, "EMITTER M", 0.5, 60.0, _dist, func(v: float) -> void:
		_dist = v
		_place_emitter())
	_slider(row, "BEARING", -180.0, 180.0, _bearing_deg, func(v: float) -> void:
		_bearing_deg = v
		_place_emitter())
	_slider(row, "LOOP PITCH", 0.0, 1.0, 0.5, _set_loop_pitch)
	_button(row, "STILL 5 M", func() -> void: EventBus.error_proximity.emit(&"still", 5.0))
	_button(row, "STILL GONE", func() -> void: EventBus.error_proximity.emit(&"still", 50.0))
	_button(row, "INSIDE STATIC", func() -> void: AudioManager.set_static_inside(true))
	_button(row, "OUTSIDE STATIC", func() -> void: AudioManager.set_static_inside(false))
	_button(row, "STOP ALL", _stop_all)
	# M2.14: the Null tone at the emitter, the drone (intensity, phases, title, ending), and
	# Flicker's total silence.
	_button(row, "NULL AT EMITTER", func() -> void:
		CoherenceRenderer.set_null(_emitter.global_position, Tuning.NULL_UNRENDER_RADIUS))
	_button(row, "NULL GONE", func() -> void: CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0))
	_slider(row, "INTENSITY", 0.0, 1.0, 0.0, func(v: float) -> void: AudioManager.music.set_intensity(v))
	for ph: StringName in [&"build", &"peak", &"relief", &"pursuit"]:
		_button(row, String(ph).to_upper(), func() -> void: AudioManager.music.set_phase(ph))
	_button(row, "TITLE MUSIC", func() -> void: AudioManager.music.play_title())
	_button(row, "ENDING", func() -> void: AudioManager.music.play_ending())
	_button(row, "LUNGE SILENCE", func() -> void: AudioManager.silence(&"World", Tuning.FLICKER_DARK_TIME))
	_button(row, "ECHO PAIR", echo_pair)
	var wall := CheckButton.new()
	wall.text = "WALL"
	wall.toggled.connect(set_wall)
	row.add_child(wall)
	_meter = Label.new()
	_meter.theme_type_variation = &"HudLabel"
	_content.add_child(_meter)
	_place_emitter()


func _process(_delta: float) -> void:
	if _meter == null:
		return
	var parts: PackedStringArray = []
	for bus: StringName in Tuning.AUDIO_BUSES:
		var i := AudioServer.get_bus_index(bus)
		var pk := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
		parts.append("%s %s" % [String(bus).to_upper(), "-" if pk < -79.0 else "%.0f" % pk])
	_meter.text = "PEAK DB  " + "  ".join(parts)


## The player's step (as the game plays it, at the feet under the camera), then Echo's at the
## emitter, 800 ms late, on Errors at -3 dB (03 Echo).
func echo_pair() -> void:
	var foot := StringName("foot_%s" % AudioManager.step_surface())
	AudioManager.play_3d(foot, _listener.global_position + Vector3.DOWN * Tuning.PLAYER_CAMERA_HEIGHT)
	await get_tree().create_timer(Tuning.ECHO_TRAIL_DELAY).timeout
	if is_inside_tree():
		AudioManager.play_3d(foot, _emitter.global_position, &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)


## A 6 x 4 m wall halfway between listener and emitter, on the `world` layer (03 §3 occlusion).
func set_wall(on: bool) -> void:
	if not on:
		if _wall != null:
			_wall.queue_free()
		_wall = null
		return
	if _wall != null:
		return
	_wall = StaticBody3D.new()
	_wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.3)
	shape.shape = box
	_wall.add_child(shape)
	add_child(_wall)
	_place_emitter()


func has_wall() -> bool:
	return _wall != null


func _add_section(bus: StringName, ids: Array) -> void:
	var header := Label.new()
	header.text = String(bus).to_upper()
	header.theme_type_variation = &"HudLabel"
	_content.add_child(header)
	var flow := HFlowContainer.new()
	_content.add_child(flow)
	for id: StringName in ids:
		if AudioManager.library.is_loop(id):
			var t := CheckButton.new()
			t.text = String(id)
			t.toggled.connect(func(on: bool) -> void: _toggle_loop(id, on))
			flow.add_child(t)
			_buttons[id] = t
		else:
			_buttons[id] = _button(flow, String(id), func() -> void: _play(id))


func _play(id: StringName) -> void:
	if _spatial(id):
		AudioManager.play_3d(id, _emitter.global_position)
	else:
		AudioManager.play_2d(id)


func _toggle_loop(id: StringName, on: bool) -> void:
	if not on:
		if _loops.has(id):
			(_loops[id] as AudioLoop).release()
			_loops.erase(id)
		return
	var h := AudioManager.loop(id, _emitter if _spatial(id) else null)
	_loops[id] = h
	h.start()


## World-bus mono sounds play at the emitter; Player, Music, UI and stereo ones are 2D.
func _spatial(id: StringName) -> bool:
	var e := AudioManager.library.entry(id)
	return int(e.get("channels", 1)) == 1 and not AudioManager.library.bus(id) in NON_SPATIAL_BUSES


func _set_loop_pitch(v: float) -> void:
	for h: AudioLoop in _loops.values():
		h.set_pitch01(v)


## Bearing 0 is straight ahead of the listener (-Z), positive to the right.
func _place_emitter() -> void:
	var b := deg_to_rad(_bearing_deg)
	_emitter.position = Vector3(sin(b) * _dist, 0.0, -cos(b) * _dist)
	if _wall != null:
		_wall.position = _emitter.position * 0.5
		_wall.rotation = Vector3(0.0, -b, 0.0)


func _stop_all() -> void:
	for id: StringName in _loops.keys():
		var t := _buttons.get(id) as CheckButton
		if t != null:
			t.set_pressed_no_signal(false)
		(_loops[id] as AudioLoop).release()
	_loops.clear()
	AudioManager.stop_all()


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var box := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(160, 0)
	s.value_changed.connect(on_change)
	box.add_child(s)
	parent.add_child(box)
