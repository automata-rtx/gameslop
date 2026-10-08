class_name HudCoherence
extends Control
## The Coherence readout, top-left (04 §6, pillar 1: always visible): `COHERENCE` in
## ui_dim, the numeral in ui_fg Bold, and a 240 px bar beneath (2 px track, 4 px fill,
## ten 10-unit cells). The numeral ticks toward the value at 30 units per second. Loss:
## the lost segment stays lit in ui_danger for 600 ms, then shutters out. Gain: the gained
## segment flashes ui_accent for 200 ms. Below 25: label and numeral turn ui_danger and
## the track pulses at the heartbeat rate.

const CELLS := 10
const CELL_GAP := 2
const BAR_GAP_Y := UiTokens.GRID
const LOSS := 0
const GAIN := 1
## 11 §3: the heartbeat sharpens to a beat then decays (fraction of a period).
const BEAT_DECAY := 8.0

## Target Coherence (the bar shows it immediately).
var value: float = Tuning.COHERENCE_MAX
## The numeral's walking value.
var shown: float = Tuning.COHERENCE_MAX
## Director threat 0..1 (EventBus.threat_changed), sets the heartbeat rate.
var threat: float = 0.0
## Live segments: {from, to, kind, t}.
var segments: Array[Dictionary] = []

var _label: Label
var _numeral: Label
var _beat_t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTokens.GRID)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.theme_type_variation = &"HudLabel"
	_label.text = Strings.HUD_COHERENCE
	_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_label)
	_numeral = Label.new()
	_numeral.name = "Numeral"
	_numeral.theme_type_variation = &"HudNumeral"
	row.add_child(_numeral)
	add_child(row)
	_render_numeral()


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


## 04 Interfaces: set_coherence(v, delta). `delta` < 0 lights a loss segment, > 0 a gain
## segment; 0 (a reset) snaps the numeral.
func set_value(v: float, delta: float) -> void:
	var before := value
	value = clampf(v, 0.0, Tuning.COHERENCE_MAX)
	if is_zero_approx(delta):
		shown = value
		segments.clear()
	elif value < before:
		segments.append({"from": value, "to": before, "kind": LOSS, "t": 0.0})
	elif value > before:
		segments.append({"from": before, "to": value, "kind": GAIN, "t": 0.0})
	_render_numeral()
	queue_redraw()


func numeral_text() -> String:
	return _numeral.text


func is_danger() -> bool:
	return shown < Tuning.COHERENCE_DANGER_BELOW


func numeral_color() -> Color:
	return _numeral.get_theme_color(&"font_color")


## 06 §9: heartbeat floor 90 bpm below the danger threshold; otherwise by threat (03).
func heartbeat_bpm() -> float:
	var bpm := lerpf(Tuning.AUDIO_HEARTBEAT_MIN_BPM, Tuning.AUDIO_HEARTBEAT_MAX_BPM, clampf(threat, 0.0, 1.0))
	return maxf(bpm, Tuning.COHERENCE_HEARTBEAT_FLOOR_BPM)


## 0..1 brightness of the track pulse right now.
func track_pulse() -> float:
	if not is_danger():
		return 0.0
	var period := 60.0 / heartbeat_bpm()
	return exp(-BEAT_DECAY * fposmod(_beat_t, period) / period)


func advance(dt: float) -> void:
	var before := shown
	shown = UiMotion.tick_toward(shown, value, Tuning.COHERENCE_TICK_RATE, dt)
	_beat_t += dt
	var live: Array[Dictionary] = []
	for s in segments:
		s["t"] = float(s["t"]) + dt
		if float(s["t"]) < _segment_life(int(s["kind"])):
			live.append(s)
	segments = live
	if not is_equal_approx(before, shown):
		_render_numeral()
	queue_redraw()


func _segment_life(kind: int) -> float:
	if kind == GAIN:
		return Tuning.HUD_GAIN_FLASH_MS / 1000.0
	return Tuning.HUD_LOSS_LINGER_MS / 1000.0 + UiMotion.SHUTTER_TIME


func _render_numeral() -> void:
	# Never 000 while any Coherence is left: zero is the dissolve (noclip review).
	_numeral.text = str(maxi(ceili(shown - 0.0001), 1 if shown > 0.0 else 0)).pad_zeros(Tuning.HUD_COHERENCE_PAD)
	var c := UiTokens.UI_DANGER if is_danger() else UiTokens.UI_FG
	_numeral.add_theme_color_override(&"font_color", c)
	_label.add_theme_color_override(&"font_color", UiTokens.UI_DANGER if is_danger() else UiTokens.UI_DIM)


func _bar_top() -> float:
	return get_child(0).get_combined_minimum_size().y + BAR_GAP_Y


func _get_minimum_size() -> Vector2:
	return Vector2(UiTokens.COHERENCE_BAR_WIDTH, _bar_top() + UiTokens.BAR_FILL)


func _draw() -> void:
	var y := _bar_top()
	var track_color := UiTokens.UI_DIM.lerp(UiTokens.UI_DANGER, track_pulse())
	var track_y := y + (UiTokens.BAR_FILL - UiTokens.BAR_TRACK) * 0.5
	_draw_range(0.0, Tuning.COHERENCE_MAX, track_y, UiTokens.BAR_TRACK, track_color)
	_draw_range(0.0, value, y, UiTokens.BAR_FILL, UiTokens.UI_FG)
	for s in segments:
		var t := float(s["t"])
		if int(s["kind"]) == GAIN:
			_draw_range(float(s["from"]), minf(float(s["to"]), value), y, UiTokens.BAR_FILL, UiTokens.UI_ACCENT)
			continue
		var from := maxf(float(s["from"]), value)
		var to := float(s["to"])
		var linger := Tuning.HUD_LOSS_LINGER_MS / 1000.0
		if t < linger:
			_draw_range(from, to, y, UiTokens.BAR_FILL, UiTokens.UI_DANGER)
		else:
			# 04 §6: then shutters out (the 6 bands of the 4 px segment close).
			for band in UiMotion.SHUTTER_BANDS:
				var sl := UiMotion.band_slice(band, UiTokens.BAR_FILL, UiMotion.shutter_band_closing(band, t - linger))
				if sl.y > 0.0:
					_draw_range(from, to, y + sl.x, sl.y, UiTokens.UI_DANGER)


## Draws the units [a, b] of the bar at height `h`, cut into the ten cells.
func _draw_range(a: float, b: float, y: float, h: float, color: Color) -> void:
	if b <= a:
		return
	var unit := float(UiTokens.COHERENCE_BAR_WIDTH) / Tuning.COHERENCE_MAX
	var cell_w := float(UiTokens.COHERENCE_BAR_WIDTH) / CELLS
	for i in CELLS:
		var x0 := cell_w * i
		var x1 := x0 + cell_w - CELL_GAP
		var l := maxf(x0, a * unit)
		var r := minf(x1, b * unit)
		if r > l:
			draw_rect(Rect2(l, y, r - l, h), color)
