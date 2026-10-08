class_name PoolsGenerator
extends StratumGenerator
## Pools grammar (07 §5.2): big tiled halls on a spine. One long 1-cell corridor runs across
## the grid from the spawn antechamber (west edge, the stairwell landing beyond it) with 3
## to 5 branches off it; the bands either side are split (bsp) into pieces and the pool
## halls are drawn from them until the walkable target is met, each attached by an open
## arch to the spine, a branch, or a hall already attached. Corridor stubs nothing opens
## onto are trimmed. Every hall gets a sunken basin (PoolBasins); the exit hall, the far
## east hall, has the dry 1.8 m basin with the drain hatch at its bottom. Pump rooms (2x2,
## a door) are cut beside corridors and host the pump-corner hide spots (and the breaker).

const HALL := &"pool_hall"
const PUMP := &"pump"
## Halls land this fraction below the walkable target, at random, so levels vary in size.
const WALKABLE_JITTER := 0.08
## Branch cells that survive trimming, for the budget estimate.
const BRANCH_KEEP_ESTIMATE := 0.3
const BREAKER_INSET := 0.05
const LONG_MAX := 14
const SHORT_MAX := 10

var spawn_room: RoomData = null
var exit_room: RoomData = null
var halls: Array[RoomData] = []
var pumps: Array[RoomData] = []
var basins: PoolBasins = null
var spine_z: int = 0
## Cell index -> true for spine and branch cells.
var _corridor: Dictionary = {}
## Selected hall rects and their pre-rolled basin parameters, before they become rooms.
var _plans: Array[Dictionary] = []
## Pump rooms the grammar wanted (validator rule 8 counts their hide spots against it).
var _pump_target: int = 0
## Door edge -> the pump rect it was found for (_pump_door).
var _pump_rects: Dictionary = {}


func layout() -> void:
	var n := grid.size.x
	var ss := Tuning.POOLS_SPAWN_ROOM_SIZE
	spine_z = n / 2 + rng_layout.randi_range(-2, 1)
	spawn_room = RoomOps.add_room(grid, Rect2i(0, spine_z - ss.y / 2, ss.x, ss.y), RoomData.SPAWN)
	data.spawn_dir = LevelGrid.W
	data.spawn_cell = Vector2i(0, spine_z)
	_carve_line(Vector2i(ss.x, spine_z), LevelGrid.E, n - ss.x)
	grid.set_wall(Vector2i(ss.x - 1, spine_z), LevelGrid.E, LevelGrid.NONE)
	spawn_room.doors.append(Vector3i(ss.x - 1, spine_z, LevelGrid.E))
	var branches := _branches(n)
	var pump_count := rng_layout.randi_range(Tuning.POOLS_PUMP_ROOMS_MIN, Tuning.POOLS_PUMP_ROOMS_MAX)
	basins = PoolBasins.new(self)
	_select_halls(_pieces(n, branches), branches.size(), pump_count)
	_open_arches()
	_trim_corridors()
	grid.finalize_walls()
	for k in halls.size():
		basins.dig(halls[k], _plans[k], halls[k] == exit_room)
	_pump_target = pump_count
	_insert_pumps(pump_count)
	grid.finalize_walls()
	grid.refresh_ledges()
	MazeOps.mark_dead_ends(grid)


func _carve_line(from: Vector2i, dir: int, length: int) -> void:
	var prev := Vector2i(-1, -1)
	for k in length:
		var c := from + LevelGrid.DIRS[dir] * k
		if not grid.in_bounds(c):
			break
		grid.set_kind(c, LevelGrid.FLOOR)
		_corridor[grid.idx(c)] = true
		if k > 0:
			grid.set_wall(prev, dir, LevelGrid.NONE)
		prev = c


