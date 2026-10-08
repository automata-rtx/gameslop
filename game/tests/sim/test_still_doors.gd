extends TestCase
## Still crosses an opened doorway on a real Halls level (cp-04 review item 1): an open
## leaf swings into the cell beside the doorway and must not stop the column dead. The
## player stands far off in the dark (unobserved); sight is off to isolate the walk.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const CROSS_TIME := 20.0         # s of game time for a two-cell walk through one doorway

var _level: Level
var _p: Player


func before_all() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"halls", 1, 1))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_level.attach_player(_p, _p.rig.camera)
	_level.light_pool.set_all_powered(false)
	_p.flashlight.set_on(false, true)
	await await_physics_frames(10)


func after_all() -> void:
	Engine.time_scale = 1.0
	_level.queue_free()


func after_each() -> void:
	Engine.time_scale = 1.0
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


## Open doors between two walkable corridor cells, farthest from the player first.
func _open_doors() -> Array[Door]:
	var g := _level.data.grid
	var out: Array[Door] = []
	for n in get_tree().get_nodes_in_group(&"doors"):
		var door := n as Door
		if door == null or not door.leaf.has_meta(&"cell"):
			continue
		var c: Vector2i = door.leaf.get_meta(&"cell")
		var d := int(door.leaf.get_meta(&"dir"))
		var far := c + LevelGrid.DIRS[d]
		if g.is_walkable(c) and g.is_walkable(far) and g.can_step(c, LevelGrid.opposite(d)) \
				and g.can_step(far, d):
			out.append(door)
	out.sort_custom(func(a: Door, b: Door) -> bool:
		return a.global_position.distance_to(_p.global_position) > b.global_position.distance_to(_p.global_position))
	return out


## Walks Still from one cell before the doorway to one cell past it (hinted, unobserved).
func _cross(door: Door, from: Vector2i, to: Vector2i) -> float:
	var g := _level.data.grid
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, 21)
	_level.add_child(still)
	still.place_at(g.world_of(from))
	still.senses.sight_range = 0.0
	still.senses.hearing_mult = 0.0
	still.set_aggression(0.25)
	still.hint(g.world_of(to))
	still.wake()
	var goal := g.world_of(to)
	var t := 0.0
	while t < CROSS_TIME:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		assert_false(still.observed, "unobserved")
		if ErrorFixture.flat(still.body_position(), goal) <= Tuning.ERROR_ARRIVE_DIST + 0.1:
			break
	var cell := g.cell_of(still.body_position())
	still.queue_free()
	await await_physics_frames(2)
	assert_eq(cell, to, "crossed %s (%.1f s)" % [door.name, t])
	return t


func test_crosses_an_open_doorway_both_ways() -> void:
	assert_true(_level.builder.navigation_ok)
	var doors := _open_doors()
	assert_gt(doors.size(), 0, "the level has a corridor door")
	if doors.is_empty():
		return
	Engine.time_scale = 4.0
	var door := doors[0]
	door.open()
	await await_physics_frames(int(Tuning.DOOR_SWING_TIME * Engine.physics_ticks_per_second) + 2)
	assert_true(door.is_open)
	var c: Vector2i = door.leaf.get_meta(&"cell")
	var d := int(door.leaf.get_meta(&"dir"))
	var before := c - LevelGrid.DIRS[d]
	var after := c + LevelGrid.DIRS[d] * 2
	var g := _level.data.grid
	# Two cells either side when the corridor runs on; else the cells at the doorway.
	if not g.is_walkable(before) or not g.can_step(c, LevelGrid.opposite(d)):
		before = c
	if not g.is_walkable(after) or not g.can_step(c + LevelGrid.DIRS[d], d):
		after = c + LevelGrid.DIRS[d]
	await _cross(door, before, after)
	await _cross(door, after, before)


func test_open_leaves_are_not_obstacles_closed_ones_are() -> void:
	var doors := _open_doors()
	if doors.is_empty():
		fail("no corridor door")
		return
	var door := doors[0]
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, 22)
	_level.add_child(still)
	# Beyond ERROR_DOOR_OPEN_DIST, so Still does not open the door again itself.
	var g := _level.data.grid
	var dist := g.distance_field(door.leaf.get_meta(&"cell"))
	var at := Vector2i(-1, -1)
	for i in dist.size():
		if dist[i] == 4:
			at = g.cell_at(i)
			break
	still.place_at(g.world_of(at))
	still.senses.sight_range = 0.0
	still.senses.hearing_mult = 0.0
	still.hint(g.world_of(at))
	still.wake()
	door.close()
	await await_physics_frames(2)
	assert_false(still.body.get_collision_exceptions().has(door.leaf), "a closed leaf blocks")
	door.open()
	await await_physics_frames(2)
	assert_true(still.body.get_collision_exceptions().has(door.leaf), "an open leaf does not")

