class_name HallsGenerator
extends StratumGenerator
## Halls grammar (07 §5.1): a braided maze of 2 m corridors with rooms. The spawn room and
## the exit room sit on opposite edges of the grid (the Landing cabin and the elevator are
## outside the perimeter wall); generic rooms are carved on a jittered grid; the maze fills
## the rest and is thinned to the walkable target; the breaker room and closets are cut
## into the finished maze so they never break it.

const PROPS: Array[StringName] = [&"vending", &"payphone", &"chair", &"wall_clock"]
## Wall-standing props sit this far off the wall plane (m).
const PROP_INSET := 0.35
const LOCKER_INSET := 0.3
const BREAKER_INSET := 0.05
## Thinning lands this fraction below the walkable target, at random, so levels vary in size.
const WALKABLE_JITTER := 0.08
## Void masses: one block per BLOCK_SLOT x BLOCK_SLOT slot, BLOCK_MIN..BLOCK_MAX cells a
## side, placed until the maze has this multiple of the walkable target left to fill
## (thinning removes the rest).
const BLOCK_SLOT := 4
const BLOCK_MIN := 2
const BLOCK_MAX := 3
const BLOCK_FREE_MARGIN := 1.1
## Passes over the slots (a slot whose block did not fit gets another throw).
const BLOCK_ROUNDS := 3
## Cells the exit room is expected to add when it is cut into the maze.
const EXIT_RESERVE := 4
## The exit is placed this many cells inside the path band (low, high) so the shortcuts the
## breaker room and doors add later do not push the walk out of it.
const EXIT_BAND_INSET := Vector2(6.0, 10.0)
## Closets stand at least this many cells apart (Chebyshev), so two never share a halo.
const CLOSET_SPACING := 4
## Cells to spare over the breaker's distance from the exit (later doors may cut it).
const BREAKER_MARGIN := 2

var spawn_room: RoomData = null
var exit_room: RoomData = null
var breaker_room: RoomData = null
var closets: Array[RoomData] = []
var _protected: Dictionary = {}
## M2.3 hooks for the Substrate, which runs this layout and then unfinishes it (07 §5.6):
## the walkable target is scaled up by the cells the unfinish step removes, and no closets
## are cut (no hide spots in the Substrate).
var walkable_scale: float = 1.0
var closets_enabled: bool = true
var exit_band_inset: Vector2 = EXIT_BAND_INSET


func layout() -> void:
	var n := grid.size.x
	var side := rng_layout.randi_range(0, 3)
	spawn_room = RoomOps.add_room(grid, _border_rect(n, side, Tuning.HALLS_SPAWN_ROOM_SIZE), RoomData.SPAWN)
	data.spawn_dir = side
	data.spawn_cell = side_middle(spawn_room, side)
	var closet_count := rng_layout.randi_range(Tuning.HALLS_CLOSETS_MIN, Tuning.HALLS_CLOSETS_MAX)
	if not closets_enabled:
		closet_count = 0
	var powered := data.exit_lock == Tuning.LOCK_POWERED
	var total := rng_layout.randi_range(Tuning.HALLS_ROOMS_MIN, Tuning.HALLS_ROOMS_MAX)
	var generic := 0 if simplest else maxi(0, total - 2 - closet_count - (1 if powered else 0))
	var rooms := RoomOps.carve_rooms(grid, generic, Tuning.HALLS_ROOM_SIZE_MIN, Tuning.HALLS_ROOM_SIZE_MAX,
		Tuning.HALLS_ROOM_MARGIN, rng_layout)
	var target := int(walkable_target(data.depth) * walkable_scale * (1.0 - rng_layout.randf() * WALKABLE_JITTER))
	var room_cells := 0
	for r in grid.room_list:
		room_cells += r.rect.get_area()
	var blocked := _void_blocks(int(target * BLOCK_FREE_MARGIN) - room_cells)
	MazeOps.maze_fill(grid, Rect2i(Vector2i.ZERO, grid.size), rng_layout, blocked)
	RoomOps.connect_rooms(grid, [spawn_room] as Array[RoomData], Vector2i(1, 2), rng_layout, 0.0)
	RoomOps.connect_rooms(grid, rooms, Vector2i(1, 3), rng_layout, 0.5)
	_protect_doors()
	var reserve := closet_count + EXIT_RESERVE + (Tuning.HALLS_BREAKER_ROOM_SIZE.x * Tuning.HALLS_BREAKER_ROOM_SIZE.y if powered else 0)
	MazeOps.sparsify(grid, target - reserve, rng_layout, _protected)
	var braid := 0.0 if simplest else Tuning.HALLS_BRAID * (Tuning.CYCLE2_BRAID_MULT if data.cycle > 1 else 1.0)
	MazeOps.braid(grid, braid, rng_layout)
	MazeOps.straighten(grid, 0.0 if simplest else Tuning.HALLS_STRAIGHTEN, rng_layout)
	MazeOps.limit_dead_ends(grid, Tuning.VALIDATE_DEAD_END_CHAIN_MAX, _protected)
	grid.finalize_walls()
	_insert_exit_room(side)
	if powered:
		_insert_breaker_room()
	_insert_closets(closet_count)
	MazeOps.mark_dead_ends(grid)
	grid.finalize_walls()


