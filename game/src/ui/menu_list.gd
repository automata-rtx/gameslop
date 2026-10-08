class_name MenuList
extends VBoxContainer
## The menus' left-column list (04 §7): 22 px items in 40 px rows, the selected item in
## ui_accent with a `▸` prefix, disabled items in ui_dim. Arrows / Enter and the mouse both
## work; the selection follows the hovered item. Emits `activated(id)`.
## `active` false parks the keyboard (a page has moved focus to its detail column); the
## selection then shows in ui_fg so only one accent is on screen (04 §3).

signal activated(id: StringName)
signal selection_changed(id: StringName)
## Right arrow on an item (pages move focus into their detail column).
signal advanced(id: StringName)

var ids: Array[StringName] = []
var selected: int = 0
var active: bool = true:
	set(v):
		active = v
		_refresh()
var _labels: Array[Label] = []
var _texts: Array[String] = []
var _enabled: Array[bool] = []


func _init() -> void:
	add_theme_constant_override(&"separation", 0)
	focus_mode = Control.FOCUS_NONE


func add_item(id: StringName, text: String, enabled: bool = true) -> void:
	var l := Label.new()
	l.theme_type_variation = &"MenuItemLabel"
	l.custom_minimum_size.y = UiTokens.MENU_ROW_HEIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	var i := ids.size()
	l.mouse_entered.connect(func() -> void:
		if active:
			select(i))
	l.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if not active:
				active = true
			activate(i))
	add_child(l)
	ids.append(id)
	_labels.append(l)
	_texts.append(text)
	_enabled.append(enabled)
	_refresh()


func clear_items() -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	ids.clear()
	_texts.clear()
	_enabled.clear()
	selected = 0


func set_item_text(id: StringName, text: String) -> void:
	var i := ids.find(id)
	if i >= 0:
		_texts[i] = text
		_refresh()


func set_item_enabled(id: StringName, enabled: bool) -> void:
	var i := ids.find(id)
	if i >= 0:
		_enabled[i] = enabled
		_refresh()


func is_item_enabled(id: StringName) -> bool:
	var i := ids.find(id)
	return i >= 0 and _enabled[i]


func selected_id() -> StringName:
	return ids[selected] if selected >= 0 and selected < ids.size() else &""


func select(i: int) -> void:
	if i < 0 or i >= ids.size() or i == selected:
		return
	selected = i
	AudioManager.play_2d(&"ui_move")
	_refresh()
	selection_changed.emit(ids[i])


func select_id(id: StringName) -> void:
	select(ids.find(id))


func activate(i: int = -1) -> void:
	if i < 0:
		i = selected
	if i < 0 or i >= ids.size() or not _enabled[i]:
		return
	selected = i
	_refresh()
	AudioManager.play_2d(&"ui_confirm")
	activated.emit(ids[i])


func _unhandled_input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree() or ids.is_empty():
		return
	if handle_key(event):
		get_viewport().set_input_as_handled()


## Keyboard navigation (also called by pages that route input by hand). True when used.
func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_down", true):
		select(posmod(selected + 1, ids.size()))
	elif event.is_action_pressed(&"ui_up", true):
		select(posmod(selected - 1, ids.size()))
	elif event.is_action_pressed(&"ui_accept"):
		activate()
	elif event.is_action_pressed(&"ui_right") and advanced.get_connections().size() > 0:
		advanced.emit(selected_id())
	else:
		return false
	return true


func _refresh() -> void:
	for i in _labels.size():
		var on := i == selected
		_labels[i].text = (Strings.MENU_SELECTED_PREFIX if on else "  ") + _texts[i]
		var col := UiTokens.UI_FG if _enabled[i] else UiTokens.UI_DIM
		if on and _enabled[i] and active:
			col = UiTokens.UI_ACCENT
		_labels[i].add_theme_color_override(&"font_color", col)
