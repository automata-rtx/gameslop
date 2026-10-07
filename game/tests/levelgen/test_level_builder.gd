extends TestCase
## LevelBuilder integration (07 §8, 14 §10): build one Halls level headless through
## level.tscn and check budgets, collision metadata, navigation and the light pool.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
## The slice budget is 4 ms (14 §10). CI shares its CPU with other jobs, so one slice may be
## preempted: 90% of slices must fit the budget, and none may exceed it by this factor.
const SLICE_CI_ALLOWANCE := 4.0
const SLICE_PERCENTILE := 0.9
const MAX_FRAMES := 1200

var _level: Level
var _data: LevelData
var _frames: int = 0


func before_all() -> void:
	_data = LevelGenerator.generate(&"halls", 1, 1)
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(_data)
	while not _level.is_ready() and _frames < MAX_FRAMES:
		await get_tree().process_frame
		_frames += 1
	var map := _level.get_world_3d().navigation_map
	var it := NavigationServer3D.map_get_iteration_id(map)
	for i in 30:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > it + 1:
			break
	var b := _level.builder
	print("  # build: %d frames, %d slices, max slice %.2f ms, plan %.1f ms, bake %.1f ms, nodes %d, meshes %d"
		% [_frames, b.slices, b.max_slice_ms, b.plan_ms, b.bake_ms, _count(_level), b.mesh_instance_count()])
	print("  # slowest job %s %.2f ms" % [b.slowest_job, b.slowest_job_ms])


func after_all() -> void:
	_level.queue_free()


func _count(n: Node) -> int:
	var c := 1
	for child in n.get_children():
		c += _count(child)
	return c


func test_build_completes() -> void:
	assert_true(_level.is_walkable_now(), "geometry built")
	assert_true(_level.is_ready(), "built (navigation baked) within %d frames" % MAX_FRAMES)
	assert_true(_level.builder.navigation_ok)


func test_node_budget() -> void:
	assert_lt(_count(_level), 3000, "14 §10: nodes in a level")


func test_draw_call_proxy() -> void:
	# Merged chunk meshes: 3 x 3 chunks x (floor, ceiling, wall) plus one per soft wall.
	var n := _level.builder.mesh_instance_count()
	assert_lt(n, 40)
	assert_gt(n, 9)
	var all := _level.find_children("*", "MeshInstance3D", true, false).size()
	assert_lt(all, 1500, "14 §10: draw calls")


func test_slices_respect_budget() -> void:
	var b := _level.builder
	assert_gt(b.slices, 1, "the build is spread over frames")
	var sorted := b.slice_ms.duplicate()
	sorted.sort()
	var p90 := sorted[mini(sorted.size() - 1, int(sorted.size() * SLICE_PERCENTILE))]
	assert_true(p90 <= Tuning.LEVELBUILD_SLICE_MS, "90th percentile slice %.2f ms within 4 ms" % p90)
	assert_lt(b.max_slice_ms, Tuning.LEVELBUILD_SLICE_MS * SLICE_CI_ALLOWANCE, "worst slice (CI allowance)")


func test_bake_within_budget() -> void:
	assert_lt(_level.builder.bake_ms, Tuning.NAV_BAKE_BUDGET * 1000.0)


