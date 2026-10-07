class_name UiShutter
extends Container
## The UI's only way to appear and leave (04 §4, GLOSSARY "Shutter"): the content is
## revealed by 6 horizontal bands opening at staggered 10 ms offsets over 120 ms, and
## leaves by the same bands closing. Never a fade or a scale.
## Implementation: this container draws the open part of each band and clips its children
## to what it drew (CLIP_CHILDREN_ONLY), so any content (labels, backings, custom draws)
## shutters the same way. It fits its children to its own rect, like a MarginContainer
## with no margins. Closed means invisible.

signal opened
signal closed

enum Phase { CLOSED, OPENING, OPEN, CLOSING }

## Play the shutter sound (03 §4: every motion has its UI sound). Off for sub-elements.
@export var sound: bool = false

var phase: Phase = Phase.CLOSED
var _t: float = 0.0


func _init() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


## Starts revealing. Re-entrant: an opening shutter keeps going; a closing one turns
## around from the coverage it had reached (11 §5: interruptible).
func shutter_in() -> void:
	match phase:
		Phase.OPEN, Phase.OPENING:
			return
		Phase.CLOSING:
			_t = maxf(0.0, UiMotion.SHUTTER_TIME - _t)
		_:
			_t = 0.0
	phase = Phase.OPENING
	visible = true
	_play_sound()
	queue_redraw()


func shutter_out() -> void:
	match phase:
		Phase.CLOSED, Phase.CLOSING:
			return
		Phase.OPENING:
			_t = maxf(0.0, UiMotion.SHUTTER_TIME - _t)
		_:
			_t = 0.0
	phase = Phase.CLOSING
	_play_sound()
	queue_redraw()


## Closes instantly and opens again: a value that re-announces itself (depth label).
func reshutter() -> void:
	show_now(false)
	shutter_in()


## Snaps to open or closed without motion (initial states, gallery).
func show_now(on: bool) -> void:
	phase = Phase.OPEN if on else Phase.CLOSED
	_t = 0.0
	visible = on
	queue_redraw()


func is_shown() -> bool:
	return phase == Phase.OPEN or phase == Phase.OPENING


func is_moving() -> bool:
	return phase == Phase.OPENING or phase == Phase.CLOSING


func elapsed() -> float:
	return _t


func advance(dt: float) -> void:
	if not is_moving():
		return
	_t += dt
	if UiMotion.shutter_done(_t):
		if phase == Phase.OPENING:
			phase = Phase.OPEN
			opened.emit()
		else:
			phase = Phase.CLOSED
			visible = false
			closed.emit()
		_t = 0.0
	queue_redraw()


## Opening fraction of each band right now (tests read it; _draw draws it).
func band_open(band: int) -> float:
	match phase:
		Phase.OPEN:
			return 1.0
		Phase.OPENING:
			return UiMotion.shutter_band(band, _t)
		Phase.CLOSING:
			return UiMotion.shutter_band_closing(band, _t)
	return 0.0


func _draw() -> void:
	if phase == Phase.OPEN:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		return
	for band in UiMotion.SHUTTER_BANDS:
		var s := UiMotion.band_slice(band, size.y, band_open(band))
		if s.y > 0.0:
			draw_rect(Rect2(0.0, s.x, size.x, s.y), Color.WHITE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			if c is Control and not (c as Control).top_level:
				fit_child_in_rect(c as Control, Rect2(Vector2.ZERO, size))
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			m = m.max((c as Control).get_combined_minimum_size())
	return m


func _play_sound() -> void:
	if sound and is_inside_tree():
		AudioManager.play_2d(&"ui_shutter")
