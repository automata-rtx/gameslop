class_name UiKeyLine
extends HBoxContainer
## One line of prompt text with key caps (04 §6): plain segments are labels, key segments
## are labels framed by a 1 px `ui_fg` box. Built from UiKeys.segments().

## Theme type of the text (04 §2: prompts 20 px, uppercase tracking).
@export var text_type: StringName = &"Prompt"

var color: Color = UiTokens.UI_FG
var _segments: Array[Dictionary] = []
var _empty := StyleBoxEmpty.new()
var _cap := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 0)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_cap.bg_color = Color(0, 0, 0, 0)
	_cap.draw_center = false
	_cap.set_border_width_all(UiTokens.LINE)
	_cap.border_color = UiTokens.UI_FG
	_cap.anti_aliasing = false
	_cap.content_margin_left = UiTokens.GRID * 0.5
	_cap.content_margin_right = UiTokens.GRID * 0.5
	_cap.content_margin_top = 0.0
	_cap.content_margin_bottom = 0.0


func set_segments(segs: Array[Dictionary], tint: Color = UiTokens.UI_FG) -> void:
	_segments = segs
	color = tint
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for seg in segs:
		var l := Label.new()
		l.theme_type_variation = text_type
		l.text = String(seg[UiKeys.TEXT])
		l.add_theme_color_override(&"font_color", tint)
		l.add_theme_stylebox_override(&"normal", _cap if seg[UiKeys.KEY] else _empty)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_cap.border_color = tint


func plain_text() -> String:
	return UiKeys.plain(_segments)


func key_labels() -> Array[Label]:
	var out: Array[Label] = []
	for i in _segments.size():
		if _segments[i][UiKeys.KEY]:
			out.append(get_child(i) as Label)
	return out