## Every wall edge next to walkable space is found by a ray at chest height, and the hit
## carries 07 §7 metadata plus the `wall_kind` body meta.
func test_wall_edges_have_collision_with_metadata() -> void:
	var g := _data.grid
	var space := _level.get_world_3d().direct_space_state
	var checked := 0
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c):
				continue
			for d in 4:
				var t := g.wall(c, d)
				if t == LevelGrid.NONE or t == LevelGrid.DOOR:
					continue
				var dv := LevelGrid.DIRS[d]
				var from := g.world_of(c) + Vector3(0, 1.2, 0)
				var to := from + Vector3(dv.x, 0, dv.y) * 1.2
				var q := PhysicsRayQueryParameters3D.create(from, to, 1)
				var hit := space.intersect_ray(q)
				checked += 1
				if hit.is_empty():
					fail("no collider on edge %s %s" % [c, LevelGrid.DIR_NAMES[d]])
					continue
				var info := LevelBuilder.shape_info(hit["collider"], hit["shape"])
				if not info.has(&"wall_type"):
					# Props stand against walls; they are tagged PROP.
					assert_eq((hit["collider"] as Object).get_meta(&"wall_kind", &""), &"PROP", "edge %s %d" % [c, d])
					continue
				assert_eq(info[&"wall_type"], t, "wall type on %s %d" % [c, d])
				assert_true((hit["collider"] as Object).has_meta(&"wall_kind"))
				assert_approx(float(info[&"thickness"]), Tuning.GRID_WALL_THICKNESS)
	assert_gt(checked, 200)


func test_floor_cells_have_surface_meta() -> void:
	var g := _data.grid
	var space := _level.get_world_3d().direct_space_state
	var c := _data.spawn_cell
	var from := g.world_of(c) + Vector3(0, 1.0, 0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1))
	assert_false(hit.is_empty())
	assert_eq((hit["collider"] as Object).get_meta(&"surface", &""), &"carpet")
	assert_eq(LevelBuilder.shape_info(hit["collider"], hit["shape"])[&"cell"], c)


func test_navigation_path_spawn_to_exit() -> void:
	var map := _level.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(map)
	var from := _data.grid.world_of(_data.spawn_cell)
	var to := _data.grid.world_of(_data.exit_cell)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	assert_gt(path.size(), 1, "a path exists")
	if path.size() > 1:
		assert_lt(path[path.size() - 1].distance_to(to), 1.0, "path reaches the exit cell")
		var length := 0.0
		for i in path.size() - 1:
			length += path[i].distance_to(path[i + 1])
		assert_gt(length, from.distance_to(to) - 0.01)


func test_soft_walls_are_nodes() -> void:
	var soft := get_tree().get_nodes_in_group(&"soft_walls")
	assert_eq(soft.size(), _data.soft_walls.size())
	for n in soft:
		var mesh := (n as Node).get_node_or_null(^"Mesh") as MeshInstance3D
		assert_not_null(mesh)
		if mesh != null:
			assert_eq((mesh.material_override as ShaderMaterial).get_shader_parameter(&"soft"), 1.0)
		var body := (n as Node).get_node_or_null(^"Body") as StaticBody3D
		assert_not_null(body)
		if body != null:
			assert_eq(body.get_meta(&"wall_kind"), &"SOFT")


func test_markers_and_prefabs() -> void:
	assert_eq(get_tree().get_nodes_in_group(LevelPlacer.group_of(LevelData.P_EXIT)).size(), 1)
	assert_eq(get_tree().get_nodes_in_group(LevelPlacer.group_of(LevelData.P_SPAWN)).size(), 1)
	assert_eq(get_tree().get_nodes_in_group(LevelPlacer.GROUP_ERROR_SPAWNS).size(),
		_data.placements_of(LevelData.P_ERROR_SPAWN).size())
	assert_eq(get_tree().get_nodes_in_group(LevelPlacer.group_of(LevelData.P_ITEM)).size(),
		_data.placements_of(LevelData.P_ITEM).size())
	for m in get_tree().get_nodes_in_group(LevelPlacer.group_of(LevelData.P_NOTE)):
		assert_true((m as Node).has_meta(LevelPlacer.META_PLACEMENT))
	assert_eq(get_tree().get_nodes_in_group(&"hide_spots").size(), _data.placements_of(LevelData.P_HIDE_SPOT).size())
	assert_eq(_level.light_pool.fixtures().size(), _data.placements_of(LevelData.P_FIXTURE).size())


