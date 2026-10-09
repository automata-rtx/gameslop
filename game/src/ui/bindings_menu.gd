class_name BindingsMenu
extends MenuPage
## KEY BINDINGS (12 §5, 04 §7): every rebindable action (06 §2) with its primary and
## secondary binding. Enter rebinds the selected slot: the next key or mouse button (wheel
## included) is captured; Esc cancels; Backspace clears. A conflict swaps the two bindings and
## both rows flash ui_accent for 2 s. `RESET TAB TO DEFAULTS` restores the default map.

const ROW_RESET := &"reset_bindings"
## A click that starts a capture must not be captured itself.
const CAPTURE_GUARD_MS := 150

var rows: MenuRows
var help: Label
var capturing_row: BindingRow = null
var _capture_started_msec: int = 0


func build() -> void:
	title = String(Strings.SETTING_LABELS[&"key_bindings"])
	left.visible = false
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	for t in [Strings.CONTROLS_COLUMN_PRIMARY, Strings.CONTROLS_COLUMN_SECONDARY]:
		var l := Label.new()
		l.theme_type_variation = &"DimLabel"
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = BindingRow.CAP_WIDTH
		head.add_child(l)
	detail.add_child(head)
	rows = MenuRows.new()
	rows.max_height_ratio = _rows_ratio()   # 19 actions and the reset line fit at UI scale 1.0
	rows.active = true
	rows.row_activated.connect(_on_row_activated)
	detail.add_child(rows)
	for action in SettingsManager.REBINDABLE_ACTIONS:
		var r := BindingRow.new(action)
		r.rebind_requested.connect(begin_capture)
		rows.add_row(r)
	rows.add_row(MenuRow.new(ROW_RESET, Strings.SETTINGS_RESET_TAB))
	help = MenuPage.description_label(Strings.CONTROLS_HELP)
	detail.add_child(help)
	SettingsManager.bindings_changed.connect(_on_bindings_changed)


## M3.6: the rows' share of a compact screen leaves room for the header line and the help.
static func _rows_ratio() -> float:
	return 0.6 if UiTokens.compact else 0.72


func apply_compact() -> void:
	super.apply_compact()
	if rows == null:  # a resize can reach a page before its _ready built the rows
		return
	rows.max_height_ratio = _rows_ratio()
	rows.fit_height()


func on_open() -> void:
	end_capture()
	rows.active = true
	if rows.selected < 0:
		rows.select_index(0)
	rows.refresh_all()


func handle_cancel() -> bool:
	if capturing_row != null:
		end_capture()
		return true
	return false


func is_capturing() -> bool:
	return capturing_row != null


func begin_capture(action: StringName, slot: int) -> void:
	var row := rows.find_row(action) as BindingRow
	if row == null:
		return
	end_capture()
	capturing_row = row
	rows.active = true
	rows.select_row(row)
	row.slot = slot
	row.capturing = true
	rows.locked = true
	_capture_started_msec = Time.get_ticks_msec()
	row.refresh()


func end_capture() -> void:
	if capturing_row != null:
		capturing_row.capturing = false
		capturing_row.refresh()
	capturing_row = null
	if rows != null:
		rows.locked = false


## The captured input (also the tests' entry point): Esc cancels, Backspace clears, anything
## else that is a key or a mouse button binds. Returns true when the event was used.
func capture(event: InputEvent) -> bool:
	if capturing_row == null:
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return true
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_ESCAPE:
			end_capture()
			return true
		if code == KEY_BACKSPACE:
			SettingsManager.clear_binding(capturing_row.id, capturing_row.slot)
			end_capture()
			return true
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if not b.pressed or Time.get_ticks_msec() - _capture_started_msec < CAPTURE_GUARD_MS:
			return true
	else:
		return event is InputEventMouseMotion
	var row := capturing_row
	var partner := SettingsManager.rebind(row.id, event, row.slot)
	end_capture()
	AudioManager.play_2d(&"ui_confirm")
	if partner != &"":
		# 04 §7, 12 §5: conflicts are resolved by swapping and shown in ui_accent for 2 s.
		row.flash_accent()
		var other := rows.find_row(partner)
		if other != null:
			other.flash_accent()
	return true


func _input(event: InputEvent) -> void:
	if capturing_row != null and is_visible_in_tree() and capture(event):
		get_viewport().set_input_as_handled()


func _on_row_activated(row: MenuRow) -> void:
	if row.id == ROW_RESET:
		SettingsManager.reset_bindings()


func _on_bindings_changed() -> void:
	if rows != null:
		rows.refresh_all()
