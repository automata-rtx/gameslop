extends TestCase
## M0.5: UI assets of 04 (glyphs, theme, fonts) load headless, mirror UiTokens, and the
## debug gallery instantiates and frees without engine errors.

const GALLERY_PATH := "res://scenes/debug/ui_gallery.tscn"
const DOC_04 := "res://../docs/design/04_ui_design_language.md"
const FONT_LICENCE := "res://assets/fonts/OFL.txt"

## Theme types 04 / the M0.5 brief require, with one item each must define.
const REQUIRED_ITEMS: Array[Array] = [
	[&"Button", Theme.DATA_TYPE_STYLEBOX, &"normal"],
	[&"Button", Theme.DATA_TYPE_FONT, &"font"],
	[&"Label", Theme.DATA_TYPE_COLOR, &"font_color"],
	[&"Panel", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"PanelContainer", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"LineEdit", Theme.DATA_TYPE_STYLEBOX, &"normal"],
	[&"LineEdit", Theme.DATA_TYPE_STYLEBOX, &"focus"],
	[&"HSlider", Theme.DATA_TYPE_STYLEBOX, &"slider"],
	[&"HSlider", Theme.DATA_TYPE_STYLEBOX, &"grabber_area"],
	[&"CheckBox", Theme.DATA_TYPE_ICON, &"checked"],
	[&"CheckBox", Theme.DATA_TYPE_ICON, &"unchecked"],
	[&"OptionButton", Theme.DATA_TYPE_ICON, &"arrow"],
	[&"OptionButton", Theme.DATA_TYPE_STYLEBOX, &"normal"],
	[&"ScrollContainer", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"VScrollBar", Theme.DATA_TYPE_STYLEBOX, &"grabber"],
	[&"TabContainer", Theme.DATA_TYPE_STYLEBOX, &"tab_selected"],
	[&"TabContainer", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"Leader", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"MenuPanel", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"NoteSheetFaller", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"NoteSheetBuilder", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"NoteSheetStray", Theme.DATA_TYPE_STYLEBOX, &"panel"],
	[&"Prompt", Theme.DATA_TYPE_STYLEBOX, &"normal"],
	[&"Caption", Theme.DATA_TYPE_STYLEBOX, &"normal"],
]


## Collects engine errors and warnings raised while a block runs (Godot 4.5+ Logger).
class ErrorCatcher extends Logger:
	var lines: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("[%d] %s (%s:%d %s) %s" % [error_type, code, file, line, function, rationale])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _theme() -> Theme:
	return load(UiTokens.THEME_PATH) as Theme


func test_glyph_list_matches_doc_04() -> void:
	var path := ProjectSettings.globalize_path(DOC_04)
	if not FileAccess.file_exists(path):
		# Exported builds have no docs; the repository always does.
		fail("04 not found at %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var section := text.get_slice("## 5. Glyphs", 1).get_slice("\n## ", 0)
	var listed := section.get_slice("Required set:", 1)
	var rx := RegEx.create_from_string("`([a-z_]+)`")
	var names: Array[StringName] = []
	for m in rx.search_all(listed):
		names.append(StringName(m.get_string(1)))
	assert_gt(names.size(), 30, "parsed the 04 §5 list")
	assert_eq(names, UiTokens.GLYPHS, "UiTokens.GLYPHS mirrors 04 §5 in order")


func test_every_glyph_exists_and_loads_as_texture() -> void:
	for glyph_name in UiTokens.GLYPHS:
		var path := UiTokens.glyph_path(glyph_name)
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var tex := load(path) as Texture2D
		assert_not_null(tex, "%s loads as Texture2D" % path)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE), "%s is 24x24" % glyph_name)


