class_name OfficeFurnish
extends RefCounted
## Offices furniture and light (07 §5.4, 09 §6, §7, 02 §7), for OfficesGenerator.decorate:
## desks with monitors in 60% of the cubicle cells, each desk a hide spot host (under_desk,
## a marker until M2.8); lockers in the closets; chairs only in corridors (Poisson, 3 cells
## apart, random facing); water coolers at corridor junctions; filing cabinets in small
## offices; troffers every 2 cells in corridors and open offices, one per small office, and
## 40% of the fixture groups dark (60% in Cycle 2) so the floor has unlit regions until the
## breaker is thrown.

## Desk footprint (m): 1.4 wide along its wall, 0.6 deep, 0.74 high (prefab desk.tscn): a
## cubicle cell keeps a lane wide enough for the 0.4 m navigation agent beside it.
const DESK_DEPTH := 0.6
const DESK_HEIGHT := 0.74
## The monitor stands this far off the desk's wall.
const MONITOR_INSET := 0.2
const LOCKER_INSET := 0.3
const CHAIR_INSET := 0.3
const COOLER_INSET := 0.25
const CABINET_INSET := 0.3
## Filing cabinets per small office: 0 to this many.
const CABINETS_MAX := 2
## Fixture groups that never start dark: the spawn lobby's (the player arrives in light).

var gen: OfficesGenerator
var grid: LevelGrid
var data: LevelData
var rng: RandomNumberGenerator
var _used: Dictionary = {}


func _init(g: OfficesGenerator) -> void:
	gen = g
	grid = g.grid
	data = g.data
	rng = g.rng_props


## 07 §5.4: desk + monitor in 60% of the cubicle cells, against a partition (or the
## office's wall), each a hide spot host. Cells holding an opening out of the office stay
## clear. Desk cells are kept free of pickups.
func desks() -> void:
	var hosts := 0
	for room in gen.open_rooms:
		var cells: Array[Vector2i] = []
		for c in room.cells():
			if _opens_out(room, c):
				continue
			cells.append(c)
		RoomOps.shuffle(cells, rng)
		var want := roundi(room.rect.get_area() * Tuning.OFFICES_DESK_FRACTION)
		for c in cells:
			if want <= 0:
				break
			var d := _desk_edge(c)
			if d < 0:
				continue
			want -= 1
			hosts += 1
			_desk(c, d)
	data.expected_hide_spots = hosts + Tuning.OFFICES_LOCKERS


func _opens_out(room: RoomData, c: Vector2i) -> bool:
	for d in 4:
		if not room.rect.has_point(c + LevelGrid.DIRS[d]) and grid.can_step(c, d):
			return true
	return false


## A closed edge for the desk's back: a partition first, else a plain wall (never a soft
## wall, a door or glass).
func _desk_edge(c: Vector2i) -> int:
	var walls: Array[int] = []
	var parts: Array[int] = []
	for d in 4:
		match grid.wall(c, d):
			LevelGrid.PARTITION:
				parts.append(d)
			LevelGrid.WALL, LevelGrid.SOLID:
				walls.append(d)
	var pool := parts if not parts.is_empty() else walls
	if pool.is_empty():
		return -1
	return pool[rng.randi_range(0, pool.size() - 1)]


func _desk(c: Vector2i, d: int) -> void:
	var yaw := LevelData.yaw_facing(LevelGrid.opposite(d))
	var at := StratumGenerator.wall_offset(d, DESK_DEPTH * 0.5)
	data.add_placement(LevelData.P_PROP, c, at, yaw, {&"prop": &"desk", &"dir": d})
	data.add_placement(LevelData.P_PROP, c, StratumGenerator.wall_offset(d, MONITOR_INSET) + Vector3(0.0, DESK_HEIGHT, 0.0), yaw,
		{&"prop": &"monitor", &"dir": d})
	grid.add_flag(c, LevelGrid.F_HIDE_SPOT_HOST)
	data.add_placement(LevelData.P_HIDE_SPOT, c, at, yaw,
		{&"kind": &"under_desk", &"dir": d, &"view_yaw_limit": Tuning.HIDE_YAW_LIMIT_DEFAULT})
	gen.occupied[grid.idx(c)] = true
	_used[grid.idx(c)] = true


## Lockers (09 §6) in the closets, OFFICES_LOCKERS in all.
func lockers() -> void:
	if gen.closets.is_empty():
		return
	for i in Tuning.OFFICES_LOCKERS:
		var closet := gen.closets[i % gen.closets.size()]
		var slots := gen.wall_slots(closet)
		var k := i / gen.closets.size()
		if k >= slots.size():
			continue
		var e := slots[k]
		var c := Vector2i(e.x, e.y)
		grid.add_flag(c, LevelGrid.F_HIDE_SPOT_HOST)
		data.add_placement(LevelData.P_HIDE_SPOT, c, StratumGenerator.wall_offset(e.z, LOCKER_INSET),
			LevelData.yaw_facing(LevelGrid.opposite(e.z)),
			{&"kind": &"locker", &"dir": e.z, &"view_yaw_limit": Tuning.HIDE_LOCKER_YAW_LIMIT})


