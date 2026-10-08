class_name OfficeRooms
extends RefCounted
## Offices rooms (07 §5.4), for OfficesGenerator.layout: the cross corridors through the
## ring's interior, the open offices (a cubicle maze of PARTITION edges, braided), the glass
## meeting room, small offices cut from what is left (interior pieces and the band outside
## the ring), then the breaker room and the closets cut into void beside a corridor.

const OPEN := &"office_open"
const SMALL := &"office_small"
const MEETING := &"meeting"
## Openings of an open office onto corridors (no door: an open plan).
const OPEN_OPENINGS := Vector2i(2, 3)
## Cells to spare over the breaker's distance from the exit (later openings may cut it).
const BREAKER_MARGIN := 3
## Closets stand at least this many cells apart (Chebyshev).
const CLOSET_SPACING := 4

var gen: OfficesGenerator
var grid: LevelGrid
var rng: RandomNumberGenerator
## Interior rect inside the ring, and the leftover rects small offices are cut from.
var inner: Rect2i
var pieces: Array[Rect2i] = []


func _init(g: OfficesGenerator) -> void:
	gen = g
	grid = g.grid
	rng = g.rng_layout
	inner = g.ring.grow(-1)


# ---------------------------------------------------------------- corridors and sections

## 1 to 2 cross corridors (07 §5.4) joining opposite sides of the ring: one, either way,
## or two crossing at right angles. Returns the interior sections between them.
func cross_corridors() -> Array[Rect2i]:
	var count := Tuning.OFFICES_CROSS_CORRIDORS_MIN if gen.simplest else \
		rng.randi_range(Tuning.OFFICES_CROSS_CORRIDORS_MIN, Tuning.OFFICES_CROSS_CORRIDORS_MAX)
	var m := inner.size.x
	var lo := Tuning.OFFICES_OPEN_SIZE_MIN.x
	var hi := maxi(lo, m - 1 - Tuning.OFFICES_OPEN_SIZE_MIN.x)
	var vertical := rng.randi_range(0, 1) == 0
	var xs: Array[int] = []
	var zs: Array[int] = []
	if count >= 2 or vertical:
		xs.append(inner.position.x + rng.randi_range(lo, hi))
	if count >= 2 or not vertical:
		zs.append(inner.position.y + rng.randi_range(lo, hi))
	for x in xs:
		RingOps.carve_line(grid, Vector2i(x, inner.position.y), LevelGrid.S, inner.size.y, gen.corridor)
	for z in zs:
		RingOps.carve_line(grid, Vector2i(inner.position.x, z), LevelGrid.E, inner.size.x, gen.corridor)
	# A crossing cell is carved twice: re-open it on both axes.
	for x in xs:
		for z in zs:
			for d in 4:
				if grid.kind(Vector2i(x, z) + LevelGrid.DIRS[d]) == LevelGrid.FLOOR:
					grid.set_wall(Vector2i(x, z), d, LevelGrid.NONE)
	return _split(inner, xs, zs)


static func _split(r: Rect2i, xs: Array[int], zs: Array[int]) -> Array[Rect2i]:
	var cx: Array[int] = [r.position.x - 1]
	cx.append_array(xs)
	cx.append(r.end.x)
	var cz: Array[int] = [r.position.y - 1]
	cz.append_array(zs)
	cz.append(r.end.y)
	var out: Array[Rect2i] = []
	for j in cz.size() - 1:
		for i in cx.size() - 1:
			var rect := Rect2i(cx[i] + 1, cz[j] + 1, cx[i + 1] - cx[i] - 1, cz[j + 1] - cz[j] - 1)
			if rect.size.x > 0 and rect.size.y > 0:
				out.append(rect)
	return out


# ---------------------------------------------------------------- open offices and meeting

