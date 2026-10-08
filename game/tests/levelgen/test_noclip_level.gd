extends TestCase
## M1.4 integration: noclip on a real generated Halls level (07 §7 metadata from the
## builder). Pick an interior WALL between two walkable cells, stand in one facing it,
## hold noclip, and end up standing in the other, outside all geometry. Walls whose far
## cell is not walkable refuse with NO SPACE (orchestrator rule, hollow void blocks).

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500

var _level: Level
var _data: LevelData


func before_all() -> void:
	_data = LevelGenerator.generate(&"halls", 1, 1)
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(_data)
	var frames := 0
	while not _level.is_walkable_now() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	await await_physics_frames(3)


func after_all() -> void:
	PlayerFixture.release_all()
	_level.queue_free()


## Eye pose standing at the centre of `c` facing edge `d`.
func _pose(c: Vector2i, d: int) -> Array:
	var g := _data.grid
	var base := g.world_of(c)
	var dv := LevelGrid.DIRS[d]
	return [base, Vector3(dv.x, 0, dv.y)]


func _eval(c: Vector2i, d: int) -> Dictionary:
	var pose := _pose(c, d)
	var base: Vector3 = pose[0]
	var eye := base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
	return NoclipQuery.evaluate(_level.get_world_3d().direct_space_state, eye, pose[1], base,
			NoclipFixture.capsule(), 100.0, false)


## Interior WALL edges, both cells plain walkable floor, scanned in grid order.
func _wall_edges(far_walkable: bool) -> Array:
	var g := _data.grid
	var out: Array = []
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c):
				continue
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				if g.wall(c, d) == LevelGrid.WALL and g.in_bounds(o) and g.is_walkable(o) == far_walkable:
					out.append([c, d])
	return out


func test_level_is_walkable() -> void:
	assert_true(_level.is_walkable_now())


func test_pass_through_a_wall_between_two_corridors() -> void:
	var g := _data.grid
	var pick: Array = []
	for e: Array in _wall_edges(true):
		if _eval(e[0], e[1])[&"valid"]:
			pick = e
			break
	assert_false(pick.is_empty(), "some interior wall between walkable cells is passable")
	if pick.is_empty():
		return
	var c: Vector2i = pick[0]
	var d: int = pick[1]
	var other := c + LevelGrid.DIRS[d]
	var pose := _pose(c, d)
	var p := PlayerFixture.spawn_player(_level, pose[0] + Vector3.UP * 0.02)
	var fwd: Vector3 = pose[1]
	p.rotation.y = atan2(-fwd.x, -fwd.z)
	await await_physics_frames(3)
	assert_eq(g.cell_of(p.global_position), c, "starts in the near cell")
	Input.action_press(&"noclip")
	var guard := 0
	var passed := false
	while guard < 200:
		guard += 1
		await get_tree().physics_frame
		if p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS):
			passed = true
		if passed and p.state_machine.is_in(PlayerStateMachine.IDLE):
			break
	Input.action_release(&"noclip")
	assert_true(passed, "the pass ran")
	assert_eq(g.cell_of(p.global_position), other, "standing in the far corridor")
	assert_true(NoclipQuery.is_free(p.get_world_3d().direct_space_state, p.global_position,
			p.collision.shape, [p.get_rid()]), "not inside geometry")
	assert_approx(p.coherence, 100.0 - Tuning.NOCLIP_WALL_COST, 0.0001)
	while get_tree().paused:
		await get_tree().process_frame
	p.queue_free()
	await await_physics_frames(2)


func test_walls_onto_non_walkable_cells_refuse() -> void:
	var edges := _wall_edges(false)
	var checked := 0
	for e: Array in edges:
		var a := _eval(e[0], e[1])
		if a[&"distance"] > Tuning.NOCLIP_RANGE or a[&"target"] == NoclipQuery.TARGET_FLOOR:
			continue
		checked += 1
		assert_false(a[&"valid"], "edge %s dir %d onto a non-walkable cell" % [e[0], e[1]])
	print("  # non-walkable far cells checked: %d of %d WALL edges" % [checked, edges.size()])
	# Edges to void are SOLID or WALL depending on the builder pass; both must refuse.
	var solid := 0
	for z in _data.grid.size.y:
		for x in _data.grid.size.x:
			var c := Vector2i(x, z)
			if _data.grid.is_walkable(c):
				for d in 4:
					var o := c + LevelGrid.DIRS[d]
					if not _data.grid.in_bounds(o) or not _data.grid.is_walkable(o):
						if _eval(c, d)[&"valid"]:
							solid += 1
	assert_eq(solid, 0, "no wall onto a non-walkable cell is ever valid")


