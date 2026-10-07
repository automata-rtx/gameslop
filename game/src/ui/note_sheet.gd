class_name NoteSheet
extends UiShutter
## A note as a sheet in the lower third (04 §8, 01 §7): 720 px wide, 8 px padding, the
## voice's backing at 92% with a 1 px ui_dim top rule. Per voice:
##   faller  `NOTE H3 · HANDWRITTEN`, warm backing, hand-set ragged left margin;
##   builder `RENDER NOTE 0014`, cold backing, a form header line under the header (the
##           memo number moves from the text into the header);
##   stray   `FOUND OBJECT`, grey backing, centred text.
## Text types at 90 characters per second. Any movement key held 0.5 s dismisses it with
## the shutter, and it lowers out by itself after 8 s (01 §7). The world does not pause.

signal dismissed

const VOICE_FALLER := &"faller"
const VOICE_BUILDER := &"builder"
const VOICE_STRAY := &"stray"
const VOICE_BUILDER_FINAL := &"builder_final"
## Theme type of the backing per voice (noclip_theme.tres, 04 §8).
const PANEL_TYPES: Dictionary = {
	&"faller": &"NoteSheetFaller",
	&"builder": &"NoteSheetBuilder",
	&"stray": &"NoteSheetStray",
	&"builder_final": &"NoteSheetBuilder",
}
## 01 §7 ragged left margin: each faller line is set in by 0, 4 or 8 px.
const RAGGED_STEP := 4
const RAGGED_STEPS := 3
const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## Fallback line width in characters when no font is available.
const FALLBACK_COLUMNS := 60

var note: NoteData
var voice: StringName = &""
var header_text: String = ""
var body_text: String = ""
## Returns true while any movement key is held. Tests and the gallery replace it.
var movement_held: Callable

var _lines: PackedStringArray = []
var _type_t: float = 0.0
var _life: float = 0.0
var _hold: float = 0.0
var _typing: bool = false

@onready var _panel: PanelContainer = %Panel
@onready var _header: Label = %Header
@onready var _rule: ColorRect = %Rule
@onready var _lines_box: VBoxContainer = %Lines


func _init() -> void:
	movement_held = _movement_keys_held


func _ready() -> void:
	sound = true
	custom_minimum_size.x = UiTokens.NOTE_SHEET_WIDTH
	_rule.color = UiTokens.UI_DIM
	_rule.custom_minimum_size.y = UiTokens.LINE


## 04 Interfaces show_note(note). Starts typing from the first character.
func show_note(n: NoteData) -> void:
	if n == null:
		return
	note = n
	voice = n.voice
	header_text = header_for(n)
	body_text = body_for(n)
	_panel.theme_type_variation = PANEL_TYPES.get(voice, &"NoteSheet")
	_header.text = header_text
	_rule.visible = voice == VOICE_BUILDER or voice == VOICE_BUILDER_FINAL
	_build_lines()
	_type_t = 0.0
	_life = 0.0
	_hold = 0.0
	_typing = true
	_render_lines()
	if phase == Phase.CLOSING or phase == Phase.CLOSED:
		shutter_in()


static func header_for(n: NoteData) -> String:
	match n.voice:
		VOICE_FALLER:
			return Strings.NOTE_HEADER_FALLER.replace("{id}", String(n.id))
		VOICE_BUILDER:
			return Strings.NOTE_HEADER_BUILDER.replace("{number}", memo_number(n))
		VOICE_STRAY:
			return Strings.NOTE_HEADER_STRAY
	return Strings.NOTE_HEADER_BUILDER_FINAL.replace("{id}", String(n.id))


## Builder memos open with `RENDER NOTE 0014.`; the number goes in the header.
static func memo_number(n: NoteData) -> String:
	var m := _memo_regex().search(n.text)
	return m.get_string(1) if m != null else String(n.id)