## Chairs (corridors only), water coolers (junctions), filing cabinets (small offices).
func props() -> void:
	_chairs()
	_coolers()
	for room in gen.small_rooms:
		var slots := gen.wall_slots(room)
		RoomOps.shuffle(slots, rng)
		var want := rng.randi_range(0, CABINETS_MAX)
		for e in slots:
			if want <= 0:
				break
			var c := Vector2i(e.x, e.y)
			if _used.has(grid.idx(c)) or gen.occupied.has(grid.idx(c)) or grid.wall(c, e.z) == LevelGrid.SOFT:
				continue
			_used[grid.idx(c)] = true
			want -= 1
			data.add_placement(LevelData.P_PROP, c, StratumGenerator.wall_offset(e.z, CABINET_INSET),
				LevelData.yaw_facing(LevelGrid.opposite(e.z)), {&"prop": &"filing_cabinet", &"dir": e.z})


## 07 §5.4: chairs only in corridors, Poisson 3 cells apart, random facing, pushed to one
## side of a straight run (never in a junction or before an opening, so they never close a
## corridor). One per OFFICES_CHAIR_CORRIDOR_CELLS corridor cells.
func _chairs() -> void:
	var cells: Array[Vector2i] = []
	for i in grid.cell_count():
		if not gen.corridor.has(i) or grid.cells[i] != LevelGrid.FLOOR:
			continue
		var m := grid.open_mask(i)
		if m != 5 and m != 10:
			continue
		var c := grid.cell_at(i)
		var side_open := false
		for d in 4:
			if (m & (1 << d)) == 0 and grid.wall(c, d) != LevelGrid.WALL and grid.wall(c, d) != LevelGrid.SOLID:
				side_open = true
		if not side_open:
			cells.append(c)
	var want := gen.corridor.size() / Tuning.OFFICES_CHAIR_CORRIDOR_CELLS
	for c in PlaceOps.poisson_cells(cells, want, Tuning.OFFICES_CHAIR_MIN_SPACING_CELLS, rng):
		var m := grid.open_mask(grid.idx(c))
		var k := rng.randi_range(0, 1)
		var d := (LevelGrid.N if k == 0 else LevelGrid.S) if m == 10 else (LevelGrid.E if k == 0 else LevelGrid.W)
		_used[grid.idx(c)] = true
		data.add_placement(LevelData.P_PROP, c, StratumGenerator.wall_offset(d, CHAIR_INSET), rng.randf() * TAU,
			{&"prop": &"chair", &"dir": -1})


## Water coolers at corridor junctions, against the junction's closed edge.
func _coolers() -> void:
	for i in grid.cell_count():
		if not gen.corridor.has(i) or grid.openings_i(i) != 3:
			continue
		var c := grid.cell_at(i)
		for d in 4:
			var t := grid.wall(c, d)
			if t == LevelGrid.WALL or t == LevelGrid.SOLID:
				_used[i] = true
				data.add_placement(LevelData.P_PROP, c, StratumGenerator.wall_offset(d, COOLER_INSET),
					LevelData.yaw_facing(LevelGrid.opposite(d)), {&"prop": &"water_cooler", &"dir": d})
				break


# ---------------------------------------------------------------- light

## 07 §5.4 fixtures, then the dark groups.
func fixtures() -> void:
	var height := float(Tuning.STRATUM_CEILING_HEIGHT[&"offices"])
	var kind := &"troffer"
	FixtureOps.corridor_fixtures(gen, Tuning.OFFICES_FIXTURE_SPACING_CELLS, Tuning.OFFICES_GROUP_MAX_FIXTURES, height, kind)
	for room in grid.room_list:
		match room.kind:
			OfficeRooms.OPEN:
				FixtureOps.lattice_fixtures(gen, room, Tuning.OFFICES_FIXTURE_SPACING_CELLS, height, kind)
			OfficeRooms.SMALL:
				FixtureOps.single_fixture(gen, room, height, kind)
			_:
				FixtureOps.room_fixtures(gen, room, height, kind)
	dark_groups(Tuning.CYCLE2_OFFICES_DARK_FRACTION if data.cycle > 1 else Tuning.OFFICES_DARK_GROUP_FRACTION)


## 07 §5.4: `fraction` of the fixture groups start unpowered, whole groups at a time (the
## Still/Flicker light dilemma needs dark regions, not dark fixtures). The spawn lobby's
## group stays lit. Fixture placements of a dark group carry params.dark = true.
func dark_groups(fraction: float) -> void:
	var ids: Array[int] = []
	for id: int in grid.groups:
		if id != gen.spawn_room.fixture_group:
			ids.append(id)
	ids.sort()
	RoomOps.shuffle(ids, gen.rng_fixtures)
	var dark: Dictionary = {}
	for k in roundi((ids.size() + 1) * fraction):
		if k < ids.size():
			dark[ids[k]] = true
	for p in data.placements:
		if p[&"kind"] == LevelData.P_FIXTURE and dark.has(int(p[&"params"][&"group"])):
			p[&"params"][&"dark"] = true