## Void masses between corridors (07 §2 VOID): blocks on a jittered grid, at least one cell
## apart and clear of rooms, until the free cells left for the maze reach `free_target`.
## The maze then runs between them, so the level covers the whole grid evenly.
func _void_blocks(free_target: int) -> Dictionary:
	var blocked: Dictionary = {}
	var free := 0
	for k in grid.cells:
		if k == LevelGrid.VOID:
			free += 1
	var per_axis := grid.size.x / BLOCK_SLOT
	var order: Array[int] = []
	for i in per_axis * per_axis:
		order.append(i)
	RoomOps.shuffle(order, rng_layout)
	var tries: Array[int] = []
	for k in BLOCK_ROUNDS:
		tries.append_array(order)
	for s in tries:
		if free <= free_target:
			break
		var sz := Vector2i(rng_layout.randi_range(BLOCK_MIN, BLOCK_MAX), rng_layout.randi_range(BLOCK_MIN, BLOCK_MAX))
		var origin := Vector2i(s % per_axis, s / per_axis) * BLOCK_SLOT
		var pos := origin + Vector2i(rng_layout.randi_range(0, BLOCK_SLOT - sz.x), rng_layout.randi_range(0, BLOCK_SLOT - sz.y))
		var rect := Rect2i(pos, sz)
		if not _block_fits(rect, blocked):
			continue
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				blocked[grid.idx(Vector2i(x, z))] = true
				free -= 1
	return blocked


func _block_fits(rect: Rect2i, blocked: Dictionary) -> bool:
	if rect.end.x > grid.size.x or rect.end.y > grid.size.y:
		return false
	for z in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var c := Vector2i(x, z)
			if not grid.in_bounds(c):
				continue
			if grid.kind(c) != LevelGrid.VOID or blocked.has(grid.idx(c)):
				return false
	return true


## The exit room (3x3) is cut into the finished maze against a grid edge other than the
## spawn's, where the walk from spawn lands inside the critical path band (07 §8 rule 2).
func _insert_exit_room(spawn_side: int) -> void:
	var sz := Tuning.HALLS_EXIT_ROOM_SIZE
	var ds := grid.distance_field(data.spawn_cell)
	var band := LevelValidator.path_band(data) / Tuning.GRID_CELL_SIZE
	var lo := band.x + exit_band_inset.x
	var hi := band.y - exit_band_inset.y
	var mid := (lo + hi) * 0.5
	var good: Array[Vector3i] = []
	var best := Vector3i(-1, -1, -1)
	var best_err := INF
	var halo := RoomOps.room_halo(grid)
	for s in 4:
		if s == spawn_side:
			continue
		for t in range(Tuning.HALLS_ROOM_MARGIN, grid.size.x - Tuning.HALLS_ROOM_MARGIN - sz.x + 1):
			var rect := _border_rect_at(grid.size.x, s, sz, t)
			if not RoomOps.rect_free(grid, rect, halo, true):
				continue
			var exit_cell := _side_middle_rect(rect, s)
			var est := INF
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var d := ds[grid.idx(Vector2i(x, z))]
					if d >= 0:
						est = minf(est, d + absi(x - exit_cell.x) + absi(z - exit_cell.y))
			if est == INF:
				continue
			if est >= lo and est <= hi:
				good.append(Vector3i(s, t, 0))
			if absf(est - mid) < best_err:
				best_err = absf(est - mid)
				best = Vector3i(s, t, 0)
	var pick := best
	if not good.is_empty():
		pick = good[rng_layout.randi_range(0, good.size() - 1)]
	if pick.x < 0:
		return
	exit_room = RoomOps.insert_room(grid, _border_rect_at(grid.size.x, pick.x, sz, pick.y), RoomData.EXIT)
	data.exit_dir = pick.x
	data.exit_cell = side_middle(exit_room, pick.x)


## A room of `sz` touching the grid edge `side`, at least the room margin from the corners.
func _border_rect(n: int, side: int, sz: Vector2i) -> Rect2i:
	var m := Tuning.HALLS_ROOM_MARGIN
	return _border_rect_at(n, side, sz, rng_layout.randi_range(m, n - m - sz.x))