## 3 to 5 branches off the spine, each to one side, at least POOLS_BRANCH_SPACING apart on
## its side, running to the grid edge. Vector2i(x, side) with side -1 north, +1 south.
func _branches(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var want := rng_layout.randi_range(Tuning.POOLS_BRANCHES_MIN, Tuning.POOLS_BRANCHES_MAX)
	var lo := Tuning.POOLS_SPAWN_ROOM_SIZE.x + Tuning.POOLS_HALL_MIN_SIDE
	var xs: Array[int] = []
	for x in range(lo, n - Tuning.POOLS_HALL_MIN_SIDE):
		xs.append(x)
	RoomOps.shuffle(xs, rng_layout)
	for x in xs:
		if out.size() >= want:
			break
		var side := -1 if rng_layout.randi_range(0, 1) == 0 else 1
		var ok := true
		for b in out:
			if b.y == side and absi(b.x - x) < Tuning.POOLS_BRANCH_SPACING:
				ok = false
		if not ok:
			continue
		out.append(Vector2i(x, side))
		var dir := LevelGrid.N if side < 0 else LevelGrid.S
		var start := Vector2i(x, spine_z + side)
		_carve_line(start, dir, spine_z if side < 0 else n - 1 - spine_z)
		grid.set_wall(Vector2i(x, spine_z), dir, LevelGrid.NONE)
	return out


## The bands north and south of the spine, cut at the branches and split (bsp) into pieces
## at least POOLS_HALL_MIN_SIDE a side.
func _pieces(n: int, branches: Array[Vector2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var min_side := Tuning.POOLS_HALL_MIN_SIDE
	for side: int in [-1, 1]:
		var z0 := 0 if side < 0 else spine_z + 1
		var z1 := spine_z - 1 if side < 0 else n - 1
		var cuts: Array[int] = []
		for b in branches:
			if b.y == side:
				cuts.append(b.x)
		cuts.sort()
		cuts.append(n)
		var a := Tuning.POOLS_SPAWN_ROOM_SIZE.x
		for cut in cuts:
			var region := Rect2i(a, z0, cut - a, z1 - z0 + 1)
			a = cut + 1
			if region.size.x < min_side or region.size.y < min_side:
				continue
			out.append_array(RoomOps.bsp_split(region, Vector2i(min_side, min_side), rng_layout))
	return out


## Sides of `rect` (directions) that have a corridor cell just outside.
func _corridor_sides(rect: Rect2i) -> Array[int]:
	var out: Array[int] = []
	for e in RoomData.new(rect).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if grid.in_bounds(o) and _corridor.has(grid.idx(o)) and not out.has(e.z):
			out.append(e.z)
	return out


## Draws halls from the pieces: the exit hall first (the corridor-side piece farthest east),
## then pieces beside a corridor, then pieces beside a chosen hall, each shrunk to the
## 07 sizes and to what is left of the walkable budget.
func _select_halls(pieces: Array[Rect2i], branch_count: int, pump_count: int) -> void:
	var target := int(walkable_target(data.depth) * (1.0 - rng_layout.randf() * WALKABLE_JITTER))
	var spine := grid.size.x - Tuning.POOLS_SPAWN_ROOM_SIZE.x
	var branch_cells := 0
	for i in _corridor:
		branch_cells += 1
	branch_cells -= spine
	var left := target - spine - int(branch_cells * BRANCH_KEEP_ESTIMATE) \
		- Tuning.POOLS_SPAWN_ROOM_SIZE.x * Tuning.POOLS_SPAWN_ROOM_SIZE.y \
		- pump_count * Tuning.POOLS_PUMP_ROOM_SIZE.x * Tuning.POOLS_PUMP_ROOM_SIZE.y
	RoomOps.shuffle(pieces, rng_layout)
	var exit_k := -1
	for k in pieces.size():
		if not _corridor_sides(pieces[k]).is_empty() and (exit_k < 0 or pieces[k].end.x > pieces[exit_k].end.x):
			exit_k = k
	if exit_k < 0:
		return
	var order: Array[Rect2i] = [pieces[exit_k]]
	for k in pieces.size():
		if k != exit_k:
			order.append(pieces[k])
	var min_area := Tuning.POOLS_HALL_MIN_SIDE * Tuning.POOLS_HALL_MIN_SIDE
	# Share the budget among the number of halls the grammar wants (07: 6 to 9).
	var count := rng_layout.randi_range(Tuning.POOLS_HALLS_MIN, Tuning.POOLS_HALLS_MAX)
	var share := maxi(min_area, left / count)
	for pass_k in 2:
		for piece in order:
			if _plans.size() >= Tuning.POOLS_HALLS_MAX or (left < min_area and not _plans.is_empty()):
				return
			if _taken(piece):
				continue
			var sides := _corridor_sides(piece)
			var anchor := sides[rng_layout.randi_range(0, sides.size() - 1)] if not sides.is_empty() else -1
			if anchor < 0 and pass_k == 0:
				continue
			if anchor < 0:
				anchor = _hall_side(piece)
				if anchor < 0:
					continue
			var exit := _plans.is_empty()
			var rect := _shrink(piece, anchor, mini(maxi(left, min_area), share))
			var plan := basins.roll(rect, exit)
			plan[&"piece"] = piece
			_plans.append(plan)
			left -= int(plan[&"walkable"])


func _taken(piece: Rect2i) -> bool:
	for p in _plans:
		if p[&"piece"] == piece:
			return true
	return false


## A side of `piece` that touches a chosen hall rect, or -1.
func _hall_side(piece: Rect2i) -> int:
	for e in RoomData.new(piece).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		for p in _plans:
			if (p[&"rect"] as Rect2i).has_point(o):
				return e.z
	return -1


## Clamps a piece to the hall sizes (long side <= 14, short <= 10) and to `max_area`,
## keeping the side `anchor` in place; the other axis shrinks about its centre.
func _shrink(rect: Rect2i, anchor: int, max_area: int) -> Rect2i:
	var sz := rect.size
	var long_x := sz.x >= sz.y
	sz.x = mini(sz.x, LONG_MAX if long_x else SHORT_MAX)
	sz.y = mini(sz.y, SHORT_MAX if long_x else LONG_MAX)
	var m := Tuning.POOLS_HALL_MIN_SIDE
	while sz.x * sz.y > max_area and (sz.x > m or sz.y > m):
		if sz.x >= sz.y and sz.x > m:
			sz.x -= 1
		else:
			sz.y -= 1
	var pos := rect.position
	match anchor:
		LevelGrid.N:
			pos.x += (rect.size.x - sz.x) / 2
		LevelGrid.S:
			pos.x += (rect.size.x - sz.x) / 2
			pos.y = rect.end.y - sz.y
		LevelGrid.W:
			pos.y += (rect.size.y - sz.y) / 2
		LevelGrid.E:
			pos.y += (rect.size.y - sz.y) / 2
			pos.x = rect.end.x - sz.x
	return Rect2i(pos, sz)


## Rooms for the chosen rects, each with an open arch (07 §5.2: a 1-cell doorway, no door
## prefab) to a corridor or to a hall already attached; a second arch sometimes. A rect
## that cannot be attached is dropped (it stays void).
func _open_arches() -> void:
	var attached: Array[Dictionary] = []
	var pending := _plans.duplicate()
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for plan: Dictionary in pending.duplicate():
			var rect: Rect2i = plan[&"rect"]
			var arches := _arch_edges(rect, attached)
			if arches.is_empty():
				continue
			pending.erase(plan)
			progress = true
			var room := RoomOps.add_room(grid, rect, RoomData.EXIT if attached.is_empty() else HALL)
			attached.append(plan)
			halls.append(room)
			var first := arches[arches.size() / 2]
			_open(room, first)
			var extra := 1.0 if simplest else Tuning.POOLS_EXTRA_ARCH_CHANCE
			if arches.size() > 1 and rng_layout.randf() < extra:
				var other := arches[rng_layout.randi_range(0, arches.size() - 1)]
				if other.z != first.z or absi(other.x - first.x) + absi(other.y - first.y) > 2:
					_open(room, other)
	_plans = attached
	exit_room = halls[0] if not halls.is_empty() else null


## Perimeter edges of `rect` facing a corridor cell, else facing an attached hall.
func _arch_edges(rect: Rect2i, attached: Array[Dictionary]) -> Array[Vector3i]:
	var to_corridor: Array[Vector3i] = []
	var to_hall: Array[Vector3i] = []
	for e in RoomData.new(rect).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if not grid.in_bounds(o):
			continue
		if _corridor.has(grid.idx(o)) and grid.kind(o) == LevelGrid.FLOOR:
			to_corridor.append(e)
			continue
		for p in attached:
			if (p[&"rect"] as Rect2i).has_point(o):
				to_hall.append(e)
	return to_corridor if not to_corridor.is_empty() else to_hall


func _open(room: RoomData, e: Vector3i) -> void:
	grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.NONE)
	room.doors.append(e)


## Corridor cells that lead nowhere (a stub with one opening, no arch) go back to void,
## repeatedly; the spine cell at the spawn antechamber is kept.
func _trim_corridors() -> void:
	var keep := grid.idx(Vector2i(Tuning.POOLS_SPAWN_ROOM_SIZE.x, spine_z))
	var changed := true
	while changed:
		changed = false
		for i: int in _corridor.keys():
			if i == keep or grid.cells[i] != LevelGrid.FLOOR or grid.openings_i(i) > 1:
				continue
			var c := grid.cell_at(i)
			for d in 4:
				grid.set_wall(c, d, LevelGrid.WALL)
			grid.set_kind(c, LevelGrid.VOID)
			_corridor.erase(i)
			changed = true


## Pump rooms (07 §5.2): 2x2 with a DOOR, cut into void beside a corridor (the door opens
## onto it) or, failing that, beside a hall's floor ring (the door opens into the hall).
func _insert_pumps(count: int) -> void:
	var sz := Tuning.POOLS_PUMP_ROOM_SIZE
	for k in count:
		_pump_rects.clear()
		var by_corridor: Array[Vector3i] = []
		var by_hall: Array[Vector3i] = []
		for z in range(0, grid.size.y - sz.y + 1):
			for x in range(0, grid.size.x - sz.x + 1):
				var rect := Rect2i(x, z, sz.x, sz.y)
				var door := _pump_door(rect)
				if door.x < 0:
					continue
				var o := Vector2i(door.x, door.y) + LevelGrid.DIRS[door.z]
				(by_corridor if grid.kind(o) == LevelGrid.FLOOR else by_hall).append(door)
		var pool := by_corridor if not by_corridor.is_empty() else by_hall
		if pool.is_empty():
			return
		var pick := pool[rng_layout.randi_range(0, pool.size() - 1)]
		var at := Vector2i(pick.x, pick.y)
		var rect := _pump_rect_of(pick)
		var room := RoomOps.add_room(grid, rect, PUMP)
		grid.set_wall(at, pick.z, LevelGrid.DOOR)
		room.doors.append(pick)
		pumps.append(room)


## The door edge of a free 2x2 void rect beside a corridor or a hall's level floor (in that
## order), as Vector3i(x, z, dir) on the room side; (-1, -1, -1) when the rect is not free.
## The rect position is encoded in the edge's cell and recovered by _pump_rect_of.
func _pump_door(rect: Rect2i) -> Vector3i:
	for c in RoomData.new(rect).cells():
		if grid.kind(c) != LevelGrid.VOID or grid.room_id[grid.idx(c)] >= 0:
			return Vector3i(-1, -1, -1)
	var best := Vector3i(-1, -1, -1)
	for e in RoomData.new(rect).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if not grid.in_bounds(o) or grid.room_id[grid.idx(o)] == spawn_room.id:
			continue
		if grid.kind(o) == LevelGrid.FLOOR and _corridor.has(grid.idx(o)):
			_pump_rects[e] = rect
			return e
		var r := grid.room_of(o)
		if best.x < 0 and grid.kind(o) == LevelGrid.ROOM and r != null and r.kind != PUMP and is_zero_approx(grid.floor_y(o)):
			best = e
	if best.x >= 0:
		_pump_rects[best] = rect
	return best


func _pump_rect_of(door: Vector3i) -> Rect2i:
	return _pump_rects[door]


func decorate() -> void:
	if exit_room == null or data.exit_cell == LevelData.NO_CELL or data.critical_path.is_empty():
		return  # Rule 1 fails; the generator retries.
	flag_room(spawn_room, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_NO_SPAWN)
	flag_room(exit_room, LevelGrid.F_EXIT_ROOM | LevelGrid.F_NO_SPAWN)
	data.add_placement(LevelData.P_SPAWN, data.spawn_cell, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(data.spawn_dir)),
		{&"cabin_dir": data.spawn_dir})
	data.add_placement(LevelData.P_EXIT, data.exit_cell, Vector3.ZERO, LevelData.yaw_facing(data.exit_dir),
		{&"exit_kind": &"drain_hatch", &"lock": data.exit_lock, &"dir": data.exit_dir})
	if data.exit_lock == Tuning.LOCK_POWERED and not pumps.is_empty():
		flag_room(pumps[0], LevelGrid.F_LOCK_ROOM)
		_place_breaker(pumps[0])
	var soft := Tuning.POOLS_SOFT_WALLS + (Tuning.CYCLE2_EXTRA_SOFT_WALLS if data.cycle > 1 else 0)
	PopulateOps.soft_walls(self, soft, false, LevelGrid.F_EXIT_ROOM)
	_place_hide_spots()
	PopulateOps.lock_pickups(self)
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool)
	basins.place_props()
	_place_fixtures()
	PopulateOps.error_spawns(self)


