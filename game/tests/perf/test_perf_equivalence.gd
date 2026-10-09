extends TestCase
## M3.5: the performance pass changes no behaviour. On a built Server level (116 fixtures,
## Cycle 2 depth 5), the indexed LightPool queries answer exactly what the old full scans
## answered, the packed Static cut test agrees with the old Dictionary search, and the
## prop-loop distance cull, the HUD gauge repaint skip and the fan spin enabler behave.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const SAMPLES := 400

var _level: Level


func before_all() -> void:
	var data := LevelGenerator.generate(Tuning.STRATUM_SERVER, 11, PerfBench.seed_for(Tuning.STRATUM_SERVER, 11), false, 2)
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(data)
	var frames := 0
	while not _level.is_walkable_now() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1


func after_all() -> void:
	if _level != null:
		_level.queue_free()


## The pre-M3.5 LightPool.is_lit: every powered fixture in range with a grid sight line.
static func _is_lit_scan(pool: LightPool, pos: Vector3) -> bool:
	for f in pool.fixtures():
		if not f.powered:
			continue
		var r := float(f.light_value(&"range", pool.light_range))
		var a := pool.anchor_of(f)
		if a.distance_squared_to(pos) <= r * r and (pool.grid == null or SightOps.clear(pool.grid, a, pos)):
			return true
	return false


## The pre-M3.5 DirectorSpawn.static_cuts_path search (after the covered-cell scan).
static func _cuts_scan(grid: LevelGrid, centre: Vector3, radius: float, from: Vector2i, to: Vector2i) -> bool:
	if not grid.in_bounds(from) or not grid.in_bounds(to) or not grid.is_walkable(from) or not grid.is_walkable(to):
		return false
	var covered: Dictionary = {}
	var on_path := false
	var span := int(ceil(radius / Tuning.GRID_CELL_SIZE)) + 1
	var cc := grid.cell_of(centre)
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c := cc + Vector2i(dx, dz)
			if grid.in_bounds(c) and grid.is_walkable(c) and DirectorSpawn.flat_dist(grid.world_of(c), centre) < radius:
				covered[c] = true
				on_path = on_path or grid.has_flag(c, LevelGrid.F_CRITICAL_PATH)
	if not on_path:
		return false
	if covered.has(to):
		return true
	covered.erase(from)
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			return false
		for d in 4:
			if not grid.can_step(c, d):
				continue
			var n := c + LevelGrid.DIRS[d]
			if seen.has(n) or covered.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return true


func _random_point(rng: RandomNumberGenerator) -> Vector3:
	var g := _level.data.grid
	var c := g.random_walkable_cell(rng)
	return g.world_of(c) + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.2, 2.2), rng.randf_range(-0.9, 0.9))


func test_lit_fixtures_near_matches_the_full_scan() -> void:
	var pool := _level.light_pool
	assert_gt(pool.fixtures().size(), 50, "a Server level's fixtures")
	var rng := make_rng(35)
	# Some groups dark, as after a power cut, so `powered` matters.
	for g in pool.group_ids():
		if int(g) % 3 == 0:
			pool.set_group_powered(int(g), false)
	var nonempty := 0
	for i in SAMPLES:
		var p := _random_point(rng)
		var r := rng.randf_range(1.0, 12.0)
		var want := FixtureGroups.lit_near(pool.fixtures(), pool.grid, pool.anchor_of, p, r)
		var got := pool.lit_fixtures_near(p, r)
		assert_eq(got, want, "lit_fixtures_near at %s r %.1f" % [p, r])
		if not want.is_empty():
			nonempty += 1
			var g := want[0].group_id
			assert_eq(pool.lit_fixtures_near(p, r, g), want.filter(func(f: Fixture) -> bool: return f.group_id == g),
				"the group filter keeps that group's, in order")
		assert_eq(pool.is_lit(p), _is_lit_scan(pool, p), "is_lit at %s" % p)
	assert_gt(nonempty, SAMPLES / 4, "the samples hit lit fixtures")
	pool.set_all_powered(true)


func test_static_cut_test_matches_the_old_search() -> void:
	var data := _level.data
	var g := data.grid
	var rng := make_rng(36)
	var cuts := 0
	for i in SAMPLES:
		var centre := g.world_of(data.critical_path[rng.randi_range(0, data.critical_path.size() - 1)])
		var radius := rng.randf_range(2.0, 9.0)
		var from := g.random_walkable_cell(rng)
		var want := _cuts_scan(g, centre, radius, from, data.exit_cell)
		assert_eq(DirectorSpawn.static_cuts_path(g, centre, radius, from, data.exit_cell), want,
			"cut test at %s r %.1f from %s" % [centre, radius, from])
		if want:
			cuts += 1
	assert_gt(cuts, 0, "some samples cut the route")


func test_prop_loops_stop_out_of_reach_and_come_back() -> void:
	var host := Node3D.new()
	add_child(host)
	var loop := AudioManager.loop(&"fan_loop", host)
	assert_true(loop.is_valid(), "the fan loop exists")
	if not loop.is_valid():
		host.free()
		return
	loop.start()
	AudioCull.mark(loop)
	var p := loop.player as AudioStreamPlayer3D
	assert_gt(p.max_distance, 0.0)
	AudioCull.tick([p], host.global_position + Vector3(p.max_distance + AudioCull.CULL_MARGIN - 0.5, 0, 0))
	assert_true(p.playing, "inside the margin: still playing")
	AudioCull.tick([p], host.global_position + Vector3(p.max_distance + AudioCull.CULL_MARGIN + 1.0, 0, 0))
	assert_false(p.playing, "out of reach: stopped")
	assert_true(AudioCull.is_culled(p))
	AudioCull.tick([p], host.global_position)
	assert_true(p.playing, "back in reach: playing again")
	# The owner's own stop holds, in reach or not.
	AudioCull.tick([p], host.global_position + Vector3(100, 0, 0))
	loop.stop()
	AudioCull.tick([p], host.global_position)
	assert_false(p.playing, "an owner stop is not undone by the cull")
	# Unmarked loops are never touched.
	var other := AudioManager.loop(&"fan_loop", host)
	other.start()
	AudioCull.tick([other.player], host.global_position + Vector3(100, 0, 0))
	assert_true(other.is_playing(), "unmarked: left alone")
	loop.release()
	other.release()
	host.queue_free()


func test_crank_gauge_repaints_only_on_a_shown_change() -> void:
	var gauge := HudCrank.new()
	add_child(gauge)
	gauge.set_charge(50.2)
	assert_contains(gauge.percent_text(), "50")
	gauge.set_charge(49.9)
	assert_contains(gauge.percent_text(), "50", "rounds to the same percent")
	gauge.set_charge(49.4)
	assert_contains(gauge.percent_text(), "49")
	gauge.set_charge(Tuning.CRANK_GAUGE_DANGER_BELOW + 0.2)
	var normal := gauge.percent_color()
	gauge.set_charge(Tuning.CRANK_GAUGE_DANGER_BELOW - 0.2)
	assert_ne(gauge.percent_color(), normal, "crossing into danger repaints even at the same rounded percent")
	gauge.free()


func test_fan_spin_runs_only_on_screen() -> void:
	var fan := (load("res://scenes/props/server/fan_grille.tscn") as PackedScene).instantiate() as ServerFan
	add_child(fan)
	var en := fan.get_node_or_null(^"SpinOnScreen") as VisibleOnScreenEnabler3D
	assert_not_null(en, "the fan has its on-screen enabler")
	if en != null:
		assert_eq(en.get_node(en.enable_node_path), fan.anim, "it drives the rotor's AnimationPlayer")
	fan.free()
