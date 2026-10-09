class_name UiFitBox
extends Container
## Holds one column of a menu inside the space the layout gives it (M3.6, 12 §2 UI scale):
## the child gets this box's width, capped at `max_width`, and this box's height. When the
## child's minimum size is larger than that (UI scale 1.5 at 1280 x 720 lays a 1080p menu out
## in 1280 x 720 logical pixels, and a 5:4 screen in 900 x 720), the child is scaled down
## uniformly until it fits, the same way the UI scale itself scales. The box asks for no
## minimum size of its own, so it never pushes its parent past the screen (the column's
## floor is `custom_minimum_size`). The scale changes only when the child's minimum size or
## this box's size does, so a page keeps one scale while its content stays the same size.

## The widest the child is laid out (0: no cap). 04 §7's detail column stays readable
## instead of spanning a 1440p screen.
var max_width: float = 0.0
## The scale applied to the child now (1.0 when it fits).
var fit_scale: float = 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The scale that fits a child of minimum size `need` into `space` with a width cap.
static func scale_for(need: Vector2, space: Vector2, cap: float = 0.0) -> float:
	var w := minf(space.x, cap) if cap > 0.0 else space.x
	var s := 1.0
	if need.x > w and need.x > 0.0:
		s = minf(s, w / need.x)
	if need.y > space.y and need.y > 0.0:
		s = minf(s, space.y / need.y)
	return maxf(s, 0.05)


## The child is laid out at the column's width (or its own minimum width, if wider) and only
## its height follows the scale: a wrapped label's height depends on its width, so a width
## that followed the scale would change the height it is scaled for, and never settle.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for c in get_children():
		var ch := c as Control
		if ch == null or ch.top_level:
			continue
		var need := ch.get_combined_minimum_size()
		var w := minf(size.x, max_width) if max_width > 0.0 else size.x
		var child_w := maxf(w, need.x)
		fit_scale = scale_for(Vector2(child_w, need.y), Vector2(w, size.y))
		fit_child_in_rect(ch, Rect2(Vector2.ZERO, Vector2(child_w, maxf(size.y / fit_scale, need.y))))
		ch.scale = Vector2(fit_scale, fit_scale)   # after: fit_child_in_rect resets the scale


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
