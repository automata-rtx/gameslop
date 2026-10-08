class_name ServerGenerator
extends StratumGenerator
## Server grammar (07 §5.5): parallel aisles. A corridor runs round the perimeter (a ring
## inset 3 cells, as Offices); inside it the rack hall (ServerRacks): rows of RACK cells 6 to
## 9 long with 1-cell aisles, cross aisles between blocks, staggered so no aisle runs
## straight for more than 12 cells. 2 to 4 cages (4x4, fenced with GLASS-type mesh: no
## passage, sight passes, never noclipped) hold an item each behind a DOOR gate. The spawn
## is a 3x3 stairwell landing in the band outside the ring; the exit a 3x3 clearing at the
## end of an aisle holding the floor hatch, lit by one white light. A breaker room (2x2,
## a door) stands in the band when Powered. Three rack-gap nooks are cut into back-to-back
## racks. No soft walls (racks are not walls; a rack noclip passes the whole rack, 07 §7).

const CAGE := &"cage"
const BREAKER_INSET := 0.05
## Cells to spare over the breaker's distance from the exit.
const BREAKER_MARGIN := 2
## Rack-gap nooks stand at least this many cells apart.
const NOOK_SPACING := 3
## The exit clearing lands this many cells inside the critical path band (low, high).
const EXIT_BAND_INSET := Vector2(4.0, 6.0)

var ring: Rect2i = Rect2i()
var corridor: Dictionary = {}
var spawn_room: RoomData = null
var exit_room: RoomData = null
var breaker_room: RoomData = null
var cages: Array[RoomData] = []
## Nooks: Vector3i(x, z, dir to the aisle).
var nooks: Array[Vector3i] = []
var racks: ServerRacks = null
var furnish: ServerFurnish = null
var _t: bool = false


## Layout (u, v) to grid cell: rows run along u.
func cell(u: int, v: int) -> Vector2i:
	return Vector2i(v, u) if _t else Vector2i(u, v)


func rows_along_x() -> bool:
	return not _t


## The two directions along the rows, and the two across them (towards the aisles).
func along_dirs() -> Array[int]:
	var out: Array[int] = [LevelGrid.E, LevelGrid.W]
	if _t:
		out = [LevelGrid.N, LevelGrid.S]
	return out


func across_dirs() -> Array[int]:
	var out: Array[int] = [LevelGrid.N, LevelGrid.S]
	if _t:
		out = [LevelGrid.E, LevelGrid.W]
	return out


func layout() -> void:
	var n := grid.size.x
	var inset := Tuning.SERVER_RING_INSET
	ring = RingOps.carve_ring(grid, inset, corridor)
	_t = rng_layout.randi_range(0, 1) == 1
	racks = ServerRacks.new(self)
	racks.build()
	var side := rng_layout.randi_range(0, 3)
	var ss := Tuning.SERVER_SPAWN_ROOM_SIZE
	var along := RingOps.along_range(n, inset, ss.x)
	spawn_room = RoomOps.add_room(grid, RingOps.band_rect(n, inset, side, rng_layout.randi_range(along.x, along.y), ss.x, ss.y), RoomData.SPAWN)
	RingOps.open_middle(grid, spawn_room, LevelGrid.opposite(side), LevelGrid.NONE)
	data.spawn_dir = side
	data.spawn_cell = side_middle(spawn_room, side)
	grid.finalize_walls()
	_exit_clearing()
	_cages()
	_nooks()
	grid.finalize_walls()
	if data.exit_lock == Tuning.LOCK_POWERED and exit_room != null:
		_breaker_room()
		grid.finalize_walls()
	MazeOps.mark_dead_ends(grid)


## 07 §5.5: a 3x3 clearing at the end of an aisle, where the walk from spawn lands inside
## the critical path band (the middle of it when none does).
func _exit_clearing() -> void:
	var ds := grid.distance_field(data.spawn_cell)
	var band := LevelValidator.path_band(data) / Tuning.GRID_CELL_SIZE
	var lo := band.x + EXIT_BAND_INSET.x
	var hi := band.y - EXIT_BAND_INSET.y
	var good: Array[Rect2i] = []
	var best := Rect2i()
	var best_d := -1
	for r in racks.block_rects(Tuning.SERVER_EXIT_ROOM_SIZE, true):
		if not racks.runs_ok(r):
			continue
		var est := INF
		for c in RoomData.new(r).cells():
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				if not r.has_point(o) and grid.is_walkable(o) and ds[grid.idx(o)] >= 0:
					est = minf(est, ds[grid.idx(o)] + 1 + absi(c.x - (r.position.x + 1)) + absi(c.y - (r.position.y + 1)))
		if est == INF:
			continue
		if est >= lo and est <= hi:
			good.append(r)
		if est > best_d and est <= hi:
			best_d = int(est)
			best = r
	var pick := best
	if not good.is_empty():
		pick = good[rng_layout.randi_range(0, good.size() - 1)]
	if pick.size == Vector2i.ZERO:
		return
	exit_room = _clearing(pick, RoomData.EXIT)
	data.exit_cell = exit_room.center()
	data.exit_dir = LevelGrid.N


func _clearing(r: Rect2i, kind: StringName) -> RoomData:
	var room := RoomOps.add_room(grid, r, kind)
	racks.open_all(room)
	return room


