extends "res://tests/levelgen/test_level_builder_strata.gd"
## LevelBuilder on a Server level (M2.2): it builds, bakes, has a navmesh path from spawn to
## the exit clearing (the base tests), racks are bodies tagged WALL with `rack`, and the
## M2.2 rack ruling holds: a rack face passes through the whole rack to the walkable cell
## beyond it (NO SPACE when another rack stands there); a cage's mesh fence is SOLID.


func stratum() -> StringName:
	return &"server"


func depth() -> int:
	return 4


func _eval(level: Level, c: Vector2i, d: int, down: float) -> Dictionary:
	var g := level.data.grid
	var base := g.world_of(c)
	var eye := base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
	var dv := LevelGrid.DIRS[d]
	return NoclipQuery.evaluate(level.get_world_3d().direct_space_state, eye, Vector3(dv.x, -down, dv.y).normalized(), base,
		NoclipFixture.capsule(), 100.0, false)


## Aisle cells beside a rack cell: [aisle, dir to the rack].
func _rack_faces(g: LevelGrid) -> Array:
	var out: Array = []
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR or g.has_flag(c, LevelGrid.F_HIDE_SPOT_HOST):
			continue
		for d in 4:
			if g.kind(c + LevelGrid.DIRS[d]) == LevelGrid.RACK:
				out.append([c, d])
	return out


func test_rack_noclip_passes_the_whole_rack() -> void:
	var level: Level = _levels[&"server"]
	var g := level.data.grid
	var through := 0
	var no_space := 0
	for f: Array in _rack_faces(g):
		var c: Vector2i = f[0]
		var d: int = f[1]
		var rack := c + LevelGrid.DIRS[d]
		var beyond := rack + LevelGrid.DIRS[d]
		var a := _eval(level, c, d, 0.3)
		assert_eq(a[&"wall_kind"], &"WALL", "a rack face is WALL (07 §7)")
		if g.is_walkable(beyond) and not g.has_flag(beyond, LevelGrid.F_HIDE_SPOT_HOST):
			if a[&"valid"]:
				through += 1
				assert_eq(g.cell_of(a[&"landing"]), beyond, "lands beyond the rack")
				assert_approx(float(a[&"pass_depth"]), Tuning.GRID_CELL_SIZE, 0.001)
		elif not g.is_walkable(beyond):
			assert_false(a[&"valid"], "%s %d: a rack behind the rack" % [c, d])
			assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE)
			no_space += 1
		if through >= 25 and no_space >= 10:
			break
	print("  # server racks: %d passes through, %d NO SPACE" % [through, no_space])
	assert_gt(through, 10)
	assert_gt(no_space, 0)


## A held noclip at a rack carries the body through it to the aisle beyond.
func test_player_passes_a_rack() -> void:
	var level: Level = _levels[&"server"]
	var g := level.data.grid
	var pick: Array = []
	for f: Array in _rack_faces(g):
		var beyond: Vector2i = f[0] + LevelGrid.DIRS[f[1]] * 2
		if g.is_walkable(beyond) and _eval(level, f[0], f[1], 0.3)[&"valid"]:
			pick = f
			break
	assert_false(pick.is_empty(), "a passable rack face")
	if pick.is_empty():
		return
	var c: Vector2i = pick[0]
	var d: int = pick[1]
	var dv := LevelGrid.DIRS[d]
	var p := PlayerFixture.spawn_player(level, g.world_of(c) + Vector3.UP * 0.02)
	p.rotation.y = atan2(-dv.x, -dv.y)
	await await_physics_frames(3)
	Input.action_press(&"noclip")
	var guard := 0
	var passed := false
	while guard < 240:
		guard += 1
		await get_tree().physics_frame
		if p.state_machine.is_in(PlayerStateMachine.NOCLIP_PASS):
			passed = true
		if passed and p.state_machine.is_in(PlayerStateMachine.IDLE):
			break
	Input.action_release(&"noclip")
	assert_true(passed, "the pass ran")
	assert_eq(g.cell_of(p.global_position), c + dv * 2, "standing in the aisle beyond the rack")
	assert_true(NoclipQuery.is_free(p.get_world_3d().direct_space_state, p.global_position, p.collision.shape, [p.get_rid()]))
	while get_tree().paused:
		await get_tree().process_frame
	p.queue_free()
	await await_physics_frames(2)


## 07 §5.5: the cage fence (GLASS) is SOLID to noclip; every cage has a door leaf.
func test_cage_fence_refuses() -> void:
	var level: Level = _levels[&"server"]
	var g := level.data.grid
	var refused := 0
	for room in g.rooms():
		if room.kind != ServerGenerator.CAGE:
			continue
		for e in room.perimeter_edges():
			if g.wall(Vector2i(e.x, e.y), e.z) != LevelGrid.GLASS:
				continue
			var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
			var a := _eval(level, o, LevelGrid.opposite(e.z), 0.2)
			assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID)
			refused += 1
			break
	assert_gt(refused, 1)


## Rack bodies carry the 07 §7 metadata.
func test_rack_bodies() -> void:
	var level: Level = _levels[&"server"]
	var racks := 0
	for b in level.builder.plan.boxes:
		if b[&"kind"] == BuildPlan.BODY_RACK:
			racks += 1
			var meta: Dictionary = b[&"meta"]
			assert_true(meta[&"rack"])
			assert_eq(meta[&"wall_kind"], &"WALL")
			assert_approx((b[&"size"] as Vector3).y, Tuning.SERVER_RACK_HEIGHT, 0.001)
	var cells := 0
	for k in level.data.grid.cells:
		cells += 1 if k == LevelGrid.RACK else 0
	assert_eq(racks, cells)
