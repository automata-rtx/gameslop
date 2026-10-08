class_name OfficesGenerator
extends StratumGenerator
## Offices grammar (07 §5.4): a 1-cell corridor ring inset 3 cells from the perimeter with
## 1 to 2 cross corridors; the interior holds 2 to 3 open offices (cubicle mazes of
## PARTITION edges, waist high, seen over) and the glass meeting room; small offices with
## doors line the band outside the ring and fill the interior's leftovers (OfficeRooms).
## The spawn lobby and the exit lobby (the elevator in the perimeter wall) stand in the band
## on opposite sides, the Landing cabin and the elevator shaft beyond the perimeter. A
## breaker room always exists (07: the player may light the floor even when the lock is not
## Powered); 40% of the fixture groups start dark (OfficeFurnish). The simplest grammar
## (07 §1 rule 5) keeps one cross corridor, two open offices and no braiding.

## Small offices are added until the walkable count reaches this fraction below the
## target, at random, so levels vary in size.
const WALKABLE_JITTER := 0.08
const BREAKER_INSET := 0.05

var ring: Rect2i = Rect2i()
## Cell index -> true for ring and cross corridor cells.
var corridor: Dictionary = {}
var spawn_room: RoomData = null
var exit_room: RoomData = null
var breaker_room: RoomData = null
var meeting_room: RoomData = null
var open_rooms: Array[RoomData] = []
var small_rooms: Array[RoomData] = []
var closets: Array[RoomData] = []
var furnish: OfficeFurnish = null
## M2.3: the Substrate runs this layout (Cycle 2) and unfinishes it; it grows the target by
## the cells the unfinish step removes.
var walkable_scale: float = 1.0


func layout() -> void:
	ring = RingOps.carve_ring(grid, Tuning.OFFICES_RING_INSET, corridor)
	var side := rng_layout.randi_range(0, 3)
	spawn_room = _lobby(side, Tuning.OFFICES_SPAWN_ROOM_SIZE, RoomData.SPAWN)
	data.spawn_dir = side
	data.spawn_cell = side_middle(spawn_room, side)
	var far := LevelGrid.opposite(side)
	exit_room = _lobby(far, Tuning.OFFICES_EXIT_ROOM_SIZE, RoomData.EXIT)
	data.exit_dir = far
	data.exit_cell = side_middle(exit_room, far)
	var rooms := OfficeRooms.new(self)
	var reserve := Tuning.OFFICES_BREAKER_ROOM_SIZE.x * Tuning.OFFICES_BREAKER_ROOM_SIZE.y + Tuning.OFFICES_CLOSETS_MAX
	var target := int(walkable_target(data.depth) * walkable_scale * (1.0 - rng_layout.randf() * WALKABLE_JITTER)) - reserve
	var sections := rooms.cross_corridors()
	rooms.interior(sections, target)
	rooms.band_pieces()
	rooms.small_offices(target)
	grid.finalize_walls()
	rooms.breaker_room()
	rooms.closets()
	grid.finalize_walls()
	MazeOps.mark_dead_ends(grid)


## A lobby room (spawn or exit) in the band on `side`, the full band deep (its outer side
## on the perimeter, where the cabin or the elevator stands), open onto the ring.
func _lobby(side: int, size: Vector2i, kind: StringName) -> RoomData:
	var n := grid.size.x
	var inset := Tuning.OFFICES_RING_INSET
	var along := RingOps.along_range(n, inset, size.x)
	var rect := RingOps.band_rect(n, inset, side, rng_layout.randi_range(along.x, along.y), size.x, mini(size.y, inset))
	var room := RoomOps.add_room(grid, rect, kind)
	RingOps.open_middle(grid, room, LevelGrid.opposite(side), LevelGrid.NONE)
	return room


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
		if data.exit_lock == Tuning.LOCK_POWERED:
			flag_room(breaker_room, LevelGrid.F_LOCK_ROOM)
		_place_breaker()
	var soft := Tuning.OFFICES_SOFT_WALLS + (Tuning.CYCLE2_EXTRA_SOFT_WALLS if data.cycle > 1 else 0)
	# 07 §5.4: between small offices and the ring where a wall there saves the walk.
	var prefer := func(e: Vector3i) -> bool:
		var a := Vector2i(e.x, e.y)
		var b := a + LevelGrid.DIRS[e.z]
		return (_is_small(a) and corridor.has(grid.idx(b))) or (_is_small(b) and corridor.has(grid.idx(a)))
	PopulateOps.soft_walls(self, soft, false, LevelGrid.F_EXIT_ROOM | LevelGrid.F_SPAWN_ROOM, prefer)
	furnish = OfficeFurnish.new(self)
	furnish.desks()
	furnish.lockers()
	PopulateOps.lock_pickups(self)
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool)
	furnish.props()
	furnish.fixtures()
	PopulateOps.error_spawns(self)


func release() -> void:
	furnish = null


func _is_small(c: Vector2i) -> bool:
	var r := grid.room_of(c)
	return r != null and r.kind == OfficeRooms.SMALL


## The breaker on the breaker room's wall with nothing walkable behind it when it can.
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
