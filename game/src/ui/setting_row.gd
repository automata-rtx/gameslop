class_name SettingRow
extends MenuRow
## A settings row (04 §7, 12): `LABEL ………… value`. Enums and toggles show their value and
## step with left/right (a click cycles); numbers show a 200 px slider track with the numeric
## value to its right, editable by typing (Enter on the row puts the caret in the field).
## The row never writes settings itself: it emits `value_chosen(key, value)` and the page
## decides (set_value, or try_display for the window). refresh() re-reads SettingsManager.

signal value_chosen(key: StringName, value: Variant)

## Slider value standing for Unlimited on the Max FPS track (one past 360).
const FPS_UNLIMITED_SLOT := Tuning.SETTINGS_FPS_MAX + 1
const FIELD_WIDTH := UiTokens.GRID * 16

var kind: StringName = &""
## Value shown in place of the setting while greyed (the AA row shows `FSR 2`, 12 §2).
var override_text: String = ""
var value_label: Label
var slider: HSlider
var field: LineEdit
var _syncing: bool = false


func _init(key: StringName = &"") -> void:
	super(key, String(Strings.SETTING_LABELS.get(key, String(key).to_upper())),
			String(Strings.SETTING_DESCRIPTIONS.get(key, "")))
	kind = SettingsSchema.kind_of(key)
	if is_slider():
		var o := SettingsSchema.option(key)
		slider = HSlider.new()
		slider.custom_minimum_size = Vector2(UiTokens.SLIDER_TRACK_WIDTH, UiTokens.MENU_ROW_HEIGHT)
		slider.min_value = float(o[&"min"])
		slider.max_value = float(FPS_UNLIMITED_SLOT if key == &"max_fps" else o[&"max"])
		slider.step = float(o[&"step"])
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider)
		value_box.add_child(slider)
		field = LineEdit.new()
		field.custom_minimum_size = Vector2(FIELD_WIDTH, 0)
		field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		field.select_all_on_focus = true
		field.text_submitted.connect(func(t: String) -> void:
			submit_text(t)
			field.release_focus())
		field.focus_exited.connect(func() -> void: refresh())
		value_box.add_child(field)
	else:
		value_label = Label.new()
		value_label.theme_type_variation = &"MenuItemLabel"
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_box.add_child(value_label)
	refresh()


func has_value() -> bool:
	return true


func is_slider() -> bool:
	return kind == SettingsSchema.KIND_INT or kind == SettingsSchema.KIND_FLOAT


func is_editing() -> bool:
	return field != null and field.has_focus()


func current_value() -> Variant:
	return SettingsManager.get_value(id)


## The enum choices of this row (machine-dependent for resolution and output device).
func choices() -> Array:
	match kind:
		SettingsSchema.KIND_ENUM:
			var vals: Array = (SettingsSchema.option(id)[&"values"] as Array).duplicate()
			if id == &"preset":
				vals.erase(SettingsSchema.PRESET_CUSTOM)
			return vals
		SettingsSchema.KIND_BOOL:
			return [false, true]
		SettingsSchema.KIND_RESOLUTION:
			var screen := Vector2i.ZERO
			if DisplayServer.get_name() != "headless":
				screen = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
			return SettingsSchema.resolutions_for(screen)
		SettingsSchema.KIND_DEVICE:
			var list := AudioServer.get_output_device_list()
			return Array(list) if not list.is_empty() else [SettingsSchema.DEVICE_DEFAULT]
	return []


func adjust(dir: int) -> bool:
	if not enabled:
		return false
	if is_slider():
		var o := SettingsSchema.option(id)
		var v := slider.value + float(o[&"step"]) * dir
		_choose(_from_slider(clampf(v, slider.min_value, slider.max_value)))
		return true
	var c := choices()
	if c.is_empty():
		return false
	var i := _index_in(c, current_value())
	var j := clampi(i + dir, 0, c.size() - 1) if i >= 0 else 0
	if j == i:
		return true
	_choose(c[j])
	return true


func activate() -> void:
	if not enabled:
		return
	if is_slider():
		field.grab_focus()
		field.select_all()
		return
	_cycle()


