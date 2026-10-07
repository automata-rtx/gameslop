class_name HudCrosshair
extends Control
## The centre of the screen (04 §6). Draws the mark: a 2 px dot; a 12 px ring with a 2 px
## gap on an interactable within reach; a dashed ring while stunned (11 §3, 1.2 s); the
## `eye` glyph while hidden. Owns the stamina arc and the noclip arc (each behind its own
## shutter) and the one-word invalid reason under the crosshair. Never dimmed.

enum Mark { DOT, RING, STUNNED, EYE, NONE }

## Size of the crosshair area; the arcs and glyph fit inside it.
const AREA := 128.0
## 04 §6: the reason word prints below the crosshair, clear of the 24 px arc and its echo.
const REASON_Y := 40.0
const STUN_DASHES := 6

## 12 §6 crosshair option: &"off", &"dot", &"dot_ring".
var style: StringName = &"dot_ring"
var has_target: bool = false
var stunned: bool = false
var hidden_state: bool = false

var stamina_shutter: UiShutter
var stamina_arc: HudArc
var noclip_shutter: UiShutter
var noclip_arc: HudArc
var reason_shutter: UiShutter
var reason_label: Label

var _eye: Texture2D
## Seconds since stamina reached full while the arc is up (-1: not counting).
var _full_t: float = -1.0
var _exhausted_left: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(AREA, AREA)
	stamina_arc = HudArc.new()
	stamina_arc.kind = HudArc.Kind.STAMINA
	stamina_shutter = _wrap(stamina_arc, "StaminaShutter")
	noclip_arc = HudArc.new()
	noclip_arc.kind = HudArc.Kind.NOCLIP
	noclip_shutter = _wrap(noclip_arc, "NoclipShutter")
	reason_label = Label.new()
	reason_label.theme_type_variation = &"HudBody"
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_shutter = UiShutter.new()
	reason_shutter.name = "ReasonShutter"
	reason_shutter.add_child(reason_label)
	add_child(reason_shutter)


func _ready() -> void:
	_eye = UiTokens.glyph(&"eye")
	_layout()


func _wrap(arc: HudArc, shutter_name: String) -> UiShutter:
	var s := UiShutter.new()
	s.name = shutter_name
	s.add_child(arc)
	add_child(s)
	return s


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	for s: UiShutter in [stamina_shutter, noclip_shutter]:
		s.position = Vector2.ZERO
		s.size = size
	var rs := reason_shutter.get_combined_minimum_size()
	reason_shutter.size = rs
	reason_shutter.position = Vector2(roundf((size.x - rs.x) * 0.5), roundf(size.y * 0.5 + REASON_Y - rs.y * 0.5))


func mark() -> Mark:
	if hidden_state:
		return Mark.EYE
	if stunned:
		return Mark.STUNNED
	if style == &"off":
		return Mark.NONE
	if has_target and style == &"dot_ring":
		return Mark.RING
	return Mark.DOT


# --- stamina (04 §6, 11 §2) ---------------------------------------------------------------

func set_stamina(v: float) -> void:
	stamina_arc.stamina = v
	if v < Tuning.STAMINA_MAX:
		_full_t = -1.0
		stamina_shutter.shutter_in()
	elif stamina_shutter.is_shown() and _full_t < 0.0:
		_full_t = 0.0
	stamina_arc.queue_redraw()


## 11 §2 sprint start: the stamina arc appears.
func set_sprinting(on: bool) -> void:
	if on:
		_full_t = -1.0
		stamina_shutter.shutter_in()
	elif stamina_arc.stamina >= Tuning.STAMINA_MAX and stamina_shutter.is_shown() and _full_t < 0.0:
		_full_t = 0.0


## 11 §2 stamina empty: the arc turns ui_danger and blinks twice; danger lasts the lockout.
func stamina_exhausted() -> void:
	stamina_arc.exhausted = true
	stamina_arc.exhausted_t = 0.0
	_exhausted_left = Tuning.STAMINA_LOCKOUT_TIME
	stamina_shutter.shutter_in()


# --- noclip (04 §6, 06 §8) -----------------------------------------------------------------

func set_noclip(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	noclip_arc.charge = charge
	noclip_arc.target = target
	noclip_arc.valid = valid
	noclip_arc.queue_redraw()
	var invalid := not valid and reason != &""
	if charge > 0.0 or invalid:
		noclip_shutter.shutter_in()
	else:
		noclip_shutter.shutter_out()
	if invalid:
		reason_label.text = String(Strings.NOCLIP_REASONS.get(reason, String(reason)))
		reason_shutter.shutter_in()
		_layout()
	else:
		reason_shutter.shutter_out()


func reason_text() -> String:
	return reason_label.text if reason_shutter.is_shown() else ""


# --- mark -----------------------------------------------------------------------------

func set_target(on: bool) -> void:
	has_target = on
	queue_redraw()


func set_stunned(on: bool) -> void:
	stunned = on
	queue_redraw()


func set_hidden(on: bool) -> void:
	hidden_state = on
	queue_redraw()


func advance(dt: float) -> void:
	if _full_t >= 0.0:
		_full_t += dt
		if _full_t >= Tuning.HUD_STAMINA_ARC_HIDE_DELAY:
			_full_t = -1.0
			stamina_shutter.shutter_out()
	if _exhausted_left > 0.0:
		_exhausted_left -= dt
		if _exhausted_left <= 0.0:
			stamina_arc.exhausted = false


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _draw() -> void:
	var c := (size * 0.5).round()
	match mark():
		Mark.DOT:
			var d := float(Tuning.HUD_CROSSHAIR_DOT)
			draw_rect(Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), UiTokens.UI_FG)
		Mark.RING:
			# 04 §6: a 12 px circle with a 2 px gap (the gap opens at the top).
			var r := Tuning.HUD_CROSSHAIR_RING * 0.5
			var gap := float(Tuning.HUD_CROSSHAIR_RING_GAP) / r
			var top := -PI * 0.5
			draw_arc(c, r, top + gap * 0.5, top + TAU - gap * 0.5, 32, UiTokens.UI_FG, 1.0)
		Mark.STUNNED:
			var r := Tuning.HUD_CROSSHAIR_RING * 0.5
			var step := TAU / STUN_DASHES
			for i in STUN_DASHES:
				draw_arc(c, r, step * i, step * i + step * 0.5, 6, UiTokens.UI_FG, 1.0)
		Mark.EYE:
			if _eye != null:
				draw_texture(_eye, (c - _eye.get_size() * 0.5).round(), UiTokens.UI_FG)
