@tool
class_name LeaderStyleBox
extends StyleBox
## The dotted leader of settings rows, `LABEL ………… value` (04 §7), provided by the theme
## (04 Interfaces) as type variation "Leader" (base Panel). Draws square dots of
## `thickness` px every `period` px along a horizontal line at `vertical_ratio` of the
## rect's height, so it sits near the text baseline when it fills a row's leftover width.

@export var color: Color = UiTokens.UI_DIM:
	set(v):
		color = v
		emit_changed()
@export_range(1, 8, 1) var thickness: int = UiTokens.LINE:
	set(v):
		thickness = v
		emit_changed()
@export_range(2, 16, 1) var period: int = 4:
	set(v):
		period = v
		emit_changed()
@export_range(0.0, 1.0, 0.01) var vertical_ratio: float = 0.7:
	set(v):
		vertical_ratio = v
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var step := maxi(period, thickness + 1)
	var y := floorf(rect.position.y + rect.size.y * vertical_ratio)
	var x := ceilf(rect.position.x)
	var x_end := rect.end.x - thickness
	while x <= x_end:
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(x, y, thickness, thickness), color)
		x += step
