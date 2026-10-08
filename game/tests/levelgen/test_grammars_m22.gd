extends TestCase
## M2.2: the Offices and Server grammars (07 §5.4, §5.5) validate for GATE_SEEDS seeds per
## stratum in the merge gate and 1,000 in the checkpoint run (NOCLIP_FULL_TESTS=1), at
## every depth they appear at and in Cycle 2; their simplest grammars validate; the counts
## and shapes 07 names hold; and rule 10 catches what it should.

const SEEDS := Tuning.VALIDATE_SEEDS_PER_STRATUM
const GATE_SEEDS := 300
const OPTS := {&"fuse_unlocked": true, &"item_pool": Tuning.ITEM_KINDS}


func _batch(stratum: StringName, n: int, depth: int = 0) -> Dictionary:
	var report := LevelValidator.run_batch(stratum, n, depth)
	print("  # %s x%d: valid %d, retried %d, fallbacks %d, path %.0f m (%.0f..%.0f), walkable %.0f (%d..%d), %.1f ms/level (max %.0f)" % [
		stratum, report["count"], report["valid"], report["retried"], report["fallbacks"],
		report["path_m_mean"], report["path_m_min"], report["path_m_max"],
		report["walkable_mean"], report["walkable_min"], report["walkable_max"],
		report["ms_mean"], report["ms_max"]])
	assert_eq(report["count"], n)
	assert_eq(report["invalid"], 0, "levels shipped invalid: %s" % [report["failures"]])
	assert_eq(report["fallbacks"], 0, "no seed should need the simplest grammar")
	assert_budget(report["ms_mean"], float(Tuning.LEVELGEN_WORKER_BUDGET_MS), "mean ms per level")
	return report


func test_offices_seeds_validate() -> void:
	_batch(&"offices", SEEDS if full_run() else GATE_SEEDS)


func test_server_seeds_validate() -> void:
	_batch(&"server", SEEDS if full_run() else GATE_SEEDS)


## Offices appear at depths 3 to 5, Server at 4 to 5, both in Cycle 2 (+2 cells a side).
func test_other_depths_and_cycle_2() -> void:
	for stratum: StringName in [&"offices", &"server"]:
		var depths: Array[int] = [3, 4, 5]
		if stratum == &"server":
			depths = [4, 5]
		for depth in depths:
			for cycle in [1, 2]:
				for i in 3:
					var level := LevelGenerator.generate(stratum, depth + (6 if cycle == 2 else 0), 700 + i, false, cycle, OPTS)
					assert_true(level.failures.is_empty(), "%s depth %d cycle %d seed %d: %s" % [stratum, depth, cycle, 700 + i, level.failures])
					assert_false(level.fallback, "%s depth %d: no fallback" % [stratum, depth])
					assert_eq(level.grid.size.x, StratumGenerator.grid_side(depth, cycle))


## The simplest grammars (07 §1 rule 5) validate for most seeds.
func test_simplest_grammars() -> void:
	for stratum: StringName in [&"offices", &"server"]:
		var ok := 0
		for i in 10:
			var level := LevelGenerator.grammar_for(stratum).generate(stratum, 4, 40 + i, false, 1, {}, 9, true)
			if LevelValidator.validate(level).is_empty():
				ok += 1
		assert_gt(ok, 7, "%s simplest grammar" % stratum)


func _room_kinds(level: LevelData) -> Dictionary:
	var kinds := {}
	for r in level.grid.rooms():
		kinds[r.kind] = kinds.get(r.kind, 0) + 1
	return kinds


