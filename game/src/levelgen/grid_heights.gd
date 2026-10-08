class_name GridHeights
extends RefCounted
## Writers for a LevelGrid's heights (M2.1): ramp runs (Garage ramps, Pools basin steps) and
## the ledge mask that keeps walkers off height breaks (a basin rim, a deck edge). The grid
## holds the data and the readers (floor_y, ramp_dir_of, edge_floor_y, open_mask honours
## the ledges); pure data, worker thread.


## Makes `run` (cells in uphill order, each one step from the last along `uphill`) a ramp
## rising from `y_low` (the floor before run[0]) to `y_high` (the floor after the last).
## The slope covers the cell interiors and the strips between them (2n - 0.2 m for n
## cells); the strips at both ends stay flat at the neighbours' floors.
static func set_ramp(grid: LevelGrid, run: Array[Vector2i], uphill: int, y_low: float, y_high: float) -> void:
	var n := run.size()
	var inner := Tuning.GRID_CELL_SIZE - Tuning.GRID_WALL_THICKNESS
	var grade := (y_high - y_low) / (n * Tuning.GRID_CELL_SIZE - Tuning.GRID_WALL_THICKNESS)
	for k in n:
		var i := grid.idx(run[k])
		grid.cells[i] = LevelGrid.RAMP
		grid.ramp_dir[i] = uphill + 1
		grid.ramp_grade[i] = grade
		grid.floor_heights[i] = y_low + grade * (k * Tuning.GRID_CELL_SIZE + inner * 0.5)


## Recomputes `ledges`: open edges between walkable cells whose floors differ by more than
## a walker's climb (Tuning.NAV_MAX_CLIMB) cannot be stepped. Call after setting heights.
static func refresh_ledges(grid: LevelGrid) -> void:
	grid.ledges.fill(0)
	for i in grid.cell_count():
		if not grid._walkable_i(i):
			continue
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			var o := c + LevelGrid.DIRS[d]
			if not grid.in_bounds(o) or not grid._walkable_i(grid.idx(o)):
				continue
			if absf(grid.edge_floor_y(c, d) - grid.edge_floor_y(o, LevelGrid.opposite(d))) > Tuning.NAV_MAX_CLIMB:
				grid.ledges[i] |= 1 << d
				grid.ledges[grid.idx(o)] |= 1 << LevelGrid.opposite(d)