static func _side_middle_rect(rect: Rect2i, side: int) -> Vector2i:
	return side_middle(RoomData.new(rect), side)


## A room of `sz` touching the grid edge `side` at offset `t` along that edge.
static func _border_rect_at(n: int, side: int, sz: Vector2i, t: int) -> Rect2i:
	match side:
		LevelGrid.N:
			return Rect2i(Vector2i(t, 0), sz)
		LevelGrid.E:
			return Rect2i(Vector2i(n - sz.x, t), sz)
		LevelGrid.S:
			return Rect2i(Vector2i(t, n - sz.y), sz)
	return Rect2i(Vector2i(0, t), sz)


func _protect_doors() -> void:
	for room in grid.room_list:
		for e in room.doors:
			_protected[grid.idx(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z])] = true


## Breaker room (07 §5.1, 2x2), at least half the critical path's length from the exit on
## foot (07 / 05 §10, 2026-10-08). First Descent: cut across the critical path in its first
## half (05 §10); otherwise in the far two thirds from spawn when it can be.
func _insert_breaker_room() -> void:
	var sz := Tuning.HALLS_BREAKER_ROOM_SIZE
	var dist := grid.distance_field(data.spawn_cell)
	var de := grid.distance_field(data.exit_cell)
	var path := PathOps.critical_path(grid, data.spawn_cell, data.exit_cell, false)
	var length := path.size() - 1
	var on_path: Dictionary = {}
	for k in path.size():
		if k >= length * 0.2 and PopulateOps.breaker_far_enough(de, grid.idx(path[k]), length, BREAKER_MARGIN):
			on_path[path[k]] = true
	var far := int(PathOps.max_distance(dist) / 3.0)
	var halo := RoomOps.room_halo(grid)
	var best: Array[Rect2i] = []
	var fair: Array[Rect2i] = []
	var w := grid.size.x
	for z in range(1, grid.size.y - sz.y):
		for x in range(1, w - sz.x):
			var i := z * w + x
			var cells: Array[int] = [i, i + 1, i + w, i + w + 1]
			var on := false
			var spawn_far := false
			var exit_far := true
			var open := 0
			for j in cells:
				if not LevelGrid.kind_walkable(grid.cells[j]):
					continue
				open += 1
				on = on or on_path.has(grid.cell_at(j))
				spawn_far = spawn_far or dist[j] >= far
				exit_far = exit_far and PopulateOps.breaker_far_enough(de, j, length, BREAKER_MARGIN)
			var rect := Rect2i(x, z, sz.x, sz.y)
			if open == 0 or not exit_far or not RoomOps.rect_free(grid, rect, halo, true):
				continue
			if data.first_run:
				if on:
					best.append(rect)
			elif spawn_far:
				best.append(rect)
			else:
				fair.append(rect)
	var pool := best if not best.is_empty() else fair
	if pool.is_empty():
		return
	breaker_room = RoomOps.insert_room(grid, pool[rng_layout.randi_range(0, pool.size() - 1)], RoomData.BREAKER)


## Closets (07 §5.1): 1x1 rooms with a DOOR, cut into void cells beside corridors.
func _insert_closets(count: int) -> void:
	var halo := RoomOps.room_halo(grid)
	var candidates: Array[Vector2i] = []
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.VOID or halo[i] != 0:
			continue
		var c := grid.cell_at(i)
		for d in 4:
			if grid.kind(c + LevelGrid.DIRS[d]) == LevelGrid.FLOOR:
				candidates.append(c)
				break
	var picks := PlaceOps.poisson_cells(candidates, count, CLOSET_SPACING, rng_layout)
	for c in picks:
		var room := RoomOps.insert_room(grid, Rect2i(c, Vector2i.ONE), RoomData.CLOSET)
		if room != null:
			closets.append(room)


