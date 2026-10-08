class_name GarageParking
extends RefCounted
## The Garage grammar's bays, cars, barriers and lamps (07 §5.3). Bays are deck cells
## against a strip or a perimeter wall. Cars (two bay cells along the wall, 4.2 m) fill
## about 35% of the bays, a cell apart, each a hide spot host (under_car, a marker until
## M2.8); barriers stand at 10% of the bay-row ends. Nothing parks where it would cut the
## deck in two: every car and barrier keeps all walkable cells reachable around it.
## Lamps: a sodium cage lamp on one face of every pillar (the face looking down the longest
## open run), grouped by 4x4-cell quadrants; one in each core room and on each ramp.

const CAR_COLORS := 4
## Distance from the wall plane to the car's centre line (m): 0.15 m clear plus half its width.
const CAR_INSET := 1.05
const BARRIER_INSET := 1.0

var gen: GarageGenerator
var grid: LevelGrid
## Cell index -> true for cells a car or barrier stands on.
var blocked: Dictionary = {}
var cars: int = 0


## Cell index -> true for the cells either side of a soft wall (kept clear).
var _soft_cells: Dictionary = {}


func _init(generator: GarageGenerator) -> void:
	gen = generator
	grid = generator.grid
	for e in gen.data.soft_walls:
		var a := Vector2i(e.x, e.y)
		_soft_cells[grid.idx(a)] = true
		_soft_cells[grid.idx(a + LevelGrid.DIRS[e.z])] = true


## Bay cells: Vector3i(x, z, wall dir) for deck cells against a strip or the deck's
## outer wall (a wall with nothing walkable behind it, or a strip between deck cells), not
## against a core, keeping ramp mouths and core openings clear.
func bays() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.FLOOR:
			continue
		var c := grid.cell_at(i)
		if _near_mouth(c):
			continue
		for d in 4:
			var w := grid.wall(c, d)
			var o := c + LevelGrid.DIRS[d]
			if (w == LevelGrid.WALL or w == LevelGrid.SOLID) and not gen.core_cells.has(grid.idx(o)) \
					and not (grid.in_bounds(o) and grid.kind(o) == LevelGrid.RAMP):
				out.append(Vector3i(c.x, c.y, d))
	return out


## True next to a ramp cell or in front of a room's opening.
func _near_mouth(c: Vector2i) -> bool:
	for d in 4:
		var o := c + LevelGrid.DIRS[d]
		if not grid.in_bounds(o):
			continue
		if grid.kind(o) == LevelGrid.RAMP:
			return true
		if grid.kind(o) == LevelGrid.ROOM and grid.can_step(c, d):
			return true
	return false


func park() -> void:
	var rng := gen.rng_props
	var all := bays()
	var bay_of: Dictionary = {}
	for e in all:
		bay_of[Vector3i(e.x, e.y, e.z)] = true
	var want := roundi(Tuning.GARAGE_CAR_FILL * all.size() / 2.0)
	var pairs: Array[Vector4i] = []
	for e in all:
		for along: int in [(e.z + 1) % 4]:
			var b := Vector2i(e.x, e.y) + LevelGrid.DIRS[along]
			if bay_of.has(Vector3i(b.x, b.y, e.z)) and grid.can_step(Vector2i(e.x, e.y), along):
				pairs.append(Vector4i(e.x, e.y, e.z, along))
	RoomOps.shuffle(pairs, rng)
	var hosts: Array[Dictionary] = []
	for p in pairs:
		if cars >= want:
			break
		var a := Vector2i(p.x, p.y)
		var b := a + LevelGrid.DIRS[p.w]
		if not _clear_around(a) or not _clear_around(b) or not _keeps_connected([a, b]):
			continue
		for c in [a, b]:
			blocked[grid.idx(c)] = true
			gen.occupied[grid.idx(c)] = true
			grid.add_flag(c, LevelGrid.F_NO_SPAWN)
		grid.add_flag(a, LevelGrid.F_HIDE_SPOT_HOST)
		var off := StratumGenerator.wall_offset(p.z, CAR_INSET) + Vector3(LevelGrid.DIRS[p.w].x, 0, LevelGrid.DIRS[p.w].y) * Tuning.GRID_CELL_SIZE * 0.5
		var yaw := LevelData.yaw_facing(p.w)
		gen.data.add_placement(LevelData.P_PROP, a, off, yaw,
			{&"prop": &"car", &"dir": p.z, &"color": rng.randi_range(0, CAR_COLORS - 1)})
		hosts.append({&"cell": a, &"off": off, &"yaw": yaw, &"dir": p.z})
		cars += 1
	gen.data.expected_hide_spots = hosts.size()
	for h in hosts:
		gen.data.add_placement(LevelData.P_HIDE_SPOT, h[&"cell"], h[&"off"], h[&"yaw"],
			{&"kind": &"under_car", &"dir": h[&"dir"], &"view_yaw_limit": Tuning.HIDE_UNDER_CAR_YAW_LIMIT})
	_barriers(all, bay_of, rng)


