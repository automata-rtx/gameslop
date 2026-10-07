class_name DebugOverlay
extends CanvasLayer
## 14 §9 debug overlay, toggled with F3 in debug builds. Shows engine counters plus the
## lines from every node in the `debug_info` group (each implements `debug_info() -> Dictionary`).
## Systems add their own lines by joining the group (Director phase, error states, exit status).

const GROUP := &"debug_info"
const LAYER := 100
const REFRESH_S := 0.25

var _label: Label
var _accum := 0.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_label = Label.new()
	_label.position = Vector2(16, 120)
	_label.add_theme_color_override(&"font_color", UiTokens.UI_FG)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3 and OS.is_debug_build():
		visible = not visible
		_refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= REFRESH_S:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	_label.text = text()


## The overlay text; public so tests can read it headless.
func text() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS %d   FRAME %.1f ms   PHYS %.1f ms" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	lines.append("DRAW CALLS %d   OBJECTS %d   NODES %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node.has_method(&"debug_info"):
			continue
		var info: Dictionary = node.call(&"debug_info")
		for key in info:
			lines.append("%s %s" % [String(key).to_upper(), str(info[key])])
	return "\n".join(lines)
