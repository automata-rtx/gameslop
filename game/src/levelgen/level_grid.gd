class_name LevelGrid
extends RefCounted
## The level as pure data (07 §2): 2 m cells, walls on cell edges, per-cell kind, room id,
## floor height, deck and flags. No nodes; safe to build and read on a worker thread.
## Coordinates: cell (x, z) is centred on world (x * 2, floor_y, z * 2) and spans +-1 m.
## Directions: N = -z, E = +x, S = +z, W = -x. Every edge is stored on both cells that share
## it; `set_wall` keeps the two copies equal (the symmetry invariant the tests check).

# Cell kinds (07 §2).
const VOID := 0
const FLOOR := 1
const ROOM := 2
const RAMP := 3
const BASIN := 4
const RACK := 5

# Wall types, in the order of Tuning.GRID_WALL_TYPES.
const NONE := 0
const WALL := 1
const SOLID := 2
const SOFT := 3
const PARTITION := 4
const DOOR := 5
const GLASS := 6

# Directions.
const N := 0
const E := 1
const S := 2
const W := 3
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES: Array[String] = ["N", "E", "S", "W"]

# Cell flags (07 §2).
const F_WATER := 1
const F_UNFINISHED := 2
const F_NO_SPAWN := 4
const F_CRITICAL_PATH := 8
const F_EXIT_ROOM := 16
const F_SPAWN_ROOM := 32
const F_LOCK_ROOM := 64
const F_HIDE_SPOT_HOST := 128
const F_DEAD_END := 256

var size: Vector2i = Vector2i.ZERO
var cells: PackedByteArray = PackedByteArray()
var room_id: PackedInt32Array = PackedInt32Array()
var floor_heights: PackedFloat32Array = PackedFloat32Array()
var walls: PackedByteArray = PackedByteArray()
var deck: PackedByteArray = PackedByteArray()
var flags: PackedInt32Array = PackedInt32Array()
var room_list: Array[RoomData] = []
## Fixture group id -> Array[Vector2i] of fixture cells (filled by decorate).
var groups: Dictionary = {}
## Runtime state (main thread, not part of the generated data or its hash): DOOR edges whose
## leaf is closed, keyed by edge_key. A closed door blocks sight (SightOps, 09 §5).
var closed_doors: Dictionary = {}
## Bumped on every door change so sight caches know to drop their rows.
var door_version: int = 0


func _init(grid_size: Vector2i = Vector2i(1, 1)) -> void:
	size = grid_size
	var n := size.x * size.y
	cells.resize(n)
	room_id.resize(n)
	room_id.fill(-1)
	floor_heights.resize(n)
	walls.resize(n * 4)
	walls.fill(WALL)
	deck.resize(n)
	flags.resize(n)
	for x in size.x:
		set_wall(Vector2i(x, 0), N, SOLID)
		set_wall(Vector2i(x, size.y - 1), S, SOLID)
	for z in size.y:
		set_wall(Vector2i(0, z), W, SOLID)
		set_wall(Vector2i(size.x - 1, z), E, SOLID)


# ------------------------------------------------------------------ indexing

func cell_count() -> int:
	return size.x * size.y

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func idx(c: Vector2i) -> int:
	return c.y * size.x + c.x

func cell_at(i: int) -> Vector2i:
	return Vector2i(i % size.x, i / size.x)

static func opposite(dir: int) -> int:
	return (dir + 2) % 4


# ------------------------------------------------------------------ cells

func kind(c: Vector2i) -> int:
	return cells[idx(c)] if in_bounds(c) else VOID

func set_kind(c: Vector2i, k: int) -> void:
	cells[idx(c)] = k

static func kind_walkable(k: int) -> bool:
	return k == FLOOR or k == ROOM or k == RAMP or k == BASIN

func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and kind_walkable(cells[idx(c)])

func walkable_count() -> int:
	var n := 0
	for k in cells:
		if kind_walkable(k):
			n += 1
	return n

