extends TestCase
## M2.3: the Substrate grammar (07 §5.6) and Cycle 2 corruption (07 §9, 02 §7). The Substrate
## validates for GATE_SEEDS seeds in the merge gate and 1,000 in the checkpoint run
## (NOCLIP_FULL_TESTS=1) with no fallback; its shapes match 07 §5.6 (the pocket, the unfinish
## step, studio lights, no doors, locks or hide spots, Null's and the Statics' spawns); the
## validator's rule 10 catches what it should; it is byte-deterministic on a worker thread;
## and every ordinary stratum in Cycle 2 validates with its corruption in place.

const SEEDS := Tuning.VALIDATE_SEEDS_PER_STRATUM
const GATE_SEEDS := 300
const OPTS := {&"fuse_unlocked": true, &"item_pool": Tuning.ITEM_KINDS}
## Each ordinary stratum's first Cycle 1 depth (Cycle 2 adds 6).
const FIRST_DEPTH := {&"halls": 1, &"pools": 2, &"garage": 2, &"offices": 3, &"server": 4}

var _hashes: Dictionary = {}


func test_substrate_seeds_validate() -> void:
	var n := SEEDS if full_run() else GATE_SEEDS
	var report := LevelValidator.run_batch(&"substrate", n)
	print("  # substrate x%d: valid %d, retried %d, fallbacks %d, path %.0f m (%.0f..%.0f), walkable %.0f (%d..%d), %.1f ms/level (max %.0f)" % [
		report["count"], report["valid"], report["retried"], report["fallbacks"],
		report["path_m_mean"], report["path_m_min"], report["path_m_max"],
		report["walkable_mean"], report["walkable_min"], report["walkable_max"], report["ms_mean"], report["ms_max"]])
	assert_eq(report["count"], n)
	assert_eq(report["invalid"], 0, "levels shipped invalid: %s" % [report["failures"]])
	assert_eq(report["fallbacks"], 0, "no seed should need the simplest grammar")
	assert_gt(report["path_m_min"], Tuning.SUBSTRATE_PATH_MIN - 0.01)
	assert_lt(report["path_m_max"], Tuning.SUBSTRATE_PATH_MAX + 0.01)
	assert_budget(report["ms_mean"], float(Tuning.LEVELGEN_WORKER_BUDGET_MS), "mean ms per level")


## Cycle 2 (depth 12; even Cycles alternate Offices modules) and Cycle 3 (depth 18).
func test_substrate_later_cycles() -> void:
	for cycle in [2, 3]:
		for i in 6:
			var level := LevelGenerator.generate(&"substrate", 6 * cycle, 900 + i, false, cycle, OPTS)
			var tag := "cycle %d seed %d" % [cycle, 900 + i]
			assert_true(level.failures.is_empty(), "%s: %s" % [tag, level.failures])
			assert_false(level.fallback, tag)
			assert_eq(level.grid.size.x, StratumGenerator.grid_side(6, cycle))
			var offices := 0
			var partitions := 0
			for r in level.grid.rooms():
				if r.kind == OfficeRooms.OPEN:
					offices += 1
					for c in r.cells():
						if level.grid.wall(c, LevelGrid.E) == LevelGrid.PARTITION:
							partitions += 1
			if cycle == 2:
				assert_gt(offices, 0, tag + ": Offices modules alternate with Halls rooms")
				assert_gt(partitions, 0, tag + ": a cubicle maze")
			else:
				assert_eq(offices, 0, tag + ": odd Cycles are Halls")
			var statics := 0
			for p in level.placements_of(LevelData.P_ERROR_SPAWN):
				statics += 1 if p[&"params"].get(&"error", &"") == &"static" else 0
			assert_eq(statics, Tuning.SUBSTRATE_STATIC_COUNT + Tuning.CYCLE2_EXTRA_STATIC, tag + ": one more Static")
			assert_eq(level.soft_walls.size(), Tuning.SUBSTRATE_SOFT_WALLS + Tuning.CYCLE2_EXTRA_SOFT_WALLS)


