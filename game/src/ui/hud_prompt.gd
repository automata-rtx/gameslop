class_name HudPrompt
extends Control
## The interaction prompt (04 §6), centred on this control's position (the HUD puts it
## 120 px below the crosshair): `[E] OPEN DOOR`, `[HOLD E] LEAVE HIDING`, with the key
## cap drawn as a 1 px box around the bound key's name, on a 60% black backing. It appears
## and leaves with the shutter. Hold prompts carry an underline that fills with the hold
## (11 §2 "Interact hold": underline fills on the prompt). Also used for captions and,
## later, first-run hints (same position family, 04 §8, §9).

## Interaction key action (06 §2).
const ACTION_INTERACT := &"interact"

## Theme type of the text: Prompt (20 px), Caption (20 px).
@export var text_type: StringName = &"Prompt"
@export var shutter_sound: bool = true

var shutter: UiShutter
var line: UiKeyLine
var hold_time: float = 0.0
var progress: float = 0.0
var raw_text: String = ""
var _bar: HoldBar


class HoldBar extends Control:
	## Under the prompt text: 1 px ui_dim track, the 2 px fill in ui_accent ("you can act").
	var fraction: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, UiTokens.BAR_TRACK + UiTokens.LINE)

	func _draw() -> void:
		draw_rect(Rect2(0, size.y - UiTokens.LINE, size.x, UiTokens.LINE), UiTokens.UI_DIM)
		if fraction > 0.0:
			draw_rect(Rect2(0, size.y - UiTokens.BAR_TRACK, roundf(size.x * fraction), UiTokens.BAR_TRACK), UiTokens.accent())


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shutter = UiShutter.new()
	shutter.name = "Shutter"
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Backing"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line = UiKeyLine.new()
	box.add_child(line)
	_bar = HoldBar.new()
	_bar.visible = false
	box.add_child(_bar)
	panel.add_child(box)
	shutter.add_child(panel)
	add_child(shutter)
	shutter.minimum_size_changed.connect(_layout)


func _ready() -> void:
	shutter.sound = shutter_sound
	line.text_type = text_type
	_layout()


## 04 Interfaces show_prompt(text). `text` is the interactable's words (`OPEN DOOR`), which
## are framed with the interact key: PROMPT_HOLD when `hold` > 0, else PROMPT_PRESS. A
## text that already carries brackets is rendered as given (hints).
func show_text(text: String, hold: float = 0.0) -> void:
	if text.is_empty():
		hide_text()
		return
	var segs: Array[Dictionary]
	if text.contains("["):
		segs = UiKeys.segments(text, {}, {})
	else:
		var template := Strings.PROMPT_HOLD if hold > 0.0 else Strings.PROMPT_PRESS
		segs = UiKeys.segments(template, {&"text": text}, {&"key": UiKeys.key_name(ACTION_INTERACT)})
	set_segments(segs, hold)
	raw_text = text


## 04 §6 notice: a dim, keyless line (`FUSE MISSING`), no hold underline.
func show_notice(text: String) -> void:
	if text.is_empty():
		hide_text()
		return
	var segs: Array[Dictionary] = UiKeys.segments("{text}", {&"text": text}, {})
	set_segments(segs, 0.0, UiTokens.UI_DIM)
	raw_text = text


## Shows pre-built segments (captions are plain: one segment, no key).
func set_segments(segs: Array[Dictionary], hold: float = 0.0, tint: Color = UiTokens.UI_FG) -> void:
	hold_time = hold
	progress = 0.0
	line.text_type = text_type
	line.set_segments(segs, tint)
	_bar.visible = hold > 0.0
	_bar.fraction = 0.0
	_bar.queue_redraw()
	shutter.shutter_in()
	_layout.call_deferred()


func hide_text() -> void:
	raw_text = ""
	progress = 0.0
	shutter.shutter_out()


func set_progress(f: float) -> void:
	progress = clampf(f, 0.0, 1.0)
	_bar.fraction = progress
	_bar.queue_redraw()


func is_shown() -> bool:
	return shutter.is_shown()


func plain_text() -> String:
	return line.plain_text() if shutter.is_shown() else ""


func underline_visible() -> bool:
	return _bar.visible


func _layout() -> void:
	var s := shutter.get_combined_minimum_size()
	shutter.size = s
	shutter.position = (-s * 0.5).round()
