extends TestCase
## 09 §2, §5: items and notes in the world, and the spawner that places them from LevelData.

var _world: Node3D
var _p: Player
var _inv: Inventory


func before_each() -> void:
	PlayerFixture.release_all()
	SettingsManager.set_value(&"hold_to_press", false)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func _pickup(kind: StringName, pos: Vector3 = Vector3(0, 0, -5)) -> ItemPickup:
	var data := DataRegistry.item(kind)
	var p := data.world_scene.instantiate() as ItemPickup
	_world.add_child(p)
	p.global_position = pos
	return p


func test_pickup_scenes_exist_for_every_belt_item() -> void:
	for kind in [&"polaroid", &"chalk", &"glowstick", &"flare", &"radio", &"fuse"]:
		var data := DataRegistry.item(kind)
		assert_not_null(data.world_scene, "world_scene of %s" % kind)
		var p := _pickup(kind)
		assert_eq(p.kind, kind)
		assert_eq(p.body.collision_layer, 24, "layers 4 (interactable) and 5 (items)")
		assert_eq(p.body.collision_layer & PlayerLayers.INTERACTABLE_MASK, PlayerLayers.INTERACTABLE_MASK)
		assert_eq(Interactable.find_on(p.body), p.interactable)
		assert_eq(p.light.omni_range, 1.0)
		assert_approx(p.light.light_energy, 0.15)
		assert_gt(p.bob.get_child_count(), 1, "primitive model plus light")


func test_world_light_uses_the_item_colour() -> void:
	var p := _pickup(&"glowstick")
	assert_eq(p.light.light_color.to_html(false), "7cff4a")


func test_bob_is_two_centimetres_at_point_two_hertz() -> void:
	var p := _pickup(&"polaroid")
	var lo := 1e9
	var hi := -1e9
	for i in 600:
		p._process(0.1)  # 60 s: 12 cycles
		lo = minf(lo, p.bob.position.y)
		hi = maxf(hi, p.bob.position.y)
	assert_approx(hi - lo, 0.04, 0.002, "+-2 cm")
	assert_approx(Tuning.ITEM_WORLD_BOB_HZ, 0.2)


## R4 #12: a pickup rests just above the floor: its lowest point is 3 cm up at the bottom of the bob.
func test_pickups_rest_three_centimetres_above_the_floor() -> void:
	for kind in [&"polaroid", &"chalk", &"glowstick", &"flare", &"radio", &"fuse"]:
		var p := _pickup(kind)
		var model := p.bob.get_child(p.bob.get_child_count() - 1) as Node3D
		var low := INF
		for i in 60:
			p._process(0.1)
			low = minf(low, p.bob.position.y + ItemPickup.model_bottom(model))
		assert_approx(low, Tuning.ITEM_WORLD_REST_HEIGHT, 0.003, kind)


func test_ray_finds_the_pickup_and_prompts() -> void:
	var p := _pickup(&"glowstick", Vector3(0, 1.35, -1.5))  # body centre at eye height
	var prompts := []
	_p.prompt_changed.connect(func(t: String, _h: float) -> void: prompts.append(t))
	await await_physics_frames(3)
	assert_eq(_p.interactor.target, p.interactable)
	assert_eq(prompts.back(), "PICK UP GLOWSTICK")
	Input.action_press(&"interact")
	await await_physics_frames(2)
	Input.action_release(&"interact")
	assert_eq(_inv.count_of(&"glowstick"), 1)
	assert_true(p.picked)


func test_pickup_emits_item_picked_and_flies_away() -> void:
	var seen: Array[StringName] = []
	var cb := func(k: StringName) -> void: seen.append(k)
	EventBus.item_picked.connect(cb)
	var p := _pickup(&"polaroid")
	assert_true(p.take(_p))
	EventBus.item_picked.disconnect(cb)
	assert_eq(seen, [&"polaroid"] as Array[StringName])
	assert_true(p.picked)
	assert_false(p.interactable.can_interact(_p))
	await get_tree().create_timer(0.5).timeout
	assert_true(not is_instance_valid(p) or p.is_queued_for_deletion(), "gone after the 0.3 s fly-in")


