extends TestCase
## 07 §10: every grammar validates for 1,000 seeds (after retries) within the worker budget.
## Only Halls exists so far (M1.1); later grammars add a line here.

const SEEDS := Tuning.VALIDATE_SEEDS_PER_STRATUM


func test_halls_1000_seeds_validate() -> void:
	var report := LevelValidator.run_batch(&"halls", SEEDS)
	print("  # halls x%d: valid %d, retried %d, fallbacks %d, path %.0f m (%.0f..%.0f), walkable %.0f (%d..%d), %.1f ms/level (max %.0f)" % [
		report["count"], report["valid"], report["retried"], report["fallbacks"],
		report["path_m_mean"], report["path_m_min"], report["path_m_max"],
		report["walkable_mean"], report["walkable_min"], report["walkable_max"],
		report["ms_mean"], report["ms_max"]])
	assert_eq(report["count"], SEEDS)
	assert_eq(report["invalid"], 0, "levels shipped invalid: %s" % [report["failures"]])
	assert_eq(report["fallbacks"], 0, "no seed should need the simplest grammar")
	# 07 §3: layout and placement under 300 ms on the worker thread.
	assert_lt(report["ms_mean"], float(Tuning.LEVELGEN_WORKER_BUDGET_MS))


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


func test_unbuilt_stratum_is_reported_unsupported() -> void:
	assert_false(LevelGenerator.supports(&"pools"))
	var r := LevelValidator.run_batch(&"pools", 3)
	assert_false(r["supported"])
	assert_eq(r["count"], 0)
