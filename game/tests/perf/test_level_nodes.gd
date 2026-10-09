extends TestCase
## R19 (14 §10 "Nodes in a level ≤ 3,000"): every stratum at its largest depth in Cycle 2
## (Halls 7, Pools/Garage/Offices/Server 11 = Cycle 2's depth 5, the Substrate 12), built by
## the real run (run.tscn: the level, its prepared exit and pickups, the player, the
## Director's roster), counted as PerfProbe counts it (the level subtree). Offices was over
## at M3.5 (3,097: 144 under-desk hide spots at 6 nodes each); an under-desk hide spot is now
## 3 nodes (the host is its own StaticBody3D: shape, Interactable; view and exit points are
## transforms). Counts are deterministic, so they are asserted in the gate (Offices on two
## seeds; the checkpoint run on five).

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 60.0
## Stratum -> its largest depth in Cycle 2 (05 §2: Halls is always first, the Substrate last);
## Offices, the stratum over budget at M3.5, has its own test below.
const LARGEST: Dictionary = {
	&"halls": 7, &"pools": 11, &"garage": 11, &"server": 11, &"substrate": 12,
}
const UNDER_DESK_NODES := 3
const GATE_OFFICES_SEEDS := 2
const FULL_OFFICES_SEEDS := 5

var _meta: MetaState


func before_all() -> void:
	_meta = GameState.meta


func after_all() -> void:
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = _meta


## Seeds whose strata order puts `stratum` at `depth`, starting from `from`.
static func seeds_for(stratum: StringName, depth: int, count: int, from: int = 1) -> Array[int]:
	var out: Array[int] = []
	var s := from
	while out.size() < count and s < 20000:
		var order := GameState.strata_order_for(s)
		if order[posmod(depth - 1, Tuning.RUN_CYCLE_LENGTH)] == stratum:
			out.append(s)
		s += 1
	return out


## Builds `stratum` at `depth` with `run_seed` in a real run and returns the level's node count
## (-1 when the run never became playable).
func _count(stratum: StringName, depth: int, run_seed: int) -> Dictionary:
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	GameState.run.depth = depth
	GameState.run.max_depth = depth
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	add_child(run)
	var end := Time.get_ticks_msec() + int(TIMEOUT_S * 1000.0)
	while run.phase != Run.PHASE_PLAYING and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	var out := {&"nodes": -1, &"built": &"", &"under_desk": 0}
	if run.phase == Run.PHASE_PLAYING and run.level != null:
		# The Director's roster and the deferred marker frees settle within a few frames.
		await await_physics_frames(10)
		out[&"nodes"] = PerfProbe.level_node_count(run.level)
		out[&"built"] = run.data.stratum
		for s in run.level.find_children("*", "HideSpot", true, false):
			if (s as HideSpot).kind == HideSpot.KIND_UNDER_DESK:
				out[&"under_desk"] = int(out[&"under_desk"]) + 1
	run.queue_free()
	await await_frames(3)
	GameState.end_run(&"abandon")
	return out


func test_every_stratum_at_its_largest_depth_is_under_the_node_budget() -> void:
	for stratum: StringName in LARGEST:
		var depth: int = LARGEST[stratum]
		var seeds := seeds_for(stratum, depth, 1)
		assert_false(seeds.is_empty(), "%s can stand at depth %d" % [stratum, depth])
		for s in seeds:
			var r := await _count(stratum, depth, s)
			print("  # %s depth %d seed %d: %d nodes (%d under-desk hide spots)" % [stratum, depth, s, r[&"nodes"], r[&"under_desk"]])
			assert_eq(r[&"built"], stratum, "%s seed %d built" % [stratum, s])
			assert_gt(int(r[&"nodes"]), 0, "%s seed %d reached a level" % [stratum, s])
			assert_lt(int(r[&"nodes"]), Tuning.BUDGET_NODES_PER_LEVEL, "%s depth %d seed %d: nodes in the level" % [stratum, depth, s])


## Offices at Cycle 2 depth 5 (3,097 nodes at M3.5): under the 14 §10 budget on several seeds,
## with its desks' hide spots built (the count that broke it).
func test_offices_at_cycle2_depth5_is_under_the_node_budget() -> void:
	var seeds := seeds_for(&"offices", 11, FULL_OFFICES_SEEDS if full_run() else GATE_OFFICES_SEEDS)
	assert_eq(seeds.size(), FULL_OFFICES_SEEDS if full_run() else GATE_OFFICES_SEEDS, "Offices can stand at depth 11")
	for s in seeds:
		var r := await _count(&"offices", 11, s)
		print("  # offices depth 11 seed %d: %d nodes (%d under-desk hide spots)" % [s, r[&"nodes"], r[&"under_desk"]])
		assert_eq(r[&"built"], &"offices", "seed %d built Offices" % s)
		assert_gt(int(r[&"under_desk"]), 50, "seed %d: the desks' hide spots are there" % s)
		assert_lt(int(r[&"nodes"]), Tuning.BUDGET_NODES_PER_LEVEL, "Offices depth 11 seed %d: nodes in the level" % s)


func test_under_desk_hide_spot_is_three_nodes() -> void:
	var s := (load(LevelPlacer.HIDE_SPOT_SCENES[HideSpot.KIND_UNDER_DESK]) as PackedScene).instantiate() as HideSpot
	add_child(s)
	assert_eq(PerfProbe.level_node_count(s), UNDER_DESK_NODES, "host body, shape, Interactable")
	s.free()
