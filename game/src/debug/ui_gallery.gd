class_name UiGallery
extends Control
## Debug gallery for screenshot review of the readout UI (04 §11). M0.5 placeholder: every
## glyph with its name, the type scale, colour tokens, one of each themed control, the
## dotted leader, and the note-sheet voices. HUD states and menus join it as they are
## built. Debug-only text: the strings here are labels for review, not player text, so
## they do not live in strings.gd.

const GLYPH_COLUMNS := 6
const SWATCH_SIZE := Vector2(64, 32)

## Type roles of 04 §2 as theme type variations, with a sample in the role's casing.
const TYPE_ROLES: Array[Array] = [
	[&"Wordmark", "NOCLIP"],
	[&"MenuHeading", "SETTINGS"],
	[&"MenuItemLabel", "DESCEND"],
	[&"HudNumeral", "087"],
	[&"Prompt", "[E] OPEN DOOR"],
	[&"Hint", "[F] FLASHLIGHT"],
	[&"HudBody", "DEPTH 03 · GARAGE"],
	[&"HudLabel", "COHERENCE"],
	[&"TitleSubline", "v1.0.0 · MADE BY AN AI"],
	[&"Caption", "[hum, left]"],
	[&"NoteHeader", "NOTE H3 · HANDWRITTEN"],
	[&"NoteBody", "The lights here are on a timer that nobody set."],
	[&"Description", "Horizontal field of view at 16:9."],
	[&"AccentLabel", "ITEM UNLOCKED: RADIO"],
	[&"DangerLabel", "DISSOLVED"],
	[&"ColdLabel", "DEPTH 06 · SUBSTRATE"],
]

const NOTE_VOICES: Array[Array] = [
	[&"NoteSheetFaller", "NOTE H3 · HANDWRITTEN", "I counted the doors twice and got two answers."],
	[&"NoteSheetBuilder", "RENDER NOTE 0014", "Corridor tiling exceeds budget. Left as is."],
	[&"NoteSheetStray", "FOUND OBJECT", "A receipt for one coffee, dated tomorrow."],
	[&"NoteSheet", "NOTE", "Default backing."],
]

@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	_section("GLYPHS", _glyph_grid())
	_section("TYPE SCALE", _type_scale())
	_section("COLOUR", _swatches())
	_section("CONTROLS", _controls())
	_section("NOTE SHEETS", _note_sheets())


func _section(title: String, body: Control) -> void:
	var heading := Label.new()
	heading.theme_type_variation = &"MenuHeading"
	heading.text = title
	_content.add_child(heading)
	_content.add_child(HSeparator.new())
	_content.add_child(body)


func _glyph_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = GLYPH_COLUMNS
	grid.add_theme_constant_override(&"h_separation", UiTokens.GRID * 4)
	grid.add_theme_constant_override(&"v_separation", UiTokens.GRID * 2)
	for glyph_name in UiTokens.GLYPHS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override(&"separation", UiTokens.GRID)
		var icon := TextureRect.new()
		icon.name = "Glyph_%s" % glyph_name
		icon.texture = UiTokens.glyph(glyph_name)
		icon.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cell.add_child(icon)
		var label := Label.new()
		label.theme_type_variation = &"HudBody"
		label.text = String(glyph_name).to_upper()
		cell.add_child(label)
		grid.add_child(cell)
	return grid


func _type_scale() -> Control:
	var box := VBoxContainer.new()
	for role in TYPE_ROLES:
		var row := HBoxContainer.new()
		var tag := Label.new()
		tag.theme_type_variation = &"DimLabel"
		tag.custom_minimum_size.x = UiTokens.GRID * 28
		tag.text = "%s %d" % [role[0], get_theme_font_size(&"font_size", role[0])]
		row.add_child(tag)
		var sample := Label.new()
		sample.theme_type_variation = role[0]
		sample.text = role[1]
		row.add_child(sample)
		box.add_child(row)
	return box


func _swatches() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	for token: StringName in UiTokens.COLORS:
		var swatch := ColorRect.new()
		swatch.color = UiTokens.COLORS[token]
		swatch.custom_minimum_size = SWATCH_SIZE
		grid.add_child(swatch)
		var label := Label.new()
		label.theme_type_variation = &"HudBody"
		label.text = "%s  #%s" % [String(token).to_upper(), (UiTokens.COLORS[token] as Color).to_html()]
		grid.add_child(label)
	return grid