func test_chalk_pickup_adds_eight_uses_and_tops_up_partially() -> void:
	var p := _pickup(&"chalk")
	assert_eq(p.count, 8)
	_inv.add(&"chalk", 15)
	assert_true(p.can_take(_inv))
	assert_false(p.take(_p), "only 5 fit")
	assert_eq(_inv.count_of(&"chalk"), 20)
	assert_eq(p.count, 3, "the rest stays in the world")
	assert_false(p.picked)
	assert_false(p.can_take(_inv), "a full stack cannot take more")
	assert_false(p.interactable.can_interact(_p))


func test_swap_when_the_belt_holds_four_other_kinds() -> void:
	_inv.add(&"polaroid", 2)
	_inv.add(&"chalk", 8)
	_inv.add(&"radio")
	_inv.add(&"fuse")
	var p := _pickup(&"glowstick", Vector3(1, 0, -3))
	assert_true(p.can_take(_inv))
	assert_eq(p.prompt_for(_inv), "SWAP FOR GLOWSTICK")
	assert_true(p.interactable.can_interact(_p))
	assert_eq(p.interactable.prompt_text(), "SWAP FOR GLOWSTICK")
	_inv.select(0)
	assert_true(p.take(_p))
	assert_eq(_inv.slots[0].kind, &"glowstick")
	assert_false(_inv.has(&"polaroid"))
	var dropped: Array[ItemPickup] = []
	for n in get_tree().get_nodes_in_group(&"pickups"):
		if n is ItemPickup and n != p and (n as ItemPickup).kind == &"polaroid":
			dropped.append(n)
	assert_eq(dropped.size(), 1, "the swapped-out stack lies at the player's feet")
	assert_eq(dropped[0].count, 2)
	assert_lt(dropped[0].global_position.distance_to(_p.global_position), 1.0)
	await get_tree().create_timer(0.5).timeout


## R4 #5 / M2.8: a swap puts the selected stack on the floor, so every belt kind needs a world
## scene (all of them have one now): swapping a fuse out works and the fuse lies at the feet.
func test_swap_out_of_a_fuse_puts_it_on_the_floor() -> void:
	_inv.add(&"polaroid", 2)
	_inv.add(&"chalk", 8)
	_inv.add(&"radio")
	_inv.add(&"fuse")
	_inv.select(_inv.slot_of(&"fuse"))
	var p := _pickup(&"glowstick", Vector3(1, 0, -3))
	assert_true(_inv.can_swap_out())
	assert_true(p.can_take(_inv))
	assert_true(p.take(_p))
	assert_false(_inv.has(&"fuse"))
	var dropped := get_tree().get_nodes_in_group(&"pickups").filter(
			func(n: Node) -> bool: return n is ItemPickup and (n as ItemPickup).kind == &"fuse")
	assert_eq(dropped.size(), 1, "the fuse lies at the player's feet")
	await get_tree().create_timer(0.5).timeout


## R4 #17: a partly fitting Polaroid pickup moves only the accepted photos to the belt.
func test_partial_polaroid_pickup_moves_only_accepted_photos() -> void:
	_inv.add(&"polaroid", 2, {&"images": [0, 1]})
	var p := _pickup(&"polaroid")
	p.count = 2
	p.state = {&"images": [5, 6]}
	assert_false(p.take(_p), "only one fits; the pickup stays")
	assert_eq(_inv.count_of(&"polaroid"), 3)
	assert_eq(_inv.slots[_inv.slot_of(&"polaroid")].state[&"images"], [0, 1, 5])
	assert_eq(p.count, 1)
	assert_eq(p.state[&"images"], [6], "the photo of the one left behind stays with it")


func test_a_fifth_kind_without_a_selected_item_cannot_swap_nothing() -> void:
	var p := _pickup(&"glowstick")
	assert_true(p.can_take(_inv), "a free slot takes it")
	assert_eq(p.prompt_for(_inv), "PICK UP GLOWSTICK")


func test_prompt_strings_follow_04() -> void:
	var p := _pickup(&"chalk")
	assert_eq(p.prompt_for(_inv), "PICK UP CHALK")
	assert_eq(Interactable.new().prompt_text(), "")


# --- notes ------------------------------------------------------------------------------

