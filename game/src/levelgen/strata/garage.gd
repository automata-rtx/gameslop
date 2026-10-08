class_name GarageGenerator
extends StratumGenerator
## Garage grammar (07 §5.3), split-level: two decks of equal size, deck 1 (the spawn deck,
## floor +3.2 m) beside deck 0 (the exit deck), joined by 2 or 3 straight ramp runs of 4
## cells across a band of solid ground between them (CHANGELOG M2.1: the grid holds one
## floor per cell, so the decks sit side by side, not stacked). Layout coordinates are
## (u, v): u runs along the band, v across it (deck 1 at low v); the whole layout is
## transposed at random so the band may run either way.
## Each deck: perimeter walls; pillars (VOID cells with no walls, a pillar mesh) every 4
## cells; 3 to 5 interior WALL strips of 4 to 10 cells off the deck's outer walls; two
## 3x3 cores at the same places on both decks. Core A is the elevator lobby on deck 1
## (the spawn, against the outer perimeter, the Landing cabin beyond) and the stairwell
## core on deck 0 (the exit); core B is solid, or the breaker room when Powered. Cars and
## barriers (GarageParking) line the bays.

## Decks land this fraction below the walkable target, at random.
const WALKABLE_JITTER := 0.08
const BREAKER_INSET := 0.05

var lobby: RoomData = null
var exit_room: RoomData = null
var breaker_room: RoomData = null
var parking: GarageParking = null
## Deck rectangles in (u, v): deck 1 then deck 0.
var deck_uv: Array[Rect2i] = []
## Ramp runs, bottom (deck 0 side) first, in grid cells.
var ramps: Array[Array] = []
## Grid cells that are core cells (lobby, exit, breaker, solid cores).
var core_cells: Dictionary = {}
var _t: bool = false


## Layout (u, v) to grid cell.
func cell(u: int, v: int) -> Vector2i:
	return Vector2i(v, u) if _t else Vector2i(u, v)


## Layout direction to grid direction (transposing swaps N with W and S with E).
func dir(d: int) -> int:
	return 3 - d if _t else d


func layout() -> void:
	var n := grid.size.x
	_t = rng_layout.randi_range(0, 1) == 1
	var band := Tuning.GARAGE_RAMP_LENGTH_CELLS
	var a := (n - band) / 2 + rng_layout.randi_range(-1, 1)
	var depth1 := a
	var depth0 := n - a - band
	var target := walkable_target(data.depth) * (1.0 - rng_layout.randf() * WALKABLE_JITTER)
	var per_row := float(depth1 + depth0) * (1.0 - 1.0 / float(Tuning.GARAGE_PILLAR_SPACING_CELLS * Tuning.GARAGE_PILLAR_SPACING_CELLS))
	var cores := Tuning.GARAGE_CORE_SIZE.x * Tuning.GARAGE_CORE_SIZE.y * 2
	var w := clampi(roundi((target + cores) / per_row), Tuning.GARAGE_DECK_WIDTH_MIN, n)
	var u0 := rng_layout.randi_range(0, n - w)
	deck_uv = [Rect2i(u0, 0, w, depth1), Rect2i(u0, a + band, w, depth0)]
	for k in 2:
		var deck_no := 1 - k
		var r := deck_uv[k]
		for v in range(r.position.y, r.end.y):
			for u in range(r.position.x, r.end.x):
				var c := cell(u, v)
				grid.set_kind(c, LevelGrid.FLOOR)
				grid.set_floor_y(c, Tuning.GARAGE_DECK_RISE * deck_no)
				grid.deck[grid.idx(c)] = deck_no
				for d in 4:
					var o := c + LevelGrid.DIRS[d]
					if grid.in_bounds(o) and grid.kind(o) == LevelGrid.FLOOR and grid.deck[grid.idx(o)] == deck_no:
						grid.set_wall(c, d, LevelGrid.NONE)
	_cores()
	_ramps(a, band)
	grid.finalize_walls()
	# Pillars first: a strip never takes a pillar's place on the lattice (the lamps hang there).
	_pillars()
	for k in 2:
		_strips(k)
	GridHeights.refresh_ledges(grid)
	MazeOps.mark_dead_ends(grid)


