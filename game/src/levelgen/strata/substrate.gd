class_name SubstrateGenerator
extends StratumGenerator
## Substrate grammar (07 §5.6): the Halls grammar at 28x28 (even Cycles: every second room an
## Offices cubicle module, `office_modules`), then unfinished (SubstrateUnfinish):
## 20% of the corridor cells removed in clusters and the fewest of them restored to keep the
## level whole, dead ends cut to 4 cells, a quarter of the rooms floating +-0.25 m, 30% of
## the surfaces left as the placeholder checker, whole rooms or corridor segments. Every edge
## between walkable space and VOID is SOLID: the drawing's boundary, drawn as the brighter
## grid. No fixtures: 6 to 10 studio lights at least 6 cells apart, one in the spawn room and
## one in the pocket. The exit room is the Threshold's pocket (3x3, lit): the threshold_door
## stands alone at its centre facing the way in. No lock, no hide spots, no doors; 6 soft
## walls; the floor is solid (no drops) in a Descent. Null spawns on the critical path at
## 55% (at least 20 m from the spawn), two Statics off the path (Cycle 2: three).

const STUDIO_LIGHT := &"studio_light"
const THRESHOLD_DOOR := &"threshold_door"
## The studio light's pole stands this far from its cell's centre on both axes (m), in the
## corner away from the room's middle, its head at STUDIO_LIGHT_HEAD (m) above the floor (the
## lent light hangs there: drop 0). R13: the pole's 0.12 m collider then keeps the cell's
## cross clear (LEVEL_PROP_CLEARANCE 0.4 + 0.12, 2 cm to spare), and the tripod's feet (0.42 m) stay
## off the walls with one leg pointing into the corner.
const STUDIO_LIGHT_HEAD := 2.1
const STUDIO_LIGHT_CORNER := 0.54
## Weights of the studio light draw: rooms and finished cells (02 §7 "marking the finished
## pockets").
const LIGHT_WEIGHT_ROOM := 2.0
const LIGHT_WEIGHT_FINISHED := 2.0
## The Halls layout grows by this factor so the walkable count lands on the depth's target
## after the unfinish step (07 §2: 360 at depth 6).
const HALLS_WALKABLE_SCALE := 1.3
## Cells inside the 140..220 m band the Halls layout aims the pocket at (low, high): the
## unfinish step keeps that walk, but dead-end repairs can shorten it.
const HALLS_EXIT_BAND_INSET := Vector2(14.0, 4.0)

var spawn_room: RoomData = null
var pocket: RoomData = null
## Cells the spawn room and the pocket open onto: never removed.
var keep: Dictionary = {}


## 07 §5.6 "Cycle 2: Offices grammar alternates" (M2.3 reading, CHANGELOG): on even Cycles
## the Halls maze's generic rooms alternate with Offices modules, every second one a cubicle
## maze of PARTITION edges (OfficeRooms.cubicles). An Offices ring at 30x30 cannot hold the
## 140 m walk 07 forces, so the maze stays Halls and the modules alternate (02 §7 "hall and
## office modules"). The simplest grammar keeps plain Halls rooms.
func office_modules() -> bool:
	return data.cycle % 2 == 0 and not simplest


func layout() -> void:
	var h := HallsGenerator.new()
	h.adopt(self)
	h.walkable_scale = HALLS_WALKABLE_SCALE
	h.closets_enabled = false
	h.exit_band_inset = HALLS_EXIT_BAND_INSET
	h.layout()
	spawn_room = h.spawn_room
	pocket = h.exit_room
	if spawn_room == null or pocket == null:
		return  # Rule 1 fails; the generator retries.
	pocket.kind = RoomData.POCKET
	_open_doors()
	if office_modules():
		_office_modules()
	_unfinish()
	# The Threshold stands at the pocket's centre (02 §7 "standing alone on a lit pocket").
	data.exit_cell = pocket.center()


## The Substrate has no door prefabs: every DOOR edge is an open gap.
func _open_doors() -> void:
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if grid.wall(c, d) == LevelGrid.DOOR:
				grid.set_wall(c, d, LevelGrid.NONE)


## Every second generic room (by id) becomes an open office: a cubicle maze, waist high.
func _office_modules() -> void:
	var o := OfficesGenerator.new()
	o.adopt(self)
	var rooms := OfficeRooms.new(o)
	var k := 0
	for r in grid.room_list:
		if r.kind != RoomData.GENERIC:
			continue
		if k % 2 == 1:
			r.kind = OfficeRooms.OPEN
			rooms.cubicles(r)
		k += 1


