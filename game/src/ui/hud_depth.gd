class_name HudDepth
extends VBoxContainer
## Depth and exit status, top-right (04 §6): `DEPTH 03 · GARAGE` with the numeral in
## ui_accent (Substrate: ui_cold), shuttering in on arrival (11 §3); beneath it the exit
## status line in ui_dim (`EXIT: UNKNOWN`, `EXIT: POWERED`, `EXIT: SEALED 02:14`), in
## ui_fg once the lock is cleared (`EXIT: OPEN`). A timed status counts down here
## between `exit_status_changed` events. While the keycard is held (09 §2: not a belt item)
## the `key` glyph shutters in left of the depth label.

const STATUS_UNKNOWN := &"unknown"
const STATUS_OPEN := &"open"
const SUBSTRATE := &"substrate"

var depth: int = 0
var stratum: StringName = &""
var status: StringName = STATUS_UNKNOWN
var timer: float = 0.0

var depth_shutter: UiShutter
var exit_shutter: UiShutter
var key_shutter: UiShutter
var has_keycard: bool = false
var _prefix: Label
var _numeral: Label
var _suffix: Label
var _exit: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", UiTokens.GRID * 0.5)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prefix = _label(&"HudLabel", row)
	_numeral = _label(&"HudBody", row)
	_suffix = _label(&"HudBody", row)
	depth_shutter = UiShutter.new()
	depth_shutter.name = "DepthShutter"
	depth_shutter.sound = true
	depth_shutter.add_child(row)
	# Shutters do not nest (hud.gd): the key glyph has its own, beside the depth line's.
	var top := HBoxContainer.new()
	top.name = "DepthRow"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_theme_constant_override(&"separation", UiTokens.GRID)
	key_shutter = UiShutter.new()
	key_shutter.name = "KeyShutter"
	key_shutter.sound = true
	key_shutter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := TextureRect.new()
	key.name = "KeyGlyph"
	key.texture = UiTokens.glyph(&"key")
	key.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	key.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_shutter.add_child(key)
	top.add_child(key_shutter)
	top.add_child(depth_shutter)
	add_child(top)
	exit_shutter = UiShutter.new()
	exit_shutter.name = "ExitShutter"
	exit_shutter.size_flags_horizontal = Control.SIZE_SHRINK_END
	_exit = Label.new()
	_exit.theme_type_variation = &"HudBody"
	_exit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	exit_shutter.add_child(_exit)
	add_child(exit_shutter)


func _ready() -> void:
	# Words are separate labels; one space of the HUD font separates them.
	var font := _numeral.get_theme_font(&"font")
	var fs := _numeral.get_theme_font_size(&"font_size")
	var row := _numeral.get_parent() as HBoxContainer
	row.add_theme_constant_override(&"separation", int(font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x))


func _label(type: StringName, parent: Node) -> Label:
	var l := Label.new()
	l.theme_type_variation = type
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 04 Interfaces set_depth(depth, stratum). Re-announces with the shutter (11 §3 arrival).
func set_depth(d: int, s: StringName) -> void:
	depth = d
	stratum = s
	var parts := Strings.HUD_DEPTH_LINE.split("{depth}")
	var name_text := String(Strings.STRATUM_NAMES.get(s, String(s).to_upper()))
	_prefix.text = parts[0].strip_edges()
	_numeral.text = str(d).pad_zeros(Tuning.HUD_DEPTH_STRATUM_PAD)
	_suffix.text = (parts[1] if parts.size() > 1 else "").replace("{stratum}", name_text).strip_edges()
	_paint_numeral()
	depth_shutter.reshutter()


## Repaints after a 12 §6 token change (colour-blind accent): no shutter, no sound.
func repaint() -> void:
	if depth > 0:
		_paint_numeral()


## Accent numeral; the Substrate's is cold and, with the colour-blind accent, marked `~`.
func _paint_numeral() -> void:
	_numeral.text = str(depth).pad_zeros(Tuning.HUD_DEPTH_STRATUM_PAD)
	if stratum == SUBSTRATE:
		_numeral.text = UiTokens.cold_mark(_numeral.text)
	UiTokens.paint(_numeral, UiTokens.UI_COLD if stratum == SUBSTRATE else UiTokens.accent())


## The keycard is held (Inventory.keycard_changed): its glyph shutters in or out.
func set_keycard(on: bool) -> void:
	has_keycard = on
	if on:
		key_shutter.shutter_in()
	else:
		key_shutter.shutter_out()


## 04 Interfaces set_exit_status(status, timer). Returns the previous status.
func set_exit_status(st: StringName, t: float) -> StringName:
	var before := status
	status = st
	timer = maxf(0.0, t)
	var text_before := _exit.text
	_render_exit()
	if not exit_shutter.is_shown():
		exit_shutter.shutter_in()
	elif before != st and text_before != _exit.text:
		# 11 §3 "Exit seen": the status shutters in.
		exit_shutter.reshutter()
	return before


## 05 §4: the Landing cabin has no exit; the line shutters out until the next level sets it.
func clear_exit_status() -> void:
	exit_shutter.shutter_out()


## 12 §7 "Exit status line" option.
func set_exit_line_enabled(on: bool) -> void:
	_exit.visible = on


func depth_text() -> String:
	return "%s %s %s" % [_prefix.text, _numeral.text, _suffix.text]


func numeral_color() -> Color:
	return _numeral.get_theme_color(&"font_color")


func exit_text() -> String:
	return _exit.text


func exit_color() -> Color:
	return _exit.get_theme_color(&"font_color")


static func format_time(seconds: float) -> String:
	var s := shown_seconds(seconds)
	return "%02d:%02d" % [floori(s / 60.0), s % 60]


## The whole seconds format_time() shows (R21: advance compares these, not two strings).
static func shown_seconds(seconds: float) -> int:
	return ceili(maxf(0.0, seconds) - 0.0001)


func advance(dt: float) -> void:
	if timer > 0.0:
		var before := shown_seconds(timer)
		timer = maxf(0.0, timer - dt)
		if shown_seconds(timer) != before:
			_render_exit()


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _render_exit() -> void:
	var template: String
	if status == STATUS_OPEN and timer > 0.0:
		template = Strings.HUD_EXIT_OPEN_TIMED
	else:
		template = String(Strings.HUD_EXIT_STATUS.get(status, Strings.HUD_EXIT_UNKNOWN))
	_exit.text = template.replace("{time}", format_time(timer))
	_exit.add_theme_color_override(&"font_color", UiTokens.UI_FG if status == STATUS_OPEN else UiTokens.UI_DIM)
