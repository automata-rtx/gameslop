class_name CreditsMenu
extends MenuPage
## The Archive's CREDITS page (16 §6: the credits are "shown in the ending and from the
## Archive"; M3.6). It prints Credits.entries(), the full list, in order, one section per
## left-column item: NOCLIP (the AI line), ENGINE (Godot's MIT notice in full), COMPONENTS
## n/N (the engine's third-party components as `name ………… license` rows, a page at a time so
## nothing scrolls, 04 §7), TYPEFACE, and SOUND, which ends with the LICENSES.txt line and
## "Thank you for looking.". A new heading in the entries starts a new section. Read-only:
## the list is the only focus. The ArchiveMenu opens it (ArchiveMenu.PAGE_CREDITS).

const SECTION_PREFIX := "credits_"
## Short left-column labels for headings too long for the list (the detail prints the heading).
const SHORT_LABELS: Dictionary = {Strings.CREDITS_HEADING_COMPONENTS: "COMPONENTS"}

var body: VBoxContainer
## [{id, label, entries}] in order (entries as Credits.entries() gives them).
var sections: Array[Dictionary] = []


func build() -> void:
	title = Strings.ARCHIVE_CREDITS
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UiTokens.GRID)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(body)
	_add_items()
	list.selection_changed.connect(show_section)


func on_open() -> void:
	list.active = true
	show_section(list.selected_id())


## The component pages follow the row budget of the compact flag (M3.6).
func apply_compact() -> void:
	var keep := list.selected
	list.clear_items()
	_add_items()
	list.select(clampi(keep, 0, list.ids.size() - 1))
	super.apply_compact()
	if is_visible_in_tree():
		show_section(list.selected_id())


func _add_items() -> void:
	sections = build_sections(LicensesMenu.per_page())
	for s in sections:
		list.add_item(s[&"id"], s[&"label"])


## Credits.entries() cut into sections at each heading; a section with more component rows
## than `per_page` becomes several, `COMPONENTS 1/4` and so on, each repeating the heading.
static func build_sections(per_page: int) -> Array[Dictionary]:
	var raw: Array[Dictionary] = [{&"label": Strings.TITLE_WORDMARK, &"entries": []}]
	for e in Credits.entries():
		if e["style"] == Credits.STYLE_HEADING:
			var text := String(e["text"])
			raw.append({&"label": String(SHORT_LABELS.get(text, text)), &"entries": [e]})
		else:
			(raw[-1][&"entries"] as Array).append(e)
	var out: Array[Dictionary] = []
	for s in raw:
		var entries: Array = s[&"entries"]
		var comps: Array = entries.filter(func(e: Dictionary) -> bool: return e["style"] == Credits.STYLE_COMPONENT)
		if comps.size() <= per_page:
			out.append({&"id": StringName(SECTION_PREFIX + str(out.size())), &"label": s[&"label"], &"entries": entries})
			continue
		var head: Array = entries.filter(func(e: Dictionary) -> bool: return e["style"] == Credits.STYLE_HEADING)
		var tail: Array = entries.filter(func(e: Dictionary) -> bool:
			return e["style"] != Credits.STYLE_HEADING and e["style"] != Credits.STYLE_COMPONENT)
		var pages := ceili(float(comps.size()) / float(per_page))
		for p in pages:
			var part: Array = head.duplicate()
			part.append_array(comps.slice(p * per_page, (p + 1) * per_page))
			if p == pages - 1:
				part.append_array(tail)
			var label := Strings.LICENSES_COMPONENTS_PAGE.replace("{page}", str(p + 1)).replace("{pages}", str(pages))
			out.append({&"id": StringName(SECTION_PREFIX + str(out.size())), &"label": label, &"entries": part})
	return out


func section(id: StringName) -> Dictionary:
	for s in sections:
		if s[&"id"] == id:
			return s
	return {}


## Builds the detail column for section `id`.
func show_section(id: StringName) -> void:
	if body == null:
		return
	MenuPage.clear_children(body)
	var s := section(id)
	var entries: Array = s.get(&"entries", [])
	# Component rows sit flush (24 px rows, as on the LICENSES page); prose keeps a gap.
	var rows := entries.any(func(e: Dictionary) -> bool: return e["style"] == Credits.STYLE_COMPONENT)
	body.add_theme_constant_override(&"separation", 0 if rows else UiTokens.GRID)
	for e: Dictionary in entries:
		body.add_child(entry_node(e))


## One entry as the readout prints it.
static func entry_node(e: Dictionary) -> Control:
	var text := String(e["text"])
	match e["style"]:
		Credits.STYLE_GAP:
			var gap := Control.new()
			gap.custom_minimum_size.y = UiTokens.GRID
			return gap
		Credits.STYLE_HEADING:
			return TitlePage._line(&"DimLabel", text)
		Credits.STYLE_SMALL:
			return MenuPage.description_label(text)
		Credits.STYLE_COMPONENT:
			var cut := text.rfind(" · ")
			if cut > 0:
				return LicensesMenu._component_row(text.left(cut), text.substr(cut + 3))
			return MenuPage.description_label(text)
	# Sentence-case lines (the AI line, the engine line, the thanks) print untracked (04 §2:
	# tracking is for uppercase), in ui_fg.
	var l := MenuPage.description_label(text)
	l.add_theme_color_override(&"font_color", UiTokens.UI_FG)
	return l


## The texts section `id` prints (tests).
func section_text(id: StringName) -> String:
	show_section(id)
	var out := PackedStringArray()
	for n in body.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return "\n".join(out)
