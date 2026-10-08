class_name BindingRow
extends MenuRow
## A key binding row (12 §5): action name, primary and secondary binding, each drawn as a key
## name in a 1 px box (04 §6 key caps). Left/right picks the slot, Enter asks to rebind it
## (`rebind_requested`); while capturing, the slot reads `PRESS A KEY` in ui_accent.

signal rebind_requested(action: StringName, slot: int)

const CAP_WIDTH := UiTokens.GRID * 24

var slot: int = 0
var capturing: bool = false
var caps: Array[Label] = []
var _boxes: Array[StyleBoxFlat] = []


func _init(action: StringName = &"") -> void:
	super(action, String(Strings.ACTION_LABELS.get(action, String(action).to_upper())),
			String(Strings.SETTING_DESCRIPTIONS[&"key_bindings"]))
	for i in Tuning.SETTINGS_BINDING_SLOTS:
		var cap := Label.new()
		cap.theme_type_variation = &"MenuItemLabel"
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(CAP_WIDTH, UiTokens.GRID * 4)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.set_border_width_all(UiTokens.hairline())
		box.border_color = UiTokens.UI_DIM
		cap.add_theme_stylebox_override(&"normal", box)
		var s := i
		cap.mouse_entered.connect(func() -> void:
			if selected and not capturing:
				slot = s
				refresh())
		cap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not capturing:
				hovered.emit(self)
				slot = s
				refresh()
				activate()
				cap.accept_event())
		value_box.add_child(cap)
		caps.append(cap)
		_boxes.append(box)
	refresh()


func has_value() -> bool:
	return true


func adjust(dir: int) -> bool:
	if capturing:
		return true
	var next := clampi(slot + dir, 0, Tuning.SETTINGS_BINDING_SLOTS - 1)
	if next == slot:
		return dir > 0
	slot = next
	AudioManager.play_2d(&"ui_move")
	refresh()
	return true


func activate() -> void:
	if enabled and not capturing:
		AudioManager.play_2d(&"ui_confirm")
		rebind_requested.emit(id, slot)


func click() -> void:
	activate()


static func slot_text(action: StringName, s: int) -> String:
	var ev := SettingsManager.binding(action, s)
	if ev == null:
		return Strings.BINDING_NONE
	var n := UiKeys.event_name(ev)
	return n if not n.is_empty() else Strings.BINDING_NONE


func refresh() -> void:
	super()
	for i in caps.size():
		var on := selected and i == slot
		var cap := caps[i]
		if capturing and on:
			cap.text = Strings.CONTROLS_REBIND_PROMPT
		else:
			cap.text = slot_text(id, i)
		var col := UiTokens.UI_FG
		if flash > 0.0 or on:
			col = UiTokens.accent()
		UiTokens.paint(cap, col)
		_boxes[i].border_color = UiTokens.accent() if on else UiTokens.UI_DIM
