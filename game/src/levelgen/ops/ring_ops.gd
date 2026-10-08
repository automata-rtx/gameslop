class_name RingOps
extends RefCounted
## Ring corridor operations (07 §5.4 Offices, §5.5 Server): a 1-cell FLOOR ring `inset`
## cells in from the perimeter, the band of cells outside it, and band rooms that stand
## between the ring and the grid edge and open onto the ring. Pure data, worker thread.
## Band sides are named by the grid edge they lie along (N, E, S, W); a band room on side
## s faces the ring in direction opposite(s).


## Carves the ring: the boundary of Rect2i(inset, inset, n - 2 inset, n - 2 inset) as FLOOR
## with open edges between consecutive ring cells. `corridor` (cell index -> true) gets
## every ring cell. Returns the ring's rect.
static func carve_ring(grid: LevelGrid, inset: int, corridor: Dictionary) -> Rect2i:
	var n := grid.size.x
	var r := Rect2i(inset, inset, n - inset * 2, grid.size.y - inset * 2)
	var cells := ring_cells(r)
	for c in cells:
		grid.set_kind(c, LevelGrid.FLOOR)
		corridor[grid.idx(c)] = true
	for k in cells.size():
		var a := cells[k]
		var b := cells[(k + 1) % cells.size()]
		var d := LevelGrid.DIRS.find(b - a)
		if d >= 0:
			grid.set_wall(a, d, LevelGrid.NONE)
	return r


## The ring's cells in order (clockwise from the north-west corner).
static func ring_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x - 1
	var z1 := r.end.y - 1
	for x in range(x0, x1):
		out.append(Vector2i(x, z0))
	for z in range(z0, z1):
		out.append(Vector2i(x1, z))
	for x in range(x1, x0, -1):
		out.append(Vector2i(x, z1))
	for z in range(z1, z0, -1):
		out.append(Vector2i(x0, z))
	return out


## Carves a straight corridor of FLOOR cells from `from` in `dir` for `length` cells, open
## to each other and to the corridor cells at both ends. Marks them in `corridor`.
static func carve_line(grid: LevelGrid, from: Vector2i, dir: int, length: int, corridor: Dictionary) -> void:
	var prev := from - LevelGrid.DIRS[dir]
	for k in length:
		var c := from + LevelGrid.DIRS[dir] * k
		grid.set_kind(c, LevelGrid.FLOOR)
		corridor[grid.idx(c)] = true
		if grid.kind(prev) == LevelGrid.FLOOR:
			grid.set_wall(prev, dir, LevelGrid.NONE)
		prev = c
	var after := prev + LevelGrid.DIRS[dir]
	if grid.kind(after) == LevelGrid.FLOOR:
		grid.set_wall(prev, dir, LevelGrid.NONE)


## A band room on side `side`: `length` cells along the side from `along`, `depth` cells
## deep, its inner face on the band row next to the ring. Its along-range must lie within
## the ring's span for every cell of the inner face to touch the ring.
static func band_rect(n: int, inset: int, side: int, along: int, length: int, depth: int) -> Rect2i:
	match side:
		LevelGrid.N:
			return Rect2i(along, inset - depth, length, depth)
		LevelGrid.E:
			return Rect2i(n - inset, along, depth, length)
		LevelGrid.S:
			return Rect2i(along, n - inset, length, depth)
	return Rect2i(inset - depth, along, depth, length)


## Range of `along` for a band room of `length` whose inner face touches the ring only
## (not the ring's corners): [inset + 1, n - inset - 1 - length].
static func along_range(n: int, inset: int, length: int) -> Vector2i:
	return Vector2i(inset + 1, n - inset - 1 - length)


## True when every cell of `rect` is VOID and no other room holds it.
static func rect_void(grid: LevelGrid, rect: Rect2i) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > grid.size.x or rect.end.y > grid.size.y:
		return false
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * grid.size.x + x
			if grid.cells[i] != LevelGrid.VOID or grid.room_id[i] >= 0:
				return false
	return true


## Opens one edge of `room` onto the corridor cell beside the middle of its side `dir`
## (NONE or DOOR). Returns the edge (room-side cell and dir), or (-1, -1, -1).
static func open_middle(grid: LevelGrid, room: RoomData, dir: int, type: int) -> Vector3i:
	var c := StratumGenerator.side_middle(room, dir)
	if not grid.is_walkable(c + LevelGrid.DIRS[dir]):
		return Vector3i(-1, -1, -1)
	grid.set_wall(c, dir, type)
	var e := Vector3i(c.x, c.y, dir)
	room.doors.append(e)
	return e


## Perimeter edges of `room` whose outside cell passes `outside` (Callable(Vector2i) -> bool).
static func edges_onto(grid: LevelGrid, room: RoomData, outside: Callable) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for e in room.perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if grid.in_bounds(o) and outside.call(o):
			out.append(e)
	return out