func test_light_pool_cap_and_shadows() -> void:
	var pool := _level.light_pool
	var p := StratumEnvironment.preset_of(Tuning.QUALITY_PRESET_DEFAULT)
	var target := Node3D.new()
	_level.add_child(target)
	pool.target = target
	var g := _data.grid
	# Walk the target along the critical path; the cap holds everywhere. Every step is a
	# new cell (the uncached worst case for the selector).
	var us := 0
	for c in _data.critical_path:
		target.global_position = g.world_of(c) + Vector3(0, 1.6, 0)
		var t0 := Time.get_ticks_usec()
		pool.reevaluate()
		us += Time.get_ticks_usec() - t0
		assert_true(pool.active_light_count() <= int(p[&"lights"]), "pool cap")
		assert_true(pool.shadowed_light_count() <= int(p[&"shadowed"]), "shadow cap")
	assert_gt(pool.active_light_count(), 0)
	var mean_ms := us / 1000.0 / maxf(1.0, _data.critical_path.size())
	print("  # light pool re-evaluation: %.2f ms mean over %d new cells" % [mean_ms, _data.critical_path.size()])
	assert_lt(mean_ms, Tuning.BUDGET_SCRIPT_MS, "14 §10 script budget")
	pool.target = null
	target.queue_free()


## 02 §6: lights go only to fixtures the target can see on the grid (unshadowed lights
## lent behind walls would leak through them).
func test_light_pool_lends_only_to_fixtures_in_view() -> void:
	var pool := _level.light_pool
	var g := _data.grid
	var target := Node3D.new()
	_level.add_child(target)
	pool.target = target
	for c in _data.critical_path:
		var eye := g.world_of(c) + Vector3(0, 1.6, 0)
		target.global_position = eye
		pool.reevaluate()
		var eyes: Array[Vector3] = [eye]
		for d in 4:
			if g.can_step(c, d):
				eyes.append(g.world_of(c + LevelGrid.DIRS[d]))
		for l in pool.get_children():
			if not (l is Light3D and (l as Light3D).visible):
				continue
			var fx := (l as Node3D).global_position
			var seen := false
			for e in eyes:
				seen = seen or SightOps.clear(g, e, fx)
			assert_true(seen, "light at %s is in view of %s" % [fx, c])
	pool.target = null
	target.queue_free()


func test_light_pool_power_and_flicker() -> void:
	var pool := _level.light_pool
	var gid: int = pool.group_ids()[0]
	pool.set_group_powered(gid, false)
	for f in pool.group(gid):
		assert_false(f.powered)
		assert_false(f.is_emitting())
	var origin := pool.group(gid)[0].global_position
	var last := pool.power_wave(origin)
	assert_true(last >= 0.0)
	pool.set_group_powered(gid, true)
	pool.set_group_flicker(gid, true)
	assert_true(pool.group(gid)[0].is_flickering())
	pool.set_group_flicker(gid, false)
	assert_false(pool.group(gid)[0].is_flickering())
	assert_true(pool.is_lit(origin - Vector3(0, 1.0, 0)))


func test_doors_carry_edge_meta() -> void:
	for d in get_tree().get_nodes_in_group(&"doors"):
		var leaf := (d as Door).leaf
		assert_eq(leaf.get_meta(&"wall_kind"), &"DOOR")
		assert_true(leaf.has_meta(&"cell"))


## 07 §3: walkable as soon as the geometry is built: the player stands on the spawn floor
## and reads the floor's `surface` meta (06 Interfaces).
func test_player_stands_on_spawn() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	_level.add_child(player)
	_level.attach_player(player, player.rig.camera)
	var start := player.global_position
	for i in 30:
		await get_tree().physics_frame
	assert_true(player.is_on_floor(), "on the floor")
	assert_lt(absf(player.global_position.y - start.y), 0.2, "did not fall through")
	assert_eq(player.floor_surface(), &"carpet")
	assert_true(_level.light_pool.target == player.rig.camera)
	_level.detach_player(player)
	player.queue_free()
