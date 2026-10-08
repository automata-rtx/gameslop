class_name PoolPumps
extends RefCounted
## The Pools grammar's pump rooms (07 §5.2): 1 to 2 rooms of 2x2 with a DOOR, cut into void
## beside a corridor (or, failing that, beside a hall's level floor), each the host of a
## pump-corner hide spot (09 §6, a marker until M2.8); one is the breaker room when the
## lock is Powered.

const BREAKER_INSET := 0.05

var gen: PoolsGenerator
## Door edge -> the pump rect it was found for (_pump_door).
var _pump_rects: Dictionary = {}


func _init(generator: PoolsGenerator) -> void:
	gen = generator


## Pump rooms (07 §5.2): 2x2 with a DOOR, cut into void beside a corridor (the door opens
## onto it) or, failing that, beside a hall's floor ring (the door opens into the hall).
func insert(count: int) -> void:
	gen.pump_target = count
	var sz := Tuning.POOLS_PUMP_ROOM_SIZE
	for k in count:
		_pump_rects.clear()
		var by_corridor: Array[Vector3i] = []
		var by_hall: Array[Vector3i] = []
		for z in range(0, gen.grid.size.y - sz.y + 1):
			for x in range(0, gen.grid.size.x - sz.x + 1):
				var rect := Rect2i(x, z, sz.x, sz.y)
				var door := _pump_door(rect)
				if door.x < 0:
					continue
				var o := Vector2i(door.x, door.y) + LevelGrid.DIRS[door.z]
				(by_corridor if gen.grid.kind(o) == LevelGrid.FLOOR else by_hall).append(door)
		var pool := by_corridor if not by_corridor.is_empty() else by_hall
		if pool.is_empty():
			return
		var pick := pool[gen.rng_layout.randi_range(0, pool.size() - 1)]
		var at := Vector2i(pick.x, pick.y)
		var rect := _pump_rect_of(pick)
		var room := RoomOps.add_room(gen.grid, rect, PoolsGenerator.PUMP)
		gen.grid.set_wall(at, pick.z, LevelGrid.DOOR)
		room.doors.append(pick)
		gen.pumps.append(room)


## The door edge of a free 2x2 void rect beside a corridor or a hall's level floor (in that
## order), as Vector3i(x, z, dir) on the room side; (-1, -1, -1) when the rect is not free.
func _pump_door(rect: Rect2i) -> Vector3i:
	for c in RoomData.new(rect).cells():
		if gen.grid.kind(c) != LevelGrid.VOID or gen.grid.room_id[gen.grid.idx(c)] >= 0:
			return Vector3i(-1, -1, -1)
	var best := Vector3i(-1, -1, -1)
	for e in RoomData.new(rect).perimeter_edges():
		var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
		if not gen.grid.in_bounds(o) or gen.grid.room_id[gen.grid.idx(o)] == gen.spawn_room.id:
			continue
		if gen.grid.kind(o) == LevelGrid.FLOOR and gen.corridor.has(gen.grid.idx(o)):
			_pump_rects[e] = rect
			return e
		var r := gen.grid.room_of(o)
		if best.x < 0 and gen.grid.kind(o) == LevelGrid.ROOM and r != null and r.kind != PoolsGenerator.PUMP and is_zero_approx(gen.grid.floor_y(o)):
			best = e
	if best.x >= 0:
		_pump_rects[best] = rect
	return best


func _pump_rect_of(door: Vector3i) -> Rect2i:
	return _pump_rects[door]


static func place_breaker(gen: PoolsGenerator, room: RoomData) -> void:
	var slots := gen.wall_slots(room)
	if slots.is_empty():
		return
	var pick := slots[0]
	for e in slots:
		if not gen.grid.is_walkable(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]):
			pick = e
			break
	gen.data.breaker_cell = Vector2i(pick.x, pick.y)
	gen.data.add_placement(LevelData.P_BREAKER, gen.data.breaker_cell, StratumGenerator.wall_offset(pick.z, BREAKER_INSET),
		LevelData.yaw_facing(LevelGrid.opposite(pick.z)), {&"variant": gen.data.lock_variant, &"dir": pick.z})


## 09 §6 pump room corner: one per pump room, in the corner cell farthest from its door,
## facing the door (the player watches through the door's window). A marker until the hide
## spot interactable exists (M2.8).
static func place_hide_spots(gen: PoolsGenerator) -> void:
	gen.data.expected_hide_spots = gen.pump_target
	for room in gen.pumps:
		var door := Vector2i(room.doors[0].x, room.doors[0].y) if not room.doors.is_empty() else room.rect.position
		var best := room.rect.position
		for c in room.cells():
			if (c - door).length_squared() > (best - door).length_squared():
				best = c
		gen.grid.add_flag(best, LevelGrid.F_HIDE_SPOT_HOST)
		var to_door := Vector2(door - best)
		var face := LevelGrid.E if absf(to_door.x) >= absf(to_door.y) and to_door.x > 0 else \
			(LevelGrid.W if absf(to_door.x) >= absf(to_door.y) else (LevelGrid.S if to_door.y > 0 else LevelGrid.N))
		gen.occupied[gen.grid.idx(best)] = true
		gen.data.add_placement(LevelData.P_HIDE_SPOT, best, Vector3.ZERO, LevelData.yaw_facing(face),
			{&"kind": &"pump_corner", &"dir": face, &"view_yaw_limit": Tuning.HIDE_YAW_LIMIT_DEFAULT})
