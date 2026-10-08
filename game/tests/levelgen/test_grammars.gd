extends TestCase
## 07 §10: every grammar validates for 1,000 seeds (after retries) within the worker budget.
## The per-merge gate runs GATE_SEEDS per stratum; the checkpoint script (NOCLIP_FULL_TESTS=1,
## tools/ci/checkpoint.sh) runs the full 1,000 and enforces the worker-time budget.

const SEEDS := Tuning.VALIDATE_SEEDS_PER_STRATUM
const GATE_SEEDS := 300


func test_halls_1000_seeds_validate() -> void:
	var n := SEEDS if full_run() else GATE_SEEDS
	var report := LevelValidator.run_batch(&"halls", n)
	print("  # halls x%d: valid %d, retried %d, fallbacks %d, path %.0f m (%.0f..%.0f), walkable %.0f (%d..%d), %.1f ms/level (max %.0f)" % [
		report["count"], report["valid"], report["retried"], report["fallbacks"],
		report["path_m_mean"], report["path_m_min"], report["path_m_max"],
		report["walkable_mean"], report["walkable_min"], report["walkable_max"],
		report["ms_mean"], report["ms_max"]])
	assert_eq(report["count"], n)
	assert_eq(report["invalid"], 0, "levels shipped invalid: %s" % [report["failures"]])
	assert_eq(report["fallbacks"], 0, "no seed should need the simplest grammar")
	# 07 §3: layout and placement under 300 ms on the worker thread.
	assert_budget(report["ms_mean"], float(Tuning.LEVELGEN_WORKER_BUDGET_MS), "mean ms per level")


## Halls only appears at depth 1 in a Descent, but the grammar must hold at every grid size
## (Endless and the Substrate reuse it): a smaller sample per depth and Cycle.
func test_halls_other_depths_and_cycle_2() -> void:
	var opts := {&"fuse_unlocked": true, &"item_pool": Tuning.ITEM_KINDS}
	for depth in [2, 3, 4, 5, 6]:
		for cycle in [1, 2]:
			for i in 4:
				var level := LevelGenerator.generate(&"halls", depth, 500 + i, false, cycle, opts)
				assert_true(level.failures.is_empty(), "depth %d cycle %d seed %d: %s" % [depth, cycle, 500 + i, level.failures])
				assert_eq(level.grid.size.x, StratumGenerator.grid_side(depth, cycle))


func test_first_descent_guarantees() -> void:
	for i in 20:
		var level := LevelGenerator.generate(&"halls", 1, 9000 + i, true)
		assert_true(level.failures.is_empty(), "seed %d: %s" % [9000 + i, level.failures])
		assert_eq(level.exit_lock, Tuning.LOCK_POWERED, "05 §10: first Descent depth 1 is Powered")
		var polaroids := 0
		for p in level.placements_of(LevelData.P_ITEM):
			if p[&"params"][&"item"] == &"polaroid":
				polaroids += 1
		assert_gt(polaroids, 0, "05 §10: one Polaroid")


func test_halls_counts_match_the_grammar() -> void:
	for i in 20:
		var level := LevelGenerator.generate(&"halls", 1, 300 + i)
		var g := level.grid
		var kinds := {}
		for r in g.rooms():
			kinds[r.kind] = kinds.get(r.kind, 0) + 1
		assert_eq(kinds.get(RoomData.SPAWN, 0), 1)
		assert_eq(kinds.get(RoomData.EXIT, 0), 1)
		assert_eq(kinds.get(RoomData.BREAKER, 0), 1 if level.exit_lock == Tuning.LOCK_POWERED else 0)
		var closets: int = kinds.get(RoomData.CLOSET, 0)
		assert_true(closets >= Tuning.HALLS_CLOSETS_MIN and closets <= Tuning.HALLS_CLOSETS_MAX, "closets %d" % closets)
		assert_true(g.rooms().size() <= Tuning.HALLS_ROOMS_MAX, "rooms %d" % g.rooms().size())
		assert_eq(level.soft_walls.size(), Tuning.HALLS_SOFT_WALLS)
		assert_eq(level.placements_of(LevelData.P_HIDE_SPOT).size(), Tuning.HALLS_HIDE_SPOTS)
		assert_eq(level.placements_of(LevelData.P_NOTE).size(), Tuning.NOTES_PER_LEVEL)
		var payphones := 0
		for p in level.placements_of(LevelData.P_PROP):
			if p[&"params"][&"prop"] == &"payphone" and g.kind(p[&"cell"]) == LevelGrid.FLOOR:
				payphones += 1
		assert_eq(payphones, Tuning.HALLS_PAYPHONES_PER_LEVEL, "one payphone on a corridor wall")
		for id: int in g.fixture_groups():
			assert_true(g.fixture_groups()[id].size() <= Tuning.HALLS_GROUP_MAX_FIXTURES, "group %d too big" % id)