## Open offices in the largest sections (2 to 3), each a cubicle maze; the rest of each
## section and the sections without one become pieces. Then the meeting room. The open
## offices share what the walkable `target` leaves after the corridors, lobbies, the
## meeting room and the fewest small offices (07 §2 rule 4 wins over their size range).
func interior(sections: Array[Rect2i], target: int) -> void:
	sections.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return a.get_area() > b.get_area() or (a.get_area() == b.get_area() and (a.position.y * 1000 + a.position.x) < (b.position.y * 1000 + b.position.x)))
	var want := Tuning.OFFICES_OPEN_COUNT_MIN if gen.simplest else \
		rng.randi_range(Tuning.OFFICES_OPEN_COUNT_MIN, Tuning.OFFICES_OPEN_COUNT_MAX)
	var mt := Tuning.OFFICES_MEETING_SIZE
	var small := Tuning.OFFICES_SMALL_SIZE_MIN
	var budget := target - grid.walkable_count() - mt.x * mt.y - Tuning.OFFICES_SMALL_COUNT_MIN * small.x * small.y
	for s in sections:
		var left := want - gen.open_rooms.size()
		var size := _open_size(s, budget / maxi(1, left)) if left > 0 else Vector2i.ZERO
		if size == Vector2i.ZERO:
			pieces.append(s)
			continue
		var at := _corner(s, size)
		var room := RoomOps.add_room(grid, Rect2i(at, size), OPEN)
		budget -= size.x * size.y
		gen.open_rooms.append(room)
		cubicles(room)
		RoomOps.connect_rooms(grid, [room] as Array[RoomData], OPEN_OPENINGS, rng, 0.0)
		pieces.append_array(_guillotine(s, room.rect))
	_meeting()


## A random open office size within 07's range that fits `s` (either orientation), shrunk
## towards the minimum while its area exceeds `max_area`; ZERO when none fits.
func _open_size(s: Rect2i, max_area: int) -> Vector2i:
	var mn := Tuning.OFFICES_OPEN_SIZE_MIN
	var mx := Tuning.OFFICES_OPEN_SIZE_MAX
	var options: Array[Vector2i] = []
	for o in 2:
		var a := Vector2i(mn.x, mn.y) if o == 0 else Vector2i(mn.y, mn.x)
		var b := Vector2i(mx.x, mx.y) if o == 0 else Vector2i(mx.y, mx.x)
		if s.size.x >= a.x and s.size.y >= a.y:
			var size := Vector2i(rng.randi_range(a.x, mini(b.x, s.size.x)), rng.randi_range(a.y, mini(b.y, s.size.y)))
			while size.x * size.y > max_area and (size.x > a.x or size.y > a.y):
				if size.x - a.x >= size.y - a.y:
					size.x -= 1
				else:
					size.y -= 1
			options.append(size)
	if options.is_empty():
		return Vector2i.ZERO
	return options[rng.randi_range(0, options.size() - 1)]


## Top-left of a `size` rect in a random corner of `s`.
func _corner(s: Rect2i, size: Vector2i) -> Vector2i:
	var x := s.position.x if rng.randi_range(0, 1) == 0 else s.end.x - size.x
	var z := s.position.y if rng.randi_range(0, 1) == 0 else s.end.y - size.y
	return Vector2i(x, z)


