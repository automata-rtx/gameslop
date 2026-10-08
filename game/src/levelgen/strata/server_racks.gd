class_name ServerRacks
extends RefCounted
## Server rack hall (07 §5.5), for ServerGenerator.layout. Layout coordinates (u, v): rows
## run along u and stack along v; the level transposes at random so rows run either way.
## The hall (inside the ring) is cut along v into bands of 6 to 10 rows; each band along u
## into blocks of 6 to 9 cells with a 1-cell cross aisle between blocks. In a block, rows
## alternate rack and aisle (07: 1-cell aisles between 1-cell rows); neighbouring blocks
## start on opposite rows and neighbouring bands put their cross aisles elsewhere (a
## staggered pattern), so no aisle runs straight for more than 12 cells. Where two bands
## meet, two rack rows may stand back to back: the rack-gap nooks are cut there.

const BAND_ROWS_MIN := 6
const BAND_ROWS_MAX := 10
## Attempts at a band's block lengths whose cross aisles miss the previous band's.
const CROSS_TRIES := 12

var gen: ServerGenerator
var grid: LevelGrid
var rng: RandomNumberGenerator
var inner: Rect2i
## Grid rects of the blocks (rack rows and aisles), and per block its band index.
var blocks: Array[Rect2i] = []
var block_band: PackedInt32Array = PackedInt32Array()
## Cross aisle cells (grid), for fixtures and props.
var cross: Dictionary = {}


func _init(g: ServerGenerator) -> void:
	gen = g
	grid = g.grid
	rng = g.rng_layout
	inner = g.ring.grow(-1)


func cell(u: int, v: int) -> Vector2i:
	return gen.cell(u, v)


## Fills the hall: cross aisles and aisle rows FLOOR (open to each other and to the ring),
## rack rows RACK.
func build() -> void:
	var u0 := inner.position.x
	var v0 := inner.position.y
	var m := inner.size.x
	var bands := _partition(m, BAND_ROWS_MIN, BAND_ROWS_MAX, 0)
	var vb := v0
	var prev_cross: Array[int] = []
	for b in bands.size():
		var depth := bands[b]
		var lengths: Array[int] = []
		var cuts: Array[int] = []
		for t in CROSS_TRIES:
			lengths = _partition(m, Tuning.SERVER_ROW_LENGTH_MIN, Tuning.SERVER_CROSS_AISLE_MAX - 1, 1)
			cuts = _cuts(u0, lengths)
			var clash := false
			for c in cuts:
				clash = clash or prev_cross.has(c)
			if not clash:
				break
		prev_cross = cuts
		var ub := u0
		for j in lengths.size():
			var phase := (b + j) % 2
			for v in range(vb, vb + depth):
				for u in range(ub, ub + lengths[j]):
					# A band after the first opens with a rack row in every block: where the band
					# before ends on a rack row the two stand back to back (the nooks' hosts).
					var rack := (v - vb) % 2 == phase if b == 0 else (v == vb or (v - vb - 1) % 2 == phase)
					grid.set_kind(cell(u, v), LevelGrid.RACK if rack else LevelGrid.FLOOR)
			var a := cell(ub, vb)
			var z := cell(ub + lengths[j] - 1, vb + depth - 1)
			blocks.append(Rect2i(Vector2i(mini(a.x, z.x), mini(a.y, z.y)), (z - a).abs() + Vector2i.ONE))
			block_band.append(b)
			ub += lengths[j]
			if j < lengths.size() - 1:
				for v in range(vb, vb + depth):
					grid.set_kind(cell(ub, v), LevelGrid.FLOOR)
					cross[grid.idx(cell(ub, v))] = true
				ub += 1
		vb += depth
	_open_floor()


## Splits `total` into parts in [lo, hi] with `gap` cells between parts, the fewest parts
## that fit; the slack is spread one cell at a time at random.
func _partition(total: int, lo: int, hi: int, gap: int) -> Array[int]:
	var k := 1
	while k * hi + (k - 1) * gap < total:
		k += 1
	var parts: Array[int] = []
	for i in k:
		parts.append(lo)
	var slack := total - (k * lo + (k - 1) * gap)
	var guard := slack * 8 + 8
	while slack > 0 and guard > 0:
		guard -= 1
		var i := rng.randi_range(0, k - 1)
		if parts[i] < hi:
			parts[i] += 1
			slack -= 1
	return parts


