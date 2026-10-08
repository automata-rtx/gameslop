extends TestCase
## LevelBuilder on Pools (this file) and Garage (test_level_builder_garage.gd extends it;
## one level per file, both build at the world origin), M2.1, 07 §8 rule 11: the level
## builds through level.tscn, bakes navigation with a path from spawn to exit (down a pool's
## steps; across a ramp), puts floors at their heights, makes one WaterVolume per wet basin,
## and lets noclip pass a deck strip onto deck 1's floor while refusing a wall onto the
## solid band between the decks.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500

## A stand-in for the Player's `water_depth` (06 §3).
class Wader:
	extends CharacterBody3D
	var water_depth: float = 0.0

var _levels: Dictionary = {}


## The stratum this file builds (the Garage file overrides it).
func stratum() -> StringName:
	return &"pools"


## The depth it is generated at (Offices and Server override it: their first depths).
func depth() -> int:
	return 2


func before_all() -> void:
	for stratum: StringName in [stratum()]:
		var data := LevelGenerator.generate(stratum, depth(), 3)
		var level := LEVEL_SCENE.instantiate() as Level
		add_child(level)
		level.begin(data)
		var frames := 0
		while not level.is_ready() and frames < MAX_FRAMES:
			await get_tree().process_frame
			frames += 1
		var map := level.get_world_3d().navigation_map
		var it := NavigationServer3D.map_get_iteration_id(map)
		for i in 30:
			await get_tree().physics_frame
			if NavigationServer3D.map_get_iteration_id(map) > it + 1:
				break
		var b := level.builder
		print("  # %s build: %d frames, max slice %.2f ms, plan %.1f ms, bake %.1f ms, meshes %d"
			% [stratum, frames, b.max_slice_ms, b.plan_ms, b.bake_ms, b.mesh_instance_count()])
		_levels[stratum] = level


func after_all() -> void:
	PlayerFixture.release_all()
	for l: Level in _levels.values():
		l.queue_free()


func _ray_floor(level: Level, at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 4.0, PlayerLayers.WORLD_MASK)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit[&"position"] as Vector3).y if not hit.is_empty() else -INF


func test_both_build_and_bake() -> void:
	for stratum: StringName in _levels:
		var level: Level = _levels[stratum]
		assert_true(level.is_ready(), "%s built" % stratum)
		assert_true(level.builder.navigation_ok, "%s navigation" % stratum)
		assert_eq(level.builder.plan.errors.size(), 0)


## 07 §8 rule 11: a navmesh path from spawn to exit.
func test_navigation_path_spawn_to_exit() -> void:
	for stratum: StringName in _levels:
		var level: Level = _levels[stratum]
		var g := level.data.grid
		var map := level.get_world_3d().navigation_map
		var from := NavigationServer3D.map_get_closest_point(map, g.world_of(level.data.spawn_cell))
		var to := NavigationServer3D.map_get_closest_point(map, g.world_of(level.data.exit_cell))
		assert_lt(from.distance_to(g.world_of(level.data.spawn_cell)), 0.6, "%s spawn on the navmesh" % stratum)
		assert_lt(to.distance_to(g.world_of(level.data.exit_cell)), 0.6, "%s exit on the navmesh" % stratum)
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		assert_gt(path.size(), 1, "%s path" % stratum)
		if path.size() > 1:
			assert_lt(path[path.size() - 1].distance_to(to), 0.3, "%s path reaches the exit" % stratum)


func test_floors_stand_at_their_heights() -> void:
	for stratum: StringName in _levels:
		var level: Level = _levels[stratum]
		var g := level.data.grid
		var checked := 0
		# Cells holding furniture (a desk, a chair, a car) are measured by the next test's rays.
		var furnished: Dictionary = {}
		for p in level.data.placements:
			if p[&"kind"] == LevelData.P_PROP or p[&"kind"] == LevelData.P_HIDE_SPOT:
				furnished[p[&"cell"]] = true
		for i in range(0, g.cell_count(), 3):
			var c := g.cell_at(i)
			if not g.is_walkable(c) or g.has_flag(c, LevelGrid.F_NO_SPAWN) or furnished.has(c):
				continue
			var y := _ray_floor(level, g.world_of(c))
			assert_approx(y, g.floor_y(c), 0.12, "%s floor of %s" % [stratum, c])
			checked += 1
		assert_gt(checked, 40)