func _unfinish() -> void:
	keep = SubstrateUnfinish.doorway_cells(grid, [spawn_room, pocket] as Array[RoomData])
	# The base layout's walk to the pocket is kept whole: the unfinish step never lengthens
	# it past the band the layout aimed for (07 §5.6: 140 to 220 m).
	for c in PathOps.critical_path(grid, data.spawn_cell, pocket.center(), false):
		keep[grid.idx(c)] = true
	data.unfinish_base = SubstrateUnfinish.unfinish(grid, rng_layout, data.spawn_cell, keep,
		Tuning.NULL_DEAD_END_MAX_CELLS, data.unfinished_void)
	var rooms: Array[RoomData] = []
	for r in grid.room_list:
		if r != spawn_room and r != pocket:
			rooms.append(r)
	SubstrateUnfinish.offset_rooms(grid, rooms, rng_layout)
	var units := SubstrateUnfinish.units(grid, [spawn_room, pocket] as Array[RoomData])
	SubstrateUnfinish.mark_units(grid, units, Tuning.SUBSTRATE_UNFINISHED_FRACTION, rng_layout)
	MazeOps.mark_dead_ends(grid)


func decorate() -> void:
	if pocket == null or spawn_room == null or data.critical_path.is_empty():
		return  # Rule 1 fails; the generator retries.
	flag_room(spawn_room, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_NO_SPAWN)
	flag_room(pocket, LevelGrid.F_EXIT_ROOM | LevelGrid.F_NO_SPAWN)
	data.add_placement(LevelData.P_SPAWN, data.spawn_cell, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(data.spawn_dir)),
		{&"cabin_dir": data.spawn_dir})
	var facing := _door_facing()
	data.exit_dir = facing
	data.add_placement(LevelData.P_EXIT, data.exit_cell, Vector3.ZERO, LevelData.yaw_facing(facing),
		{&"exit_kind": THRESHOLD_DOOR, &"lock": data.exit_lock, &"dir": facing})
	var soft := Tuning.SUBSTRATE_SOFT_WALLS + (Tuning.CYCLE2_EXTRA_SOFT_WALLS if data.cycle > 1 else 0)
	# 07 §4: soft walls prefer dead ends; here they are the way out of one (08 §7).
	var prefer := func(e: Vector3i) -> bool:
		var a := Vector2i(e.x, e.y)
		return grid.has_flag(a, LevelGrid.F_DEAD_END) or grid.has_flag(a + LevelGrid.DIRS[e.z], LevelGrid.F_DEAD_END)
	PopulateOps.soft_walls(self, soft, false, LevelGrid.F_EXIT_ROOM, prefer)
	# A soft wall may cut its shortcut through a removed cell (PlaceOps.carve_soft_shortcut).
	var still: Array[Vector2i] = []
	for c in data.unfinished_void:
		if grid.kind(c) == LevelGrid.VOID:
			still.append(c)
	data.unfinished_void = still
	_solid_edges()
	MazeOps.mark_dead_ends(grid)
	data.expected_hide_spots = 0
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool)
	_studio_lights()
	PopulateOps.error_spawns(self)
	_error_roles()


## The door faces the pocket's way in: the side of its first opening (the critical path's
## way in when it can see it).
func _door_facing() -> int:
	var path := data.critical_path
	for k in range(path.size() - 1, 0, -1):
		if not pocket.has_cell(path[k - 1]):
			var into := path[k] - path[k - 1]
			# The door faces back towards where the path came in.
			return LevelGrid.opposite(LevelGrid.DIRS.find(into)) if into != Vector2i.ZERO else LevelGrid.S
	for e in pocket.perimeter_edges():
		if grid.can_step(Vector2i(e.x, e.y), e.z):
			return e.z
	return LevelGrid.S


## 07 §5.6: every edge between walkable space and VOID is SOLID (the drawing's boundary).
func _solid_edges() -> void:
	for i in grid.cell_count():
		if not LevelGrid.kind_walkable(grid.cells[i]):
			continue
		var c := grid.cell_at(i)
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if grid.in_bounds(o) and grid.kind(o) == LevelGrid.VOID and grid.wall(c, d) == LevelGrid.WALL:
				grid.set_wall(c, d, LevelGrid.SOLID)