func click() -> void:
	if not enabled or is_slider():
		return
	_cycle()


func _cycle() -> void:
	var c := choices()
	if c.is_empty():
		return
	var i := _index_in(c, current_value())
	_choose(c[posmod(i + 1, c.size())])


## Typed value from the numeric field (12 §5: the sensitivity field takes 0.10 to 3.00).
func submit_text(t: String) -> void:
	var s := t.strip_edges()
	if id == &"max_fps" and (s.is_empty() or s.to_upper() == String(Strings.SETTINGS_VALUES[&"unlimited"])):
		_choose(SettingsSchema.FPS_UNLIMITED)
		return
	if not s.is_valid_float():
		refresh()
		return
	_choose(SettingsSchema.validate(id, s.to_float()))


func _choose(v: Variant) -> void:
	AudioManager.play_2d(&"ui_slider_step" if is_slider() else &"ui_move")
	value_chosen.emit(id, v)
	refresh()


func _on_slider(v: float) -> void:
	if _syncing:
		return
	value_chosen.emit(id, _from_slider(v))
	AudioManager.play_2d(&"ui_slider_step")
	_sync_field()


func _from_slider(v: float) -> Variant:
	if id == &"max_fps" and roundi(v) >= FPS_UNLIMITED_SLOT:
		return SettingsSchema.FPS_UNLIMITED
	return roundi(v) if kind == SettingsSchema.KIND_INT else snappedf(v, slider.step)


func refresh() -> void:
	super()
	if not is_inside_tree() and value_label == null and slider == null:
		return
	var v: Variant = current_value()
	var col := UiTokens.UI_FG if enabled else UiTokens.UI_DIM
	if flash > 0.0:
		col = UiTokens.UI_ACCENT
	if value_label != null:
		value_label.text = override_text if not override_text.is_empty() else value_text(id, v)
		value_label.add_theme_color_override(&"font_color", col)
	if slider != null:
		_syncing = true
		var sv := float(v) if v is int or v is float else slider.min_value
		if id == &"max_fps" and int(sv) == SettingsSchema.FPS_UNLIMITED:
			sv = FPS_UNLIMITED_SLOT
		slider.value = sv
		slider.editable = enabled
		_syncing = false
		_sync_field()
		field.editable = enabled
		field.add_theme_color_override(&"font_color", col)


func _sync_field() -> void:
	if field != null and not field.has_focus():
		field.text = value_text(id, current_value())


static func _index_in(c: Array, v: Variant) -> int:
	for i in c.size():
		if typeof(c[i]) == TYPE_BOOL or typeof(v) == TYPE_BOOL:
			if typeof(c[i]) == typeof(v) and c[i] == v:
				return i
		elif String(c[i]) == String(v):
			return i
	return -1


## The value as the row prints it (Strings; uppercase; numbers at the step's precision).
static func value_text(key: StringName, v: Variant) -> String:
	var kind_ := SettingsSchema.kind_of(key)
	match kind_:
		SettingsSchema.KIND_BOOL:
			return String(Strings.SETTINGS_VALUES[&"on" if bool(v) else &"off"])
		SettingsSchema.KIND_INT:
			if key == &"max_fps" and int(v) == SettingsSchema.FPS_UNLIMITED:
				return String(Strings.SETTINGS_VALUES[&"unlimited"])
			return str(int(v))
		SettingsSchema.KIND_FLOAT:
			return "%.2f" % float(v)
		SettingsSchema.KIND_RESOLUTION:
			if StringName(v) == SettingsSchema.NATIVE:
				return String(Strings.SETTINGS_VALUES[&"native"])
			return String(v).replace("x", " × ")
		SettingsSchema.KIND_DEVICE:
			if String(v) == SettingsSchema.DEVICE_DEFAULT:
				return String(Strings.SETTINGS_VALUES[&"default"])
			return String(v).to_upper()
	var table: Dictionary = Strings.SETTINGS_VALUES
	if key == &"shadow_quality":
		table = Strings.SETTINGS_SHADOW_VALUES
	elif key == &"hud_mode":
		table = Strings.SETTINGS_HUD_VALUES
	return String(table.get(StringName(str(v)), str(v).to_upper()))