## 2 to 4 cages (4x4) inside blocks: GLASS-type fence where they meet walkable cells, one
## DOOR gate onto an aisle (07 §5.5, rule 10).
func _cages() -> void:
	var want := Tuning.SERVER_CAGES_MIN if simplest else rng_layout.randi_range(Tuning.SERVER_CAGES_MIN, Tuning.SERVER_CAGES_MAX)
	var options := racks.block_rects(Tuning.SERVER_CAGE_SIZE, false)
	RoomOps.shuffle(options, rng_layout)
	for r in options:
		if cages.size() >= want:
			break
		if not racks.is_clear(r.grow(1)):
			continue
		var room := RoomOps.add_room(grid, r, CAGE)
		var fence := RingOps.edges_onto(grid, room, func(c: Vector2i) -> bool: return grid.is_walkable(c))
		if fence.is_empty():
			continue
		for e in fence:
			grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.GLASS)
		# The gate never lines up a straight walk longer than the aisle rule allows.
		var gates: Array[Vector3i] = []
		for e in fence:
			var dv := LevelGrid.DIRS[e.z]
			var across := r.size.x if dv.x != 0 else r.size.y
			if across + racks.reach(Vector2i(e.x, e.y) + dv, e.z) <= Tuning.SERVER_AISLE_STRAIGHT_MAX:
				gates.append(e)
		if gates.is_empty():
			gates = fence
		var gate := gates[rng_layout.randi_range(0, gates.size() - 1)]
		grid.set_wall(Vector2i(gate.x, gate.y), gate.z, LevelGrid.DOOR)
		room.doors.append(gate)
		cages.append(room)


## Three rack-gap nooks (07 §5.5): a rack cell between racks, open to one aisle only.
func _nooks() -> void:
	var options := racks.nook_candidates()
	var cells: Array[Vector2i] = []
	var ok: Array[Vector3i] = []
	for e in options:
		var c := Vector2i(e.x, e.y)
		if grid.room_id[grid.idx(c + LevelGrid.DIRS[e.z])] >= 0:
			continue
		cells.append(c)
		ok.append(e)
	for c in PlaceOps.poisson_cells(cells, Tuning.SERVER_RACK_GAP_HIDE_SPOTS, NOOK_SPACING, rng_layout):
		var e := ok[cells.find(c)]
		grid.set_kind(c, LevelGrid.FLOOR)
		grid.set_wall(c, e.z, LevelGrid.NONE)
		nooks.append(e)


## The breaker room (2x2, a DOOR) in the band beside the ring, at least half the critical
## path's length from the exit (2026-10-08 ruling).
func _breaker_room() -> void:
	var n := grid.size.x
	var inset := Tuning.SERVER_RING_INSET
	var sz := Tuning.SERVER_BREAKER_ROOM_SIZE
	var de := grid.distance_field(data.exit_cell)
	var length := PathOps.critical_path(grid, data.spawn_cell, data.exit_cell, false).size() - 1
	var good: Array[Vector3i] = []
	var along := RingOps.along_range(n, inset, sz.x)
	for side in 4:
		for a in range(along.x, along.y + 1):
			var r := RingOps.band_rect(n, inset, side, a, sz.x, sz.y)
			if not RingOps.rect_void(grid, r):
				continue
			var mid := StratumGenerator.side_middle(RoomData.new(r), LevelGrid.opposite(side))
			var o := mid + LevelGrid.DIRS[LevelGrid.opposite(side)]
			if PopulateOps.breaker_far_enough(de, grid.idx(o), length, BREAKER_MARGIN):
				good.append(Vector3i(side, a, 0))
	if good.is_empty():
		return
	var pick := good[rng_layout.randi_range(0, good.size() - 1)]
	breaker_room = RoomOps.add_room(grid, RingOps.band_rect(n, inset, pick.x, pick.y, sz.x, sz.y), RoomData.BREAKER)
	RingOps.open_middle(grid, breaker_room, LevelGrid.opposite(pick.x), LevelGrid.DOOR)


func decorate() -> void:
	if exit_room == null or data.critical_path.is_empty():
		return  # Rule 1 fails; the generator retries.
	flag_room(spawn_room, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_NO_SPAWN)
	flag_room(exit_room, LevelGrid.F_EXIT_ROOM | LevelGrid.F_NO_SPAWN)
	data.add_placement(LevelData.P_SPAWN, data.spawn_cell, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(data.spawn_dir)),
		{&"cabin_dir": data.spawn_dir})
	data.add_placement(LevelData.P_EXIT, data.exit_cell, Vector3.ZERO, LevelData.yaw_facing(data.exit_dir),
		{&"exit_kind": &"floor_hatch", &"lock": data.exit_lock, &"dir": data.exit_dir})
	if breaker_room != null:
		flag_room(breaker_room, LevelGrid.F_LOCK_ROOM)
		_place_breaker()
	data.soft_walls = []
	data.expected_soft_walls = Tuning.SERVER_SOFT_WALLS
	furnish = ServerFurnish.new(self)
	furnish.nooks()
	# Each cage's item cell is reserved before the keycard and notes are placed.
	var cage_cells: Array[Vector2i] = []
	for cage in cages:
		var c := furnish.cage_item_cell(cage)
		cage_cells.append(c)
		occupied[grid.idx(c)] = true
	PopulateOps.lock_pickups(self)
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool, cage_cells)
	furnish.props()
	furnish.fixtures()
	PopulateOps.error_spawns(self)


func release() -> void:
	racks = null
	furnish = null


func _place_breaker() -> void:
	var slots := wall_slots(breaker_room)
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
