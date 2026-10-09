class_name UiTokens
extends RefCounted
## Design tokens of the readout UI, mirroring 04 §2 to §8 (and the colour-blind accent of
## 12 §6). Code uses these constants instead of literals. The same colours and sizes live
## in res://assets/ui/noclip_theme.tres (type "NoclipTokens"); tests/unit/test_ui_assets.gd
## fails if the two drift. Change 04, this file, and the theme together.

const THEME_PATH := "res://assets/ui/noclip_theme.tres"
const GLYPH_DIR := "res://assets/ui/glyphs"
const FONT_REGULAR_PATH := "res://assets/fonts/JetBrainsMono-Regular.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/JetBrainsMono-Bold.ttf"
## Theme type that carries the colour tokens and size constants (04 Interfaces: Theme).
const THEME_TOKEN_TYPE := &"NoclipTokens"

# --- 04 §3 colour -------------------------------------------------------------------------
const UI_FG := Color("#F2F2F2")        # all text and lines
const UI_DIM := Color("#8C8C8C")       # secondary text, inactive items, bar tracks
const UI_BG := Color("#000000")        # menu backgrounds, backings
const UI_ACCENT := Color("#FFB000")    # "you can act on this"
const UI_DANGER := Color("#FF3B3B")    # "you are about to lose"
const UI_COLD := Color("#3B8BFF")      # "unreal"
## 12 §6 colour-blind safe accent replaces UI_ACCENT when that option is on.
const UI_ACCENT_CB := Color("#FFD166")
## 04 §2/§6: backing rectangle behind prompts and captions is ui_bg at 60%.
const BACKING_ALPHA := 0.6
const UI_BACKING := Color(UI_BG, BACKING_ALPHA)
## 04 §7 pause: the frozen frame is overlaid with 70% black.
const PAUSE_OVERLAY := Color(UI_BG, Tuning.UI_PAUSE_OVERLAY_ALPHA)
## 04 §8 note sheet backings (92% alpha) per note voice.
const NOTE_ALPHA := 0.92
const NOTE_BG := Color(Color("#1A1A1A"), NOTE_ALPHA)
const NOTE_BG_FALLER := Color(Color("#1F1B14"), NOTE_ALPHA)
const NOTE_BG_BUILDER := Color(Color("#141A1F"), NOTE_ALPHA)
const NOTE_BG_STRAY := Color(Color("#171717"), NOTE_ALPHA)

## Token names as they appear in the theme (and in 04 §3), with their values.
const COLORS := {
	&"ui_fg": UI_FG,
	&"ui_dim": UI_DIM,
	&"ui_bg": UI_BG,
	&"ui_accent": UI_ACCENT,
	&"ui_danger": UI_DANGER,
	&"ui_cold": UI_COLD,
	&"ui_accent_cb": UI_ACCENT_CB,
	&"ui_backing": UI_BACKING,
	&"pause_overlay": PAUSE_OVERLAY,
	&"note_bg": NOTE_BG,
	&"note_bg_faller": NOTE_BG_FALLER,
	&"note_bg_builder": NOTE_BG_BUILDER,
	&"note_bg_stray": NOTE_BG_STRAY,
}

# --- 04 §2 typography (px at 1080p; the UI scale setting multiplies) ------------------------
const FONT_HUD_BODY := 18
const FONT_HUD_NUMERAL := 24      # Bold
const FONT_PROMPT := 20
const FONT_MENU_ITEM := 22
const FONT_MENU_HEADING := 28     # Bold
const FONT_WORDMARK := 160        # Bold
const FONT_TITLE_SUBLINE := 18    # 04 §7 version line under the wordmark
const FONT_NOTE := 20
const FONT_CAPTION := 20
## Uppercase strings carry +0.08 em tracking; the wordmark 0.18 em.
const TRACKING_UPPER_EM := 0.08
const TRACKING_WORDMARK_EM := 0.18

# --- 04 §4 geometry -----------------------------------------------------------------------
const GRID := 8
const SAFE_MARGIN := 32
const LINE := 1                   # 1 px at 1080p, scaled, minimum 1 px
const BAR_TRACK := 2
const BAR_FILL := 4

# --- 04 §6 HUD geometry ---------------------------------------------------------------------
const COHERENCE_BAR_WIDTH := 240
const CROSSHAIR_DOT := 2
const CROSSHAIR_RING := 12
const CROSSHAIR_RING_GAP := 2
const STAMINA_ARC_RADIUS := 18
const NOCLIP_ARC_RADIUS := 24
const PROMPT_OFFSET_Y := 120

# --- 04 §7 menus, §8 note sheet ---------------------------------------------------------------
const MENU_ROW_HEIGHT := 40
## M3.6 compact menus: a logical viewport under COMPACT_HEIGHT px tall (the UI scale above
## 1.08; the UI scale sets the logical height to 1080 / scale at every resolution) sets menu
## rows 32 px apart, so a 1080p menu fits 720 logical px without scaling down.
const MENU_ROW_HEIGHT_COMPACT := 32
const COMPACT_HEIGHT := 1000.0
const SLIDER_TRACK_WIDTH := 200
const SENSITIVITY_TEST_SIZE := 200
const NOTE_SHEET_WIDTH := 720
const NOTE_SHEET_PADDING := 8