func floor_y(c: Vector2i) -> float:
	return floor_heights[idx(c)] if in_bounds(c) else 0.0

func has_flag(c: Vector2i, f: int) -> bool:
	return in_bounds(c) and (flags[idx(c)] & f) != 0

func add_flag(c: Vector2i, f: int) -> void:
	flags[idx(c)] |= f

func clear_flag(c: Vector2i, f: int) -> void:
	flags[idx(c)] &= ~f


# ------------------------------------------------------------------ walls

func wall(c: Vector2i, dir: int) -> int:
	return walls[idx(c) * 4 + dir] if in_bounds(c) else SOLID

## Sets an edge on both cells that share it. Edges on the grid border stay SOLID.
func set_wall(c: Vector2i, dir: int, type: int) -> void:
	var o := c + DIRS[dir]
	if not in_bounds(o):
		walls[idx(c) * 4 + dir] = SOLID
		return
	walls[idx(c) * 4 + dir] = type
	walls[idx(o) * 4 + opposite(dir)] = type

## Edge key independent of which side names it (E or S form).
static func edge_key(c: Vector2i, dir: int) -> Vector3i:
	if dir == N or dir == W:
		return Vector3i(c.x + DIRS[dir].x, c.y + DIRS[dir].y, opposite(dir))
	return Vector3i(c.x, c.y, dir)

## Records a door leaf's state on its edge (Door calls this; runtime only).
func set_door_closed(c: Vector2i, dir: int, closed: bool) -> void:
	var k := edge_key(c, dir)
	if closed == closed_doors.has(k):
		return
	if closed:
		closed_doors[k] = true
	else:
		closed_doors.erase(k)
	door_version += 1

func is_door_closed(c: Vector2i, dir: int) -> bool:
	return closed_doors.has(edge_key(c, dir))

static func wall_walkable(type: int) -> bool:
	return type == NONE or type == DOOR

## 07 §7: SOLID and GLASS refuse noclip; WALL, PARTITION, DOOR (closed) and SOFT are
## candidates (the shape cast then decides NO SPACE). NONE is not a wall at all.
static func wall_noclip_candidate(type: int) -> bool:
	return type == WALL or type == PARTITION or type == DOOR or type == SOFT

func noclip_candidate(c: Vector2i, dir: int) -> bool:
	return wall_noclip_candidate(wall(c, dir))

## 07 §7: floor drops are valid on FLOOR, ROOM and BASIN cells (never on the final depth,
## which the caller knows).
func floor_drop_valid(c: Vector2i) -> bool:
	var k := kind(c)
	return k == FLOOR or k == ROOM or k == BASIN

## True when a walker can step from c to its neighbour in dir.
func can_step(c: Vector2i, dir: int) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return false
	return (open_mask(c.y * size.x + c.x) & (1 << dir)) != 0

## Bit d set when a walker can step from cell index i in direction d. Hot path of every
## maze op: index arithmetic only (border edges are SOLID, so open edges stay in range).
func open_mask(i: int) -> int:
	var k := cells[i]
	if k == VOID or k == RACK:
		return 0
	var m := 0
	var base := i * 4
	var w := walls[base]
	if (w == NONE or w == DOOR) and _walkable_i(i - size.x):
		m |= 1
	w = walls[base + 1]
	if (w == NONE or w == DOOR) and _walkable_i(i + 1):
		m |= 2
	w = walls[base + 2]
	if (w == NONE or w == DOOR) and _walkable_i(i + size.x):
		m |= 4
	w = walls[base + 3]
	if (w == NONE or w == DOOR) and _walkable_i(i - 1):
		m |= 8
	return m

func _walkable_i(j: int) -> bool:
	var k := cells[j]
	return k != VOID and k != RACK

## Number of walkable neighbours reachable in one step.
func openings(c: Vector2i) -> int:
	return openings_i(idx(c)) if in_bounds(c) else 0

func openings_i(i: int) -> int:
	var m := open_mask(i)
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)