## 07 §5.4: the ring inset 3, 2 to 3 open offices with partition mazes, 6 to 10 small
## offices with doors, one glass meeting room, a breaker room always, 1 to 2 closets, 4
## soft walls, desks with monitors in 60% of cubicle cells (each an under_desk hide spot),
## chairs only in corridors, 40% of the fixture groups dark.
func test_offices_counts_match_the_grammar() -> void:
	for i in 12:
		var level := LevelGenerator.generate(&"offices", 3, 300 + i)
		var g := level.grid
		var kinds := _room_kinds(level)
		var inset := Tuning.OFFICES_RING_INSET
		for c in RingOps.ring_cells(Rect2i(inset, inset, g.size.x - inset * 2, g.size.y - inset * 2)):
			assert_eq(g.kind(c), LevelGrid.FLOOR, "ring cell %s" % c)
		var opens: int = kinds.get(OfficeRooms.OPEN, 0)
		assert_true(opens >= Tuning.OFFICES_OPEN_COUNT_MIN and opens <= Tuning.OFFICES_OPEN_COUNT_MAX, "open offices %d" % opens)
		var smalls: int = kinds.get(OfficeRooms.SMALL, 0)
		assert_true(smalls >= Tuning.OFFICES_SMALL_COUNT_MIN and smalls <= Tuning.OFFICES_SMALL_COUNT_MAX, "small offices %d" % smalls)
		assert_eq(kinds.get(OfficeRooms.MEETING, 0), 1)
		assert_eq(kinds.get(RoomData.BREAKER, 0), 1, "a breaker room whatever the lock")
		var closets: int = kinds.get(RoomData.CLOSET, 0)
		assert_true(closets >= Tuning.OFFICES_CLOSETS_MIN and closets <= Tuning.OFFICES_CLOSETS_MAX, "closets %d" % closets)
		assert_eq(level.soft_walls.size(), Tuning.OFFICES_SOFT_WALLS)
		var partitions := 0
		var cubicle_cells := 0
		for r in g.rooms():
			if r.kind == OfficeRooms.OPEN:
				cubicle_cells += r.rect.get_area()
				assert_true(r.rect.size.x >= mini(Tuning.OFFICES_OPEN_SIZE_MIN.x, Tuning.OFFICES_OPEN_SIZE_MIN.y))
				for c in r.cells():
					for d: int in [LevelGrid.E, LevelGrid.S]:
						if g.wall(c, d) == LevelGrid.PARTITION:
							partitions += 1
			if r.kind == OfficeRooms.SMALL:
				var doors := 0
				for e in r.perimeter_edges():
					doors += 1 if g.wall(Vector2i(e.x, e.y), e.z) == LevelGrid.DOOR else 0
				assert_eq(doors, 1, "small office %d has one door" % r.id)
		assert_gt(partitions, 40, "cubicle partitions")
		var desks := 0
		var monitors := 0
		for p in level.placements_of(LevelData.P_PROP):
			match p[&"params"][&"prop"]:
				&"desk":
					desks += 1
					assert_true(g.room_of(p[&"cell"]).kind == OfficeRooms.OPEN)
				&"monitor":
					monitors += 1
				&"chair":
					assert_eq(g.kind(p[&"cell"]), LevelGrid.FLOOR, "07 §5.4: chairs only in corridors")
		assert_eq(desks, monitors)
		assert_true(desks >= cubicle_cells * Tuning.OFFICES_DESK_FRACTION * 0.75 and desks <= ceili(cubicle_cells * Tuning.OFFICES_DESK_FRACTION) + 3,
			"desks %d of %d cubicle cells" % [desks, cubicle_cells])
		var under_desk := 0
		for p in level.placements_of(LevelData.P_HIDE_SPOT):
			if p[&"params"][&"kind"] == &"under_desk":
				under_desk += 1
		assert_eq(under_desk, desks, "each desk a hide spot host")
		var groups: Dictionary = {}
		var dark: Dictionary = {}
		for p in level.placements_of(LevelData.P_FIXTURE):
			groups[p[&"params"][&"group"]] = true
			if p[&"params"].get(&"dark", false):
				dark[p[&"params"][&"group"]] = true
		var frac := float(dark.size()) / groups.size()
		assert_true(absf(frac - Tuning.OFFICES_DARK_GROUP_FRACTION) < 0.08, "dark group fraction %.2f" % frac)


