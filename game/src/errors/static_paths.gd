class_name StaticPaths
extends RefCounted
## Grid movement helpers for Static (08 §3), split out of ErrorStatic (14 §6 400-line
## limit): the BFS cell path (doors open: it is sound), the flare list (gathered at most
## once per physics frame for every Static, and only while the group is not empty:
## get_node_count_in_group is the cheap counter), and the flare push's walkability tests.

static var _flare_cache: Array[Node3D] = []
static var _flare_frame: int = -1


## BFS cell path from `from` to `to` (both included after `from`), empty if unreachable.
## R19: over cell indices with LevelGrid.open_mask (the same steps, in the same N, E, S, W
## order, as can_step), so the path is the one the Vector2i search found; it was 2.7 to
## 4.8 ms per Static at Relief entry (three Statics re-planned in one Director tick).
static func cell_path(g: LevelGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		out.append(to)
		return out
	if not g.in_bounds(from) or not g.in_bounds(to):
		return out
	var prev := PackedInt32Array()
	prev.resize(g.cell_count())
	prev.fill(-1)
	var start := g.idx(from)
	var goal := g.idx(to)
	var w := g.size.x
	var steps := PackedInt32Array([-w, 1, w, -1])
	prev[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal:
			break
		var m := g.open_mask(i)
		if m == 0:
			continue
		for d in 4:
			if (m & (1 << d)) != 0:
				var j := i + steps[d]
				if prev[j] == -1:
					prev[j] = i
					queue.append(j)
	if prev[goal] == -1:
		return out
	var k := goal
	while k != start:
		out.append(g.cell_at(k))
		k = prev[k]
	out.reverse()
	return out


## Burning flares (group Tuning.STATIC_FLARE_GROUP) in the tree.
static func flares(tree: SceneTree) -> Array[Node3D]:
	if tree == null or tree.get_node_count_in_group(Tuning.STATIC_FLARE_GROUP) == 0:
		_flare_cache.clear()
		return _flare_cache
	var frame := Engine.get_physics_frames()
	if frame != _flare_frame:
		_flare_frame = frame
		_flare_cache.clear()
		for n in tree.get_nodes_in_group(Tuning.STATIC_FLARE_GROUP):
			var f := n as Node3D
			if f != null and f.is_inside_tree():
				_flare_cache.append(f)
	return _flare_cache


static func flare_dist(p: Vector3, flare: Node3D) -> float:
	return Vector2(p.x - flare.global_position.x, p.z - flare.global_position.z).length()


## The nearest burning flare within 6 m (XZ) of `pos`, or null.
static func nearest_flare(tree: SceneTree, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for f in flares(tree):
		var d := flare_dist(pos, f)
		if d < Tuning.STATIC_FLARE_RANGE and d < best_d:
			best_d = d
			best = f
	return best


## One flare push step of `step` m from `pos` straight away from `flare` (08 §3); returns
## the new position. A step that would leave the walkable cells (or cross a wall between
## cells) is rejected; it slides along one axis instead, else follows `escape` (filled
## here: the cell path to the nearest cell outside the flare's 6 m), so it never freezes.
static func push_step(g: LevelGrid, pos: Vector3, flare: Node3D, step: float, escape: Array[Vector3]) -> Vector3:
	if escape.is_empty():
		var off := pos - flare.global_position
		off.y = 0.0
		var away := off.normalized() if off.length() > 0.001 else Vector3.RIGHT
		for dir: Vector3 in [away, Vector3(signf(away.x), 0.0, 0.0), Vector3(0.0, 0.0, signf(away.z))]:
			if dir.length() < 0.5:
				continue
			var next := pos + dir.normalized() * step
			if walkable_step(g, pos, next) and flare_dist(next, flare) > flare_dist(pos, flare):
				return next
		escape.assign(escape_path(g, pos, flare))
		if escape.is_empty():
			return pos  # nowhere outside its reach on foot: hold until the flare burns out
	var target := escape[0]
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if to.length() <= step:
		escape.remove_at(0)
		return target
	return pos + to.normalized() * step


## True when moving from `a` to `b` stays on walkable cells and crosses only open edges.
static func walkable_step(g: LevelGrid, a: Vector3, b: Vector3) -> bool:
	if g == null:
		return true
	var ca := g.cell_of(a)
	var cb := g.cell_of(b)
	if not g.in_bounds(cb) or not g.is_walkable(cb):
		return false
	if ca == cb:
		return true
	var d := cb - ca
	if absi(d.x) + absi(d.y) != 1:
		return false
	return g.can_step(ca, LevelGrid.DIRS.find(d))


## Cell path from `pos` to the nearest walkable cell (walking) outside the flare's 6 m.
static func escape_path(g: LevelGrid, pos: Vector3, flare: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if g == null:
		return out
	var from := g.cell_of(pos)
	var dist := g.distance_field(from)
	var best := -1
	for i in dist.size():
		if dist[i] < 0 or flare_dist(g.world_of(g.cell_at(i)), flare) < Tuning.STATIC_FLARE_RANGE:
			continue
		if best == -1 or dist[i] < dist[best]:
			best = i
	if best == -1:
		return out
	for c in cell_path(g, from, g.cell_at(best)):
		out.append(g.world_of(c))
	return out


## 08 §3 Wander: a seeded walkable cell within 10 cells (grid walking distance) that
## passes `filter` ((cell: Vector2i) -> bool; invalid: every cell); with none in reach,
## the nearest passing cell by walking. Without a grid, a seeded point within 20 m.
static func wander_target(grid: LevelGrid, here: Vector3, rng: RandomNumberGenerator, filter: Callable) -> Vector3:
	if grid == null:
		var a := rng.randf() * TAU
		var r := rng.randf() * Tuning.STATIC_WANDER_CELLS * Tuning.GRID_CELL_SIZE
		return here + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var dist := grid.distance_field(grid.cell_of(here))
	var pool: Array[Vector2i] = []
	var nearest := -1
	for i in dist.size():
		if dist[i] <= 0 or (filter.is_valid() and not bool(filter.call(grid.cell_at(i)))):
			continue
		if dist[i] <= Tuning.STATIC_WANDER_CELLS:
			pool.append(grid.cell_at(i))
		elif nearest == -1 or dist[i] < dist[nearest]:
			nearest = i
	if pool.is_empty():
		return grid.world_of(grid.cell_at(nearest)) if nearest != -1 else here
	return grid.world_of(pool[rng.randi_range(0, pool.size() - 1)])