## 07 §5.6 and 02 §7, seed by seed.
func test_substrate_matches_the_grammar() -> void:
	for i in 12:
		var level := LevelGenerator.generate(&"substrate", 6, 300 + i)
		var g := level.grid
		var tag := "seed %d" % (300 + i)
		assert_true(level.failures.is_empty(), "%s: %s" % [tag, level.failures])
		assert_eq(g.size, Vector2i(28, 28), "07 §5.6: 28x28")
		assert_eq(level.exit_lock, Tuning.LOCK_OPEN, "no lock")
		assert_true(level.floor_solid, "the floor is solid (no drops)")
		var pocket := g.room_of(level.exit_cell)
		assert_eq(pocket.kind, RoomData.POCKET)
		assert_eq(pocket.rect.size, Tuning.SUBSTRATE_THRESHOLD_POCKET_SIZE)
		assert_eq(level.exit_cell, pocket.center(), "the door stands alone at the pocket's centre")
		var exit: Dictionary = level.placements_of(LevelData.P_EXIT)[0]
		assert_eq(exit[&"params"][&"exit_kind"], &"threshold_door")
		# The door faces the way the critical path comes into the pocket.
		var path := level.critical_path
		var k := path.size() - 1
		while k > 0 and pocket.has_cell(path[k - 1]):
			k -= 1
		var came_from := path[k - 1] - path[k] if k > 0 else Vector2i.ZERO
		assert_eq(LevelGrid.DIRS[int(exit[&"params"][&"dir"])], came_from, tag + ": the door faces the way in")
		assert_true(level.placements_of(LevelData.P_HIDE_SPOT).is_empty())
		assert_eq(level.soft_walls.size(), Tuning.SUBSTRATE_SOFT_WALLS)
		# Studio lights: one in the spawn room, one in the pocket, 6 to 10 in all.
		var lights := level.placements_of(LevelData.P_FIXTURE)
		assert_true(lights.size() >= Tuning.SUBSTRATE_STUDIO_LIGHTS_MIN and lights.size() <= Tuning.SUBSTRATE_STUDIO_LIGHTS_MAX)
		var in_spawn := 0
		var in_pocket := 0
		for p in lights:
			assert_eq(p[&"params"][&"fixture"], &"studio_light", "07 §5.6: no other fixture")
			in_spawn += 1 if g.has_flag(p[&"cell"], LevelGrid.F_SPAWN_ROOM) else 0
			in_pocket += 1 if pocket.has_cell(p[&"cell"]) else 0
		assert_eq(in_spawn, 1, tag + ": the spawn room has its light")
		assert_eq(in_pocket, 1, tag + ": the pocket always has one")
		# The unfinish step.
		var frac := StratumRules.void_fraction(level)
		assert_true(frac >= Tuning.SUBSTRATE_VOID_FRACTION_MIN and frac <= Tuning.SUBSTRATE_VOID_FRACTION_MAX, "%s void %.2f" % [tag, frac])
		for chain in MazeOps.dead_end_chains(g):
			var soft_tip := false
			for d in 4:
				soft_tip = soft_tip or g.wall(chain[0], d) == LevelGrid.SOFT
			assert_true(chain.size() <= Tuning.NULL_DEAD_END_MAX_CELLS or soft_tip, "%s dead end of %d" % [tag, chain.size()])
		var unfinished := 0
		for c2 in range(g.cell_count()):
			if LevelGrid.kind_walkable(g.cells[c2]) and (g.flags[c2] & LevelGrid.F_UNFINISHED) != 0:
				unfinished += 1
		var share := float(unfinished) / g.walkable_count()
		assert_true(share >= 0.25 and share <= 0.45, "%s unfinished %.2f (30%% in whole units)" % [tag, share])
		var offset := 0
		for r in g.rooms():
			var flagged := 0
			for c in r.cells():
				flagged += 1 if g.has_flag(c, LevelGrid.F_UNFINISHED) else 0
			assert_true(flagged == 0 or flagged == r.rect.get_area(), "%s room %d unfinished partly" % [tag, r.id])
			var y := g.floor_y(r.rect.position)
			if absf(y) > 0.001:
				offset += 1
				assert_approx(absf(y), Tuning.SUBSTRATE_FLOOR_OFFSET, 0.0001)
				assert_true(r.kind != RoomData.SPAWN and r.kind != RoomData.POCKET, "the spawn room and pocket stay level")
		assert_eq(offset, roundi((g.rooms().size() - 2) * Tuning.SUBSTRATE_FLOOR_OFFSET_FRACTION), tag + ": 25% of rooms float")
		# Null on the critical path at 55%, at least 20 m away; Statics off the path.
		var at := path.find(level.null_spawn_cell)
		assert_gt(at, -1, tag + ": Null on the critical path")
		assert_true(at >= roundi((path.size() - 1) * Tuning.NULL_SPAWN_PATH_FRACTION), "%s Null at %d of %d" % [tag, at, path.size()])
		assert_gt(at * Tuning.GRID_CELL_SIZE, Tuning.NULL_SPAWN_MIN_DIST - 0.01)