# --- 04 §4 motion ---------------------------------------------------------------------------
const VALUE_TWEEN_S := 0.18       # TRANS_EXPO / EASE_OUT
const VALUE_TWEEN_TRANS := Tween.TRANS_EXPO
const VALUE_TWEEN_EASE := Tween.EASE_OUT
const SHUTTER_S := 0.12
const SHUTTER_BANDS := 6
const SHUTTER_STAGGER_S := 0.01
const GLITCH_S := 0.12
const GLITCH_BANDS_MIN := 8
const GLITCH_BANDS_MAX := 14
const GLITCH_OFFSET_PX := 12
const GLITCH_CA := 0.02
const TYPE_CPS := 60.0            # notifications, summary lines
const NOTE_TYPE_CPS := 90.0       # 04 §8 note sheets
const CURSOR_BLINK_HZ := 2.0

# --- 04 §5 glyphs ---------------------------------------------------------------------------
const GLYPH_SIZE := 24
const GLYPH_STROKE := 1.5
## The required glyph set, in the order 04 §5 lists it.
const GLYPHS: Array[StringName] = [
	&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse", &"key", &"flashlight",
	&"crank", &"noclip", &"exit", &"breaker", &"note", &"eye", &"wave", &"bolt", &"steps",
	&"null", &"depth", &"coherence", &"settings", &"archive", &"daily", &"endless", &"check",
	&"cross", &"arrow_l", &"arrow_r", &"arrow_u", &"arrow_d", &"mouse_l", &"mouse_r",
	&"mouse_wheel", &"key_cap",
]


# --- 12 §6 accessibility (live; SettingsApply sets these) -----------------------------------
## Colour-blind safe accent on: accent() is UI_ACCENT_CB, accent labels carry a 1 px ui_fg
## outline, danger text adds `!` and cold text adds `~`.
static var colorblind: bool = false
## Text size: multiplies note and caption sizes only (12 §6).
static var text_size: float = 1.0
## Compact menus (M3.6): set by MenuShell from its logical height.
static var compact: bool = false


## The menu row height now (04 §7 40 px; 32 px compact).
static func row_height() -> int:
	return MENU_ROW_HEIGHT_COMPACT if compact else MENU_ROW_HEIGHT
## 12 §6 glyphs (marks, not words, so they live with the tokens rather than in Strings).
const CB_DANGER_GLYPH := "!"
const CB_COLD_GLYPH := "~"
## M3.6 (open item from M2.12): on accent text smaller than this the 1 px colour-blind
## outline is ui_bg, not ui_fg; a light outline round 18 px strokes turned the depth numeral
## nearly white. Menu items (22 px) and larger keep the ui_fg outline.
const CB_OUTLINE_LIGHT_MIN_PX := 20


## The accent colour now (04 §3 ui_accent, or the 12 §6 colour-blind safe accent).
static func accent() -> Color:
	return UI_ACCENT_CB if colorblind else UI_ACCENT


## Sets a label's font colour; with the colour-blind accent on, an accent-coloured label
## also gets the 1 px outline (12 §6; cb_outline_color), and any other colour loses it.
static func paint(c: Control, color: Color) -> void:
	c.add_theme_color_override(&"font_color", color)
	if colorblind and color.is_equal_approx(UI_ACCENT_CB):
		c.add_theme_constant_override(&"outline_size", LINE)
		c.add_theme_color_override(&"font_outline_color", cb_outline_color(c.get_theme_font_size(&"font_size")))
	else:
		c.remove_theme_constant_override(&"outline_size")
		c.remove_theme_color_override(&"font_outline_color")


## The colour-blind outline for accent text of `font_px` (M3.6): ui_fg from 20 px up, ui_bg
## below, so small accent text keeps its hue.
static func cb_outline_color(font_px: int) -> Color:
	return UI_FG if font_px >= CB_OUTLINE_LIGHT_MIN_PX else UI_BG


## 12 §6: danger adds a `!` glyph, cold a `~` glyph, while the colour-blind accent is on.
static func danger_mark(text: String) -> String:
	return "%s %s" % [text, CB_DANGER_GLYPH] if colorblind else text


static func cold_mark(text: String) -> String:
	return "%s %s" % [text, CB_COLD_GLYPH] if colorblind else text


## A text-size-scaled pixel size (notes and captions).
static func text_px(base: int) -> int:
	return maxi(1, roundi(base * text_size))


static func glyph_path(glyph: StringName) -> String:
	return "%s/%s.svg" % [GLYPH_DIR, glyph]


static func glyph(glyph_name: StringName) -> Texture2D:
	var path := glyph_path(glyph_name)
	if not ResourceLoader.exists(path):
		push_error("UiTokens: no glyph %s" % glyph_name)
		return null
	return load(path) as Texture2D


## Letter spacing in whole pixels for a font size and an em amount (FontVariation spacing
## is integral). 04 §2: uppercase +0.08 em.
static func tracking_px(font_size: int, em: float = TRACKING_UPPER_EM) -> int:
	return roundi(font_size * em)


## Line thickness at a UI scale: 1 px at 1.0, scaled, never below 1 px (04 §4).
static func line_px(ui_scale: float) -> int:
	return maxi(1, roundi(LINE * ui_scale))


## A 1 px line in layout units that stays at least one screen pixel when the root window
## scales the UI down (12 §2 UI scale below 1080p): 04 §4 "minimum 1 px".
static func hairline() -> int:
	var ml := Engine.get_main_loop() as SceneTree
	var scale := ml.root.content_scale_factor if ml != null and ml.root != null else 1.0
	return maxi(LINE, ceili(LINE / maxf(scale, 0.01) - 0.001))
