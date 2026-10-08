extends TestCase
## 08 §4 (2026-10-08 ruling) on a real Halls level: Still is observed when ANY observe
## point is in the frustum, has a clear ray and is lit. The 2.1 m door header hides the
## column's upper point; the centre stays clear. With the eye 6 m from a doorway and Still
## in the doorway or 0 to 2 m past it, light on, it never moves a millimetre over 180
## frames. Also the drawn column's top stays under the header while it overlaps the
## doorway (R9, presentation only).

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const EYE_FROM_DOORWAY := 6.0
const FRAMES := 180
const OFFSETS: Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0]

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
	await await_physics_frames(10)


func after_all() -> void:
	_level.queue_free()


func after_each() -> void:
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


## A doorway the viewer can face down a straight run: [door, cell before the doorway
## (viewer side), dir toward the doorway]. The run holds 3 open cells before the doorway
## edge and 2 cells past it, so the eye stands 6 m back and Still up to 2 m past.
func _doorway() -> Array:
	var g := _level.data.grid
	for n in get_tree().get_nodes_in_group(&"doors"):
		var door := n as Door
		if door == null or not door.leaf.has_meta(&"cell"):
			continue
		var c0: Vector2i = door.leaf.get_meta(&"cell")
		var d0 := int(door.leaf.get_meta(&"dir"))
		for side in 2:
			var c := c0 if side == 0 else c0 + LevelGrid.DIRS[d0]
			var d := d0 if side == 0 else LevelGrid.opposite(d0)
			if _straight(g, c, d):
				return [door, c, d]
	return []


func _straight(g: LevelGrid, c: Vector2i, d: int) -> bool:
	var dv := LevelGrid.DIRS[d]
	var back := LevelGrid.opposite(d)
	# Back from the doorway cell: three cells joined by open edges (no other door).
	for k in 3:
		var a := c - dv * k
		if not g.is_walkable(a) or g.wall(a, back) != LevelGrid.NONE or not g.can_step(a, back):
			return false
	# Past the doorway: two cells in a straight line.
	return g.can_step(c, d) and g.can_step(c + dv, d) and g.wall(c + dv, d) == LevelGrid.NONE


func test_observed_in_and_past_a_doorway_never_moves() -> void:
	assert_true(_level.builder.navigation_ok)
	var found := _doorway()
	assert_false(found.is_empty(), "the Halls level has a doorway down a straight run")
	if found.is_empty():
		return
	var door: Door = found[0]
	var c: Vector2i = found[1]
	var d: int = found[2]
	var g := _level.data.grid
	var dv := LevelGrid.DIRS[d]
	var fwd := Vector3(dv.x, 0.0, dv.y)
	door.open()
	await await_physics_frames(int(Tuning.DOOR_SWING_TIME * Engine.physics_ticks_per_second) + 2)
	_level.light_pool.set_all_powered(true)
	_p.flashlight.set_on(true, true)
	var plane := g.world_of(c) + fwd * Tuning.GRID_CELL_SIZE * 0.5
	_p.global_position = plane - fwd * EYE_FROM_DOORWAY + Vector3.UP * 0.05
	_p.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	_level.light_pool.reevaluate()
	await await_physics_frames(20)
	assert_approx(ErrorFixture.flat(_p.eye_position(), plane), EYE_FROM_DOORWAY, 0.1, "eye 6 m from the doorway")
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, 31)
	_level.add_child(still)
	still.senses.sight_range = 0.0
	still.senses.hearing_mult = 0.0
	still.set_aggression(1.0)
	for off in OFFSETS:
		var at := plane + fwd * off
		at.y = g.floor_y(g.cell_of(at))
		still.place_at(at)
		# Hinted onto the player: unobserved, it would walk straight at them at once.
		still.hint(_p.global_position, true)
		if still.is_dormant():
			still.wake()
		await await_physics_frames(1)
		var start := still.body_position()
		var moved := 0.0
		var seen := 0
		for i in FRAMES:
			await get_tree().physics_frame
			moved = maxf(moved, still.body_position().distance_to(start))
			seen += 1 if still.observed else 0
		assert_eq(seen, FRAMES, "observed every frame at %.1f m past the doorway" % off)
		assert_lt(moved, 0.001, "not a millimetre at %.1f m past the doorway (moved %.4f m)" % [off, moved])


func test_drawn_column_stays_under_the_header_in_a_doorway() -> void:
	var found := _doorway()
	if found.is_empty():
		fail("no doorway")
		return
	var c: Vector2i = found[1]
	var d: int = found[2]
	var g := _level.data.grid
	var fwd := Vector3(LevelGrid.DIRS[d].x, 0.0, LevelGrid.DIRS[d].y)
	var plane := g.world_of(c) + fwd * Tuning.GRID_CELL_SIZE * 0.5
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, 32)
	_level.add_child(still)
	for off in [-0.5, 0.0, 0.5]:
		still.place_at(plane + fwd * off)
		var top := still.column.scale.y * Tuning.STILL_CAPSULE_HEIGHT
		assert_lt(top, Tuning.LEVELBUILD_DOOR_HEIGHT, "column top %.2f m under the 2.1 m header at %.1f m" % [top, off])
	still.place_at(plane + fwd * Tuning.GRID_CELL_SIZE * 0.5)
	assert_approx(still.column.scale.y, 1.0, 0.0001, "full 2.6 m away from the header")
	# The rule's body and observe points are untouched by the drawn height.
	var pts := still.observe_points()
	assert_approx(pts[1].y - still.body_position().y, Tuning.STILL_CAPSULE_HEIGHT - Tuning.STILL_EYE_POINT_TOP, 0.0001)
	assert_eq(StillPresent.column_height(null, Vector3.ZERO), Tuning.STILL_CAPSULE_HEIGHT, "no grid: 2.6 m")