## 07 §5.6: a floating room's straight doorway corridor becomes a ramp within the climb.
func test_floating_rooms_have_doorway_ramps() -> void:
	var ramps := 0
	for i in 8:
		var level := LevelGenerator.generate(&"substrate", 6, 40 + i)
		var g := level.grid
		for c in range(g.cell_count()):
			if g.cells[c] != LevelGrid.RAMP:
				continue
			ramps += 1
			var cell := g.cell_at(c)
			# GridHeights.set_ramp: the slope spans the cell interior (the strips stay flat).
			var rise := g.ramp_grade[c] * (Tuning.GRID_CELL_SIZE - Tuning.GRID_WALL_THICKNESS)
			assert_approx(rise, Tuning.SUBSTRATE_FLOOR_OFFSET, 0.001, "a ramp climbs one offset")
			assert_true(g.ramp_dir_of(cell) >= 0)
		for c in range(g.cell_count()):
			assert_eq(g.ledges[c], 0, "every step in the Substrate is within the climb")
	assert_gt(ramps, 0, "some doorways ramp")


func test_validator_rule_10_catches() -> void:
	var base := LevelGenerator.generate(&"substrate", 6, 5)
	assert_true(base.failures.is_empty(), "%s" % [base.failures])
	# A wall to VOID that is not SOLID.
	var a := LevelGenerator.generate(&"substrate", 6, 5)
	var g := a.grid
	var done := false
	for i in g.cell_count():
		var c := g.cell_at(i)
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if not done and g.is_walkable(c) and g.in_bounds(o) and g.kind(o) == LevelGrid.VOID and g.wall(c, d) == LevelGrid.SOLID:
				g.set_wall(c, d, LevelGrid.WALL)
				done = true
	assert_true(_has(LevelValidator.validate(a), "to VOID is not SOLID"))
	# The pocket's light gone.
	var b := LevelGenerator.generate(&"substrate", 6, 5)
	var kept: Array[Dictionary] = []
	for p in b.placements:
		if not (p[&"kind"] == LevelData.P_FIXTURE and b.grid.has_flag(p[&"cell"], LevelGrid.F_EXIT_ROOM)):
			kept.append(p)
	b.placements = kept
	assert_true(_has(LevelValidator.validate(b), "pocket is not lit"))
	# Too little VOID.
	var c3 := LevelGenerator.generate(&"substrate", 6, 5)
	c3.unfinished_void = c3.unfinished_void.slice(0, 3)
	assert_true(_has(LevelValidator.validate(c3), "VOID fraction"))
	# A dead end longer than 4 cells: a corridor of 6 cells carved into the void, open at one end.
	var d := LevelGenerator.generate(&"substrate", 6, 5)
	assert_true(_carve_dead_end(d.grid, 6), "room for a long dead end")
	assert_true(_has(LevelValidator.validate(d), "Substrate dead end"))
	# Null off the critical path.
	var e := LevelGenerator.generate(&"substrate", 6, 5)
	e.null_spawn_cell = e.spawn_cell
	assert_true(_has(LevelValidator.validate(e), "Null's spawn"))


func _has(f: PackedStringArray, text: String) -> bool:
	for line in f:
		if line.contains(text):
			return true
	return false


