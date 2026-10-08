extends TestCase
## 08 §9 behaviour test on a generated level (Halls, seed 1; Garage has no grammar yet):
## Still spawned about 25 m of walking away while the player stands unobserving (fixtures
## off, flashlight off) reaches contact within 40 s, with the Director's Build-phase hints
## played by the test (a cell near the player, never the player's position). Then the
## same Still freezes while lit and observed.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const HINT_EVERY := 5.0
const SPAWN_CELLS := 12          # ~25 m walking (2 m cells)

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
	Engine.time_scale = 1.0
	_level.queue_free()


func after_each() -> void:
	Engine.time_scale = 1.0
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


func _cell_at_walk(from: Vector2i, cells: int) -> Vector2i:
	var g := _level.data.grid
	var dist := g.distance_field(from)
	for i in dist.size():
		if dist[i] == cells:
			return g.cell_at(i)
	return from


func test_contact_within_40_s_unobserved() -> void:
	assert_true(_level.builder.navigation_ok)
	var g := _level.data.grid
	_level.light_pool.set_all_powered(false)
	_p.flashlight.set_on(false, true)
	var pc := g.cell_of(_p.global_position)
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, Seeds.derive(_level.data.level_seed, ErrorBase.seed_label(&"still", 0)))
	_level.add_child(still)
	still.place_at(g.world_of(_cell_at_walk(pc, SPAWN_CELLS)))
	still.set_aggression(0.25)
	still.wake()
	var hits := [0]
	still.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	var observed := [0]
	Engine.time_scale = 4.0
	var t := 0.0
	var next_hint := 0.0
	var rng := make_rng(5)
	while hits[0] == 0 and t < 40.0:
		if t >= next_hint:
			next_hint += HINT_EVERY
			var near := g.world_of(_cell_at_walk(pc, rng.randi_range(1, 2)))
			still.hint(near)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		observed[0] += 1 if still.observed else 0
	assert_eq(observed[0], 0, "never observed in the dark")
	assert_eq(hits[0], 1, "contact after %.1f s (state %s)" % [t, still.state])
	_level.light_pool.set_all_powered(true)


func test_frozen_while_observed_in_a_lit_corridor() -> void:
	var g := _level.data.grid
	_level.light_pool.set_all_powered(true)
	_p.flashlight.set_on(true, true)
	# A straight open run of 4 cells; stand at its start and face along it.
	var pc := Vector2i(-1, -1)
	var dir := -1
	for i in g.cell_count():
		var c := g.cell_at(i)
		for d in 4:
			if g.is_walkable(c) and g.can_step(c, d) and g.can_step(c + LevelGrid.DIRS[d], d) \
					and g.can_step(c + LevelGrid.DIRS[d] * 2, d) and g.can_step(c + LevelGrid.DIRS[d] * 3, d):
				pc = c
				dir = d
				break
		if dir != -1:
			break
	assert_ne(dir, -1, "a straight run exists")
	if dir == -1:
		return
	_p.global_position = g.world_of(pc) + Vector3.UP * 0.05
	_level.light_pool.reevaluate()
	await await_physics_frames(30)
	var fwd := Vector3(LevelGrid.DIRS[dir].x, 0, LevelGrid.DIRS[dir].y)
	_p.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	var still := ErrorBase.create(&"still") as ErrorStill
	still.setup(_p, _level, 9)
	_level.add_child(still)
	still.place_at(g.world_of(pc + LevelGrid.DIRS[dir] * 3))
	still.set_aggression(1.0)
	still.hint(_p.global_position)
	still.wake()
	await await_physics_frames(2)
	var at := still.body_position()
	var frames := 0
	for i in 120:
		await get_tree().physics_frame
		frames += 1 if still.observed else 0
		assert_eq(still.body_position().distance_to(at), 0.0, "frame %d" % i)
		if still.body_position().distance_to(at) > 0.0:
			break
	assert_eq(frames, 120, "observed throughout")
