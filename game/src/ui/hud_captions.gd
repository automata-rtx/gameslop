class_name HudCaptions
extends Control
## Sound cue captions (04 §8, §10; 12 §6): bottom-centre above the prompt, `ui_fg` on 60%
## black, one line per captioned sound (`[hum, left]`, `[footsteps, behind, late]`,
## `[silence]`). The text arrives finished from AudioManager through EventBus.audio_cue
## (03 §6 rule 6: it fills {dir} from the 8-sector listener angle and {dist} near/far);
## this node only lays the lines out:
## - this control's position is the stack's bottom centre; the newest line sits lowest
##   (nearest the prompt), older lines move up, so captions never overlap the prompt (11 §6);
## - each line shutters in, holds CAPTION_TIME, and shutters out; at most CAPTION_MAX_STACK
##   lines (a new one pushes the oldest out);
## - a line that arrives again while it is still shown restarts its hold instead of stacking
##   a duplicate (a hum heard twice is one line).
## Size follows the Caption text type, which the Text size option scales (UiAccessibility).

var _stack: VBoxContainer
var _entries: Array[Entry] = []


class Entry extends RefCounted:
	var shutter: UiShutter
	var label: Label
	var text: String = ""
	var t: float = 0.0
	var leaving: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.name = "Stack"
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.add_theme_constant_override(&"separation", Tuning.CAPTION_GAP)
	add_child(_stack)
	_stack.minimum_size_changed.connect(_layout)


func _ready() -> void:
	_layout()


## Adds a caption line (04 Interfaces HUD.caption). Empty clears every line.
func show_caption(text: String) -> void:
	if text.is_empty():
		clear()
		return
	for e in _entries:
		if not e.leaving and e.text == text:
			# A repeat restarts the hold, becomes the newest line again and brightens for a
			# moment, so the reader sees the sound happened again (04 §10, 11 R channel).
			e.t = 0.0
			_stack.move_child(e.shutter, -1)
			e.label.modulate = Color(1.6, 1.6, 1.6)
			create_tween().tween_property(e.label, ^"modulate", Color.WHITE, Tuning.CAPTION_REPEAT_PULSE_S)
			_layout.call_deferred()
			return
	var e := Entry.new()
	e.text = text
	e.label = Label.new()
	e.label.theme_type_variation = &"Caption"
	e.label.text = text
	e.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Backing"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(e.label)
	e.shutter = UiShutter.new()
	e.shutter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.shutter.add_child(panel)
	e.shutter.closed.connect(_on_closed.bind(e))
	_stack.add_child(e.shutter)
	e.shutter.shutter_in()
	_entries.append(e)
	var live := _live()
	while live.size() > Tuning.CAPTION_MAX_STACK:
		_leave(live.pop_front())
	_layout.call_deferred()


## Every line leaves with the shutter.
func clear() -> void:
	for e in _entries:
		_leave(e)


## Lines shown and not leaving, oldest first.
func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in _live():
		out.append(e.text)
	return out


func labels() -> Array[Label]:
	var out: Array[Label] = []
	for e in _live():
		out.append(e.label)
	return out


func is_shown() -> bool:
	return not _live().is_empty()


## The newest line ("" when none): the HUD's single-caption reading.
func plain_text() -> String:
	var l := lines()
	return l[-1] if not l.is_empty() else ""


## The stack's rect in this control's space (tests: it ends above the prompt).
func stack_rect() -> Rect2:
	return Rect2(_stack.position, _stack.size)


func advance(dt: float) -> void:
	for e in _entries:
		e.t += dt
		if not e.leaving and e.t >= Tuning.CAPTION_TIME:
			_leave(e)


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _live() -> Array[Entry]:
	var out: Array[Entry] = []
	for e in _entries:
		if not e.leaving:
			out.append(e)
	return out


func _leave(e: Entry) -> void:
	if e.leaving:
		return
	e.leaving = true
	e.shutter.shutter_out()


func _on_closed(e: Entry) -> void:
	_entries.erase(e)
	e.shutter.queue_free()
	_layout.call_deferred()


## Bottom-centred on this control's position, growing upward.
func _layout() -> void:
	if not is_instance_valid(_stack):
		return
	var s := _stack.get_combined_minimum_size()
	_stack.size = s
	_stack.position = Vector2(-s.x * 0.5, -s.y).round()
