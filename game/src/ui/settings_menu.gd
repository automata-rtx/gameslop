class_name SettingsMenu
extends MenuPage
## SETTINGS (04 §7, 12): the six tabs as the left column; the detail column lists the tab's
## options as `LABEL ………… value` rows, the selected option's one-line description in
## ui_dim, `RESET TAB TO DEFAULTS` at the bottom. Every change applies at once through
## SettingsManager; window mode and resolution ask KEEP / REVERT with a 10 s countdown
## (12 §1). The Controls tab opens the key bindings page (`bindings`), so no list scrolls
## past one screen (04 §7). Reachable from the title and from pause.

const ROW_RESET := &"reset_tab"
const ROW_BINDINGS := &"key_bindings"
const PAGE_BINDINGS := &"bindings"
const ITEM_KEEP := &"keep"
const ITEM_REVERT := &"revert"

var rows: MenuRows
var description: Label
var extras: VBoxContainer
var revert_box: VBoxContainer
var revert_line: Label
var revert_list: MenuList
var tab: StringName = SettingsSchema.TAB_DISPLAY


func build() -> void:
	title = Strings.MENU_SETTINGS
	for i in SettingsSchema.TABS.size():
		list.add_item(SettingsSchema.TABS[i], Strings.SETTINGS_TABS[i])
	list.selection_changed.connect(func(id: StringName) -> void: show_tab(id))
	list.activated.connect(func(_id: StringName) -> void: focus_rows())
	list.advanced.connect(func(_id: StringName) -> void: focus_rows())
	rows = MenuRows.new()
	rows.retreated.connect(focus_list)
	rows.focus_taken.connect(func() -> void: list.active = false)
	rows.selection_changed.connect(_on_row_selected)
	rows.row_activated.connect(_on_row_activated)
	detail.add_child(rows)
	description = MenuPage.description_label("")
	description.custom_minimum_size.y = UiTokens.GRID * 6
	detail.add_child(description)
	extras = VBoxContainer.new()
	extras.add_theme_constant_override(&"separation", UiTokens.GRID)
	detail.add_child(extras)
	_build_revert_box()
	SettingsManager.display_resolved.connect(_on_display_resolved)
	SettingsManager.changed.connect(_on_setting_changed)
	show_tab(tab)


func on_open() -> void:
	focus_list()
	show_tab(list.selected_id())


func handle_cancel() -> bool:
	var row := rows.current()
	if row is SettingRow and (row as SettingRow).is_editing():
		(row as SettingRow).field.release_focus()
		return true
	if SettingsManager.is_display_pending():
		SettingsManager.revert_display()
		return true
	if rows.active:
		focus_list()
		return true
	return false


func focus_rows() -> void:
	if rows.rows().is_empty():
		return
	list.active = false
	rows.active = true
	if rows.selected < 0:
		rows.select_index(0)
	_on_row_selected(rows.current())


func focus_list() -> void:
	rows.active = false
	list.active = true
	description.text = ""
	_update_extras(null)


## Builds the rows of `tab_id` (12 §2 to §7 order).
func show_tab(tab_id: StringName) -> void:
	if tab_id == &"" or rows == null:
		return
	var keep := rows.current().id if rows.current() != null and tab_id == tab else &""
	tab = tab_id
	rows.clear_rows()
	for key in SettingsSchema.keys_for(tab):
		if _row_visible(key):
			var r := SettingRow.new(key)
			r.value_chosen.connect(_on_value_chosen)
			rows.add_row(r)
	if tab == SettingsSchema.TAB_CONTROLS:
		rows.add_row(MenuRow.new(ROW_BINDINGS, String(Strings.SETTING_LABELS[ROW_BINDINGS]),
				String(Strings.SETTING_DESCRIPTIONS[ROW_BINDINGS])))
	rows.add_spacer()
	rows.add_row(MenuRow.new(ROW_RESET, Strings.SETTINGS_RESET_TAB))
	refresh_rows()
	if keep != &"":
		rows.select_id(keep)
	elif rows.active:
		rows.select_index(0)
	_update_extras(rows.current() if rows.active else null)


