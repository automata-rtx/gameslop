class_name LightSelector
extends RefCounted
## Which fixtures get the pool's lights (02 §6), as data: fixture positions in, the
## nearest-first indices out. With a grid, "nearest" is walking distance, and only fixtures
## in grid view of the player's cell or of a cell one step away count: pooled lights are
## unshadowed, so a light lent to a fixture behind a wall (a parallel corridor 2 m away)
## would light the player's side of every wall through it and flatten the image.
## Without a grid, or while the player is inside a wall, it is plain straight-line nearest.
## Walking distance and sight are cached per player cell (fixtures do not move).

var grid: LevelGrid
var _pos: PackedVector3Array = PackedVector3Array()
var _cell: PackedInt32Array = PackedInt32Array()
var _field_cell: int = -1
var _field: PackedInt32Array = PackedInt32Array()
## Player cell index -> PackedByteArray per fixture: 0 untested, 1 in view, 2 not.
var _sight: Dictionary = {}


func _init(level_grid: LevelGrid = null) -> void:
	grid = level_grid


func add(pos: Vector3) -> int:
	_pos.append(pos)
	var c := grid.cell_of(pos) if grid != null else Vector2i(-1, -1)
	_cell.append(grid.idx(c) if grid != null and grid.in_bounds(c) else -1)
	_sight.clear()
	return _pos.size() - 1


func count() -> int:
	return _pos.size()


func position(i: int) -> Vector3:
	return _pos[i]


## Up to `n` fixture indices among those with eligible[i] != 0, nearest first. At most
## n * LIGHT_POOL_SIGHT_CANDIDATES candidates are sight-tested per call.
func select(from: Vector3, eligible: PackedByteArray, n: int) -> PackedInt32Array:
	var pc := grid.cell_of(from) if grid != null else Vector2i(-1, -1)
	var use_grid := grid != null and grid.is_walkable(pc)
	var pi := grid.idx(pc) if use_grid else -1
	if use_grid and pi != _field_cell:
		_field_cell = pi
		_field = grid.distance_field(pc)
	# Vector2(rank, index): Array.sort() orders these natively (no script comparator).
	var keys: Array[Vector2] = []
	for i in _pos.size():
		if eligible[i] == 0:
			continue
		var straight := _pos[i].distance_to(from)
		var rank := straight
		if use_grid:
			var walk := _field[_cell[i]] if _cell[i] >= 0 else -1
			# One cell of walking counts a cell size; straight distance breaks ties.
			rank = walk * Tuning.GRID_CELL_SIZE + straight * 0.01 if walk >= 0 else 1.0e6 + straight
		keys.append(Vector2(rank, i))
	keys.sort()
	var out := PackedInt32Array()
	if not use_grid:
		for k in mini(n, keys.size()):
			out.append(int(keys[k].y))
		return out
	var eyes := PackedInt32Array([pi])
	for d in 4:
		if grid.can_step(pc, d):
			eyes.append(grid.idx(pc + LevelGrid.DIRS[d]))
	var budget := n * Tuning.LIGHT_POOL_SIGHT_CANDIDATES
	for key in keys:
		if out.size() >= n or budget <= 0:
			break
		budget -= 1
		var i := int(key.y)
		for e in eyes:
			if _visible_from(e, i):
				out.append(i)
				break
	return out


## Sight from the centre of cell index `ci` to fixture `i`, traced once and cached.
func _visible_from(ci: int, i: int) -> bool:
	var row: PackedByteArray
	if _sight.has(ci):
		row = _sight[ci]
	else:
		row = PackedByteArray()
		row.resize(_pos.size())
	if row[i] == 0:
		row[i] = 1 if SightOps.clear(grid, grid.world_of(grid.cell_at(ci)), _pos[i]) else 2
		_sight[ci] = row  # packed arrays copy on write; store the updated row
	return row[i] == 1
