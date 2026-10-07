class_name LevelValidator
extends RefCounted
## 07 §8 validation on the data, before build. `validate` returns the failure lines (empty
## means valid). Rule numbers in the messages match 07 §8. Rules 10 (other strata) and 11
## (navmesh, after build) belong to later tasks.


## `--validate-levels N` (14 §9): generates `n` levels of `stratum` (run seeds 1..n, the
## stratum's first depth; every fourth level as a first Descent when that depth is 1) and
## reports. `valid` counts levels that shipped valid; `fallbacks` those that needed the
## simplest grammar; `retried` those that needed more than one attempt.
static func run_batch(stratum: StringName, n: int, depth: int = 0) -> Dictionary:
	var report := {
		"stratum": String(stratum), "count": 0, "valid": 0, "invalid": 0, "retried": 0, "fallbacks": 0,
		"path_m_mean": 0.0, "path_m_min": 0.0, "path_m_max": 0.0,
		"walkable_mean": 0.0, "walkable_min": 0, "walkable_max": 0,
		"ms_total": 0.0, "ms_mean": 0.0, "ms_max": 0.0, "supported": LevelGenerator.supports(stratum),
		"failures": [],
	}
	if not report["supported"]:
		return report
	var d := depth
	if d <= 0:
		d = int(DataRegistry.stratum(stratum).depth_min) if DataRegistry.stratum(stratum) != null else 1
	for i in n:
		var t0 := Time.get_ticks_usec()
		var level := LevelGenerator.generate(stratum, d, i + 1, d == 1 and i % 4 == 0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		report["count"] += 1
		report["ms_total"] += ms
		report["ms_max"] = maxf(report["ms_max"], ms)
		if level.failures.is_empty():
			report["valid"] += 1
		else:
			report["invalid"] += 1
			report["failures"].append("seed %d: %s" % [i + 1, level.failures])
		if level.attempt > 0:
			report["retried"] += 1
		if level.fallback:
			report["fallbacks"] += 1
		var m := level.critical_path_length_m()
		var w := level.grid.walkable_count()
		report["path_m_mean"] += m / n
		report["path_m_min"] = m if i == 0 else minf(report["path_m_min"], m)
		report["path_m_max"] = maxf(report["path_m_max"], m)
		report["walkable_mean"] += float(w) / n
		report["walkable_min"] = w if i == 0 else mini(report["walkable_min"], w)
		report["walkable_max"] = maxi(report["walkable_max"], w)
	report["ms_mean"] = report["ms_total"] / maxf(1.0, report["count"])
	return report


static func validate(level: LevelData) -> PackedStringArray:
	var f := PackedStringArray()
	var grid := level.grid
	if grid == null:
		f.append("r1: no grid")
		return f
	_rule_structure(level, f)
	var ds := grid.distance_field(level.spawn_cell) if grid.is_walkable(level.spawn_cell) else PackedInt32Array()
	if ds.is_empty():
		f.append("r1: spawn cell not walkable")
		return f
	_rule1_spawn_exit_path(level, ds, f)
	_rule2_path_band(level, f)
	_rule3_lock(level, ds, f)
	_rule4_walkable(level, f)
	_rule6_rooms_dead_ends(level, f)
	_rule7_error_spawns(level, ds, f)
	_rule8_pickups(level, ds, f)
	_rule9_soft_walls(level, ds, f)
	_first_descent(level, ds, f)
	return f


## Rule 5 and the edge invariants: both copies of an edge agree, the border is SOLID, and
## every walkable cell is reachable from spawn (one connected level).
static func _rule_structure(level: LevelData, f: PackedStringArray) -> void:
	var grid := level.grid
	var w := grid.size.x
	var h := grid.size.y
	var walls := grid.walls
	for i in grid.cell_count():
		var x := i % w
		var z := i / w
		# Each cell checks its E and S edges against the neighbour's copy, and its border edges.
		if x < w - 1 and walls[i * 4 + 1] != walls[(i + 1) * 4 + 3]:
			f.append("r5: edge %s E asymmetric" % Vector2i(x, z))
		if z < h - 1 and walls[i * 4 + 2] != walls[(i + w) * 4]:
			f.append("r5: edge %s S asymmetric" % Vector2i(x, z))
		if (z == 0 and walls[i * 4] != LevelGrid.SOLID) or (x == w - 1 and walls[i * 4 + 1] != LevelGrid.SOLID) \
				or (z == h - 1 and walls[i * 4 + 2] != LevelGrid.SOLID) or (x == 0 and walls[i * 4 + 3] != LevelGrid.SOLID):
			f.append("r5: border edge of %s not SOLID" % Vector2i(x, z))


static func _rule1_spawn_exit_path(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var sr := grid.room_of(level.spawn_cell)
	var er := grid.room_of(level.exit_cell)
	if sr == null or er == null or sr == er or sr.kind != RoomData.SPAWN or er.kind != RoomData.EXIT:
		f.append("r1: spawn and exit must be in distinct spawn/exit rooms")
	var path := level.critical_path
	if path.is_empty() or path[0] != level.spawn_cell or path[path.size() - 1] != level.exit_cell:
		f.append("r1: no critical path")
		return
	for k in range(1, path.size()):
		var step := path[k] - path[k - 1]
		var d := LevelGrid.DIRS.find(step)
		if d < 0 or not grid.can_step(path[k - 1], d):
			f.append("r1: critical path broken at %s" % path[k])
			return
	if path.size() - 1 != ds[grid.idx(level.exit_cell)]:
		f.append("r1: critical path is not the shortest walk")
	for i in grid.cell_count():
		if LevelGrid.kind_walkable(grid.cells[i]) and ds[i] < 0:
			f.append("r1: walkable cell %s unreachable" % grid.cell_at(i))
			return


## Halls: 80 to 160 m at depth 1, scaled by grid size for larger grids.
static func path_band(level: LevelData) -> Vector2:
	var scale := float(level.grid.size.x) / float(Tuning.GRID_SIZE_BY_DEPTH[1])
	return Vector2(Tuning.VALIDATE_HALLS_PATH_MIN, Tuning.VALIDATE_HALLS_PATH_MAX) * scale


static func _rule2_path_band(level: LevelData, f: PackedStringArray) -> void:
	var band := path_band(level)
	var m := level.critical_path_length_m()
	if m < band.x or m > band.y:
		f.append("r2: critical path %.0f m outside %.0f..%.0f" % [m, band.x, band.y])


static func _rule3_lock(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var objective := LevelData.NO_CELL
	match level.exit_lock:
		Tuning.LOCK_POWERED:
			objective = level.breaker_cell
			if level.placements_of(LevelData.P_BREAKER).size() != 1:
				f.append("r3: Powered needs exactly one breaker")
			if level.lock_variant == &"b":
				var fuses := 0
				for p in level.placements_of(LevelData.P_ITEM):
					if p[&"params"].get(&"item", &"") == &"fuse":
						fuses += 1
						if not _reachable_both_ways(level, ds, p[&"cell"]):
							f.append("r3: fuse unreachable")
				if fuses != 1:
					f.append("r3: Variant B needs exactly one fuse, found %d" % fuses)
		Tuning.LOCK_KEYED:
			objective = level.keycard_cell
			if level.placements_of(LevelData.P_KEYCARD).size() != 1:
				f.append("r3: Keyed needs exactly one keycard")
		_:
			return
	if not grid.in_bounds(objective) or not _reachable_both_ways(level, ds, objective):
		f.append("r3: %s objective unreachable on foot" % level.exit_lock)


## Reachable from spawn, and the exit reachable from it, walking only (no SOLID, GLASS,
## soft wall or wall is ever crossed on foot).
static func _reachable_both_ways(level: LevelData, ds: PackedInt32Array, c: Vector2i) -> bool:
	var grid := level.grid
	if not grid.in_bounds(c) or ds[grid.idx(c)] < 0:
		return false
	return grid.distance_field(c)[grid.idx(level.exit_cell)] >= 0


static func _rule4_walkable(level: LevelData, f: PackedStringArray) -> void:
	var target := StratumGenerator.walkable_target(level.depth)
	var n := level.grid.walkable_count()
	var tol := Tuning.LEVEL_WALKABLE_TOLERANCE
	if n < target * (1.0 - tol) or n > target * (1.0 + tol):
		f.append("r4: %d walkable cells, target %d +-%d%%" % [n, target, int(tol * 100)])


static func _rule6_rooms_dead_ends(level: LevelData, f: PackedStringArray) -> void:
	var grid := level.grid
	for room in grid.room_list:
		var open := false
		for e in room.perimeter_edges():
			open = open or grid.can_step(Vector2i(e.x, e.y), e.z)
		if not open:
			f.append("r6: room %d (%s) has no opening" % [room.id, room.kind])
	for chain in MazeOps.dead_end_chains(grid):
		if chain.size() > Tuning.VALIDATE_DEAD_END_CHAIN_MAX:
			f.append("r6: dead end chain of %d cells at %s" % [chain.size(), chain[0]])


static func _rule7_error_spawns(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var spawns := level.placements_of(LevelData.P_ERROR_SPAWN)
	if spawns.size() < Tuning.VALIDATE_ERROR_SPAWNS_MIN:
		f.append("r7: %d error spawn points, need %d" % [spawns.size(), Tuning.VALIDATE_ERROR_SPAWNS_MIN])
	for p in spawns:
		var c: Vector2i = p[&"cell"]
		if ds[grid.idx(c)] * Tuning.GRID_CELL_SIZE < Tuning.VALIDATE_ERROR_SPAWN_MIN_WALK:
			f.append("r7: error spawn %s closer than %.0f m" % [c, Tuning.VALIDATE_ERROR_SPAWN_MIN_WALK])
		if grid.has_flag(c, LevelGrid.F_SPAWN_ROOM) or grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			f.append("r7: error spawn %s inside the spawn or exit room" % c)


static func _rule8_pickups(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var items := level.placements_of(LevelData.P_ITEM)
	var notes := level.placements_of(LevelData.P_NOTE)
	var hides := level.placements_of(LevelData.P_HIDE_SPOT)
	if items.size() != level.expected_items:
		f.append("r8: %d items, expected %d" % [items.size(), level.expected_items])
	if notes.size() != level.expected_notes:
		f.append("r8: %d notes, expected %d" % [notes.size(), level.expected_notes])
	if hides.size() != level.expected_hide_spots:
		f.append("r8: %d hide spots, expected %d" % [hides.size(), level.expected_hide_spots])
	var seen: Dictionary = {}
	var pickups: Array[Dictionary] = []
	pickups.append_array(items)
	pickups.append_array(notes)
	pickups.append_array(level.placements_of(LevelData.P_KEYCARD))
	for p in pickups:
		var c: Vector2i = p[&"cell"]
		if seen.has(c):
			f.append("r8: two pickups in %s" % c)
		seen[c] = true
		if not grid.in_bounds(c) or ds[grid.idx(c)] < 0:
			f.append("r8: pickup at %s unreachable" % c)
	for p in notes:
		if grid.has_flag(p[&"cell"], LevelGrid.F_SPAWN_ROOM):
			f.append("r8: note in the spawn room")
	var length := level.critical_path.size() - 1
	var early := false
	for p in notes:
		early = early or ds[grid.idx(p[&"cell"])] <= length * Tuning.NOTES_FIRST_PATH_FRACTION
	if not notes.is_empty() and not early:
		f.append("r8: no note within the first 40% of the critical path")


static func _rule9_soft_walls(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var marked := 0
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if grid.in_bounds(c + LevelGrid.DIRS[d]) and grid.wall(c, d) == LevelGrid.SOFT:
				marked += 1
	if marked != level.soft_walls.size() or marked != level.expected_soft_walls:
		f.append("r9: %d soft walls, expected %d" % [marked, level.expected_soft_walls])
	for e in level.soft_walls:
		var a := Vector2i(e.x, e.y)
		var b := a + LevelGrid.DIRS[e.z]
		if not grid.is_walkable(a) or not grid.is_walkable(b):
			f.append("r9: soft wall %s not between walkable cells" % e)
			continue
		if grid.has_flag(a, LevelGrid.F_EXIT_ROOM) or grid.has_flag(b, LevelGrid.F_EXIT_ROOM):
			f.append("r9: soft wall %s on the exit room" % e)
		var walk := grid.distance_field(a)[grid.idx(b)]
		if walk < 0 or (walk - 1) * Tuning.GRID_CELL_SIZE < Tuning.SOFT_WALL_MIN_SAVING:
			f.append("r9: soft wall %s saves less than %.0f m" % [e, Tuning.SOFT_WALL_MIN_SAVING])


## 05 §10 first Descent guarantees that the data can show: Powered with the breaker room on
## the critical path, a soft wall on the path within 60 s of walking, note H1's slot within
## 10 m of spawn, one Polaroid.
static func _first_descent(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	if not level.first_run or level.depth != 1:
		return
	var grid := level.grid
	if level.exit_lock != Tuning.LOCK_POWERED:
		f.append("fd: first Descent depth 1 must be Powered")
	var breaker_on_path := false
	for c in level.critical_path:
		var r := grid.room_of(c)
		breaker_on_path = breaker_on_path or (r != null and r.kind == RoomData.BREAKER)
	if not breaker_on_path:
		f.append("fd: breaker room not on the critical path")
	var reach := Tuning.FIRST_DESCENT_SOFT_WALL_TIME * Tuning.PLAYER_WALK_SPEED
	var soft_ok := false
	for e in level.soft_walls:
		for c: Vector2i in [Vector2i(e.x, e.y), Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]]:
			if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH) and ds[grid.idx(c)] * Tuning.GRID_CELL_SIZE <= reach:
				soft_ok = true
	if not soft_ok:
		f.append("fd: no soft wall on the critical path within 60 s")
	var note_ok := false
	for p in level.placements_of(LevelData.P_NOTE):
		note_ok = note_ok or (p[&"params"].get(&"first_descent", false) and ds[grid.idx(p[&"cell"])] * Tuning.GRID_CELL_SIZE <= Tuning.FIRST_DESCENT_NOTE_DIST)
	if not note_ok:
		f.append("fd: no note within 10 m of spawn")
	var polaroid := false
	for p in level.placements_of(LevelData.P_ITEM):
		polaroid = polaroid or p[&"params"].get(&"item", &"") == &"polaroid"
	if not polaroid:
		f.append("fd: no Polaroid")