func _place_breaker(room: RoomData) -> void:
	var slots := wall_slots(room)
	if slots.is_empty():
		return
	var pick := slots[0]
	for e in slots:
		if not grid.is_walkable(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]):
			pick = e
			break
	data.breaker_cell = Vector2i(pick.x, pick.y)
	data.add_placement(LevelData.P_BREAKER, data.breaker_cell, wall_offset(pick.z, BREAKER_INSET),
		LevelData.yaw_facing(LevelGrid.opposite(pick.z)), {&"variant": data.lock_variant, &"dir": pick.z})


## 09 §6 pump room corner: one per pump room, in the corner cell farthest from its door,
## facing the door (the player watches through the door's window). A marker until the hide
## spot interactable exists (M2.8).
func _place_hide_spots() -> void:
	data.expected_hide_spots = _pump_target
	for room in pumps:
		var door := Vector2i(room.doors[0].x, room.doors[0].y) if not room.doors.is_empty() else room.rect.position
		var best := room.rect.position
		for c in room.cells():
			if (c - door).length_squared() > (best - door).length_squared():
				best = c
		grid.add_flag(best, LevelGrid.F_HIDE_SPOT_HOST)
		var to_door := Vector2(door - best)
		var face := LevelGrid.E if absf(to_door.x) >= absf(to_door.y) and to_door.x > 0 else \
			(LevelGrid.W if absf(to_door.x) >= absf(to_door.y) else (LevelGrid.S if to_door.y > 0 else LevelGrid.N))
		occupied[grid.idx(best)] = true
		data.add_placement(LevelData.P_HIDE_SPOT, best, Vector3.ZERO, LevelData.yaw_facing(face),
			{&"kind": &"pump_corner", &"dir": face, &"view_yaw_limit": Tuning.HIDE_YAW_LIMIT_DEFAULT})


