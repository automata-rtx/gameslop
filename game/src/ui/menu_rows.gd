class_name MenuRows
extends ScrollContainer
## The detail column's selectable rows (04 §7): up/down select, left/right adjust, Enter
## activates; the mouse selects by hovering and acts by clicking. Only reacts while `active`
## (the page decides whether focus is in the list or in the rows). The column scrolls to keep
## the selection in view only when the UI scale makes it taller than the screen; at 1.0 every
## tab fits (04 §7: the list never scrolls more than one screen).

signal selection_changed(row: MenuRow)
signal row_activated(row: MenuRow)
## Left arrow on a row that does not adjust: the page moves focus back to its list.
signal retreated
## The mouse moved onto a row while the list had focus: the page hands focus to the rows.
signal focus_taken

var active: bool = false:
	set(v):
		active = v
		_refresh_selection()
var selected: int = -1
## Input parked while a row captures (a rebind) but the selection stays drawn.
var locked: bool = false
var box: VBoxContainer
## Share of the window height the rows may take before they scroll (UI scale above 1.0).
var max_height_ratio: float = 0.72


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Scrolls without a bar: the selection is always kept in view (no decoration, 04 §1).
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	size_flags_vertical = Control.SIZE_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	follow_focus = false
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 0)
	box.minimum_size_changed.connect(fit_height)
	add_child(box)


## As tall as the rows, up to max_height_ratio of the window; beyond that it scrolls.
## (ScrollContainer's own minimum height is zero, so it is set by hand.)
func fit_height() -> void:
	var want := box.get_combined_minimum_size().y
	var cap := get_viewport_rect().size.y * max_height_ratio if is_inside_tree() else want
	custom_minimum_size.y = minf(want, cap)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		fit_height.call_deferred()


func rows() -> Array[MenuRow]:
	var out: Array[MenuRow] = []
	for c in box.get_children():
		if c is MenuRow and not c.is_queued_for_deletion() and (c as MenuRow).visible:
			out.append(c as MenuRow)
	return out


func add_row(row: MenuRow) -> MenuRow:
	box.add_child(row)
	row.hovered.connect(func(r: MenuRow) -> void:
		if locked or (not r.enabled and not active):
			return
		if not active:
			active = true
			focus_taken.emit()
		select_row(r))
	row.activated.connect(func(r: MenuRow) -> void: row_activated.emit(r))
	return row


## A non-selectable spacer or caption between rows.
func add_spacer(height: int = UiTokens.GRID * 2) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


func clear_rows() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	selected = -1


func current() -> MenuRow:
	var r := rows()
	return r[selected] if selected >= 0 and selected < r.size() else null


func find_row(row_id: StringName) -> MenuRow:
	for r in rows():
		if r.id == row_id:
			return r
	return null


func select_index(i: int) -> void:
	var r := rows()
	if r.is_empty():
		selected = -1
		return
	i = clampi(i, 0, r.size() - 1)
	var changed := i != selected
	selected = i
	_refresh_selection()
	if changed:
		AudioManager.play_2d(&"ui_move")
		_scroll_to(r[i])
		selection_changed.emit(r[i])


func select_row(row: MenuRow) -> void:
	select_index(rows().find(row))


func select_id(row_id: StringName) -> void:
	var row := find_row(row_id)
	if row != null:
		select_row(row)


func _unhandled_input(event: InputEvent) -> void:
	if not active or locked or not is_visible_in_tree():
		return
	if handle_key(event):
		get_viewport().set_input_as_handled()


func handle_key(event: InputEvent) -> bool:
	var r := rows()
	if r.is_empty():
		return false
	if event.is_action_pressed(&"ui_down", true):
		select_index(posmod(selected + 1, r.size()))
	elif event.is_action_pressed(&"ui_up", true):
		select_index(posmod(selected - 1, r.size()))
	elif event.is_action_pressed(&"ui_left", true):
		var row := current()
		if row == null or not row.adjust(-1):
			retreated.emit()
	elif event.is_action_pressed(&"ui_right", true):
		var row := current()
		if row != null:
			row.adjust(1)
	elif event.is_action_pressed(&"ui_accept"):
		var row := current()
		if row != null:
			row.activate()
	else:
		return false
	return true


func refresh_all() -> void:
	for row in rows():
		row.refresh()


func _refresh_selection() -> void:
	var r := rows()
	for i in r.size():
		r[i].selected = active and i == selected


func _scroll_to(row: MenuRow) -> void:
	if not is_inside_tree():
		return
	var top := row.position.y
	var bottom := top + row.size.y
	if top < scroll_vertical:
		scroll_vertical = int(top)
	elif bottom > scroll_vertical + size.y:
		scroll_vertical = int(bottom - size.y)