## Carves a straight dead-end corridor of `n` cells into VOID next to a walkable cell.
func _carve_dead_end(g: LevelGrid, n: int) -> bool:
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR:
			continue
		for d in 4:
			var ok := true
			for k in range(1, n + 2):
				var o := c + LevelGrid.DIRS[d] * k
				ok = ok and g.in_bounds(o) and g.kind(o) == LevelGrid.VOID
			if not ok:
				continue
			for k in range(1, n + 1):
				var o := c + LevelGrid.DIRS[d] * k
				g.set_kind(o, LevelGrid.FLOOR)
				for dd in 4:
					g.set_wall(o, dd, LevelGrid.SOLID)
				g.set_wall(o, LevelGrid.opposite(d), LevelGrid.NONE)
			return true
	return false


func test_substrate_is_deterministic() -> void:
	for s in [1, 2, 77, -5]:
		var a := LevelGenerator.generate(&"substrate", 6, s)
		var b := LevelGenerator.generate(&"substrate", 6, s)
		assert_eq(a.to_bytes(), b.to_bytes(), "seed %d bytes" % s)
		assert_eq(a.to_ascii(), b.to_ascii(), "seed %d ascii" % s)
	assert_ne(LevelGenerator.generate(&"substrate", 6, 1).hash_hex(), LevelGenerator.generate(&"substrate", 6, 2).hash_hex())
	var main := {}
	for key: String in ["substrate:6:1", "halls:7:2", "server:10:2", "substrate:12:2"]:
		var parts := key.split(":")
		main[key] = LevelGenerator.generate(StringName(parts[0]), int(parts[1]), 4242, false, int(parts[2]), OPTS).hash_hex()
	var task := WorkerThreadPool.add_task(_on_worker.bind(main.keys()))
	WorkerThreadPool.wait_for_task_completion(task)
	for key: String in main:
		assert_eq(_hashes.get(key, ""), main[key], "%s on a worker" % key)


func _on_worker(keys: Array) -> void:
	for key: String in keys:
		var parts := key.split(":")
		_hashes[key] = LevelGenerator.generate(StringName(parts[0]), int(parts[1]), 4242, false, int(parts[2]), OPTS).hash_hex()


## 07 §9, 02 §7: every ordinary stratum in Cycle 2 validates (no fallback) with its
## corruption: corridor fixtures removed, about a quarter of the rest dead, about a tenth of
## the surfaces flagged UNFINISHED in whole units, one more error spawn point than Cycle 1,
## the spawn and exit rooms untouched.
func test_cycle2_every_stratum() -> void:
	for stratum: StringName in FIRST_DEPTH:
		for i in 4:
			var seed_value := 500 + i
			var depth: int = FIRST_DEPTH[stratum] + Tuning.RUN_CYCLE_LENGTH
			var c2 := LevelGenerator.generate(stratum, depth, seed_value, false, 2, OPTS)
			var tag := "%s cycle 2 seed %d" % [stratum, seed_value]
			assert_true(c2.failures.is_empty(), "%s: %s" % [tag, c2.failures])
			assert_false(c2.fallback, tag)
			assert_eq(c2.grid.size.x, StratumGenerator.grid_side(FIRST_DEPTH[stratum], 2), tag + ": +2 a side")
			var fixtures := c2.placements_of(LevelData.P_FIXTURE)
			var dead := 0
			for p in fixtures:
				dead += 1 if p[&"params"].get(&"dead", false) else 0
			if fixtures.size() >= 8:
				assert_true(dead > 0 and dead <= ceili(fixtures.size() * Tuning.CYCLE2_FIXTURES_DARK) + 1, "%s dead %d of %d" % [tag, dead, fixtures.size()])
			var marked := 0
			for c in range(c2.grid.cell_count()):
				marked += 1 if (c2.grid.flags[c] & LevelGrid.F_UNFINISHED) != 0 else 0
			assert_gt(marked, 0, tag + ": unfinished patches")
			assert_eq(c2.placements_of(LevelData.P_ERROR_SPAWN).size(), Tuning.VALIDATE_ERROR_SPAWNS_MIN + 2 + Tuning.CYCLE2_EXTRA_STATIC,
				tag + ": one more spawn point (an extra Static)")
			for g: int in c2.grid.groups:
				assert_false((c2.grid.groups[g] as Array).is_empty(), tag + ": no empty fixture group")


