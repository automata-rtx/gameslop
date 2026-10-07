class_name HudNotifications
extends VBoxContainer
## Notifications, top-centre below the safe margin (04 §6): single typed lines in ui_dim
## (unlocks in ui_accent, 11 §3), 60 characters per second with the `▌` cursor, each held
## 4 s and leaving with the shutter; at most two stacked (a third pushes the oldest out).

var _entries: Array[Entry] = []


class Entry extends RefCounted:
	var shutter: UiShutter
	var label: UiTypedLabel
	var t: float = 0.0
	var leaving: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override(&"separation", UiTokens.GRID)


func notify(text: String, color: Color = UiTokens.UI_DIM) -> void:
	var e := Entry.new()
	e.label = UiTypedLabel.new()
	e.label.theme_type_variation = &"HudBody"
	e.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	e.label.add_theme_color_override(&"font_color", color)
	e.label.sound = true
	e.shutter = UiShutter.new()
	e.shutter.sound = true
	e.shutter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.shutter.add_child(e.label)
	add_child(e.shutter)
	e.label.type_text(text, UiTokens.TYPE_CPS)
	e.shutter.shutter_in()
	e.shutter.closed.connect(_on_closed.bind(e))
	_entries.append(e)
	var live := _live()
	while live.size() > Tuning.HUD_NOTIFY_MAX_STACK:
		_leave(live.pop_front())


## Lines on screen and not leaving, oldest first (tests).
func lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in _live():
		out.append(e.label.full_text)
	return out


func labels() -> Array[UiTypedLabel]:
	var out: Array[UiTypedLabel] = []
	for e in _live():
		out.append(e.label)
	return out


func clear() -> void:
	for e in _entries:
		e.shutter.queue_free()
	_entries.clear()


func advance(dt: float) -> void:
	for e in _entries:
		e.t += dt
		if not e.leaving and e.t >= Tuning.HUD_NOTIFY_TIME:
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
	e.leaving = true
	e.shutter.shutter_out()


func _on_closed(e: Entry) -> void:
	_entries.erase(e)
	e.shutter.queue_free()