## Core A at a random place along the decks' outer edges (lobby on deck 1, exit on deck 0);
## core B elsewhere along the decks' middles, solid or the breaker room.
func _cores() -> void:
	var sz := Tuning.GARAGE_CORE_SIZE
	var r1 := deck_uv[0]
	var r0 := deck_uv[1]
	var ua := rng_layout.randi_range(r1.position.x + 1, r1.end.x - sz.x - 1)
	lobby = _core_room(Rect2i(ua, r1.position.y, sz.x, sz.y), RoomData.SPAWN, LevelGrid.S)
	data.spawn_dir = dir(LevelGrid.N)
	data.spawn_cell = cell(ua + 1, r1.position.y)
	exit_room = _core_room(Rect2i(ua, r0.end.y - sz.y, sz.x, sz.y), RoomData.EXIT, LevelGrid.N)
	data.exit_dir = dir(LevelGrid.S)
	data.exit_cell = cell(ua + 1, r0.end.y - 1)
	# Core B: same u on both decks, mid-deck, clear of core A.
	var options: Array[int] = []
	for u in range(r1.position.x + 1, r1.end.x - sz.x):
		if u + sz.x + 1 <= ua or u >= ua + sz.x + 1:
			options.append(u)
	if options.is_empty():
		return
	var ub := options[rng_layout.randi_range(0, options.size() - 1)]
	var powered := data.exit_lock == Tuning.LOCK_POWERED
	var on_deck := rng_layout.randi_range(0, 1)
	for k in 2:
		var r := deck_uv[k]
		var vb := r.position.y + (r.size.y - sz.y) / 2
		var rect := Rect2i(ub, vb, sz.x, sz.y)
		if powered and k == on_deck:
			breaker_room = _core_room(rect, RoomData.BREAKER, LevelGrid.S if rng_layout.randi_range(0, 1) == 0 else LevelGrid.N)
		else:
			_solid_core(rect)


## A 3x3 core room in layout rect `r`: SOLID walls, one opening in the middle of side `open`.
func _core_room(r: Rect2i, kind: StringName, open: int) -> RoomData:
	var gr := _grid_rect(r)
	var room := RoomOps.add_room(grid, gr, kind)
	for e in room.perimeter_edges():
		grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.SOLID)
	var mid := StratumGenerator.side_middle(RoomData.new(r), open)
	var c := cell(mid.x, mid.y)
	grid.set_wall(c, dir(open), LevelGrid.NONE)
	room.doors.append(Vector3i(c.x, c.y, dir(open)))
	for rc in room.cells():
		core_cells[grid.idx(rc)] = true
	return room


func _solid_core(r: Rect2i) -> void:
	var gr := _grid_rect(r)
	for c in RoomData.new(gr).cells():
		grid.set_kind(c, LevelGrid.VOID)
		core_cells[grid.idx(c)] = true
	for e in RoomData.new(gr).perimeter_edges():
		grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.SOLID)


func _grid_rect(r: Rect2i) -> Rect2i:
	var a := cell(r.position.x, r.position.y)
	var b := cell(r.end.x - 1, r.end.y - 1)
	return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), (b - a).abs() + Vector2i.ONE)


## 2 or 3 ramp runs across the band, against the decks' ends first (07 §5.3: "against the
## perimeter"), at least GARAGE_RAMP_SPACING apart, never in front of a core.
func _ramps(a: int, band: int) -> void:
	var r := deck_uv[0]
	var want := rng_layout.randi_range(Tuning.GARAGE_RAMPS_MIN, Tuning.GARAGE_RAMPS_MAX)
	if simplest:
		want = Tuning.GARAGE_RAMPS_MIN
	var options: Array[int] = [r.position.x, r.end.x - 1]
	var middle: Array[int] = []
	for u in range(r.position.x + 1, r.end.x - 1):
		middle.append(u)
	RoomOps.shuffle(middle, rng_layout)
	options.append_array(middle)
	var used: Array[int] = []
	for u in options:
		if used.size() >= want:
			break
		var ok := true
		for x in used:
			ok = ok and absi(x - u) > Tuning.GARAGE_RAMP_SPACING
		var top := cell(u, a - 1)
		var bottom := cell(u, a + band)
		if not ok or core_cells.has(grid.idx(top)) or core_cells.has(grid.idx(bottom)):
			continue
		used.append(u)
		var run: Array[Vector2i] = []
		for k in band:
			run.append(cell(u, a + band - 1 - k))
		var uphill := dir(LevelGrid.N)
		GridHeights.set_ramp(grid, run, uphill, 0.0, Tuning.GARAGE_DECK_RISE)
		var prev := bottom
		for c in run:
			grid.set_wall(prev, uphill, LevelGrid.NONE)
			prev = c
		grid.set_wall(prev, uphill, LevelGrid.NONE)
		ramps.append(run)