## 07 §9 on a Cycle 1 Halls level run through Cycle2Ops: a tenth of the corridor fixtures go,
## a quarter of the rest die, the spawn and exit rooms keep theirs, groups stay whole.
func test_cycle2_ops_on_a_level() -> void:
	var gen := HallsGenerator.new()
	var level := gen.generate(&"halls", 1, 11, false, 1, {}, 0, false)
	var g := level.grid
	var corridor_before := 0
	var total_before := 0
	for p in level.placements_of(LevelData.P_FIXTURE):
		total_before += 1
		corridor_before += 1 if g.kind(p[&"cell"]) == LevelGrid.FLOOR else 0
	var host := StratumGenerator.new()
	host.data = level
	host.grid = g
	Cycle2Ops.corrupt(host, make_rng(3))
	var corridor_after := 0
	var dead := 0
	var total_after := 0
	for p in level.placements_of(LevelData.P_FIXTURE):
		total_after += 1
		corridor_after += 1 if g.kind(p[&"cell"]) == LevelGrid.FLOOR else 0
		if p[&"params"].get(&"dead", false):
			dead += 1
			assert_false(g.has_flag(p[&"cell"], LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM))
	assert_eq(corridor_before - corridor_after, roundi(corridor_before * Tuning.CYCLE2_FIXTURES_REMOVED), "07 §9: 10% removed")
	assert_eq(total_before - total_after, corridor_before - corridor_after, "only corridor fixtures go")
	assert_gt(dead, roundi(total_after * Tuning.CYCLE2_FIXTURES_DARK) - 4, "02 §7: about a quarter dark")
	assert_true(dead <= roundi(total_after * Tuning.CYCLE2_FIXTURES_DARK))
	var held := {}
	for p in level.placements_of(LevelData.P_FIXTURE):
		held[p[&"cell"]] = true
	for gid: int in g.groups:
		for c: Vector2i in g.groups[gid]:
			assert_true(held.has(c), "group %d lists a removed fixture" % gid)


func test_hue_toward_turns_twelve_degrees() -> void:
	var halls := Color("#FFEFC2")
	var pools := Color("#DDF0EE")
	var turned := Cycle2Ops.hue_toward(halls, pools)
	var delta := wrapf(turned.h - halls.h, -0.5, 0.5) * 360.0
	assert_approx(absf(delta), Tuning.CYCLE2_FIXTURE_HUE_SHIFT, 0.5, "02 §7: 12 degrees")
	assert_true(signf(delta) == signf(wrapf(pools.h - halls.h, -0.5, 0.5)), "towards the next stratum's hue")
	assert_approx(turned.s, halls.s, 0.001, "palette kept")
	assert_approx(turned.v, halls.v, 0.001)
	assert_eq(Cycle2Ops.hue_toward(halls, Color.WHITE), halls, "a grey target leaves the hue")
	assert_eq(Cycle2Ops.next_stratum(&"halls"), &"pools")
	assert_eq(Cycle2Ops.next_stratum(&"server"), &"halls", "wraps over the five ordinary strata")


func test_cycle2_materials_and_fog() -> void:
	var halls := load("res://data/strata/halls.tres") as StratumData
	var m1 := LevelMaterials.for_level(halls, BuildPlan.C_WALL, 1)
	var m2 := LevelMaterials.for_level(halls, BuildPlan.C_WALL, 2) as ShaderMaterial
	assert_eq(m1, LevelMaterials.for_class(halls, BuildPlan.C_WALL), "Cycle 1 is untouched")
	assert_ne(m2, m1)
	assert_approx(float(m2.get_shader_parameter(&"jitter_floor")), Tuning.CYCLE2_JITTER_FLOOR)
	assert_approx(float(m2.get_shader_parameter(&"unfinished_u")), Tuning.CYCLE2_SURFACE_UNRENDER_U)
	assert_eq(LevelMaterials.for_level(halls, BuildPlan.C_WALL, 2), m2, "one shared twin")
	var env := StratumEnvironment.build(halls, &"medium")
	var before := env.volumetric_fog_density
	Level.apply_cycle2_fog(env)
	assert_approx(env.volumetric_fog_density, before * Tuning.CYCLE2_FOG_MULT, 0.0001, "02 §7: fog x1.3")
