extends "res://tests/levelgen/test_level_builder_strata.gd"
## LevelBuilder on an Offices level (M2.2): it builds, bakes, has a navmesh path from spawn
## to exit (the base tests), and noclip reads its new edges: a PARTITION (waist high, seen
## over) is a passable wall that lands in the cubicle beyond; GLASS is SOLID (07 §7); the
## dark fixture groups start unpowered as whole groups; desks are hide spot markers.


func stratum() -> StringName:
	return &"offices"


func depth() -> int:
	return 3


func _eval(level: Level, c: Vector2i, d: int, down: float) -> Dictionary:
	var g := level.data.grid
	var base := g.world_of(c)
	var eye := base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
	var dv := LevelGrid.DIRS[d]
	return NoclipQuery.evaluate(level.get_world_3d().direct_space_state, eye, Vector3(dv.x, -down, dv.y).normalized(), base,
		NoclipFixture.capsule(), 100.0, false)


## 07 §7: a partition is a candidate; the pass lands in the cubicle on the other side. The
## aim dips to meet the 1.5 m partition below the 1.65 m eye.
func test_partition_noclip_lands_beyond() -> void:
	var level: Level = _levels[&"offices"]
	var g := level.data.grid
	var valid := 0
	var tried := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if not g.is_walkable(c) or g.has_flag(c, LevelGrid.F_HIDE_SPOT_HOST):
			continue
		for d in 4:
			if g.wall(c, d) != LevelGrid.PARTITION:
				continue
			var o := c + LevelGrid.DIRS[d]
			tried += 1
			var a := _eval(level, c, d, 0.45)
			assert_eq(a[&"wall_kind"], &"PARTITION", "aimed at the partition %s %d" % [c, d])
			if a[&"valid"]:
				valid += 1
				assert_eq(g.cell_of(a[&"landing"]), o, "lands in the far cubicle")
		if tried >= 40:
			break
	print("  # offices partitions: %d valid passes of %d tried" % [valid, tried])
	assert_gt(tried, 10)
	assert_gt(valid, tried / 2)


## 07 §2, §7: the meeting room's glass refuses noclip with SOLID; grid sight passes it.
func test_glass_refuses_noclip() -> void:
	var level: Level = _levels[&"offices"]
	var g := level.data.grid
	var refused := 0
	for room in g.rooms():
		if room.kind != OfficeRooms.MEETING:
			continue
		for e in room.perimeter_edges():
			if g.wall(Vector2i(e.x, e.y), e.z) != LevelGrid.GLASS:
				continue
			var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
			var a := _eval(level, o, LevelGrid.opposite(e.z), 0.1)
			assert_false(a[&"valid"])
			assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID)
			assert_eq(a[&"wall_kind"], &"GLASS")
			assert_true(SightOps.clear(g, g.world_of(o) + Vector3.UP, g.world_of(Vector2i(e.x, e.y)) + Vector3.UP), "sight passes glass")
			refused += 1
	assert_gt(refused, 0)


## 07 §5.4: dark groups start unpowered, whole groups; lit groups are powered.
func test_dark_groups_start_unpowered() -> void:
	var level: Level = _levels[&"offices"]
	var dark: Dictionary = {}
	for p in level.data.placements_of(LevelData.P_FIXTURE):
		if p[&"params"].get(&"dark", false):
			dark[int(p[&"params"][&"group"])] = true
	assert_gt(dark.size(), 0)
	var off := 0
	for f in level.light_pool.fixtures():
		assert_eq(f.powered, not dark.has(f.group_id), "fixture of group %d" % f.group_id)
		off += 0 if f.powered else 1
	assert_gt(off, 0)


## Desks are props and their hide spots markers until M2.8.
func test_desks_and_hide_spot_markers() -> void:
	var level: Level = _levels[&"offices"]
	# M2.8 turned hide-spot markers into HideSpot scenes; every desk carries an under-desk spot.
	var markers := 0
	for m in level.get_tree().get_nodes_in_group(&"hide_spots"):
		if level.is_ancestor_of(m) and (m as HideSpot) != null and (m as HideSpot).kind == &"under_desk":
			markers += 1
	var desks := 0
	for n in level.get_tree().get_nodes_in_group(&"props"):
		if level.is_ancestor_of(n) and String(n.name).begins_with("Desk"):
			desks += 1
	assert_gt(desks, 20)
	assert_gt(markers, desks - 1)