## 07 §5.5: rows of racks 6 to 12 long, 2 to 4 cages each with a gate and an item, three
## rack-gap nooks, no soft walls, a 3x3 exit clearing with one white light, emergency boxes
## on the 6-cell lattice, no aisle straight for more than 12 cells.
func test_server_counts_match_the_grammar() -> void:
	for i in 12:
		var level := LevelGenerator.generate(&"server", 4, 300 + i)
		var g := level.grid
		var kinds := _room_kinds(level)
		var cages: int = kinds.get(ServerGenerator.CAGE, 0)
		assert_true(cages >= Tuning.SERVER_CAGES_MIN and cages <= Tuning.SERVER_CAGES_MAX, "cages %d" % cages)
		assert_eq(level.soft_walls.size(), 0, "07 §5.5: no soft walls")
		var gaps := 0
		for p in level.placements_of(LevelData.P_HIDE_SPOT):
			assert_eq(p[&"params"][&"kind"], &"rack_gap")
			var c: Vector2i = p[&"cell"]
			assert_eq(g.openings(c), 1, "a nook opens to one aisle")
			gaps += 1
		assert_eq(gaps, Tuning.SERVER_RACK_GAP_HIDE_SPOTS)
		assert_lt(StratumRules.longest_hall_run(level), Tuning.SERVER_AISLE_STRAIGHT_MAX + 1)
		var exit_room := g.room_of(level.exit_cell)
		assert_eq(exit_room.rect.size, Tuning.SERVER_EXIT_ROOM_SIZE)
		var racks := 0
		for k in g.cells:
			racks += 1 if k == LevelGrid.RACK else 0
		assert_gt(racks, 150, "rack cells")
		for p in level.placements_of(LevelData.P_FIXTURE):
			if p[&"params"][&"fixture"] == ServerFurnish.EMERGENCY:
				var c: Vector2i = p[&"cell"]
				assert_true(posmod(c.x, Tuning.SERVER_EMERGENCY_SPACING_CELLS) == 0 or posmod(c.y, Tuning.SERVER_EMERGENCY_SPACING_CELLS) == 0,
					"emergency box %s on the lattice" % c)
		assert_eq(level.placements_of(LevelData.P_EXIT)[0][&"params"][&"exit_kind"], &"floor_hatch")


## Rule 10 sees what 07 forbids: a cage without its gate, glass off the meeting room, a
## partition outside an open office, a straight aisle.
func test_rule_10_catches_broken_levels() -> void:
	var server := LevelGenerator.generate(&"server", 4, 5)
	assert_true(server.failures.is_empty(), "%s" % server.failures)
	for r in server.grid.rooms():
		if r.kind == ServerGenerator.CAGE:
			var e: Vector3i = r.doors[0]
			server.grid.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.GLASS)
			break
	assert_true(_has(LevelValidator.validate(server), "has no gate"))
	var offices := LevelGenerator.generate(&"offices", 3, 5)
	assert_true(offices.failures.is_empty(), "%s" % offices.failures)
	var g := offices.grid
	var corridor := Vector2i(-1, -1)
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) == LevelGrid.FLOOR and g.room_of(c) == null and g.wall(c, LevelGrid.N) == LevelGrid.WALL \
				and g.room_of(c + LevelGrid.DIRS[LevelGrid.N]) == null:
			corridor = c
			break
	g.set_wall(corridor, LevelGrid.N, LevelGrid.GLASS)
	assert_true(_has(LevelValidator.validate(offices), "off the meeting room"))
	g.set_wall(corridor, LevelGrid.N, LevelGrid.PARTITION)
	assert_true(_has(LevelValidator.validate(offices), "outside an open office"))


func _has(failures: PackedStringArray, text: String) -> bool:
	for f in failures:
		if f.contains(text):
			return true
	return false