## 07 §5.2: ceiling panels every 3 cells in halls (on one level-wide lattice, T2) and every
## 2 cells in corridors; one group per hall and per corridor segment.
func _place_fixtures() -> void:
	var height := float(Tuning.STRATUM_CEILING_HEIGHT[&"pools"])
	var step := Tuning.POOLS_FIXTURE_SPACING_HALL_CELLS
	for room in grid.room_list:
		if room.kind != HALL and room.kind != RoomData.EXIT:
			FixtureOps.room_fixtures(self, room, height, &"panel")
			continue
		var cells: Array[Vector2i] = []
		for c in room.cells():
			if posmod(c.x, step) == 1 and posmod(c.y, step) == 1:
				cells.append(c)
		if cells.is_empty():
			cells.append(room.center())
		var group := gen_group(cells)
		room.fixture_group = group
		for c in cells:
			data.add_placement(LevelData.P_FIXTURE, c, Vector3(0.0, height - grid.floor_y(c), 0.0), 0.0,
				{&"group": group, &"fixture": &"panel"})
	FixtureOps.corridor_fixtures(self, Tuning.POOLS_FIXTURE_SPACING_CORRIDOR_CELLS, Tuning.HALLS_GROUP_MAX_FIXTURES, height, &"panel")


func release() -> void:
	basins = null


func gen_group(cells: Array[Vector2i]) -> int:
	var id := grid.groups.size()
	grid.groups[id] = cells
	return id
