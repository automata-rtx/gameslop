class_name StillPresent
extends RefCounted
## Still's presentation (02 §8, 08 §4), split out of ErrorStill (14 §6 400-line limit):
## the render-line tick and the drawn column's height in a doorway. Nothing here changes
## the rule; it draws what the rule decided. The render-line height uses Still's own
## presentation rng, never the behaviour rng.


## 08 §4 render tick: observed 2 s continuously, a 1 px white line for 100 ms with the
## 6 kHz blip, once per 2 s; once when first observed in Wander.
static func render_tick(s: ErrorStill, delta: float) -> void:
	if s.tick_left > 0.0:
		s.tick_left -= delta
		if s.tick_left <= 0.0:
			set_line(s, false)
	if not s.observed:
		s.observed_time = 0.0
		s._next_tick_at = Tuning.STILL_RENDER_TICK_AFTER
		return
	var first := is_zero_approx(s.observed_time)
	s.observed_time += delta
	if first and s.state == Tuning.ERROR_STATE_WANDER and not s._wander_ticked:
		s._wander_ticked = true
		play_tick(s)
	elif s.observed_time >= s._next_tick_at:
		s._next_tick_at += Tuning.STILL_RENDER_TICK_INTERVAL
		play_tick(s)


static func play_tick(s: ErrorStill) -> void:
	s.ticks += 1
	s.tick_left = Tuning.STILL_RENDER_TICK_DURATION_MS / 1000.0
	set_line(s, true, s._present_rng.randf_range(0.08, 0.92))
	AudioManager.play_3d(ErrorStill.TICK_SOUND, s.body_position() + Vector3.UP * ErrorStill.COLUMN_CENTRE)


## The 1 px line across the column at `height01` of its height (instance uniforms).
static func set_line(s: ErrorStill, on: bool, height01: float = 0.5) -> void:
	if s.column == null:
		return
	s.column.set_instance_shader_parameter(&"line_on", 1.0 if on else 0.0)
	if on:
		s.column.set_instance_shader_parameter(&"line_height", height01)


## The drawn column's height at `pos` (R9): 2.6 m (02 §8), or just under the 2.1 m door
## header while the column overlaps a doorway's edge strip, so the frozen column never
## pokes through a header. Presentation only: the body (0.4 x 1.8 m) and the observe
## points do not change. Without a level grid (test rooms) it is always 2.6 m.
static func column_height(grid: LevelGrid, pos: Vector3) -> float:
	if grid == null:
		return Tuning.STILL_CAPSULE_HEIGHT
	var c := grid.cell_of(pos)
	if not grid.in_bounds(c):
		return Tuning.STILL_CAPSULE_HEIGHT
	var centre := grid.world_of(c)
	var reach := Tuning.STILL_CAPSULE_RADIUS + Tuning.GRID_WALL_THICKNESS * 0.5
	for d in 4:
		if grid.wall(c, d) != LevelGrid.DOOR:
			continue
		var dir := LevelGrid.DIRS[d]
		var along := (pos.x - centre.x) * dir.x + (pos.z - centre.z) * dir.y
		if Tuning.GRID_CELL_SIZE * 0.5 - along < reach:
			return Tuning.STILL_COLUMN_DOORWAY_HEIGHT
	return Tuning.STILL_CAPSULE_HEIGHT


## Applies column_height() to the drawn column (its mesh stands on its origin; the shader's
## line height is a fraction of the drawn height, so a scale keeps the tick on the column).
static func fit_column(s: ErrorStill) -> void:
	if s.column == null:
		return
	var h := column_height(s.grid, s.body_position())
	var scale := Vector3(1.0, h / Tuning.STILL_CAPSULE_HEIGHT, 1.0)
	# R21: only a change is written (each write re-propagates the column's transform).
	if s.column.scale != scale:
		s.column.scale = scale
