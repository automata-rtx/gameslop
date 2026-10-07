class_name HudCrank
extends HBoxContainer
## The flashlight charge gauge, bottom-left (04 §6): the `crank` glyph and the percent.
## The glyph's handle rotates while the wheel turns. The gauge brightens with the
## flashlight on (or the wheel turning) and dims with it off (11 §2); it is ui_dim at 100%;
## below 15% the percent is ui_danger.

## 11 §2: the crank sways the camera at 1 Hz; the glyph turns once per sway.
const TURN_HZ := 1.0

var charge: float = Tuning.FLASH_CHARGE_MAX
var light_on: bool = false
var turning: bool = false

var _glyph: TextureRect
var _percent: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", UiTokens.GRID)
	_glyph = TextureRect.new()
	_glyph.name = "Glyph"
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_glyph.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
	_glyph.pivot_offset = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE) * 0.5
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_glyph)
	_percent = Label.new()
	_percent.name = "Percent"
	_percent.theme_type_variation = &"HudBody"
	add_child(_percent)


func _ready() -> void:
	_glyph.texture = UiTokens.glyph(&"crank")
	_render()


func set_charge(v: float) -> void:
	charge = clampf(v, 0.0, Tuning.FLASH_CHARGE_MAX)
	_render()


func set_light(on: bool) -> void:
	light_on = on
	_render()


func set_turning(on: bool) -> void:
	turning = on
	if not on:
		_glyph.rotation = 0.0
	_render()


func percent_text() -> String:
	return _percent.text


func percent_color() -> Color:
	return _percent.get_theme_color(&"font_color")


func glyph_color() -> Color:
	return _glyph.modulate


func glyph_rotation() -> float:
	return _glyph.rotation


func advance(dt: float) -> void:
	if turning:
		_glyph.rotation = fposmod(_glyph.rotation + TAU * TURN_HZ * dt, TAU)


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _render() -> void:
	var p := roundi(charge)
	_percent.text = Strings.HUD_CRANK_PERCENT.replace("{percent}", str(p))
	var full := charge >= Tuning.FLASH_CHARGE_MAX
	var base := UiTokens.UI_FG if (light_on or turning) and not full else UiTokens.UI_DIM
	_glyph.modulate = base
	var low := charge < Tuning.CRANK_GAUGE_DANGER_BELOW
	_percent.add_theme_color_override(&"font_color", UiTokens.UI_DANGER if low else base)