## The two rects left when `r` (in a corner of `s`) is cut from `s`: one full-length strip
## beside it and one strip beside it within its own span.
func _guillotine(s: Rect2i, r: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var left := r.position.x == s.position.x
	var top := r.position.y == s.position.y
	var rest_x := Rect2i(r.end.x if left else s.position.x, s.position.y, s.size.x - r.size.x, s.size.y)
	var rest_z := Rect2i(r.position.x, r.end.y if top else s.position.y, r.size.x, s.size.y - r.size.y)
	if rng.randi_range(0, 1) == 0:
		# The z strip runs the full width instead.
		rest_x = Rect2i(r.end.x if left else s.position.x, r.position.y, s.size.x - r.size.x, r.size.y)
		rest_z = Rect2i(s.position.x, r.end.y if top else s.position.y, s.size.x, s.size.y - r.size.y)
	for x in [rest_x, rest_z]:
		if (x as Rect2i).size.x > 0 and (x as Rect2i).size.y > 0:
			out.append(x)
	return out


## 07 §5.4: the cubicle maze. Every interior edge of the room becomes PARTITION, a
## recursive backtracker opens a spanning tree, then `braid` of the dead ends get one more
## partition opened.
func cubicles(room: RoomData) -> void:
	var r := room.rect
	for c in room.cells():
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if r.has_point(c + LevelGrid.DIRS[d]):
				grid.set_wall(c, d, LevelGrid.PARTITION)
	var start := r.position + Vector2i(rng.randi_range(0, r.size.x - 1), rng.randi_range(0, r.size.y - 1))
	var seen: Dictionary = {start: true}
	var stack: Array[Vector2i] = [start]
	var guard := r.get_area() * 4
	while not stack.is_empty() and guard > 0:
		guard -= 1
		var c: Vector2i = stack[stack.size() - 1]
		var options: Array[int] = []
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if r.has_point(o) and not seen.has(o):
				options.append(d)
		if options.is_empty():
			stack.pop_back()
			continue
		var d := options[rng.randi_range(0, options.size() - 1)]
		var o := c + LevelGrid.DIRS[d]
		grid.set_wall(c, d, LevelGrid.NONE)
		seen[o] = true
		stack.append(o)
	var braid := 0.0 if gen.simplest else Tuning.OFFICES_BRAID * (Tuning.CYCLE2_BRAID_MULT if gen.data.cycle > 1 else 1.0)
	for c in room.cells():
		if grid.openings(c) != 1:
			continue
		var closed: Array[int] = []
		for d in 4:
			if r.has_point(c + LevelGrid.DIRS[d]) and grid.wall(c, d) == LevelGrid.PARTITION:
				closed.append(d)
		if not closed.is_empty() and rng.randf() < braid:
			grid.set_wall(c, closed[rng.randi_range(0, closed.size() - 1)], LevelGrid.NONE)


## The meeting room (5x4, either way), cut from a piece against a corridor; GLASS on its
## corridor side with one DOOR in it (07 §5.4).
func _meeting() -> void:
	var sz := Tuning.OFFICES_MEETING_SIZE
	var order: Array[int] = []
	for i in pieces.size():
		order.append(i)
	RoomOps.shuffle(order, rng)
	for i in order:
		var p := pieces[i]
		for o in 2:
			var size := sz if o == 0 else Vector2i(sz.y, sz.x)
			if p.size.x < size.x or p.size.y < size.y:
				continue
			for corner in 4:
				var at := Vector2i(p.position.x if corner % 2 == 0 else p.end.x - size.x,
					p.position.y if corner < 2 else p.end.y - size.y)
				var rect := Rect2i(at, size)
				if not _touches_corridor(rect):
					continue
				var room := RoomOps.add_room(grid, rect, MEETING)
				gen.meeting_room = room
				var glass := RingOps.edges_onto(grid, room, func(c: Vector2i) -> bool: return gen.corridor.has(grid.idx(c)))
				for e in glass:
					grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.GLASS)
				var door := glass[rng.randi_range(0, glass.size() - 1)]
				grid.set_wall(Vector2i(door.x, door.y), door.z, LevelGrid.DOOR)
				room.doors.append(door)
				pieces.remove_at(i)
				pieces.append_array(_guillotine(p, rect))
				return


func _touches_corridor(rect: Rect2i) -> bool:
	for e in RoomData.new(rect).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if grid.in_bounds(o) and gen.corridor.has(grid.idx(o)):
			return true
	return false


# ---------------------------------------------------------------- small offices

## Band pieces: the band beside the ring on every side, outside the spawn and exit rooms,
## cut into runs of 3 to 5 cells, full band depth.
func band_pieces() -> void:
	var n := grid.size.x
	var inset := Tuning.OFFICES_RING_INSET
	for side in 4:
		var end := n - inset
		var run := 0
		for a in range(inset, end + 1):
			if a < end and RingOps.rect_void(grid, RingOps.band_rect(n, inset, side, a, 1, inset)):
				run += 1
				continue
			_cut_run(side, a - run, run)
			run = 0


## Cuts a free band run into pieces of 3 to 5 cells (no remainder shorter than 3).
func _cut_run(side: int, start: int, length: int) -> void:
	var n := grid.size.x
	var inset := Tuning.OFFICES_RING_INSET
	var smin := Tuning.OFFICES_SMALL_SIZE_MIN.x
	var smax := Tuning.OFFICES_SMALL_SIZE_MAX.x
	var a := start
	var left := length
	while left >= smin:
		var len := mini(rng.randi_range(smin, smax), left)
		if left - len > 0 and left - len < smin:
			len = left if left <= smax else left - smin
		pieces.append(RingOps.band_rect(n, inset, side, a, len, inset))
		a += len
		left -= len


## Small offices (6 to 10, 07 §5.4) from the pieces: each piece is split (bsp, 3x3 at
## least) and cropped to 5x4; a part that touches a corridor (or an open office) may become
## a small office with a DOOR. Taken in random order until the count is reached and the
## walkable target is met.
func small_offices(target: int) -> void:
	var parts: Array[Rect2i] = []
	for p in pieces:
		for q in RoomOps.bsp_split(p, Tuning.OFFICES_SMALL_SIZE_MIN, rng):
			parts.append(_crop(q))
	RoomOps.shuffle(parts, rng)
	var want_min := Tuning.OFFICES_SMALL_COUNT_MIN
	var want_max := Tuning.OFFICES_SMALL_COUNT_MAX
	var walk := grid.walkable_count()
	for q in parts:
		if gen.small_rooms.size() >= want_max or (gen.small_rooms.size() >= want_min and walk >= target):
			break
		if q.size.x < Tuning.OFFICES_SMALL_SIZE_MIN.x or q.size.y < Tuning.OFFICES_SMALL_SIZE_MIN.y:
			continue
		if not RingOps.rect_void(grid, q):
			continue
		var door := _door_edge(q)
		if door.x < 0:
			continue
		var room := RoomOps.add_room(grid, q, SMALL)
		grid.set_wall(Vector2i(door.x, door.y), door.z, LevelGrid.DOOR)
		room.doors.append(door)
		gen.small_rooms.append(room)
		walk += q.get_area()