static func _cuts(u0: int, lengths: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var u := u0
	for j in lengths.size() - 1:
		u += lengths[j]
		out.append(u)
		u += 1
	return out


## Every edge between two walkable hall or ring cells is open (racks are the obstacles).
func _open_floor() -> void:
	for z in range(inner.position.y - 1, inner.end.y + 1):
		for x in range(inner.position.x - 1, inner.end.x + 1):
			var c := Vector2i(x, z)
			if grid.kind(c) != LevelGrid.FLOOR:
				continue
			for d: int in [LevelGrid.E, LevelGrid.S]:
				var o := c + LevelGrid.DIRS[d]
				if grid.kind(o) == LevelGrid.FLOOR and (inner.has_point(c) or inner.has_point(o)):
					grid.set_wall(c, d, LevelGrid.NONE)


## Opens every edge from the room's cells to walkable cells outside (a clearing).
func open_all(room: RoomData) -> void:
	for e in room.perimeter_edges():
		if grid.is_walkable(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]):
			grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.NONE)
			room.doors.append(e)


## Rects of `size` inside a block that touch the block's u-ends (an aisle's end), never
## touching a room already cut.
func block_rects(size: Vector2i, at_ends: bool) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for b in blocks:
		for z in range(b.position.y, b.end.y - size.y + 1):
			for x in range(b.position.x, b.end.x - size.x + 1):
				var r := Rect2i(x, z, size.x, size.y)
				if at_ends and not _touches_u_end(b, r):
					continue
				if is_clear(r.grow(1)):
					out.append(r)
	return out


## True when opening `r` as a clearing keeps every straight walk through it within
## SERVER_AISLE_STRAIGHT_MAX cells (the walkable cells either side of it in line count).
func runs_ok(r: Rect2i) -> bool:
	for z in range(r.position.y, r.end.y):
		if r.size.x + reach(Vector2i(r.position.x - 1, z), LevelGrid.W) + reach(Vector2i(r.end.x, z), LevelGrid.E) > Tuning.SERVER_AISLE_STRAIGHT_MAX:
			return false
	for x in range(r.position.x, r.end.x):
		if r.size.y + reach(Vector2i(x, r.position.y - 1), LevelGrid.N) + reach(Vector2i(x, r.end.y), LevelGrid.S) > Tuning.SERVER_AISLE_STRAIGHT_MAX:
			return false
	return true


## Walkable hall cells in a line from `c` in `dir` (ring cells end the count).
func reach(c: Vector2i, dir: int) -> int:
	var n := 0
	var p := c
	while inner.has_point(p) and grid.is_walkable(p):
		n += 1
		p += LevelGrid.DIRS[dir]
	return n


func _touches_u_end(b: Rect2i, r: Rect2i) -> bool:
	if gen.rows_along_x():
		return r.position.x == b.position.x or r.end.x == b.end.x
	return r.position.y == b.position.y or r.end.y == b.end.y


func is_clear(r: Rect2i) -> bool:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, z)
			if grid.in_bounds(c) and grid.room_id[grid.idx(c)] >= 0:
				return false
	return true


## Rack-gap nook candidates (07 §5.5): a rack cell with racks on both sides along its row
## and behind it, and an aisle cell in front. Vector3i(x, z, dir to the aisle).
func nook_candidates() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var along := gen.along_dirs()
	var across := gen.across_dirs()
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.RACK:
			continue
		var c := grid.cell_at(i)
		if grid.kind(c + LevelGrid.DIRS[along[0]]) != LevelGrid.RACK or grid.kind(c + LevelGrid.DIRS[along[1]]) != LevelGrid.RACK:
			continue
		for d in across:
			var front := c + LevelGrid.DIRS[d]
			var back := c - LevelGrid.DIRS[d]
			if grid.kind(front) == LevelGrid.FLOOR and not cross.has(grid.idx(front)) and grid.kind(back) == LevelGrid.RACK:
				out.append(Vector3i(c.x, c.y, d))
	return out