func test_glyph_svgs_follow_04_rules() -> void:
	# 04 §5 / 02 T8: hand-written vector, 24x24 viewBox, 1.5 px round strokes, no raster.
	for glyph_name in UiTokens.GLYPHS:
		var src := FileAccess.get_file_as_string(UiTokens.glyph_path(glyph_name))
		assert_contains(src, "viewBox=\"0 0 24 24\"", "%s viewBox" % glyph_name)
		assert_contains(src, "stroke-width=\"1.5\"", "%s stroke" % glyph_name)
		assert_contains(src, "stroke-linecap=\"round\"", "%s caps" % glyph_name)
		assert_contains(src, "fill=\"none\"", "%s unfilled by default" % glyph_name)
		assert_false(src.contains("<image") or src.contains("data:"), "%s embeds no raster" % glyph_name)
		assert_eq(src.count("stroke-width="), 1, "%s uses one stroke weight" % glyph_name)
		var fills := src.count("fill=") - 1
		if glyph_name == &"polaroid":
			assert_eq(fills, 1, "polaroid's bottom band is the one noted fill")
		else:
			assert_eq(fills, 0, "%s has no fills (04 §5)" % glyph_name)


func test_fonts_are_bundled_with_licence() -> void:
	for p in [UiTokens.FONT_REGULAR_PATH, UiTokens.FONT_BOLD_PATH]:
		assert_true(ResourceLoader.exists(p), "%s bundled" % p)
		assert_true(load(p) is FontFile, "%s loads as FontFile" % p)
	assert_true(FileAccess.file_exists(FONT_LICENCE), "OFL.txt ships beside the fonts")
	assert_contains(FileAccess.get_file_as_string(FONT_LICENCE), "SIL Open Font License")


func test_fonts_cover_04_characters() -> void:
	# Non-ASCII characters 04 prints: menu prefix, separators, leader, belt count, empty slot.
	# System fallback is off in the import so a missing glyph shows, not a borrowed one.
	# (04 §4's block cursor U+25AE is not in JetBrains Mono; reported, not tested here.)
	var chars := "▸·…—×░ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789[]:,%"
	for p in [UiTokens.FONT_REGULAR_PATH, UiTokens.FONT_BOLD_PATH]:
		var f := load(p) as FontFile
		assert_false(f.allow_system_fallback, "%s has no system fallback" % p)
		for i in chars.length():
			assert_true(f.has_char(chars.unicode_at(i)), "%s covers %s" % [p.get_file(), chars[i]])


func test_theme_loads_with_font() -> void:
	var theme := _theme()
	assert_not_null(theme, "theme loads")
	if theme == null:
		return
	assert_not_null(theme.default_font, "default font set")
	assert_eq(theme.default_font.resource_path, UiTokens.FONT_REGULAR_PATH)
	assert_eq(theme.default_font_size, UiTokens.FONT_MENU_ITEM)
	assert_true(theme.has_font(&"bold", UiTokens.THEME_TOKEN_TYPE), "bold font token")
	assert_eq(theme.get_font(&"bold", UiTokens.THEME_TOKEN_TYPE).resource_path, UiTokens.FONT_BOLD_PATH)
	assert_eq(theme.default_font.get_font_name(), "JetBrains Mono")


func test_theme_tokens_match_ui_tokens() -> void:
	var theme := _theme()
	var t := UiTokens.THEME_TOKEN_TYPE
	for k: StringName in UiTokens.COLORS:
		assert_true(theme.has_color(k, t), "theme has colour %s" % k)
		assert_true(theme.get_color(k, t).is_equal_approx(UiTokens.COLORS[k]), "colour %s matches" % k)
	assert_eq(theme.get_font_size(&"hud_body", t), UiTokens.FONT_HUD_BODY)
	assert_eq(theme.get_font_size(&"hud_numeral", t), UiTokens.FONT_HUD_NUMERAL)
	assert_eq(theme.get_font_size(&"prompt", t), UiTokens.FONT_PROMPT)
	assert_eq(theme.get_font_size(&"menu_item", t), UiTokens.FONT_MENU_ITEM)
	assert_eq(theme.get_font_size(&"menu_heading", t), UiTokens.FONT_MENU_HEADING)
	assert_eq(theme.get_font_size(&"wordmark", t), UiTokens.FONT_WORDMARK)
	assert_eq(theme.get_font_size(&"note", t), UiTokens.FONT_NOTE)
	assert_eq(theme.get_font_size(&"caption", t), UiTokens.FONT_CAPTION)
	assert_eq(theme.get_constant(&"grid", t), UiTokens.GRID)
	assert_eq(theme.get_constant(&"line", t), UiTokens.LINE)
	assert_eq(theme.get_constant(&"menu_row_height", t), UiTokens.MENU_ROW_HEIGHT)
	# Spot-check that the controls use the tokens, not near-miss literals.
	assert_true(theme.get_color(&"font_color", &"Label").is_equal_approx(UiTokens.UI_FG))
	assert_true(theme.get_color(&"font_focus_color", &"Button").is_equal_approx(UiTokens.UI_ACCENT))
	assert_true(theme.get_color(&"font_color", &"DangerLabel").is_equal_approx(UiTokens.UI_DANGER))
	assert_true(theme.get_color(&"font_color", &"ColdLabel").is_equal_approx(UiTokens.UI_COLD))
	assert_eq(theme.get_font_size(&"font_size", &"Wordmark"), UiTokens.FONT_WORDMARK)


