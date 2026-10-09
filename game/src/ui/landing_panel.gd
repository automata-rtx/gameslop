class_name LandingPanel
extends Control
## The Landing's two-item panel (05 §4, 09 §5 "Landing panel", GLOSSARY): printed in-world on
## the cabin wall (the cabin renders this Control in a SubViewport). Each row is labelled with
## the `item_1` / `item_2` binding, the item's glyph and name; the panel also prints
## `COHERENCE +n`, the gain the arrival applies (at most 20, omitted at 0; R20), and, the
## first time, `CHOOSE ONE`. Choosing is optional and happens once. Readout style (04 §1):
## black, monospace, accent for "act".

signal chosen(kind: StringName)

const SIZE := Vector2i(480, 270)
const SLOT_ACTIONS: Array[StringName] = [&"item_1", &"item_2"]
const PAD := 24

var kinds: Array[StringName] = []
var chosen_index: int = -1
var _rows: Array[HBoxContainer] = []
var _names: Array[Label] = []
var _hint: Label
var _gain: Label
var _list: VBoxContainer


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = UiTokens.UI_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var rule := ColorRect.new()
	rule.color = UiTokens.UI_DIM
	rule.position = Vector2(PAD, PAD - 8)
	rule.size = Vector2(SIZE.x - PAD * 2, 1)
	add_child(rule)
	_list = VBoxContainer.new()
	_list.position = Vector2(PAD, PAD)
	_list.size = Vector2(SIZE.x - PAD * 2, SIZE.y - PAD * 2)
	_list.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	add_child(_list)
	_hint = _label(&"MenuHeading", Strings.MSG_CHOOSE_ONE)
	_list.add_child(_hint)
	_hint.visible = false


func _label(variation: StringName, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


## Shows `choice_kinds` (zero to two) and the Coherence line; `hint` prints CHOOSE ONE.
func setup(choice_kinds: Array[StringName], gain: float, hint: bool) -> void:
	kinds = choice_kinds.duplicate()
	chosen_index = -1
	_hint.visible = hint and not kinds.is_empty()
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_names.clear()
	for i in kinds.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
		var key := _label(&"MenuItemLabel", Strings.PROMPT_LANDING_SLOT.replace("{key}",
				UiKeys.key_name(SLOT_ACTIONS[i])).replace(" {item}", ""))
		row.add_child(key)
		var icon := TextureRect.new()
		icon.texture = UiTokens.glyph(kinds[i])
		icon.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE) * 1.5
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)
		var name_label := _label(&"MenuItemLabel", String(Strings.ITEM_NAMES.get(kinds[i], String(kinds[i]).to_upper())))
		row.add_child(name_label)
		_list.add_child(row)
		_rows.append(row)
		_names.append(name_label)
	if _gain != null:
		_gain.queue_free()
		_gain = null
	# The gain the arrival applies (R20): none at full Coherence, so no line (01 §6 rule 5).
	var shown := gain_text(gain)
	if shown != "":
		_gain = _label(&"AccentLabel", shown)
		_list.add_child(_gain)
	_refresh()


## The panel's Coherence line for `gain`, or "" when the arrival adds nothing. A fractional
## gain rounds, never below +1 (a gain that applies is printed).
static func gain_text(gain: float) -> String:
	if gain <= 0.0 or is_zero_approx(gain):
		return ""
	return Strings.MSG_COHERENCE_GAIN.replace("{amount}", str(maxi(1, roundi(gain))))


## The Coherence line as shown ("" when omitted).
func gain_line() -> String:
	return _gain.text if _gain != null else ""


## Takes slot `index` (0 or 1). Once per Landing; returns false when refused.
func choose(index: int) -> bool:
	if chosen_index >= 0 or index < 0 or index >= kinds.size():
		return false
	chosen_index = index
	AudioManager.play_2d(&"ui_confirm")
	_refresh()
	chosen.emit(kinds[index])
	return true


func _refresh() -> void:
	for i in _rows.size():
		var row := _rows[i]
		var picked := i == chosen_index
		var col := UiTokens.accent() if picked else (UiTokens.UI_DIM if chosen_index >= 0 else UiTokens.UI_FG)
		row.modulate = col
		_names[i].text = (Strings.MENU_SELECTED_PREFIX if picked else "") + \
				String(Strings.ITEM_NAMES.get(kinds[i], String(kinds[i]).to_upper()))