## No other car or barrier within one cell (07 §5.3: min spacing 1 cell).
func _clear_around(c: Vector2i) -> bool:
	if gen.occupied.has(grid.idx(c)) or grid.kind(c) != LevelGrid.FLOOR or _soft_cells.has(grid.idx(c)):
		return false
	for z in range(c.y - 1, c.y + 2):
		for x in range(c.x - 1, c.x + 2):
			var o := Vector2i(x, z)
			if grid.in_bounds(o) and blocked.has(grid.idx(o)):
				return false
	return true


## Every walkable cell not blocked stays reachable from spawn with `extra` blocked too.
## A local test first: the free cells touching the new block are joined around its ring
## of neighbours; only when they are not is the whole level searched.
func _keeps_connected(extra: Array) -> bool:
	return _ring_connected(extra) or _search_connected(extra)


func _free(c: Vector2i, extra: Array) -> bool:
	return grid.is_walkable(c) and not blocked.has(grid.idx(c)) and not extra.has(c)


func _ring_connected(extra: Array) -> bool:
	var lo: Vector2i = extra[0]
	var hi: Vector2i = extra[0]
	for c: Vector2i in extra:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var ring: Array[Vector2i] = []
	for x in range(lo.x, hi.x):
		ring.append(Vector2i(x, lo.y))
	for z in range(lo.y, hi.y):
		ring.append(Vector2i(hi.x, z))
	for x in range(hi.x, lo.x, -1):
		ring.append(Vector2i(x, hi.y))
	for z in range(hi.y, lo.y, -1):
		ring.append(Vector2i(lo.x, z))
	# Component label per ring cell (-1: not free), walking the cycle.
	var n := ring.size()
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var next := 0
	for k in n:
		if not _free(ring[k], extra):
			continue
		var prev := (k + n - 1) % n
		if label[prev] >= 0 and _joined(ring[prev], ring[k]):
			label[k] = label[prev]
		else:
			label[k] = next
			next += 1
	# Close the cycle: the last run may continue into the first.
	if n > 1 and label[0] >= 0 and label[n - 1] >= 0 and _joined(ring[n - 1], ring[0]):
		var from := label[n - 1]
		for k in n:
			if label[k] == from:
				label[k] = label[0]
	var seen := -1
	for c: Vector2i in extra:
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			var k := ring.find(o)
			if k < 0 or label[k] < 0 or not grid.can_step(c, d):
				continue
			if seen >= 0 and label[k] != seen:
				return false
			seen = label[k]
	return true


func _joined(a: Vector2i, b: Vector2i) -> bool:
	var d := LevelGrid.DIRS.find(b - a)
	return d >= 0 and grid.can_step(a, d)


func _search_connected(extra: Array) -> bool:
	var start := grid.idx(gen.data.spawn_cell)
	var seen := PackedByteArray()
	seen.resize(grid.cell_count())
	seen[start] = 1
	var queue := PackedInt32Array([start])
	var head := 0
	var w := grid.size.x
	var steps: Array[int] = [-w, 1, w, -1]
	while head < queue.size():
		var i := queue[head]
		head += 1
		var m := grid.open_mask(i)
		for d in 4:
			if (m & (1 << d)) == 0:
				continue
			var j := i + steps[d]
			if seen[j] == 0 and not blocked.has(j) and not extra.has(grid.cell_at(j)):
				seen[j] = 1
				queue.append(j)
	var want := 0
	for i in grid.cell_count():
		if LevelGrid.kind_walkable(grid.cells[i]) and not blocked.has(i) and not extra.has(grid.cell_at(i)):
			want += 1
	return queue.size() == want


