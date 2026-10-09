class_name DebugOverlay
extends CanvasLayer
## 14 §9 debug overlay, toggled with F3 in debug builds. Shows engine counters plus the
## lines from every node in the `debug_info` group (each implements `debug_info() -> Dictionary`).
## Systems add their own lines by joining the group (Director phase, error states, exit status).
## M3.6: the GAMEPLAY tab's Debug overlay option (12 §7, debug builds only) shows and hides
## it too; F3 still toggles it for the session.

const GROUP := &"debug_info"
const LAYER := 100
const REFRESH_S := 0.25
const SETTING := &"debug_overlay"

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
	SettingsManager.changed.connect(_on_setting_changed)
	_on_setting_changed(SETTING, SettingsManager.get_value(SETTING))


## 12 §7 Debug overlay (debug builds only).
func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key != SETTING or not OS.is_debug_build():
		return
	visible = value is bool and bool(value)
	_refresh()


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
	var fps := Engine.get_frames_per_second()
	# PROCESS and PHYS are the engine's worst step over the last second (Performance monitors).
	lines.append("FPS %d   FRAME %.1f ms   PROCESS %.1f ms   PHYS %.1f ms" % [fps,
		1000.0 / fps if fps > 0 else 0.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	# M3.5 (docs/qa/perf_checklist.md): the viewport's measured render times, CPU and GPU.
	var vp := get_viewport().get_viewport_rid() if is_inside_tree() else RID()
	if vp.is_valid():
		RenderingServer.viewport_set_measure_render_time(vp, visible)
		lines.append("GPU %.2f ms   RENDER CPU %.2f ms   VRAM %d MB   MEM %d MB" % [
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
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
