class_name LicensesMenu
extends MenuPage
## LICENSES (16 §6: the full notices, reachable from the title's settings; R17). The left
## column: ENGINE (`Godot Engine. MIT license.` and the engine's MIT notice in full, from
## Engine.get_license_text()), COMPONENTS n/N (the engine's third-party components as
## `name ………… license` rows, COMPONENTS_PER_PAGE to a page so nothing scrolls past one
## screen, 04 §7), TYPEFACE (the OFL line and its copyright), SOUND. The detail column shows
## the selected section; the LICENSES.txt line stands under it in ui_dim. Read-only: the list
## is the only focus. Built from Credits, the data the Archive can show too.

const SECTION_ENGINE := &"engine"
const SECTION_TYPEFACE := &"typeface"
const SECTION_AUDIO_CREDITS := &"audio_credits"
const COMPONENTS_PREFIX := "components_"
## Component rows per page: 30 rows of 24 px fit the detail column at 1080p with the footer.
const COMPONENTS_PER_PAGE := 30
## M3.6 compact menus (720 logical px): 20 rows a page.
const COMPONENTS_PER_PAGE_COMPACT := 18
const ROW_HEIGHT := UiTokens.GRID * 3
## A component row longer than this many characters (name and license) takes two lines.
const LONG_ROW_CHARS := 56

var body: VBoxContainer
var footer: Label


func build() -> void:
	title = Strings.MENU_LICENSES
	_add_items()
	list.selection_changed.connect(show_section)
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UiTokens.GRID)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(body)
	footer = MenuPage.description_label(Strings.CREDITS_LICENSES_NOTE)
	detail.add_child(footer)


func _add_items() -> void:
	list.add_item(SECTION_ENGINE, Strings.CREDITS_HEADING_ENGINE)
	var pages := component_pages()
	for i in pages:
		list.add_item(component_section(i), Strings.LICENSES_COMPONENTS_PAGE
				.replace("{page}", str(i + 1)).replace("{pages}", str(pages)))
	list.add_item(SECTION_TYPEFACE, Strings.CREDITS_HEADING_TYPEFACE)
	list.add_item(SECTION_AUDIO_CREDITS, Strings.CREDITS_HEADING_SOUND)


func on_open() -> void:
	list.active = true
	show_section(list.selected_id())


## The component pages follow the row budget of the compact flag (M3.6).
func apply_compact() -> void:
	var keep := list.selected_id()
	list.clear_items()
	_add_items()
	list.select_id(keep if list.ids.has(keep) else SECTION_ENGINE)
	super.apply_compact()
	if is_visible_in_tree():
		show_section(list.selected_id())


## Component rows a page now.
static func per_page() -> int:
	return COMPONENTS_PER_PAGE_COMPACT if UiTokens.compact else COMPONENTS_PER_PAGE


static func component_pages() -> int:
	return maxi(1, ceili(float(Credits.components().size()) / float(per_page())))


static func component_section(page_index: int) -> StringName:
	return StringName(COMPONENTS_PREFIX + str(page_index + 1))


## Builds the detail column for section `id`.
func show_section(id: StringName) -> void:
	if body == null:
		return
	MenuPage.clear_children(body)
	match id:
		SECTION_ENGINE:
			body.add_child(_line(Strings.CREDITS_GODOT))
			body.add_child(MenuPage.description_label("\n\n".join(Credits.license_paragraphs())))
		SECTION_TYPEFACE:
			body.add_child(_line(Strings.CREDITS_FONT))
			body.add_child(MenuPage.description_label(Strings.CREDITS_FONT_COPYRIGHT))
		SECTION_AUDIO_CREDITS:
			body.add_child(_line(Strings.CREDITS_SOUND))
		_:
			var s := String(id)
			if s.begins_with(COMPONENTS_PREFIX):
				_build_components(int(s.trim_prefix(COMPONENTS_PREFIX)) - 1)


func _build_components(page_index: int) -> void:
	var all := Credits.components()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 0)
	body.add_child(rows)
	var from := page_index * per_page()
	for i in range(from, mini(from + per_page(), all.size())):
		rows.add_child(_component_row(String(all[i]["name"]), String(all[i]["license"])))


## `name ………… license` at HUD size (04 §7 leader rows): the name in ui_fg, the license dim.
## M3.6: a pair longer than LONG_ROW_CHARS (the face is monospace) prints the name on its
## own line and the leader and license under it, so no row is wider than a compact column.
static func _component_row(component: String, license: String) -> Control:
	if component.length() + license.length() <= LONG_ROW_CHARS:
		return _leader_line(component, license)
	var two := VBoxContainer.new()
	two.add_theme_constant_override(&"separation", 0)
	var n := MenuPage.description_label(component)
	n.add_theme_color_override(&"font_color", UiTokens.UI_FG)
	two.add_child(n)
	two.add_child(_leader_line("", license))
	return two


static func _leader_line(component: String, license: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTokens.GRID)
	row.custom_minimum_size.y = ROW_HEIGHT
	if not component.is_empty():
		var n := MenuPage.description_label(component)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.add_theme_color_override(&"font_color", UiTokens.UI_FG)
		row.add_child(n)
	var leader := Panel.new()
	leader.theme_type_variation = &"Leader"
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(leader)
	var l := MenuPage.description_label(license)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	return row


static func _line(t: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MenuItemLabel"
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The texts section `id` prints (tests).
func section_text(id: StringName) -> String:
	show_section(id)
	var out := PackedStringArray()
	for n in body.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return "\n".join(out)