func test_note_pickup_announces_and_disappears() -> void:
	var n := (load("res://scenes/interactables/note_pickup.tscn") as PackedScene).instantiate() as NotePickup
	n.note_id = &"H3"
	_world.add_child(n)
	assert_eq(n.body.collision_layer, 24)
	assert_eq(n.interactable.prompt_text(), "READ")
	var found: Array[StringName] = []
	var cb := func(id: StringName) -> void: found.append(id)
	EventBus.note_found.connect(cb)
	assert_true(n.read())
	assert_false(n.read(), "once")
	EventBus.note_found.disconnect(cb)
	assert_eq(found, [&"H3"] as Array[StringName])
	assert_false(n.interactable.can_interact(_p))
	await get_tree().create_timer(0.4).timeout
	assert_true(not is_instance_valid(n) or n.is_queued_for_deletion(), "the paper leaves the world")


func test_note_pickup_without_an_id_does_nothing() -> void:
	var n := (load("res://scenes/interactables/note_pickup.tscn") as PackedScene).instantiate() as NotePickup
	_world.add_child(n)
	assert_false(n.read())


func test_hud_shows_the_note_sheet_when_found() -> void:
	UiMotion.manual_clock = true
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	var n := (load("res://scenes/interactables/note_pickup.tscn") as PackedScene).instantiate() as NotePickup
	n.note_id = &"H5"
	_world.add_child(n)
	n.read()
	assert_eq(hud.note_sheet.note.id, &"H5")
	hud.free()
	UiMotion.manual_clock = false


# --- spawner ----------------------------------------------------------------------------

func _level(stratum: StringName = &"halls") -> LevelData:
	var l := LevelData.new()
	l.stratum = stratum
	l.depth = 1
	l.add_placement(LevelData.P_ITEM, Vector2i(3, 4), Vector3.ZERO, 0.0, {&"item": &"polaroid", &"guaranteed": true})
	l.add_placement(LevelData.P_ITEM, Vector2i(5, 1), Vector3.ZERO, 0.0, {&"item": &"chalk", &"guaranteed": false})
	l.add_placement(LevelData.P_ITEM, Vector2i(6, 6), Vector3.ZERO, 0.0, {&"item": &"glowstick", &"guaranteed": false})
	l.add_placement(LevelData.P_ITEM, Vector2i(7, 7), Vector3.ZERO, 0.0, {&"item": &"flare", &"guaranteed": false})
	l.add_placement(LevelData.P_NOTE, Vector2i(2, 2), Vector3.ZERO, 0.0, {&"slot": 0, &"early": true, &"first_descent": false})
	l.add_placement(LevelData.P_NOTE, Vector2i(8, 8), Vector3.ZERO, 0.0, {&"slot": 1, &"early": false, &"first_descent": false})
	return l


func test_spawner_places_items_and_notes_at_the_markers() -> void:
	var root := Node3D.new()
	_world.add_child(root)
	var rng := make_rng(5)
	var out := ItemSpawner.populate(root, _level(), rng, {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: false})
	var items := out.filter(func(n: Node3D) -> bool: return n is ItemPickup)
	var notes := out.filter(func(n: Node3D) -> bool: return n is NotePickup)
	assert_eq(items.size(), 4, "every kind, the flare too, has a world scene since M2.8")
	assert_eq(notes.size(), 2)
	assert_eq(root.get_child_count(), 6)
	var pol := items.filter(func(n: ItemPickup) -> bool: return n.kind == &"polaroid")[0] as ItemPickup
	var j := Tuning.ITEM_PLACE_JITTER + 0.0001
	assert_eq(pol.position.y, 0.0, "on the floor")
	assert_lt(absf(pol.position.x - 6.0), j, "cell (3,4) at 2 m per cell, jittered in the cell")
	assert_lt(absf(pol.position.z - 8.0), j)
	assert_eq(pol.state[&"images"].size(), 1, "a Polaroid pickup is assigned one photo")
	assert_lt(int(pol.state[&"images"][0]), 8)
	var chalk := items.filter(func(n: ItemPickup) -> bool: return n.kind == &"chalk")[0] as ItemPickup
	assert_eq(chalk.count, 8)
	var ids: Array[StringName] = []
	for n in notes:
		ids.append((n as NotePickup).note_id)
	assert_ne(ids[0], ids[1], "two different notes")
	for id in ids:
		assert_eq(DataRegistry.note(id).stratum, &"halls")
		assert_eq(DataRegistry.note(id).tier, 1, "tier 2 waits for the stratum to have been reached")