## 02 §7 studio lights: 6 to 10 at least 6 cells apart, one in the spawn room and one in the
## pocket, the rest drawn over walkable cells favouring rooms and finished surfaces. Each is
## a fixture of its own group (LightPool lends it its light: white, 0.6, 15 m, unshadowed).
func _studio_lights() -> void:
	var count := rng_fixtures.randi_range(Tuning.SUBSTRATE_STUDIO_LIGHTS_MIN, Tuning.SUBSTRATE_STUDIO_LIGHTS_MAX)
	var fixed: Array[Vector2i] = [_room_corner(spawn_room, data.spawn_cell), _room_corner(pocket, data.exit_cell)]
	var cells: Array[Vector2i] = []
	var weights := PackedFloat32Array()
	for i in grid.cell_count():
		if not LevelGrid.kind_walkable(grid.cells[i]) or grid.cells[i] == LevelGrid.RAMP:
			continue
		var c := grid.cell_at(i)
		var r := grid.room_of(c)
		if r == spawn_room or r == pocket or occupied.has(i):
			continue
		cells.append(c)
		var wgt := 1.0
		if r != null:
			wgt *= LIGHT_WEIGHT_ROOM
		if not grid.has_flag(c, LevelGrid.F_UNFINISHED):
			wgt *= LIGHT_WEIGHT_FINISHED
		weights.append(wgt)
	var picks := PlaceOps.poisson_cells(cells, count - fixed.size(), Tuning.SUBSTRATE_STUDIO_LIGHT_SPACING_CELLS,
		rng_fixtures, weights, fixed)
	var all: Array[Vector2i] = fixed.duplicate()
	all.append_array(picks)
	for c in all:
		_studio_light(c)


## A corner cell of `room` off the critical path when one is (else any corner).
func _room_corner(room: RoomData, avoid: Vector2i) -> Vector2i:
	var r := room.rect
	var corners: Array[Vector2i] = [r.position, Vector2i(r.end.x - 1, r.position.y), r.end - Vector2i.ONE,
		Vector2i(r.position.x, r.end.y - 1)]
	RoomOps.shuffle(corners, rng_fixtures)
	for c in corners:
		if c != avoid and not grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			return c
	for c in corners:
		if c != avoid:
			return c
	return corners[0]


func _studio_light(c: Vector2i) -> void:
	var room := grid.room_of(c)
	# Into the cell's corner away from the room's middle (or the corridor's open side), the
	# rig turned to face the middle.
	var toward := Vector2.ZERO
	if room != null:
		toward = Vector2(room.rect.position) + Vector2(room.rect.size - Vector2i.ONE) * 0.5 - Vector2(c)
	if toward.length() < 0.01:
		toward = Vector2(LevelGrid.DIRS[_open_dir(c)])
	# Always a true corner (R13): an axis the middle does not decide goes to its closed side.
	var sx := -signf(toward.x)
	var sz := -signf(toward.y)
	if sx == 0.0:
		sx = -1.0 if grid.wall(c, LevelGrid.W) != LevelGrid.NONE and grid.wall(c, LevelGrid.E) == LevelGrid.NONE else 1.0
	if sz == 0.0:
		sz = -1.0 if grid.wall(c, LevelGrid.N) != LevelGrid.NONE and grid.wall(c, LevelGrid.S) == LevelGrid.NONE else 1.0
	var corner := Vector2(sx, sz) * STUDIO_LIGHT_CORNER
	# The rig faces the cell's middle (its -Z), the back leg into the corner.
	var yaw := atan2(corner.x, corner.y)
	var group := grid.groups.size()
	grid.groups[group] = [c] as Array[Vector2i]
	data.add_placement(LevelData.P_FIXTURE, c, Vector3(corner.x, STUDIO_LIGHT_HEAD, corner.y), yaw,
		{&"group": group, &"fixture": STUDIO_LIGHT})


func _open_dir(c: Vector2i) -> int:
	for d in 4:
		if grid.can_step(c, d):
			return d
	return LevelGrid.S


## 07 §5.6: Null's spawn on the critical path at 55% of its length, at least 20 m of walking
## from the spawn and outside the pocket; Statics on off-path spawn points.
func _error_roles() -> void:
	var path := data.critical_path
	var min_cells := ceili(Tuning.NULL_SPAWN_MIN_DIST / Tuning.GRID_CELL_SIZE)
	var k := roundi((path.size() - 1) * Tuning.NULL_SPAWN_PATH_FRACTION)
	while k < path.size() - 1 and (spawn_dist[grid.idx(path[k])] < min_cells or grid.has_flag(path[k], LevelGrid.F_NO_SPAWN)):
		k += 1
	data.null_spawn_cell = path[k]
	data.add_placement(LevelData.P_ERROR_SPAWN, path[k], Vector3.ZERO, 0.0, {&"off_path": false, &"error": &"null"})
	var statics := Tuning.SUBSTRATE_STATIC_COUNT + (Tuning.CYCLE2_EXTRA_STATIC if data.cycle > 1 else 0)
	for p in data.placements_of(LevelData.P_ERROR_SPAWN):
		if statics <= 0:
			break
		var params: Dictionary = p[&"params"]
		if params.has(&"error") or not bool(params.get(&"off_path", false)):
			continue
		params[&"error"] = &"static"
		statics -= 1
