class_name MenuRow
extends HBoxContainer
## One row of a detail column (04 §7): `LABEL ………… value` with the 1 px dotted leader. The
## selected row shows the `▸` prefix and its label in ui_accent. Subclasses (SettingRow,
## BindingRow) fill the value side and react to adjust(dir) (left/right) and activate()
## (Enter, click). A plain MenuRow is an action line (`RESET TAB TO DEFAULTS`, a submenu).

signal activated(row: MenuRow)
signal hovered(row: MenuRow)

## What the row stands for (a settings key, an action name, or an action line id).
var id: StringName = &""
var text: String = ""
var description: String = ""
var enabled: bool = true
var selected: bool = false:
	set(v):
		selected = v
		refresh()
## Seconds left of the 2 s ui_accent flash (12 §5: swapped bindings).
var flash: float = 0.0
var label: Label
var leader: Panel
var value_box: HBoxContainer


func _init(row_id: StringName = &"", row_text: String = "", row_description: String = "") -> void:
	id = row_id
	text = row_text
	description = row_description
	add_theme_constant_override(&"separation", UiTokens.GRID)
	custom_minimum_size.y = UiTokens.MENU_ROW_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	label = Label.new()
	label.theme_type_variation = &"MenuItemLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	leader = Panel.new()
	leader.theme_type_variation = &"Leader"
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(leader)
	value_box = HBoxContainer.new()
	value_box.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	value_box.alignment = BoxContainer.ALIGNMENT_END
	value_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(value_box)
	mouse_entered.connect(func() -> void: hovered.emit(self))
	refresh()


func _ready() -> void:
	leader.visible = has_value()
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		hovered.emit(self)
		click()
		accept_event()


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		if flash == 0.0:
			refresh()


## Rows without a value (action lines) hide the leader.
func has_value() -> bool:
	return false


## Left (-1) or right (+1). True when the row used it.
func adjust(_dir: int) -> bool:
	return false


## Enter. Action lines announce themselves.
func activate() -> void:
	if enabled:
		AudioManager.play_2d(&"ui_confirm")
		activated.emit(self)


## A left click on the row (value rows cycle or toggle; action lines activate).
func click() -> void:
	activate()


func flash_accent(seconds: float = Tuning.SETTINGS_REBIND_FLASH) -> void:
	flash = seconds
	refresh()


func label_color() -> Color:
	if not enabled:
		return UiTokens.UI_DIM
	if selected or flash > 0.0:
		return UiTokens.UI_ACCENT
	return UiTokens.UI_FG


func refresh() -> void:
	if label == null:
		return
	label.text = (Strings.MENU_SELECTED_PREFIX if selected else "  ") + text
	label.add_theme_color_override(&"font_color", label_color())