func _row_visible(key: StringName) -> bool:
	if key == &"light_pool_size":
		return SettingsManager.get_value(&"preset") == SettingsSchema.PRESET_CUSTOM   # 12 §3: Custom only
	if key == &"debug_overlay":
		return OS.is_debug_build()
	return true


## Greys and overrides that depend on other options (12 §2, §3).
func refresh_rows() -> void:
	if rows == null:
		return
	var want_pool := _row_visible(&"light_pool_size")
	if tab == SettingsSchema.TAB_GRAPHICS and want_pool != (rows.find_row(&"light_pool_size") != null):
		show_tab.call_deferred(tab)
		return
	var vals := {}
	for k: StringName in SettingsSchema.DEFAULTS:
		vals[k] = SettingsManager.get_value(k)
	for r in rows.rows():
		if r is SettingRow:
			var sr := r as SettingRow
			sr.enabled = true
			sr.override_text = ""
			if sr.id == &"anti_aliasing" and SettingsApply.fsr_active(vals):
				sr.enabled = false
				sr.override_text = Strings.SETTINGS_AA_FSR_ACTIVE
			elif sr.id == &"resolution" and vals[&"window_mode"] == &"fullscreen":
				sr.enabled = false   # 12 §2: windowed and exclusive only
		r.refresh()


func _on_setting_changed(_k: StringName, _v: Variant) -> void:
	if is_visible_in_tree():
		refresh_rows()


func _on_display_resolved(_kept: bool) -> void:
	_end_revert()


func _on_value_chosen(key: StringName, value: Variant) -> void:
	if key in SettingsSchema.REVERT_KEYS:
		SettingsManager.try_display(key, value)
		if SettingsManager.is_display_pending():
			_begin_revert()
	elif key == &"preset":
		SettingsManager.apply_preset(StringName(value))
	else:
		SettingsManager.set_value(key, value)
	refresh_rows()


func _on_row_activated(row: MenuRow) -> void:
	match row.id:
		ROW_RESET:
			SettingsManager.reset_tab(tab)
			show_tab(tab)
		ROW_BINDINGS:
			open_requested.emit(PAGE_BINDINGS)


func _on_row_selected(row: MenuRow) -> void:
	if row == null:
		return
	description.text = row.description
	_update_extras(row)


func _update_extras(row: MenuRow) -> void:
	MenuPage.clear_children(extras)
	if row != null and row.id == &"brightness":
		extras.add_child(SettingsExtras.brightness_strip())
	elif tab == SettingsSchema.TAB_CONTROLS:
		extras.add_child(SettingsExtras.sensitivity_test())


# --- KEEP / REVERT (12 §1) ----------------------------------------------------------------

func _build_revert_box() -> void:
	revert_box = VBoxContainer.new()
	revert_box.add_theme_constant_override(&"separation", 0)
	revert_line = Label.new()
	revert_line.theme_type_variation = &"AccentLabel"
	revert_box.add_child(revert_line)
	revert_list = MenuList.new()
	revert_list.add_item(ITEM_KEEP, Strings.SETTINGS_REVERT_KEEP)
	revert_list.add_item(ITEM_REVERT, Strings.SETTINGS_REVERT_BACK)
	revert_list.activated.connect(func(id: StringName) -> void:
		if id == ITEM_KEEP:
			SettingsManager.keep_display()
		else:
			SettingsManager.revert_display())
	revert_box.add_child(revert_list)
	revert_box.visible = false
	revert_list.active = false
	detail.add_child(revert_box)


func _begin_revert() -> void:
	revert_box.visible = true
	rows.active = false
	revert_list.active = true
	revert_list.selected = 0
	revert_list.active = true
	_update_revert_line()


func _end_revert() -> void:
	if revert_box == null or not revert_box.visible:
		return
	revert_box.visible = false
	revert_list.active = false
	rows.active = true
	refresh_rows()


func _update_revert_line() -> void:
	revert_line.text = Strings.SETTINGS_REVERT_COUNTDOWN.replace("{seconds}", str(SettingsManager.display_seconds_left()))


func _process(_delta: float) -> void:
	if revert_box != null and revert_box.visible:
		_update_revert_line()
