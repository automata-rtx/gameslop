class_name FixtureGroups
extends RefCounted
## Fixture-group geometry for Flicker's habitat (08 §5), computed by the LightPool from its
## registered fixtures: each group's centroid (XZ, at the fixtures' height) and the group
## adjacency: two groups are adjacent when any pair of their fixtures lies within 8 m in XZ,
## or when they share a door (the groups on the two sides of a DOOR edge of the grid: a
## room's own group, else the group of the fixture nearest that cell within 8 m). Walls do
## not cut adjacency: Flicker is a fault in the wiring, not a walker. Pure data; rebuilt
## when a fixture registers.

## group id -> Vector3 centroid.
var centroids: Dictionary = {}
## group id -> Array[int] of adjacent group ids, sorted.
var adjacent: Dictionary = {}


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func build(groups: Dictionary, grid: LevelGrid) -> void:
	centroids.clear()
	adjacent.clear()
	var ids: Array = groups.keys()
	ids.sort()
	for id: int in ids:
		var sum := Vector3.ZERO
		var list: Array = groups[id]
		for f: Fixture in list:
			sum += f.global_position
		centroids[id] = sum / maxf(float(list.size()), 1.0)
		adjacent[id] = {}
	# Any fixture pair within 8 m in XZ.
	var lim := Tuning.FLICKER_GROUP_ADJACENT_DIST
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: int = ids[i]
			var b: int = ids[j]
			if flat_dist(centroids[a], centroids[b]) > _radius(groups[a], centroids[a]) + _radius(groups[b], centroids[b]) + lim:
				continue
			if _pair_within(groups[a], groups[b], lim):
				_link(a, b)
	if grid != null:
		_door_links(groups, grid)
	for id: int in ids:
		var out: Array[int] = []
		for k: int in (adjacent[id] as Dictionary):
			out.append(k)
		out.sort()
		adjacent[id] = out


func neighbours(id: int) -> Array[int]:
	var out: Array[int] = []
	if adjacent.has(id):
		out.assign(adjacent[id])
	return out


func _link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	(adjacent[a] as Dictionary)[b] = true
	(adjacent[b] as Dictionary)[a] = true


static func _radius(list: Array, c: Vector3) -> float:
	var r := 0.0
	for f: Fixture in list:
		r = maxf(r, flat_dist(f.global_position, c))
	return r


static func _pair_within(a: Array, b: Array, lim: float) -> bool:
	for fa: Fixture in a:
		for fb: Fixture in b:
			if flat_dist(fa.global_position, fb.global_position) <= lim:
				return true
	return false


## "Or sharing a door": every DOOR edge links the groups on its two sides.
func _door_links(groups: Dictionary, grid: LevelGrid) -> void:
	var all: Array[Fixture] = []
	for id: int in groups:
		for f: Fixture in groups[id]:
			all.append(f)
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if grid.wall(c, d) != LevelGrid.DOOR:
				continue
			var n: Vector2i = c + LevelGrid.DIRS[d]
			if not grid.in_bounds(n):
				continue
			var ga := _cell_group(grid, c, all, groups)
			var gb := _cell_group(grid, n, all, groups)
			if ga >= 0 and gb >= 0 and adjacent.has(ga) and adjacent.has(gb):
				_link(ga, gb)


static func _cell_group(grid: LevelGrid, c: Vector2i, all: Array[Fixture], groups: Dictionary) -> int:
	var room := grid.room_of(c)
	if room != null and room.fixture_group >= 0 and groups.has(room.fixture_group):
		return room.fixture_group
	var at := grid.world_of(c)
	var best := -1
	var best_d := Tuning.FLICKER_GROUP_ADJACENT_DIST
	for f in all:
		var dist := flat_dist(f.global_position, at)
		if dist <= best_d:
			best_d = dist
			best = f.group_id
	return best


## LightPool.lit_fixtures_near: of `fixtures`, the lit ones (powered, not lunge-dark) within
## `radius` of `pos` in XZ whose light (`anchor_of`) has a clear grid line to it, nearest first.
static func lit_near(fixtures: Array[Fixture], grid: LevelGrid, anchor_of: Callable, pos: Vector3, radius: float) -> Array[Fixture]:
	var out: Array[Fixture] = []
	var d: Array[float] = []
	for f in fixtures:
		if not f.is_lit():
			continue
		var dist := flat_dist(f.global_position, pos)
		if dist > radius:
			continue
		if grid != null and not SightOps.clear(grid, anchor_of.call(f), pos):
			continue
		var k := d.bsearch(dist)
		d.insert(k, dist)
		out.insert(k, f)
	return out
