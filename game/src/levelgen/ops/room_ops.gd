class_name RoomOps
extends RefCounted
## Room operations of the shared ops library (07 §4): carve_rooms, connect_rooms, bsp_split,
## plus add_room and insert_room used by the grammars for fixed and late rooms.

## Placement tries per jittered-grid slot.
const SLOT_TRIES := 6


## True when `rect` is inside the grid, every cell is free (VOID or, with `allow_floor`,
## corridor) and no other room lies within one cell (07 §4: 1-cell gaps).
static func room_fits(grid: LevelGrid, rect: Rect2i, allow_floor: bool = false) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > grid.size.x or rect.end.y > grid.size.y:
		return false
	for z in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var c := Vector2i(x, z)
			if not grid.in_bounds(c):
				continue
			var k := grid.kind(c)
			if k == LevelGrid.ROOM or grid.room_id[grid.idx(c)] >= 0:
				return false
			if rect.has_point(c) and k != LevelGrid.VOID and not (allow_floor and k == LevelGrid.FLOOR):
				return false
	return true


## 1 on every room cell and every cell within one cell of a room (8-neighbourhood).
## With it, `rect_free` answers room_fits in O(cells of rect).
static func room_halo(grid: LevelGrid) -> PackedByteArray:
	var halo := PackedByteArray()
	halo.resize(grid.cell_count())
	for i in grid.cell_count():
		if grid.room_id[i] < 0:
			continue
		var c := grid.cell_at(i)
		for z in range(c.y - 1, c.y + 2):
			for x in range(c.x - 1, c.x + 2):
				if x >= 0 and z >= 0 and x < grid.size.x and z < grid.size.y:
					halo[z * grid.size.x + x] = 1
	return halo


## room_fits with a precomputed halo.
static func rect_free(grid: LevelGrid, rect: Rect2i, halo: PackedByteArray, allow_floor: bool) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > grid.size.x or rect.end.y > grid.size.y:
		return false
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * grid.size.x + x
			var k := grid.cells[i]
			if halo[i] != 0 or not (k == LevelGrid.VOID or (allow_floor and k == LevelGrid.FLOOR)):
				return false
	return true


## Makes `rect` a room: ROOM cells, room id, open interior edges, closed perimeter.
static func add_room(grid: LevelGrid, rect: Rect2i, kind: StringName) -> RoomData:
	var room := RoomData.new(rect, kind)
	room.id = grid.room_list.size()
	grid.room_list.append(room)
	for c in room.cells():
		grid.set_kind(c, LevelGrid.ROOM)
		grid.room_id[grid.idx(c)] = room.id
	for c in room.cells():
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if rect.has_point(o):
				grid.set_wall(c, d, LevelGrid.NONE)
			elif grid.in_bounds(o):
				grid.set_wall(c, d, LevelGrid.WALL)
	return room


## Jittered-grid placement of `count` non-overlapping rooms with sizes in
## [size_min, size_max], kept `margin` cells from the grid border. Returns the rooms placed
## (possibly fewer than asked when the grid is full).
static func carve_rooms(grid: LevelGrid, count: int, size_min: Vector2i, size_max: Vector2i,
		margin: int, rng: RandomNumberGenerator, kind: StringName = RoomData.GENERIC) -> Array[RoomData]:
	var out: Array[RoomData] = []
	if count <= 0:
		return out
	var region := Rect2i(margin, margin, grid.size.x - margin * 2, grid.size.y - margin * 2)
	var slots_per_axis := int(ceil(sqrt(float(count)))) + 1
	var slot := Vector2i(maxi(1, region.size.x / slots_per_axis), maxi(1, region.size.y / slots_per_axis))
	var order: Array[int] = []
	for i in slots_per_axis * slots_per_axis:
		order.append(i)
	shuffle(order, rng)
	for s in order:
		if out.size() >= count:
			break
		var origin := region.position + Vector2i(s % slots_per_axis, s / slots_per_axis) * slot
		for t in SLOT_TRIES:
			var sz := Vector2i(rng.randi_range(size_min.x, size_max.x), rng.randi_range(size_min.y, size_max.y))
			if rng.randi_range(0, 1) == 1:
				sz = Vector2i(sz.y, sz.x)
			var pos := origin + Vector2i(rng.randi_range(0, maxi(0, slot.x - 1)), rng.randi_range(0, maxi(0, slot.y - 1)))
			pos.x = mini(pos.x, region.end.x - sz.x)
			pos.y = mini(pos.y, region.end.y - sz.y)
			var rect := Rect2i(pos, sz)
			if room_fits(grid, rect):
				out.append(add_room(grid, rect, kind))
				break
	return out