## A piece cropped to the small office maximum (5x4 either way, the long side kept).
static func _crop(q: Rect2i) -> Rect2i:
	var mx := Tuning.OFFICES_SMALL_SIZE_MAX
	var long := maxi(mx.x, mx.y)
	var short := mini(mx.x, mx.y)
	var size := q.size
	if size.x >= size.y:
		size = Vector2i(mini(size.x, long), mini(size.y, short))
	else:
		size = Vector2i(mini(size.x, short), mini(size.y, long))
	return Rect2i(q.position, size)


## A door edge for a small office at `q`: the middle-most perimeter edge onto a corridor,
## else onto an open office. (-1, -1, -1) when it touches neither.
func _door_edge(q: Rect2i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var best_score := -INF
	var centre := Vector2(q.position) + Vector2(q.size - Vector2i.ONE) * 0.5
	for e in RoomData.new(q).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if not grid.in_bounds(o):
			continue
		var score := -Vector2(e.x, e.y).distance_to(centre)
		if gen.corridor.has(grid.idx(o)):
			score += 100.0
		elif grid.room_of(o) == null or grid.room_of(o).kind != OPEN:
			continue
		if score > best_score:
			best_score = score
			best = e
	return best


# ---------------------------------------------------------------- breaker and closets

## The breaker room (2x2, 07 §5.4): Offices always has one (07: "a breaker still exists"
## when the lock is not Powered). Cut into void beside a corridor, at least half the
## critical path's length from the exit (2026-10-08 ruling), with one DOOR.
func breaker_room() -> void:
	var sz := Tuning.OFFICES_BREAKER_ROOM_SIZE
	var de := grid.distance_field(gen.data.exit_cell)
	var path := PathOps.critical_path(grid, gen.data.spawn_cell, gen.data.exit_cell, false)
	var length := path.size() - 1
	var ds := grid.distance_field(gen.data.spawn_cell)
	var good: Array[Array] = []
	for z in range(0, grid.size.y - sz.y + 1):
		for x in range(0, grid.size.x - sz.x + 1):
			var rect := Rect2i(x, z, sz.x, sz.y)
			if not RingOps.rect_void(grid, rect):
				continue
			for e in RoomData.new(rect).perimeter_edges():
				var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
				if not grid.in_bounds(o) or not gen.corridor.has(grid.idx(o)) or ds[grid.idx(o)] < 0:
					continue
				if PopulateOps.breaker_far_enough(de, grid.idx(o), length, BREAKER_MARGIN):
					good.append([rect, e])
					break
	if good.is_empty():
		return
	var pick: Array = good[rng.randi_range(0, good.size() - 1)]
	var room := RoomOps.add_room(grid, pick[0], RoomData.BREAKER)
	var e: Vector3i = pick[1]
	grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.DOOR)
	room.doors.append(e)
	gen.breaker_room = room


## Closets (1 to 2, 1x1, a DOOR, lockers inside), cut into void beside a corridor.
func closets() -> void:
	var want := rng.randi_range(Tuning.OFFICES_CLOSETS_MIN, Tuning.OFFICES_CLOSETS_MAX)
	var candidates: Array[Vector2i] = []
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.VOID or grid.room_id[i] >= 0:
			continue
		var c := grid.cell_at(i)
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if grid.in_bounds(o) and gen.corridor.has(grid.idx(o)):
				candidates.append(c)
				break
	for c in PlaceOps.poisson_cells(candidates, want, CLOSET_SPACING, rng):
		var room := RoomOps.add_room(grid, Rect2i(c, Vector2i.ONE), RoomData.CLOSET)
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if grid.in_bounds(o) and gen.corridor.has(grid.idx(o)):
				grid.set_wall(c, d, LevelGrid.DOOR)
				room.doors.append(Vector3i(c.x, c.y, d))
				break
		gen.closets.append(room)