## After carving: border edges SOLID, walkable/void edges WALL, void/void edges NONE.
func finalize_walls() -> void:
	var w := size.x
	for i in cell_count():
		var wa := _walkable_i(i)
		# East edge (i, i + 1) and south edge (i, i + w), each stored on both cells.
		if i % w < w - 1:
			_finalize_edge(i, i + 1, 1, 3, wa, _walkable_i(i + 1))
		if i + w < cells.size():
			_finalize_edge(i, i + w, 2, 0, wa, _walkable_i(i + w))

func _finalize_edge(i: int, j: int, d: int, back: int, wa: bool, wb: bool) -> void:
	var t := walls[i * 4 + d]
	if wa != wb and t == NONE:
		t = WALL
	elif not wa and not wb:
		t = NONE
	walls[i * 4 + d] = t
	walls[j * 4 + back] = t


# ------------------------------------------------------------------ world space

func world_of(c: Vector2i) -> Vector3:
	return Vector3(c.x * Tuning.GRID_CELL_SIZE, floor_y(c), c.y * Tuning.GRID_CELL_SIZE)

func cell_of(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / Tuning.GRID_CELL_SIZE), roundi(world_pos.z / Tuning.GRID_CELL_SIZE))


# ------------------------------------------------------------------ queries (07 Interfaces)

## BFS walking distance in cells from `from` (-1: unreachable). Respects walls and doors.
func distance_field(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(cell_count())
	dist.fill(-1)
	if not is_walkable(from):
		return dist
	var queue := PackedInt32Array([idx(from)])
	dist[idx(from)] = 0
	var head := 0
	var w := size.x
	while head < queue.size():
		var i := queue[head]
		head += 1
		var base := i * 4
		var next_d := dist[i] + 1
		# Inlined neighbours: N, E, S, W.
		if walls[base] == NONE or walls[base] == DOOR:
			_visit(i - w, next_d, dist, queue)
		if walls[base + 1] == NONE or walls[base + 1] == DOOR:
			_visit(i + 1, next_d, dist, queue)
		if walls[base + 2] == NONE or walls[base + 2] == DOOR:
			_visit(i + w, next_d, dist, queue)
		if walls[base + 3] == NONE or walls[base + 3] == DOOR:
			_visit(i - 1, next_d, dist, queue)
	return dist

func _visit(j: int, d: int, dist: PackedInt32Array, queue: PackedInt32Array) -> void:
	# Border edges are SOLID, so j is always in range when the wall is open.
	if dist[j] == -1 and kind_walkable(cells[j]):
		dist[j] = d
		queue.append(j)

## A uniformly chosen walkable cell passing `filter` (Callable(Vector2i) -> bool), or (-1, -1).
func random_walkable_cell(rng: RandomNumberGenerator, filter: Callable = Callable()) -> Vector2i:
	var pool: Array[Vector2i] = []
	for i in cell_count():
		if kind_walkable(cells[i]):
			var c := cell_at(i)
			if not filter.is_valid() or filter.call(c):
				pool.append(c)
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[rng.randi_range(0, pool.size() - 1)]

func rooms() -> Array[RoomData]:
	return room_list

func fixture_groups() -> Dictionary:
	return groups

func room_of(c: Vector2i) -> RoomData:
	var r := room_id[idx(c)] if in_bounds(c) else -1
	return room_list[r] if r >= 0 else null


# ------------------------------------------------------------------ serialisation

## Byte image of everything that defines the grid, for determinism hashing.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(var_to_bytes(size))
	out.append_array(cells)
	out.append_array(room_id.to_byte_array())
	out.append_array(floor_heights.to_byte_array())
	out.append_array(walls)
	out.append_array(deck)
	out.append_array(flags.to_byte_array())
	for r in room_list:
		out.append_array(var_to_bytes([r.id, r.rect, r.kind, r.fixture_group, r.doors]))
	out.append_array(var_to_bytes(groups))
	return out