static func body_for(n: NoteData) -> String:
	if n.voice == VOICE_BUILDER:
		var m := _memo_regex().search(n.text)
		if m != null:
			return n.text.substr(m.get_end())
	return n.text


static func _memo_regex() -> RegEx:
	var re := RegEx.new()
	re.compile("^RENDER NOTE (\\d+)\\.\\s*")
	return re


func lines() -> PackedStringArray:
	return _lines


func is_typing() -> bool:
	return _typing


## Characters printed so far (all lines).
func typed_count() -> int:
	return UiMotion.typed_count(_type_t, UiTokens.NOTE_TYPE_CPS, _total_chars()) if _typing else _total_chars()


func line_labels() -> Array[Label]:
	var out: Array[Label] = []
	for c in _lines_box.get_children():
		out.append(c as Label)
	return out


func panel_type() -> StringName:
	return _panel.theme_type_variation


func dismiss() -> void:
	if is_shown():
		shutter_out()
		dismissed.emit()


func advance(dt: float) -> void:
	super.advance(dt)
	if not is_shown():
		return
	if _typing:
		_type_t += dt
		if typed_count() >= _total_chars():
			_typing = false
		_render_lines()
	_life += dt
	_hold = _hold + dt if movement_held.call() else 0.0
	if _hold >= Tuning.NOTE_SHEET_DISMISS_HOLD or _life >= Tuning.NOTE_SHEET_AUTO_LOWER_TIME:
		dismiss()


func _movement_keys_held() -> bool:
	for a in MOVE_ACTIONS:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			return true
	return false


func _total_chars() -> int:
	var n := 0
	for l in _lines:
		n += l.length()
	return n


## Wraps the body into lines by column count (the face is monospace) so each line can
## carry its own margin.
func _build_lines() -> void:
	for c in _lines_box.get_children():
		_lines_box.remove_child(c)
		c.queue_free()
	_lines = wrap_text(body_text, _columns())
	var seed_value := hash(String(note.id))
	for i in _lines.size():
		var l := Label.new()
		l.theme_type_variation = &"NoteBody"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		if voice == VOICE_STRAY:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif voice == VOICE_FALLER:
			# 01 §7: a hand-set ragged left margin, fixed per note (hash, not a random draw).
			var step := absi(seed_value + i * 7919) % RAGGED_STEPS
			var pad := StyleBoxEmpty.new()
			pad.content_margin_left = step * RAGGED_STEP
			l.add_theme_stylebox_override(&"normal", pad)
		_lines_box.add_child(l)


func _columns() -> int:
	var font: Font = get_theme_font(&"font", &"NoteBody")
	var fs := get_theme_font_size(&"font_size", &"NoteBody")
	if font == null or fs <= 0:
		return FALLBACK_COLUMNS
	var cw := font.get_char_size("M".unicode_at(0), fs).x
	var inner := UiTokens.NOTE_SHEET_WIDTH - UiTokens.NOTE_SHEET_PADDING * 2 - RAGGED_STEP * (RAGGED_STEPS - 1)
	# One column stays free for the typing cursor.
	return maxi(10, floori(inner / cw) - 1)


static func wrap_text(text: String, columns: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if candidate.length() <= columns or current.is_empty():
			current = candidate
		else:
			out.append(current)
			current = word
	if not current.is_empty():
		out.append(current)
	return out


func _render_lines() -> void:
	var count := typed_count()
	var start := 0
	var labels := _lines_box.get_children()
	for i in mini(labels.size(), _lines.size()):
		var l := labels[i] as Label
		var line := _lines[i]
		var k := clampi(count - start, 0, line.length())
		var active := _typing and k < line.length() and count >= start
		if active:
			l.text = line.substr(0, k) + UiMotion.CURSOR + line.substr(k)
			l.visible_characters = k + (1 if UiMotion.cursor_visible(_type_t) else 0)
		else:
			l.text = line
			l.visible_characters = -1 if k >= line.length() else 0
		start += line.length()
