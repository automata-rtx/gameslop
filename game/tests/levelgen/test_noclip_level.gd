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