## M2.3: every stratum has a grammar now; an unknown id is still reported unsupported.
func test_unbuilt_stratum_is_reported_unsupported() -> void:
	assert_true(LevelGenerator.supports(&"substrate"))
	assert_false(LevelGenerator.supports(&"nowhere"))
	var r := LevelValidator.run_batch(&"nowhere", 3)
	assert_false(r["supported"])
	assert_eq(r["count"], 0)


func _batch(stratum: StringName, n: int, depth: int = 0) -> void:
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


func test_pools_seeds_validate() -> void:
	_batch(&"pools", SEEDS if full_run() else GATE_SEEDS)


func test_garage_seeds_validate() -> void:
	_batch(&"garage", SEEDS if full_run() else GATE_SEEDS)


## Pools and Garage appear at depths 2 to 5 and in Cycle 2 (+2 cells a side).
func test_pools_and_garage_other_depths_and_cycle_2() -> void:
	var opts := {&"fuse_unlocked": true, &"item_pool": Tuning.ITEM_KINDS}
	for stratum: StringName in [&"pools", &"garage"]:
		for depth in [2, 3, 4, 5]:
			for cycle in [1, 2]:
				for i in 3:
					var level := LevelGenerator.generate(stratum, depth + (6 if cycle == 2 else 0), 700 + i, false, cycle, opts)
					assert_true(level.failures.is_empty(), "%s depth %d cycle %d seed %d: %s" % [stratum, depth, cycle, 700 + i, level.failures])
					assert_false(level.fallback, "%s depth %d: no fallback" % [stratum, depth])


## The simplest grammar (07 §1 rule 5) of both strata validates for most seeds (the
## generator tries up to LevelGenerator.FALLBACK_TRIES of them).
func test_pools_and_garage_simplest_grammar() -> void:
	for stratum: StringName in [&"pools", &"garage"]:
		var ok := 0
		for i in 10:
			var level := LevelGenerator.grammar_for(stratum).generate(stratum, 2, 40 + i, false, 1, {}, 9, true)
			if LevelValidator.validate(level).is_empty():
				ok += 1
		assert_gt(ok, 5, "%s simplest grammar: %d of 10 valid" % [stratum, ok])


## 07 §5.2: halls on a spine with basins (inset 2, three depths, steps), pump rooms with
## their hide spots, the exit at the bottom of a dry 1.8 m basin, three soft walls.
func test_pools_counts_match_the_grammar() -> void:
	for i in 20:
		var level := LevelGenerator.generate(&"pools", 2, 300 + i)
		var g := level.grid
		var halls := 0
		var pumps := 0
		for r in g.rooms():
			if r.kind == PoolsGenerator.HALL or r.kind == RoomData.EXIT:
				halls += 1
				# Every hall has a sunken basin, its rect inset by POOLS_BASIN_INSET.
				var b := r.rect.grow(-Tuning.POOLS_BASIN_INSET)
				var depth := -g.floor_y(b.position)
				var known := false
				for d in Tuning.POOLS_BASIN_DEPTHS:
					known = known or absf(d - depth) < 0.001
				assert_true(known, "basin depth %.2f" % depth)
				var steps := 0
				for c in RoomData.new(b).cells():
					if g.kind(c) == LevelGrid.RAMP:
						steps += 1
				assert_eq(steps, Tuning.POOLS_RAMP_CELLS, "steps in the basin of room %d" % r.id)
			elif r.kind == PoolsGenerator.PUMP:
				pumps += 1
		assert_true(halls >= 3 and halls <= Tuning.POOLS_HALLS_MAX, "halls %d" % halls)
		assert_true(pumps >= Tuning.POOLS_PUMP_ROOMS_MIN and pumps <= Tuning.POOLS_PUMP_ROOMS_MAX, "pumps %d" % pumps)
		assert_eq(level.placements_of(LevelData.P_HIDE_SPOT).size(), pumps)
		for p in level.placements_of(LevelData.P_HIDE_SPOT):
			assert_eq(p[&"params"][&"kind"], &"pump_corner")
		assert_eq(g.kind(level.exit_cell), LevelGrid.BASIN)
		assert_approx(g.floor_y(level.exit_cell), -Tuning.POOLS_EXIT_BASIN_DEPTH, 0.001)
		assert_false(g.has_flag(level.exit_cell, LevelGrid.F_WATER), "the exit basin is dry")
		assert_eq(level.soft_walls.size(), Tuning.POOLS_SOFT_WALLS)
		assert_eq(level.placements_of(LevelData.P_EXIT)[0][&"params"][&"exit_kind"], &"drain_hatch")


