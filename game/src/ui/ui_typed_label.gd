class_name UiTypedLabel
extends Label
## A line that prints itself (04 §4): `cps` characters per second with the block cursor
## `▌` after the last printed character, blinking at 2 Hz, gone when the line finishes.
## The cursor is part of the shaped text and characters after it are hidden with
## visible_characters, so the line's width never changes while it types (monospace).

signal finished

## Characters per second: 60 for notifications and summary lines, 90 for note sheets.
var cps: float = UiTokens.TYPE_CPS
## Play the type tick (03 §4) as characters print.
var sound: bool = false
var full_text: String = ""
var _t: float = 0.0
var _count: int = 0
var _typing: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


## Starts typing `line` from its first character.
func type_text(line: String, rate: float = UiTokens.TYPE_CPS) -> void:
	full_text = line
	cps = rate
	_t = 0.0
	_count = 0
	_typing = not line.is_empty()
	_render()


## Shows the whole line at once (no cursor).
func show_full(line: String) -> void:
	full_text = line
	_count = line.length()
	_typing = false
	_render()


func is_typing() -> bool:
	return _typing


func typed_count() -> int:
	return _count


## The text a reader sees right now, cursor included (tests).
func visible_text() -> String:
	if visible_characters < 0:
		return text
	return text.substr(0, visible_characters)


func advance(dt: float) -> void:
	if not _typing:
		return
	_t += dt
	var n := UiMotion.typed_count(_t, cps, full_text.length())
	if n != _count and sound and is_inside_tree():
		AudioManager.play_2d(&"ui_type")
	_count = n
	if _count >= full_text.length():
		_typing = false
		_render()
		finished.emit()
		return
	_render()


func _render() -> void:
	if not _typing:
		text = full_text
		visible_characters = -1
		return
	text = full_text.substr(0, _count) + UiMotion.CURSOR + full_text.substr(_count)
	visible_characters = _count + (1 if UiMotion.cursor_visible(_t) else 0)