func _controls() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	var buttons := HBoxContainer.new()
	var b := Button.new()
	b.text = "▸ DESCEND"
	b.theme_type_variation = &"MenuItem"
	b.custom_minimum_size.y = UiTokens.MENU_ROW_HEIGHT
	buttons.add_child(b)
	var bd := Button.new()
	bd.text = "ENDLESS"
	bd.disabled = true
	buttons.add_child(bd)
	box.add_child(buttons)
	box.add_child(_leader_row("FIELD OF VIEW", "90"))
	box.add_child(_leader_row("MOUSE SENSITIVITY", "1.00"))
	var line := LineEdit.new()
	line.placeholder_text = "seed"
	line.custom_minimum_size.x = UiTokens.SLIDER_TRACK_WIDTH
	box.add_child(_row("LINE EDIT", line))
	var slider := HSlider.new()
	slider.custom_minimum_size.x = UiTokens.SLIDER_TRACK_WIDTH
	slider.value = 60.0
	box.add_child(_row("SLIDER", slider))
	var check := CheckBox.new()
	check.text = "CAPTIONS"
	check.button_pressed = true
	box.add_child(_row("CHECK BOX", check))
	var option := OptionButton.new()
	for item in ["LOW", "MEDIUM", "HIGH"]:
		option.add_item(item)
	option.select(1)
	box.add_child(_row("OPTION BUTTON", option))
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(UiTokens.GRID * 20, UiTokens.MENU_ROW_HEIGHT)
	box.add_child(_row("PANEL", panel))
	var menu := PanelContainer.new()
	menu.theme_type_variation = &"MenuPanel"
	var menu_label := Label.new()
	menu_label.text = "MENU PANEL"
	menu.add_child(menu_label)
	box.add_child(menu)
	box.add_child(_row("SCROLL", _scroll()))
	box.add_child(_tabs())
	var bar := ProgressBar.new()
	bar.custom_minimum_size.x = UiTokens.COHERENCE_BAR_WIDTH
	bar.show_percentage = false
	bar.value = 87.0
	box.add_child(_row("PROGRESS", bar))
	return box


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.custom_minimum_size.x = UiTokens.GRID * 28
	label.text = label_text
	row.add_child(label)
	row.add_child(control)
	return row


func _leader_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(UiTokens.GRID * 70, UiTokens.MENU_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label := Label.new()
	label.theme_type_variation = &"MenuItemLabel"
	label.text = label_text
	row.add_child(label)
	var leader := Panel.new()
	leader.theme_type_variation = &"Leader"
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(leader)
	var value := Label.new()
	value.theme_type_variation = &"MenuItemLabel"
	value.text = value_text
	row.add_child(value)
	return row


func _scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(UiTokens.GRID * 40, UiTokens.GRID * 15)
	var list := VBoxContainer.new()
	for i in 12:
		var l := Label.new()
		l.theme_type_variation = &"HudBody"
		l.text = "LINE %02d" % (i + 1)
		list.add_child(l)
	scroll.add_child(list)
	return scroll


func _tabs() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(UiTokens.GRID * 70, UiTokens.GRID * 12)
	for tab_name in ["DISPLAY", "GRAPHICS", "AUDIO"]:
		var page := Label.new()
		page.name = tab_name
		page.theme_type_variation = &"Description"
		page.text = "Tab page."
		tabs.add_child(page)
	return tabs


func _note_sheets() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	for voice in NOTE_VOICES:
		var sheet := PanelContainer.new()
		sheet.theme_type_variation = voice[0]
		sheet.custom_minimum_size.x = UiTokens.NOTE_SHEET_WIDTH
		sheet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var v := VBoxContainer.new()
		var header := Label.new()
		header.theme_type_variation = &"NoteHeader"
		header.text = voice[1]
		v.add_child(header)
		var body := Label.new()
		body.theme_type_variation = &"NoteBody"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = voice[2]
		v.add_child(body)
		sheet.add_child(v)
		box.add_child(sheet)
	return box