## Deep full basins are DEEP (not walkable) except their steps; water placements cover wet
## basins at the right level.
func test_pools_water_and_deep_basins() -> void:
	var deep := 0
	var wet := 0
	for i in 40:
		var level := LevelGenerator.generate(&"pools", 2, 900 + i)
		var g := level.grid
		for p in level.placements_of(LevelData.P_WATER):
			wet += 1
			var r: Rect2i = p[&"params"][&"rect"]
			var surface: float = p[&"params"][&"surface_y"]
			var bottom: float = p[&"params"][&"floor_y"]
			assert_gt(surface, bottom)
			assert_lt(surface, 0.0, "water stays under the rim")
			for c in RoomData.new(r).cells():
				assert_true(g.has_flag(c, LevelGrid.F_WATER))
				if g.kind(c) == LevelGrid.DEEP:
					deep += 1
					assert_gt(surface - bottom, Tuning.POOLS_WADE_LIMIT - 0.2, "only deep water is DEEP")
					assert_false(g.is_walkable(c))
	assert_gt(wet, 20)
	assert_gt(deep, 0, "some full 1.8 m basins")


## 07 §5.3 (split-level, CHANGELOG M2.1): two decks at 0 and +3.2 m joined by 2 to 3
## ramps of 4 cells; spawn lobby on deck 1, exit core on deck 0; pillars every 4 cells;
## cars are under-car hide spots; the exit sign above the stairwell door.
func test_garage_counts_match_the_grammar() -> void:
	for i in 20:
		var level := LevelGenerator.generate(&"garage", 2, 300 + i)
		var g := level.grid
		assert_eq(g.deck[g.idx(level.spawn_cell)], 1)
		assert_eq(g.deck[g.idx(level.exit_cell)], 0)
		assert_approx(g.floor_y(level.spawn_cell), Tuning.GARAGE_DECK_RISE, 0.001)
		assert_approx(g.floor_y(level.exit_cell), 0.0, 0.001)
		var ramps := StratumShots.run_starts(g).size()
		assert_true(ramps >= Tuning.GARAGE_RAMPS_MIN and ramps <= Tuning.GARAGE_RAMPS_MAX, "ramps %d" % ramps)
		var pillars := 0
		for k in g.cell_count():
			if g.is_pillar(g.cell_at(k)):
				pillars += 1
		assert_gt(pillars, 4)
		var cars := 0
		var signs := 0
		for p in level.placements_of(LevelData.P_PROP):
			match p[&"params"][&"prop"]:
				&"car":
					cars += 1
				&"exit_sign":
					signs += 1
					assert_eq(p[&"cell"], level.exit_cell)
		assert_eq(signs, 1, "exit sign only above the real exit")
		assert_eq(level.placements_of(LevelData.P_HIDE_SPOT).size(), cars)
		assert_gt(cars, 4)
		assert_eq(level.soft_walls.size(), Tuning.GARAGE_SOFT_WALLS)
		for e in level.soft_walls:
			assert_eq(g.wall(Vector2i(e.x, e.y), e.z), LevelGrid.SOFT)
			assert_approx(g.floor_y(Vector2i(e.x, e.y)), g.floor_y(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]), 0.001, "a soft wall joins one floor level")
		assert_eq(level.placements_of(LevelData.P_EXIT)[0][&"params"][&"exit_kind"], &"stairwell_door")


## A Keyed Garage puts the keycard on deck 1, the other deck from the exit (07 §5.3).
func test_garage_keycard_on_the_other_deck() -> void:
	var seen := 0
	for i in 60:
		var level := LevelGenerator.generate(&"garage", 2, 1200 + i)
		if level.exit_lock != Tuning.LOCK_KEYED:
			continue
		seen += 1
		assert_eq(level.grid.deck[level.grid.idx(level.keycard_cell)], 1)
		assert_eq(level.placements_of(LevelData.P_KEYCARD).size(), 1)
	assert_gt(seen, 5)