func test_water_volumes_match_wet_basins() -> void:
	if stratum() != &"pools":
		return
	var level: Level = _levels[&"pools"]
	var vols := level.get_tree().get_nodes_in_group(WaterVolume.GROUP)
	var mine := 0
	for v in vols:
		if level.is_ancestor_of(v):
			mine += 1
			var w := v as WaterVolume
			assert_eq(w.collision_layer, 1 << (PlayerLayers.WATER - 1), "07 §8 water on layer 7")
			assert_approx(w.depth_at(w.floor_y), w.surface_y - w.floor_y, 0.001)
			assert_eq(w.depth_at(w.surface_y + 1.0), 0.0)
	assert_eq(mine, level.data.placements_of(LevelData.P_WATER).size())


## 06 §3: a body in the water gets the depth over its feet; out of it, 0.
func test_water_volume_sets_water_depth() -> void:
	if stratum() != &"pools":
		return
	var level: Level = _levels[&"pools"]
	var target: WaterVolume = null
	for v in level.get_tree().get_nodes_in_group(WaterVolume.GROUP):
		if level.is_ancestor_of(v):
			target = v
			break
	if target == null:
		return  # this seed has no wet basin (the count test covers the placements)
	var w := Wader.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	shape.shape = cap
	shape.position = Vector3(0, 0.8, 0)
	w.add_child(shape)
	w.collision_layer = PlayerLayers.PLAYER_MASK
	w.collision_mask = 0
	level.add_child(w)
	var g := level.data.grid
	w.global_position = g.world_of(target.rect.position + target.rect.size / 2) + Vector3(0, 0.02, 0)
	await await_physics_frames(4)
	assert_approx(w.water_depth, target.surface_y - w.global_position.y, 0.05, "wading depth")
	w.global_position += Vector3(0, 30, 0)
	await await_physics_frames(4)
	assert_eq(w.water_depth, 0.0, "out of the water")
	w.queue_free()


## 07 §7 on decks: a strip wall between two deck-1 cells is a valid noclip that lands on
## deck 1's floor; a wall from a deck onto the band between the decks is NO SPACE.
func test_noclip_on_deck_one() -> void:
	if stratum() != &"garage":
		return
	var level: Level = _levels[&"garage"]
	var g := level.data.grid
	var space := level.get_world_3d().direct_space_state
	var valid := 0
	var refused := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR or g.deck[i] != 1 or g.has_flag(c, LevelGrid.F_NO_SPAWN):
			continue
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if g.wall(c, d) != LevelGrid.WALL and g.wall(c, d) != LevelGrid.SOFT:
				continue
			var base := g.world_of(c)
			var eye := base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
			var dv := LevelGrid.DIRS[d]
			var a := NoclipQuery.evaluate(space, eye, Vector3(dv.x, -0.05, dv.y).normalized(), base, NoclipFixture.capsule(), 100.0, false)
			if a[&"target"] == NoclipQuery.TARGET_FLOOR:
				continue
			if g.is_walkable(o) and g.deck[g.idx(o)] == 1 and g.kind(o) == LevelGrid.FLOOR and not g.has_flag(o, LevelGrid.F_NO_SPAWN):
				if a[&"valid"]:
					valid += 1
					assert_approx((a[&"landing"] as Vector3).y, Tuning.GARAGE_DECK_RISE + Tuning.NOCLIP_LANDING_LIFT, 0.06, "lands on deck 1")
			elif not g.is_walkable(o):
				refused += 1
				assert_false(a[&"valid"], "%s %d onto a non-walkable cell" % [c, d])
	print("  # garage deck 1: %d valid strip passes, %d refused walls onto void" % [valid, refused])
	assert_gt(valid, 0)
	assert_gt(refused, 0)