## Eye poses for the sweep: walkable cells (every other one, up to `limit`), the centre and
## four points 0.55 m towards the corners.
func _sweep_poses(limit: int) -> Array:
	var g := _data.grid
	var out: Array = []
	var n := 0
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c) or (x + z) % 2 != 0:
				continue
			n += 1
			if n > limit:
				return out
			for off: Vector2 in [Vector2.ZERO, Vector2(0.55, 0.55), Vector2(-0.55, 0.55), Vector2(0.55, -0.55), Vector2(-0.55, -0.55)]:
				out.append(g.world_of(c) + Vector3(off.x, 0.0, off.y))
	return out


## Noclip review item 4: wherever the player stands and whichever way they look (corners
## included), a valid wall target lands in the far cell the grid check approved, on
## walkable floor, in free space.
func test_corner_sweep_lands_in_the_approved_far_cell() -> void:
	var g := _data.grid
	var space := _level.get_world_3d().direct_space_state
	var shape := NoclipFixture.capsule()
	var valid := 0
	var oblique := 0
	for base: Vector3 in _sweep_poses(60):
		for step in 24:
			var yaw := TAU * step / 24.0
			var dir := Vector3(sin(yaw), -0.08, cos(yaw)).normalized()
			var eye := base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
			var a := NoclipQuery.evaluate(space, eye, dir, base, shape, 100.0, false)
			if not a[&"valid"] or a[&"target"] == NoclipQuery.TARGET_FLOOR:
				continue
			valid += 1
			var land: Vector3 = a[&"landing"]
			assert_true(a[&"has_far_cell"], "the builder names the far cell")
			assert_eq(g.cell_of(land), a[&"far_cell"], "landing in the approved far cell from %s yaw %d" % [base, step])
			assert_true(g.is_walkable(a[&"far_cell"]))
			assert_approx(land.y, g.floor_y(a[&"far_cell"]) + Tuning.NOCLIP_LANDING_LIFT, 0.05, "on its floor")
			assert_true(NoclipQuery.is_free(space, land, shape))
			var n: Vector3 = a[&"normal"]
			if absf(Vector3(dir.x, 0, dir.z).normalized().dot(-n)) < 0.8:
				oblique += 1
	print("  # sweep: %d valid wall aims, %d oblique" % [valid, oblique])
	assert_gt(valid, 20, "the sweep found walls to pass")
	assert_gt(oblique, 0, "oblique aims were checked")


## Noclip review item 12: the cost of one targeting frame, headless. All aims cold (every
## landing computed), then the aims that find a landing, cold and warm (the same pose again
## within the cache lifetime: a held aim). Best of three passes.
func test_targeting_cost_per_frame() -> void:
	var space := _level.get_world_3d().direct_space_state
	var shape := NoclipFixture.capsule()
	var poses: Array = []
	for base: Vector3 in _sweep_poses(30):
		for step in 8:
			var yaw := TAU * step / 8.0
			poses.append([base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT, Vector3(sin(yaw), -0.08, cos(yaw)).normalized(), base])
	var landing_poses: Array = []
	for p: Array in poses:
		if NoclipQuery.evaluate(space, p[0], p[1], p[2], shape, 100.0, false)[&"has_landing"]:
			landing_poses.append(p)
	var all_cold := _time_evals(space, shape, poses, null)
	var cold := _time_evals(space, shape, landing_poses, null)
	var warm := _time_held(space, shape, landing_poses)
	print("  # targeting per frame: %.1f us over %d aims; with a landing %.1f us cold, %.1f us cached (%d)" % [
		all_cold, poses.size(), cold, warm, landing_poses.size()])
	assert_gt(landing_poses.size(), 0)
	assert_lt(warm, cold, "the cache saves the landing search")
	assert_budget(cold, 2000.0, "under 2 ms per frame even cold (headless CPU)")


func _time_evals(space: PhysicsDirectSpaceState3D, shape: Shape3D, poses: Array, cache: Variant) -> float:
	var best := INF
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		for p: Array in poses:
			NoclipQuery.evaluate(space, p[0], p[1], p[2], shape, 100.0, false, [], cache)
		best = minf(best, float(Time.get_ticks_usec() - t0) / maxi(poses.size(), 1))
	return best


## A held aim: each pose evaluated once to fill the cache, then timed again.
func _time_held(space: PhysicsDirectSpaceState3D, shape: Shape3D, poses: Array) -> float:
	var best := INF
	for rep in 3:
		var total := 0
		var cache := {}
		for p: Array in poses:
			NoclipQuery.evaluate(space, p[0], p[1], p[2], shape, 100.0, false, [], cache)
			var t0 := Time.get_ticks_usec()
			NoclipQuery.evaluate(space, p[0], p[1], p[2], shape, 100.0, false, [], cache)
			total += Time.get_ticks_usec() - t0
		best = minf(best, float(total) / maxi(poses.size(), 1))
	return best
