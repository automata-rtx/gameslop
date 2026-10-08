class_name SightOps
extends RefCounted
## Line of sight on the grid (pure data, worker-thread safe): a straight XZ segment is
## clear when every cell edge it crosses lets sight through between walkable cells. Sight
## has its own edge rule, not the walker's: open edges, PARTITION (1.5 m, seen over) and
## GLASS pass; WALL, SOLID, SOFT and a closed DOOR (runtime state on the grid) block.
## Used by the LightPool to lend lights only to fixtures in view (02 §6), by every lit
## predicate (fixtures and chemical lights, 06/08/09), and by anything that asks "could
## the player see that cell" without the scene tree.
## M2.1: sight also crosses DEEP water and Garage pillar cells (built open space nobody
## walks in); a light hanging over a pool or on a pillar starts its line there.


## True when sight crosses the edge (c, dir) between two sight-open cells.
static func edge_clear(grid: LevelGrid, c: Vector2i, dir: int) -> bool:
	if not grid.is_sight_open(c + LevelGrid.DIRS[dir]):
		return false
	match grid.wall(c, dir):
		LevelGrid.NONE, LevelGrid.PARTITION, LevelGrid.GLASS:
			return true
		LevelGrid.DOOR:
			return not grid.is_door_closed(c, dir)
	return false


## True when the XZ segment from world point a to b crosses no sight-blocking edge.
static func clear(grid: LevelGrid, a: Vector3, b: Vector3) -> bool:
	var cs := Tuning.GRID_CELL_SIZE
	# Cell (x, z) spans [x*cs - cs/2, x*cs + cs/2]; shift so cells start at integers.
	var p := Vector2(a.x / cs + 0.5, a.z / cs + 0.5)
	var q := Vector2(b.x / cs + 0.5, b.z / cs + 0.5)
	var c := Vector2i(floori(p.x), floori(p.y))
	var end := Vector2i(floori(q.x), floori(q.y))
	if not grid.is_sight_open(c):
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
		if not edge_clear(grid, c, dir):
			return false
		c += LevelGrid.DIRS[dir]
	return c == end


## True when `to` is in sight of the cell of `eye` or of a cell one step from it (so a light
## shown on that rule does not pop in as the viewer steps round a corner; 02 §6).
static func clear_near(grid: LevelGrid, eye: Vector3, to: Vector3) -> bool:
	if clear(grid, eye, to):
		return true
	var c := grid.cell_of(eye)
	if not grid.is_walkable(c):
		return false
	for d in 4:
		if grid.can_step(c, d) and clear(grid, grid.world_of(c + LevelGrid.DIRS[d]), to):
			return true
	return false
