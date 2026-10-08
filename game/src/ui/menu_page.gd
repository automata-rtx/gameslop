class_name MenuPage
extends HBoxContainer
## One page of the MenuShell (04 §7): a left column list (MenuList) and a right column detail
## area. Pages are registered with the shell by id and ask it to open other pages or go back
## through signals (signals up). Subclasses build their content in build() and refresh it in
## on_open(); handle_cancel() returns true when Esc was used inside the page (leaving a detail
## column, cancelling a rebind) so the shell does not go back.

signal open_requested(id: StringName)
signal back_requested

## Width of the left column at 1080p (8 px grid).
const LIST_WIDTH := UiTokens.GRID * 52
const COLUMN_GAP := UiTokens.GRID * 8
## The detail column's width at 1080p; leaders stay readable instead of spanning the screen.
const DETAIL_WIDTH := UiTokens.GRID * 120

## The title line of the shell while this page is open.
var title: String = ""
## False for pages that draw their own heading (the title screen).
var show_header: bool = true
var list: MenuList
var left: VBoxContainer
var detail: VBoxContainer
var _built: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", COLUMN_GAP)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	left = VBoxContainer.new()
	left.custom_minimum_size.x = LIST_WIDTH
	left.add_theme_constant_override(&"separation", 0)
	add_child(left)
	list = MenuList.new()
	left.add_child(list)
	detail = VBoxContainer.new()
	detail.custom_minimum_size.x = DETAIL_WIDTH
	detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override(&"separation", UiTokens.GRID)
	add_child(detail)


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	build()


## Builds the page once (override).
func build() -> void:
	pass


## Called each time the shell shows the page (override to refresh from state).
func on_open() -> void:
	pass


## Esc inside the page. True when consumed (the shell then stays on this page).
func handle_cancel() -> bool:
	return false


## A dim one-line description (sentence case, 04 §2) for the detail column.
static func description_label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Description"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## `LABEL ………… value` with the dotted leader (04 §7) for read-only rows.
static func leader_row(label_text: String, value_text: String, value_color: Color = UiTokens.UI_FG) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTokens.GRID)
	row.custom_minimum_size.y = UiTokens.GRID * 4
	var l := Label.new()
	l.theme_type_variation = &"MenuItemLabel"
	l.text = label_text
	row.add_child(l)
	var leader := Panel.new()
	leader.theme_type_variation = &"Leader"
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(leader)
	var v := Label.new()
	v.theme_type_variation = &"MenuItemLabel"
	v.text = value_text
	v.add_theme_color_override(&"font_color", value_color)
	row.add_child(v)
	return row


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