func decorate() -> void:
	if exit_room == null or data.critical_path.is_empty():
		return  # Rule 1 fails; the generator retries.
	flag_room(spawn_room, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_NO_SPAWN)
	flag_room(exit_room, LevelGrid.F_EXIT_ROOM | LevelGrid.F_NO_SPAWN)
	data.add_placement(LevelData.P_SPAWN, data.spawn_cell, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(data.spawn_dir)),
		{&"cabin_dir": data.spawn_dir})
	data.add_placement(LevelData.P_EXIT, data.exit_cell, wall_offset(data.exit_dir, 0.0), LevelData.yaw_facing(LevelGrid.opposite(data.exit_dir)),
		{&"exit_kind": &"elevator", &"lock": data.exit_lock, &"dir": data.exit_dir})
	if breaker_room != null:
		flag_room(breaker_room, LevelGrid.F_LOCK_ROOM)
		_place_breaker()
	var soft := Tuning.HALLS_SOFT_WALLS + (Tuning.CYCLE2_EXTRA_SOFT_WALLS if data.cycle > 1 else 0)
	PopulateOps.soft_walls(self, soft, data.first_run and data.depth == 1, LevelGrid.F_EXIT_ROOM)
	_place_lockers()
	PopulateOps.lock_pickups(self)
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool)
	_place_props()
	var height := float(Tuning.STRATUM_CEILING_HEIGHT[&"halls"])
	for room in grid.room_list:
		FixtureOps.room_fixtures(self, room, height, &"tube")
	FixtureOps.corridor_fixtures(self, Tuning.HALLS_FIXTURE_SPACING_CELLS, Tuning.HALLS_GROUP_MAX_FIXTURES, height, &"tube")
	PopulateOps.error_spawns(self)


func _place_breaker() -> void:
	var slots := wall_slots(breaker_room)
	if slots.is_empty():
		# Every cell holds an opening: any closed edge will do.
		for e in breaker_room.perimeter_edges():
			if not grid.wall_walkable(grid.wall(Vector2i(e.x, e.y), e.z)):
				slots.append(e)
	if slots.is_empty():
		return
	# Prefer a wall with nothing walkable behind it (the box reads as mounted, not a door).
	var pick := slots[0]
	for e in slots:
		if not grid.is_walkable(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]):
			pick = e
			break
	var c := Vector2i(pick.x, pick.y)
	data.breaker_cell = c
	data.add_placement(LevelData.P_BREAKER, c, wall_offset(pick.z, BREAKER_INSET), LevelData.yaw_facing(LevelGrid.opposite(pick.z)),
		{&"variant": data.lock_variant, &"dir": pick.z})


## Hide spots (07 §5.1): lockers in the closets, two in all (both in one closet when only
## one was cut).
func _place_lockers() -> void:
	data.expected_hide_spots = Tuning.HALLS_HIDE_SPOTS
	if closets.is_empty():
		return
	for i in Tuning.HALLS_HIDE_SPOTS:
		var closet := closets[i % closets.size()]
		var slots := wall_slots(closet)
		var k := i / closets.size()
		if k >= slots.size():
			continue
		var e := slots[k]
		var c := Vector2i(e.x, e.y)
		grid.add_flag(c, LevelGrid.F_HIDE_SPOT_HOST)
		data.add_placement(LevelData.P_HIDE_SPOT, c, wall_offset(e.z, LOCKER_INSET), LevelData.yaw_facing(LevelGrid.opposite(e.z)),
			{&"kind": &"locker", &"dir": e.z, &"view_yaw_limit": Tuning.HIDE_LOCKER_YAW_LIMIT})


## Props (07 §5.1): 0 to 2 per generic room against its walls; one payphone on a corridor wall.
func _place_props() -> void:
	var used: Dictionary = occupied.duplicate()
	var kinds: Array[StringName] = PROPS
	for room in grid.room_list:
		if room.kind != RoomData.GENERIC:
			continue
		var slots := wall_slots(room)
		RoomOps.shuffle(slots, rng_props)
		var want := rng_props.randi_range(0, Tuning.HALLS_ROOM_PROPS_MAX)
		for e in slots:
			if want <= 0:
				break
			var c := Vector2i(e.x, e.y)
			if used.has(grid.idx(c)):
				continue
			used[grid.idx(c)] = true
			want -= 1
			_add_prop(kinds[rng_props.randi_range(0, kinds.size() - 1)], c, e.z)
	var walls: Array[Vector3i] = []
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.FLOOR or used.has(i):
			continue
		var c := grid.cell_at(i)
		for d in 4:
			if grid.wall(c, d) == LevelGrid.WALL and not grid.is_walkable(c + LevelGrid.DIRS[d]):
				walls.append(Vector3i(c.x, c.y, d))
	for k in mini(Tuning.HALLS_PAYPHONES_PER_LEVEL, walls.size()):
		var e := walls[rng_props.randi_range(0, walls.size() - 1)]
		_add_prop(&"payphone", Vector2i(e.x, e.y), e.z)


func _add_prop(prop: StringName, c: Vector2i, dir: int) -> void:
	data.add_placement(LevelData.P_PROP, c, wall_offset(dir, PROP_INSET), LevelData.yaw_facing(LevelGrid.opposite(dir)),
		{&"prop": prop, &"dir": dir})
