class_name DissolveGrid
extends Control
## 11 §3 Dissolve: "the view breaks into a 48 × 27 grid of quads that scatter to black with
## grain, 1.5 s". A capture of the last frame is cut into the grid; each quad drifts outward
## from the centre, shrinks and darkens on its own delay, over black. The grain is the
## Coherence renderer's `dissolve` pulse underneath (it keeps running on the screen pass).
## Cosmetic only: offsets come from a hash of the quad index, never from gameplay RNG.

signal finished

var duration: float = Tuning.COHERENCE_DISSOLVE_TIME
var grid: Vector2i = Tuning.POST_DISSOLVE_GRID
var t: float = 0.0
var running: bool = false
var _tex: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


## Captures the current frame (when the renderer can give one) and starts the scatter.
func play() -> void:
	_tex = null
	var vp := get_viewport()
	if vp != null and DisplayServer.get_name() != "headless":
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			_tex = ImageTexture.create_from_image(img)
	t = 0.0
	running = true
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not running:
		return
	t += delta
	queue_redraw()
	if t >= duration:
		running = false
		finished.emit()


## 0..1 progress of quad `i` (staggered by a hash so the image breaks up, not fades).
func quad_progress(i: int) -> float:
	var delay := float(hash(i) % 1000) / 1000.0 * 0.5
	return clampf((t / duration - delay) / (1.0 - delay * 0.8), 0.0, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if _tex == null:
		return
	var cell := size / Vector2(grid)
	var src_cell := Vector2(_tex.get_size()) / Vector2(grid)
	var centre := size * 0.5
	for y in grid.y:
		for x in grid.x:
			var i := y * grid.x + x
			var p := quad_progress(i)
			if p >= 1.0:
				continue
			var pos := Vector2(x, y) * cell
			var away := (pos + cell * 0.5 - centre).normalized()
			var e := p * p
			var s := 1.0 - e
			var off := away * e * size.y * 0.25
			var r := Rect2(pos + off + cell * (1.0 - s) * 0.5, cell * s)
			var shade := Color(1.0 - e, 1.0 - e, 1.0 - e, 1.0)
			draw_texture_rect_region(_tex, r, Rect2(Vector2(x, y) * src_cell, src_cell), shade)