func test_theme_covers_required_controls() -> void:
	var theme := _theme()
	for item in REQUIRED_ITEMS:
		assert_true(theme.has_theme_item(item[1], item[2], item[0]), "%s/%s" % [item[0], item[2]])
	assert_true(theme.get_stylebox(&"panel", &"Leader") is LeaderStyleBox, "dotted leader StyleBox (04 Interfaces)")


func test_theme_geometry_is_hard_edged() -> void:
	# 04 §1, §4: no rounded corners, no shadows, lines 1 px.
	var theme := _theme()
	for type in theme.get_stylebox_type_list():
		for sb_name in theme.get_stylebox_list(type):
			var sb := theme.get_stylebox(sb_name, type)
			var label := "%s/%s" % [type, sb_name]
			if sb is StyleBoxFlat:
				var f := sb as StyleBoxFlat
				for c in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_LEFT, CORNER_BOTTOM_RIGHT]:
					assert_eq(f.get_corner_radius(c), 0, label + " corner")
				assert_eq(f.shadow_size, 0, label + " shadow")
				for s in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
					assert_true(f.get_border_width(s) <= UiTokens.LINE, label + " border <= 1 px")
			elif sb is StyleBoxLine:
				assert_eq((sb as StyleBoxLine).thickness, UiTokens.LINE, label + " line")


func test_tracking_matches_04() -> void:
	assert_eq(UiTokens.tracking_px(UiTokens.FONT_MENU_ITEM), 2)
	assert_eq(UiTokens.tracking_px(UiTokens.FONT_WORDMARK, UiTokens.TRACKING_WORDMARK_EM), 29)
	var wordmark := _theme().get_font(&"font", &"Wordmark") as FontVariation
	assert_not_null(wordmark, "wordmark is a tracked FontVariation")
	if wordmark != null:
		assert_eq(wordmark.spacing_glyph, 29)
	assert_eq(UiTokens.line_px(0.75), 1, "lines never below 1 px")
	assert_eq(UiTokens.line_px(1.5), 2)


func test_gallery_instantiates_and_frees_cleanly() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var packed := load(GALLERY_PATH) as PackedScene
	assert_not_null(packed, "gallery scene loads")
	if packed == null:
		OS.remove_logger(catcher)
		return
	var gallery := packed.instantiate() as Control
	assert_true(gallery is UiGallery, "root is UiGallery")
	add_child(gallery)
	await await_frames(3)
	var icons := gallery.find_children("Glyph_*", "TextureRect", true, false)
	assert_eq(icons.size(), UiTokens.GLYPHS.size(), "one TextureRect per glyph")
	for icon in icons:
		assert_not_null((icon as TextureRect).texture, "%s has a texture" % icon.name)
	gallery.queue_free()
	await await_frames(2)
	OS.remove_logger(catcher)
	assert_false(is_instance_valid(gallery), "gallery freed")
	assert_eq(catcher.lines, PackedStringArray(), "no engine errors while the gallery lived")