func test_spawner_is_deterministic_per_seed() -> void:
	var picks := []
	for i in 2:
		var root := Node3D.new()
		_world.add_child(root)
		var out := ItemSpawner.populate(root, _level(), make_rng(77), {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: true})
		var sig := []
		for n in out:
			sig.append(n.name)
			sig.append(n.transform)
			if n is ItemPickup:
				sig.append(n.state.get(&"images"))
		picks.append(sig)
		root.free()
	assert_eq(picks[0], picks[1])


func test_notes_prefer_unfound_then_repeat_at_half_weight() -> void:
	var l := _level()
	var rng := make_rng(3)
	var found: Array = [&"H1", &"H2", &"H3", &"H5"]
	var ids := ItemSpawner.pick_notes(l, rng, {ItemSpawner.OPT_FOUND: found, ItemSpawner.OPT_STRATUM_REACHED: true})
	assert_eq(ids.size(), 2)
	assert_true(ids.has(&"H4") and ids.has(&"H6"), "the two unfound notes come first: %s" % [ids])
	# Everything found: found notes still appear, never the same one twice in a level.
	var all_found: Array = []
	for n in DataRegistry.notes_for(&"halls"):
		all_found.append(n.id)
	ids = ItemSpawner.pick_notes(l, make_rng(3), {ItemSpawner.OPT_FOUND: all_found, ItemSpawner.OPT_STRATUM_REACHED: true})
	assert_ne(ids[0], &"")
	assert_ne(ids[0], ids[1])


func test_tier_two_notes_need_the_stratum_reached() -> void:
	var l := _level()
	for s in 20:
		var ids := ItemSpawner.pick_notes(l, make_rng(s), {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: false})
		for id in ids:
			assert_true(id in [&"H1", &"H2", &"H3", &"H5"], "tier 1 only, got %s" % id)
	var seen_t2 := false
	for s in 40:
		var ids := ItemSpawner.pick_notes(l, make_rng(s), {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: true})
		seen_t2 = seen_t2 or ids.has(&"H4") or ids.has(&"H6")
	assert_true(seen_t2)


func test_first_descent_note_is_h1() -> void:
	var l := LevelData.new()
	l.stratum = &"halls"
	l.add_placement(LevelData.P_NOTE, Vector2i(1, 1), Vector3.ZERO, 0.0, {&"slot": 0, &"early": true, &"first_descent": true})
	l.add_placement(LevelData.P_NOTE, Vector2i(5, 5), Vector3.ZERO, 0.0, {&"slot": 1, &"early": false, &"first_descent": false})
	for s in 10:
		var ids := ItemSpawner.pick_notes(l, make_rng(s), {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: false})
		assert_eq(ids[0], &"H1")
		assert_ne(ids[1], &"H1")


func test_spawner_on_a_generated_level() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 4242, true)
	var root := Node3D.new()
	_world.add_child(root)
	var out := ItemSpawner.populate(root, level, make_rng(1))
	var expect_items := 0
	for p in level.placements_of(LevelData.P_ITEM):
		if DataRegistry.item(p[&"params"][&"item"]).world_scene != null:
			expect_items += 1
	var items := out.filter(func(n: Node3D) -> bool: return n is ItemPickup)
	var notes := out.filter(func(n: Node3D) -> bool: return n is NotePickup)
	assert_eq(items.size(), expect_items)
	assert_eq(notes.size(), level.placements_of(LevelData.P_NOTE).size())
	assert_gt(items.size(), 0)
	for n in out:
		var centre := level.grid.world_of(level.grid.cell_of(n.position))
		if n is ItemPickup:
			assert_lt(absf(n.position.x - centre.x), Tuning.ITEM_PLACE_JITTER + 0.0001, "in the placement's cell")
			assert_lt(absf(n.position.z - centre.z), Tuning.ITEM_PLACE_JITTER + 0.0001)
		else:
			assert_eq(n.position, centre, "on the placement's cell")
	root.free()