## 3 to 5 WALL strips per deck, each 4 to 10 cells running in from the deck's outer
## perimeter or band edge, between two rows (or columns) of deck cells.
func _strips(k: int) -> void:
	var r := deck_uv[k]
	var count := Tuning.GARAGE_STRIPS_MIN if simplest else rng_layout.randi_range(Tuning.GARAGE_STRIPS_MIN, Tuning.GARAGE_STRIPS_MAX)
	var tries := count * 8
	var made := 0
	while made < count and tries > 0:
		tries -= 1
		var length := rng_layout.randi_range(Tuning.GARAGE_STRIP_LENGTH_MIN, Tuning.GARAGE_STRIP_LENGTH_MAX)
		var across := rng_layout.randi_range(0, 1) == 0
		var edges: Array[Vector3i] = []
		if across:
			# Along v from the outer or band edge, between columns u and u + 1.
			var u := rng_layout.randi_range(r.position.x + 1, r.end.x - 3)
			var from_low := rng_layout.randi_range(0, 1) == 0
			for s in mini(length, r.size.y - 2):
				var v := r.position.y + s if from_low else r.end.y - 1 - s
				edges.append(Vector3i(u, v, LevelGrid.E))
		else:
			var v := rng_layout.randi_range(r.position.y + 1, r.end.y - 3)
			var from_low := rng_layout.randi_range(0, 1) == 0
			for s in mini(length, r.size.x - 2):
				var u := r.position.x + s if from_low else r.end.x - 1 - s
				edges.append(Vector3i(u, v, LevelGrid.S))
		if _strip_ok(edges):
			for e in edges:
				grid.set_wall(cell(e.x, e.y), dir(e.z), LevelGrid.WALL)
			if _connected():
				made += 1
			else:
				for e in edges:
					grid.set_wall(cell(e.x, e.y), dir(e.z), LevelGrid.NONE)


## Every walkable cell reachable from the spawn (a strip never closes off a pocket).
func _connected() -> bool:
	var dist := grid.distance_field(data.spawn_cell)
	for i in grid.cell_count():
		if LevelGrid.kind_walkable(grid.cells[i]) and dist[i] < 0:
			return false
	return true


## A strip only stands between two plain deck cells, clear of cores, ramps and openings.
func _strip_ok(edges: Array[Vector3i]) -> bool:
	if edges.is_empty():
		return false
	for e in edges:
		var c := cell(e.x, e.y)
		var o := c + LevelGrid.DIRS[dir(e.z)]
		for x: Vector2i in [c, o]:
			if not grid.in_bounds(x) or grid.kind(x) != LevelGrid.FLOOR or core_cells.has(grid.idx(x)):
				return false
			for d in 4:
				var y := x + LevelGrid.DIRS[d]
				if grid.in_bounds(y) and (grid.kind(y) == LevelGrid.RAMP or core_cells.has(grid.idx(y))):
					return false
		if grid.wall(c, dir(e.z)) != LevelGrid.NONE:
			return false
	return true


## Pillars every 4 cells on both axes of each deck: a VOID cell with no walls (07 §5.3),
## where nothing else stands and every neighbour is open deck.
func _pillars() -> void:
	var step := Tuning.GARAGE_PILLAR_SPACING_CELLS
	for k in 2:
		var r := deck_uv[k]
		for v in range(r.position.y + step / 2, r.end.y - 1, step):
			for u in range(r.position.x + step / 2, r.end.x - 1, step):
				var c := cell(u, v)
				if not _pillar_ok(c):
					continue
				grid.set_kind(c, LevelGrid.VOID)
				for d in 4:
					grid.set_wall(c, d, LevelGrid.NONE)


