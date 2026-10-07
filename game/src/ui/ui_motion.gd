class_name UiMotion
extends RefCounted
## The readout's motion vocabulary (04 §4, 11 §5) as pure functions of elapsed time, so
## every animation is deterministic and testable without frames:
##   - shutter: 6 horizontal bands opening (or closing) at staggered 10 ms offsets, 120 ms;
##   - typing: 60 characters per second with a block cursor blinking at 2 Hz;
##   - value tween: TRANS_EXPO / EASE_OUT over 180 ms;
##   - numeral tick: a value walking toward its target at a fixed rate (30 per second).
## Motion nodes (UiShutter, UiTypedLabel, the HUD parts) keep their own elapsed time and
## step it in _process; tests and the gallery set `manual_clock` and call advance(dt).

## Bands of the shutter (04 §4).
const SHUTTER_BANDS := UiTokens.SHUTTER_BANDS
const SHUTTER_TIME := UiTokens.SHUTTER_S
const SHUTTER_STAGGER := UiTokens.SHUTTER_STAGGER_S
## Each band opens over what is left of the 120 ms after the last band's offset (70 ms),
## so the last band finishes exactly at 120 ms.
const SHUTTER_BAND_TIME := SHUTTER_TIME - SHUTTER_STAGGER * (SHUTTER_BANDS - 1)
## 04 §4 typing cursor (U+258C; CHANGELOG 2026-10-07 replaced U+25AE).
const CURSOR := Strings.MENU_CURSOR
## 04 §6 and 11 §2: short accent blinks and the select pulse last 100 ms.
const BLINK_S := 0.1
## 04 §6 item select pulse.
const PULSE_SCALE := 1.15

## True while tests or the gallery drive time by hand (UiMotion.step); motion nodes then
## ignore their _process delta. Never set in gameplay.
static var manual_clock: bool = false


## Opening fraction 0..1 of one band `t` seconds after a shutter-in started.
static func shutter_band(band: int, t: float) -> float:
	var local := (t - SHUTTER_STAGGER * band) / SHUTTER_BAND_TIME
	return clampf(local, 0.0, 1.0)


## Opening fraction of a band while closing (the same bands, the same stagger).
static func shutter_band_closing(band: int, t: float) -> float:
	return 1.0 - shutter_band(band, t)


static func shutter_done(t: float) -> bool:
	return t >= SHUTTER_TIME - 0.000001


## The visible slice of band `band` in a rect of height `h`: the band opens from its
## centre line outward. Returns Vector2(y, height).
static func band_slice(band: int, h: float, open: float) -> Vector2:
	var bh := h / SHUTTER_BANDS
	var visible := bh * clampf(open, 0.0, 1.0)
	return Vector2(bh * band + (bh - visible) * 0.5, visible)


## Characters printed `t` seconds after a line started typing at `cps`.
static func typed_count(t: float, cps: float, length: int) -> int:
	if t <= 0.0:
		return 0
	return mini(length, floori(t * cps + 0.0001))


## Seconds a line of `length` characters takes to type.
static func typing_time(length: int, cps: float) -> float:
	return float(length) / cps


## The block cursor is lit for the first half of each 2 Hz period.
static func cursor_visible(t: float) -> bool:
	var period := 1.0 / UiTokens.CURSOR_BLINK_HZ
	return fposmod(t, period) < period * 0.5


## TRANS_EXPO / EASE_OUT, the curve of every HUD value change (04 §4).
static func expo_out(x: float) -> float:
	if x >= 1.0:
		return 1.0
	if x <= 0.0:
		return 0.0
	return 1.0 - pow(2.0, -10.0 * x)


## Value `t` seconds into a 180 ms expo-out tween from `from` to `to`.
static func value_tween(from: float, to: float, t: float, duration: float = UiTokens.VALUE_TWEEN_S) -> float:
	return lerpf(from, to, expo_out(t / duration))


## A numeral walking from `shown` toward `target` at `rate` units per second (04 §6:
## "the numeral ticks, not jumps").
static func tick_toward(shown: float, target: float, rate: float, dt: float) -> float:
	return move_toward(shown, target, rate * dt)


## Item select pulse (04 §6): 1.15x at the press, back to 1.0 over 100 ms.
static func pulse(t: float) -> float:
	if t < 0.0 or t >= BLINK_S:
		return 1.0
	return lerpf(PULSE_SCALE, 1.0, expo_out(t / BLINK_S))


## Advances every motion node under `root` by `dt` (they implement advance(dt)).
static func step(root: Node, dt: float) -> void:
	if root.has_method(&"advance"):
		root.call(&"advance", dt)
	for c in root.get_children():
		step(c, dt)