## Barriers at 10% of bay-row ends (a bay whose next cell along the wall is no bay).
func _barriers(all: Array[Vector3i], bay_of: Dictionary, rng: RandomNumberGenerator) -> void:
	var ends: Array[Vector3i] = []
	for e in all:
		var c := Vector2i(e.x, e.y)
		for along: int in [(e.z + 1) % 4, (e.z + 3) % 4]:
			var o := c + LevelGrid.DIRS[along]
			if not bay_of.has(Vector3i(o.x, o.y, e.z)):
				ends.append(e)
				break
	RoomOps.shuffle(ends, rng)
	var want := roundi(Tuning.GARAGE_BARRIER_FRACTION * ends.size())
	var made := 0
	for e in ends:
		if made >= want:
			break
		var c := Vector2i(e.x, e.y)
		if not _clear_around(c) or not _keeps_connected([c]):
			continue
		blocked[grid.idx(c)] = true
		gen.occupied[grid.idx(c)] = true
		grid.add_flag(c, LevelGrid.F_NO_SPAWN)
		gen.data.add_placement(LevelData.P_PROP, c, StratumGenerator.wall_offset(e.z, BARRIER_INSET),
			LevelData.yaw_facing(e.z), {&"prop": &"barrier", &"dir": e.z})
		made += 1


## 07 §5.3 pillars (the mesh in each pillar cell) and lamps: one per pillar on its face
## down the longest open run; quadrant groups.
func place_fixtures() -> void:
	var quadrants: Dictionary = {}
	var q := Tuning.GARAGE_QUADRANT_CELLS
	var reach := Tuning.GARAGE_PILLAR_SIZE * 0.5 + 0.12
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_pillar(c):
			continue
		gen.data.add_placement(LevelData.P_PROP, c, Vector3.ZERO, 0.0, {&"prop": &"pillar", &"dir": -1})
		var best := -1
		var best_run := -1
		for d in 4:
			var run := _run(c + LevelGrid.DIRS[d], d)
			if run > best_run:
				best_run = run
				best = d
		var key := Vector3i(c.x / q, c.y / q, grid.deck[i])
		if not quadrants.has(key):
			quadrants[key] = _group([])
		var group: int = quadrants[key]
		(grid.groups[group] as Array).append(c)
		var dv := LevelGrid.DIRS[best]
		gen.data.add_placement(LevelData.P_FIXTURE, c, Vector3(dv.x * reach, Tuning.GARAGE_LAMP_HEIGHT, dv.y * reach),
			LevelData.yaw_facing(best), {&"group": group, &"fixture": &"sodium_lamp", &"dir": best})
	var height := float(Tuning.STRATUM_CEILING_HEIGHT[&"garage"])
	for room in grid.room_list:
		FixtureOps.room_fixtures(gen, room, height, &"sodium_lamp")
	# Two lamps down each ramp's 8 m tunnel (cells 1 and 3 of 4), one group per ramp.
	for run: Array in gen.ramps:
		var lit: Array[Vector2i] = []
		for k in range(1, run.size(), 2):
			lit.append(run[k])
		var group := _group(lit)
		for c in lit:
			gen.data.add_placement(LevelData.P_FIXTURE, c, Vector3(0.0, height, 0.0), 0.0,
				{&"group": group, &"fixture": &"sodium_lamp"})


## Open cells walked straight from `c` in `d` (up to 12).
func _run(c: Vector2i, d: int) -> int:
	var n := 0
	var p := c
	while n < 12 and grid.is_walkable(p) and grid.can_step(p, d):
		p += LevelGrid.DIRS[d]
		n += 1
	return n


func _group(cells: Array) -> int:
	var id := grid.groups.size()
	var typed: Array[Vector2i] = []
	typed.assign(cells)
	grid.groups[id] = typed
	return id
