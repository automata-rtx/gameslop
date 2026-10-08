class_name HudArc
extends Control
## The arcs around the crosshair (04 §6), drawn about this control's centre:
##   STAMINA: 180 degrees below the crosshair, radius 18, ui_fg; ui_danger and two blinks
##            when empty (11 §2).
##   NOCLIP:  360 degrees, radius 24, ui_cold, filling clockwise from the top; a 1 px outer
##            echo ring that completes 100 ms before commit; the target glyph at the top
##            (`noclip` for walls, `arrow_d` for the floor). Invalid: dashed in ui_dim.
## Lines are 1 px tracks with a 2 px fill (04 §4 scaled to an arc).

enum Kind { STAMINA, NOCLIP }

const POINTS := 64
const DASHES := 16
const TRACK_W := 1.0
const FILL_W := 2.0
## The echo ring sits 4 px outside the charge arc (half a grid unit).
const ECHO_OFFSET := 4.0
## Gap between the echo ring and the target glyph.
const GLYPH_GAP := 4.0

@export var kind: Kind = Kind.STAMINA

# Stamina
var stamina: float = Tuning.STAMINA_MAX
var exhausted: bool = false
## Seconds since the last exhaustion (drives the two blinks).
var exhausted_t: float = INF

# Noclip
var charge: float = 0.0
var target: StringName = &""
var valid: bool = true

var _glyph_wall: Texture2D
var _glyph_floor: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_glyph_wall = UiTokens.glyph(&"noclip")
	_glyph_floor = UiTokens.glyph(&"arrow_d")


## 04 §6: the echo ring completes HUD_NOCLIP_ECHO_RING_LEAD_MS before commit. Charge time
## comes from the target kind (06 §8): floor 2.5 s, soft wall 0.35 s, wall 0.6 s.
static func echo_fraction(charge_fraction: float, target_kind: StringName) -> float:
	var total := charge_time(target_kind)
	var lead := clampf(Tuning.HUD_NOCLIP_ECHO_RING_LEAD_MS / 1000.0 / total, 0.0, 0.9)
	return clampf(charge_fraction / (1.0 - lead), 0.0, 1.0)


static func charge_time(target_kind: StringName) -> float:
	match target_kind:
		&"floor":
			return Tuning.NOCLIP_FLOOR_TIME
		&"soft":
			return Tuning.NOCLIP_SOFT_TIME
	return Tuning.NOCLIP_WALL_TIME


static func target_glyph_name(target_kind: StringName) -> StringName:
	return &"arrow_d" if target_kind == &"floor" else &"noclip"


## Blink state of the empty stamina arc: two blinks of 100 ms off / 100 ms on.
func blink_off() -> bool:
	if exhausted_t >= UiMotion.BLINK_S * 4.0:
		return false
	return int(exhausted_t / UiMotion.BLINK_S) % 2 == 0


func stamina_color() -> Color:
	return UiTokens.UI_DANGER if exhausted else UiTokens.UI_FG


func advance(dt: float) -> void:
	if exhausted_t < INF:
		exhausted_t += dt
	queue_redraw()


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _draw() -> void:
	var c := size * 0.5
	if kind == Kind.STAMINA:
		_draw_stamina(c)
	else:
		_draw_noclip(c)


func _draw_stamina(c: Vector2) -> void:
	if exhausted and blink_off():
		return
	var r := float(Tuning.HUD_STAMINA_ARC_RADIUS)
	var col := stamina_color()
	# Below the crosshair: from 0 (right) through PI/2 (down) to PI (left). The fill
	# shrinks toward the bottom from both ends.
	draw_arc(c, r, 0.0, PI, POINTS, UiTokens.UI_DANGER if exhausted else UiTokens.UI_DIM, TRACK_W)
	var f := clampf(stamina / Tuning.STAMINA_MAX, 0.0, 1.0)
	if f > 0.0:
		draw_arc(c, r, PI * 0.5 - f * PI * 0.5, PI * 0.5 + f * PI * 0.5, POINTS, col, FILL_W)


func _draw_noclip(c: Vector2) -> void:
	var r := float(Tuning.HUD_NOCLIP_ARC_RADIUS)
	var top := -PI * 0.5
	var glyph := _glyph_floor if target == &"floor" else _glyph_wall
	if not valid:
		_draw_dashed_circle(c, r, UiTokens.UI_DIM)
		_draw_glyph(c, glyph, UiTokens.UI_DIM)
		return
	draw_arc(c, r, 0.0, TAU, POINTS, Color(UiTokens.UI_COLD, 0.35), TRACK_W)
	var f := clampf(charge, 0.0, 1.0)
	if f > 0.0:
		draw_arc(c, r, top, top + f * TAU, POINTS, UiTokens.UI_COLD, FILL_W)
	var e := echo_fraction(f, target)
	if e > 0.0:
		draw_arc(c, r + ECHO_OFFSET, top, top + e * TAU, POINTS, UiTokens.UI_COLD, TRACK_W)
	_draw_glyph(c, glyph, UiTokens.UI_COLD)
	if UiTokens.colorblind:
		# 12 §6: cold adds a `~` glyph (right of the ring, level with its centre).
		var font := get_theme_default_font()
		var fs := UiTokens.FONT_HUD_BODY
		draw_string(font, c + Vector2(r + UiTokens.GRID, fs * 0.35), UiTokens.CB_COLD_GLYPH,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.UI_COLD)


func _draw_glyph(c: Vector2, glyph: Texture2D, tint: Color) -> void:
	if glyph == null:
		return
	var gs := glyph.get_size()
	var y := c.y - Tuning.HUD_NOCLIP_ARC_RADIUS - ECHO_OFFSET - GLYPH_GAP - gs.y
	draw_texture(glyph, Vector2(roundf(c.x - gs.x * 0.5), roundf(y)), tint)


func _draw_dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var step := TAU / DASHES
	for i in DASHES:
		var a := step * i
		draw_arc(c, r, a, a + step * 0.5, 8, col, TRACK_W)