## Opens between doors_range.x and doors_range.y perimeter edges of each room onto adjacent
## corridor cells; each is DOOR with probability door_chance, else NONE. At least one
## opening per room is guaranteed when any corridor cell touches the room.
static func connect_rooms(grid: LevelGrid, rooms: Array[RoomData], doors_range: Vector2i,
		rng: RandomNumberGenerator, door_chance: float) -> void:
	for room in rooms:
		var candidates: Array[Vector3i] = []
		for e in room.perimeter_edges():
			var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
			if grid.kind(o) == LevelGrid.FLOOR:
				candidates.append(e)
		shuffle(candidates, rng)
		var n := mini(candidates.size(), rng.randi_range(doors_range.x, doors_range.y))
		for k in n:
			var e := candidates[k]
			var type := LevelGrid.DOOR if rng.randf() < door_chance else LevelGrid.NONE
			grid.set_wall(Vector2i(e.x, e.y), e.z, type)
			room.doors.append(e)


## Turns `rect` (corridor or void cells, no room within one cell) into a room after the
## maze exists. Edges that were open stay open, so connectivity only grows. A room left
## without an opening gets one DOOR onto an adjacent corridor. Returns null if it cannot.
static func insert_room(grid: LevelGrid, rect: Rect2i, kind: StringName) -> RoomData:
	if not room_fits(grid, rect, true):
		return null
	var open_edges: Array[Vector3i] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, z)
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				if not rect.has_point(o) and grid.can_step(c, d):
					open_edges.append(Vector3i(x, z, d))
	var room := add_room(grid, rect, kind)
	for e in open_edges:
		grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.NONE)
		room.doors.append(e)
	if room.doors.is_empty():
		for e in room.perimeter_edges():
			if grid.kind(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]) == LevelGrid.FLOOR:
				grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.DOOR)
				room.doors.append(e)
				break
	return room


## Binary space partition of `region` into rects no smaller than `min_size` per side.
static func bsp_split(region: Rect2i, min_size: Vector2i, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var work: Array[Rect2i] = [region]
	var guard := region.size.x * region.size.y
	while not work.is_empty() and guard > 0:
		guard -= 1
		var r: Rect2i = work.pop_back()
		var can_x := r.size.x >= min_size.x * 2
		var can_z := r.size.y >= min_size.y * 2
		if not can_x and not can_z:
			out.append(r)
			continue
		var split_x := can_x and (not can_z or (r.size.x >= r.size.y if rng.randf() < 0.75 else rng.randi_range(0, 1) == 0))
		if split_x:
			var at := rng.randi_range(min_size.x, r.size.x - min_size.x)
			work.append(Rect2i(r.position, Vector2i(at, r.size.y)))
			work.append(Rect2i(r.position + Vector2i(at, 0), Vector2i(r.size.x - at, r.size.y)))
		else:
			var at := rng.randi_range(min_size.y, r.size.y - min_size.y)
			work.append(Rect2i(r.position, Vector2i(r.size.x, at)))
			work.append(Rect2i(r.position + Vector2i(0, at), Vector2i(r.size.x, r.size.y - at)))
	out.append_array(work)
	return out


## Fisher-Yates with the given rng (Array.shuffle uses the global RNG, which is banned).
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t
