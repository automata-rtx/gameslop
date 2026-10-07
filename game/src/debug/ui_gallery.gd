class_name UiGallery
extends Control
## Debug gallery for screenshot review of the readout UI (04 §11): every glyph with its
## name, the type scale, colour tokens, one of each themed control, the dotted leader, the
## note-sheet voices, and the HUD states (M1.6, HudGalleryStates). Menus join it as they
## are built. Flags after `--`:
##   --hud-state NAME   show one HUD state full screen
##   --hud-shots DIR    save every HUD state as DIR/hud_<state>_<w>x<h>.png, then quit Debug-only text: the strings here are labels for review, not player text, so
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

## Theme variation, note id, header (Strings), for the gallery's sample sheets. Bodies are the
## real notes from DataRegistry.
const NOTE_VOICES: Array[Array] = [
	[&"NoteSheetFaller", &"H3", Strings.NOTE_HEADER_FALLER],
	[&"NoteSheetBuilder", &"H4", Strings.NOTE_HEADER_BUILDER],
	[&"NoteSheetStray", &"H6", Strings.NOTE_HEADER_STRAY],
	[&"NoteSheet", &"H3", Strings.NOTE_HEADER_FALLER],
]

const HUD_PREVIEW_SIZE := Vector2i(1920, 1080)
const HUD_PREVIEW_SCALE := 0.5

@onready var _content: VBoxContainer = %Content

var _hud_viewport: SubViewport


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shots := _arg(args, "--hud-shots")
	var one := _arg(args, "--hud-state")
	if not shots.is_empty():
		_hud_shots.call_deferred(shots)
		return
	if not one.is_empty():
		_full_screen_state(StringName(one))
		return
	_section("GLYPHS", _glyph_grid())
	_section("TYPE SCALE", _type_scale())
	_section("COLOUR", _swatches())
	_section("CONTROLS", _controls())
	_section("NOTE SHEETS", _note_sheets())
	_section("HUD STATES", _hud_states())


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
		var note: NoteData = DataRegistry.note(voice[1])
		header.text = String(voice[2]).format({"id": voice[1], "number": "0014"})
		v.add_child(header)
		var body := Label.new()
		body.theme_type_variation = &"NoteBody"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = note.text if note != null else ""
		v.add_child(body)
		sheet.add_child(v)
		box.add_child(sheet)
	return box


# --- HUD states (M1.6) -------------------------------------------------------------------

static func _arg(args: PackedStringArray, flag: String) -> String:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(flag + "="):
			return args[i].substr(flag.length() + 1)
	return ""


func _hud_states() -> Control:
	var box := VBoxContainer.new()
	var picker := OptionButton.new()
	for st in HudGalleryStates.STATES:
		picker.add_item(String(st).to_upper())
	box.add_child(picker)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.custom_minimum_size = Vector2(HUD_PREVIEW_SIZE) * HUD_PREVIEW_SCALE
	_hud_viewport = SubViewport.new()
	_hud_viewport.size = HUD_PREVIEW_SIZE
	_hud_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_hud_viewport)
	container.scale = Vector2.ONE * HUD_PREVIEW_SCALE
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(HUD_PREVIEW_SIZE) * HUD_PREVIEW_SCALE
	holder.add_child(container)
	box.add_child(holder)
	picker.item_selected.connect(func(i: int) -> void: _show_preview(HudGalleryStates.STATES[i]))
	_show_preview.call_deferred(HudGalleryStates.STATES[0])
	return box


func _show_preview(state: StringName) -> void:
	for c in _hud_viewport.get_children():
		c.free()
	var root := Control.new()
	root.theme = theme
	root.size = Vector2(HUD_PREVIEW_SIZE)
	_hud_viewport.add_child(root)
	HudGalleryStates.build(root, state)


func _clear_page() -> void:
	for c in get_children():
		c.queue_free()


func _full_screen_state(state: StringName) -> Control:
	_clear_page()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	HudGalleryStates.build(root, state)
	return root


func _hud_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var vp_size := get_viewport().get_visible_rect().size
	for state in HudGalleryStates.STATES:
		var root := _full_screen_state(state)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/hud_%s_%dx%d.png" % [dir, state, int(vp_size.x), int(vp_size.y)]
		img.save_png(path)
		print("ui_gallery: saved ", path)
		root.free()
	UiMotion.manual_clock = false
	get_tree().quit(0)


func _exit_tree() -> void:
	UiMotion.manual_clock = false
