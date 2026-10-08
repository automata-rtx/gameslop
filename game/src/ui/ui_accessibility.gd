class_name UiAccessibility
extends RefCounted
## The 12 §6 options that change the readout's tokens, applied live to the project theme
## (`noclip_theme.tres`, which every Control inherits) and to UiTokens (code-drawn colours):
## - Colour-blind safe accent: every theme colour equal to ui_accent (text, focus, StyleBox
##   fills and borders) becomes #FFD166; AccentLabel gets a 1 px ui_fg outline.
## - Text size: the note and caption text types scale (12 §6: "note and caption sizes only").
## SettingsManager calls these through SettingsApply; parts that paint in code listen to
## SettingsManager.changed and repaint (HUD, menus repaint on their next refresh).

## Theme text types that Text size multiplies, with their 04 §2 sizes.
const TEXT_SIZE_TYPES: Dictionary = {
	&"Caption": UiTokens.FONT_CAPTION,
	&"NoteBody": UiTokens.FONT_NOTE,
	&"NoteHeader": UiTokens.FONT_HUD_BODY,
}
const ACCENT_LABEL := &"AccentLabel"

## Theme entries that held ui_accent when first scanned: [type, name, kind] with kind
## &"color" or a StyleBox property name.
static var _accent_entries: Array = []
static var _scanned_theme: Theme = null


static func project_theme() -> Theme:
	var t := ThemeDB.get_project_theme()
	if t == null and ResourceLoader.exists(UiTokens.THEME_PATH):
		t = load(UiTokens.THEME_PATH) as Theme
	return t


## 12 §6 Colour-blind safe accent, live. Idempotent.
static func apply_colorblind(on: bool, theme: Theme = null) -> void:
	UiTokens.colorblind = on
	var t := theme if theme != null else project_theme()
	if t == null:
		return
	_scan(t)
	var c := UiTokens.accent()
	for e: Array in _accent_entries:
		var type: StringName = e[0]
		var item: StringName = e[1]
		var kind: StringName = e[2]
		if kind == &"color":
			var old := t.get_color(item, type)
			t.set_color(item, type, Color(c, old.a))
		else:
			var sb := t.get_stylebox(item, type) as StyleBoxFlat
			if sb != null:
				var old_c: Color = sb.get(kind)
				sb.set(kind, Color(c, old_c.a))
	if on:
		t.set_constant(&"outline_size", ACCENT_LABEL, UiTokens.LINE)
		t.set_color(&"font_outline_color", ACCENT_LABEL, UiTokens.UI_FG)
	else:
		if t.has_constant(&"outline_size", ACCENT_LABEL):
			t.clear_constant(&"outline_size", ACCENT_LABEL)
		if t.has_color(&"font_outline_color", ACCENT_LABEL):
			t.clear_color(&"font_outline_color", ACCENT_LABEL)


## 12 §6 Text size (0.9 to 1.4), live: note and caption sizes.
static func apply_text_size(v: float, theme: Theme = null) -> void:
	UiTokens.text_size = clampf(v, Tuning.SETTINGS_TEXT_SIZE_MIN, Tuning.SETTINGS_TEXT_SIZE_MAX)
	var t := theme if theme != null else project_theme()
	if t == null:
		return
	for type: StringName in TEXT_SIZE_TYPES:
		t.set_font_size(&"font_size", type, UiTokens.text_px(int(TEXT_SIZE_TYPES[type])))


## Remembers which entries are the accent (scanned once per theme, while the accent is the
## 04 §3 one, so swapping back and forth never loses an entry).
static func _scan(t: Theme) -> void:
	if _scanned_theme == t:
		return
	_scanned_theme = t
	_accent_entries.clear()
	for type in t.get_type_list():
		if type == UiTokens.THEME_TOKEN_TYPE:
			continue  # the token table keeps both values (tests compare it to UiTokens)
		for item in t.get_color_list(type):
			if _is_accent(t.get_color(item, type)):
				_accent_entries.append([type, item, &"color"])
		for item in t.get_stylebox_list(type):
			var sb := t.get_stylebox(item, type) as StyleBoxFlat
			if sb == null:
				continue
			for prop: StringName in [&"bg_color", &"border_color"]:
				if _is_accent(sb.get(prop)):
					_accent_entries.append([type, item, prop])


static func _is_accent(c: Color) -> bool:
	for ref: Color in [UiTokens.UI_ACCENT, UiTokens.UI_ACCENT_CB]:
		if absf(c.r - ref.r) < 0.003 and absf(c.g - ref.g) < 0.003 and absf(c.b - ref.b) < 0.003:
			return true
	return false
