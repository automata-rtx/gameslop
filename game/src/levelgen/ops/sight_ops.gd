class_name SightOps
extends RefCounted
## Line of sight on the grid (pure data, worker-thread safe): a straight XZ segment is
## clear when every cell edge it crosses is open (NONE or DOOR) between walkable cells.
## Used by the LightPool to lend lights only to fixtures in view (02 §6), and usable by
## anything that asks "could the player see that cell" without the scene tree.


## True when the XZ segment from world point a to b crosses no closed edge.
static func clear(grid: LevelGrid, a: Vector3, b: Vector3) -> bool:
	var cs := Tuning.GRID_CELL_SIZE
	# Cell (x, z) spans [x*cs - cs/2, x*cs + cs/2]; shift so cells start at integers.
	var p := Vector2(a.x / cs + 0.5, a.z / cs + 0.5)
	var q := Vector2(b.x / cs + 0.5, b.z / cs + 0.5)
	var c := Vector2i(floori(p.x), floori(p.y))
	var end := Vector2i(floori(q.x), floori(q.y))
	if not grid.is_walkable(c):
		return false
	var d := q - p
	var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var t_delta := Vector2(INF if is_zero_approx(d.x) else absf(1.0 / d.x), INF if is_zero_approx(d.y) else absf(1.0 / d.y))
	var t_max := Vector2(
		INF if is_zero_approx(d.x) else ((c.x + (1 if step.x > 0 else 0)) - p.x) / d.x,
		INF if is_zero_approx(d.y) else ((c.y + (1 if step.y > 0 else 0)) - p.y) / d.y)
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 2
	while c != end and guard > 0:
		guard -= 1
		var dir: int
		if t_max.x < t_max.y:
			dir = LevelGrid.E if step.x > 0 else LevelGrid.W
			t_max.x += t_delta.x
		else:
			dir = LevelGrid.S if step.y > 0 else LevelGrid.N
			t_max.y += t_delta.y
		if not grid.can_step(c, dir):
			return false
		c += LevelGrid.DIRS[dir]
	return c == end