func _pillar_ok(c: Vector2i) -> bool:
	if grid.kind(c) != LevelGrid.FLOOR or core_cells.has(grid.idx(c)):
		return false
	for d in 4:
		var o := c + LevelGrid.DIRS[d]
		if grid.kind(o) != LevelGrid.FLOOR or core_cells.has(grid.idx(o)) or grid.wall(c, d) != LevelGrid.NONE:
			return false
	return true


func decorate() -> void:
	if exit_room == null or lobby == null or data.critical_path.is_empty():
		return  # Rule 1 fails; the generator retries.
	flag_room(lobby, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_NO_SPAWN)
	flag_room(exit_room, LevelGrid.F_EXIT_ROOM | LevelGrid.F_NO_SPAWN)
	data.add_placement(LevelData.P_SPAWN, data.spawn_cell, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(data.spawn_dir)),
		{&"cabin_dir": data.spawn_dir})
	data.add_placement(LevelData.P_EXIT, data.exit_cell, wall_offset(data.exit_dir, 0.0), LevelData.yaw_facing(LevelGrid.opposite(data.exit_dir)),
		{&"exit_kind": &"stairwell_door", &"lock": data.exit_lock, &"dir": data.exit_dir})
	# 02 §7: the exit sign, the only green light in the stratum, above the stairwell door.
	data.add_placement(LevelData.P_PROP, data.exit_cell,
		wall_offset(data.exit_dir, 0.08) + Vector3(0.0, Tuning.GARAGE_EXIT_SIGN_HEIGHT, 0.0),
		LevelData.yaw_facing(LevelGrid.opposite(data.exit_dir)), {&"prop": &"exit_sign", &"dir": data.exit_dir})
	if breaker_room != null:
		flag_room(breaker_room, LevelGrid.F_LOCK_ROOM)
		_place_breaker()
	var soft := Tuning.GARAGE_SOFT_WALLS + (Tuning.CYCLE2_EXTRA_SOFT_WALLS if data.cycle > 1 else 0)
	PopulateOps.soft_walls(self, soft, false, LevelGrid.F_EXIT_ROOM | LevelGrid.F_SPAWN_ROOM | LevelGrid.F_LOCK_ROOM)
	# Cars park after the soft walls, never in front of one (a shortcut nobody can reach).
	parking = GarageParking.new(self)
	parking.park()
	_place_keycard()
	PopulateOps.lock_pickups(self)
	PopulateOps.notes(self)
	var pool: Array[StringName] = DEFAULT_ITEM_POOL.duplicate()
	if options.has(&"item_pool"):
		pool.assign(options[&"item_pool"])
	PopulateOps.items(self, pool)
	parking.place_fixtures()
	PopulateOps.error_spawns(self)


func release() -> void:
	parking = null


func _place_breaker() -> void:
	var slots := wall_slots(breaker_room)
	if slots.is_empty():
		return
	var e := slots[rng_place.randi_range(0, slots.size() - 1)]
	data.breaker_cell = Vector2i(e.x, e.y)
	data.add_placement(LevelData.P_BREAKER, data.breaker_cell, wall_offset(e.z, BREAKER_INSET),
		LevelData.yaw_facing(LevelGrid.opposite(e.z)), {&"variant": data.lock_variant, &"dir": e.z})


## 07 §5.3: the keycard lies on the other deck from the exit (deck 1), in the 35% to 70%
## band of the critical path when that band reaches deck 1, else anywhere on deck 1.
func _place_keycard() -> void:
	if data.exit_lock != Tuning.LOCK_KEYED:
		return
	var length := data.critical_path.size() - 1
	var on_deck := func(c: Vector2i) -> bool: return grid.deck[grid.idx(c)] == 1 and not grid.has_flag(c, LevelGrid.F_CRITICAL_PATH)
	var cells := PopulateOps.band_cells(self, int(ceil(length * 0.35)), int(floor(length * 0.70)), on_deck)
	if cells.is_empty():
		cells = PopulateOps.band_cells(self, 1, grid.cell_count(), on_deck)
	var pick := PlaceOps.poisson_cells(cells, 1, 0, rng_place, PopulateOps.pickup_weights(self, cells))
	if pick.is_empty():
		return
	occupied[grid.idx(pick[0])] = true
	data.keycard_cell = pick[0]
	data.add_placement(LevelData.P_KEYCARD, pick[0])
