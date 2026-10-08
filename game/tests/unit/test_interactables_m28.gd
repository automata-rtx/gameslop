extends TestCase
## 09 §5, §10: the vending machine and the payphone as interactables; the spawner and the
## Landing now know every kind.

const VENDING := "res://scenes/props/halls/vending.tscn"
const PAYPHONE := "res://scenes/props/halls/payphone.tscn"

var _world: Node3D
var _p: Player
var _inv: Inventory
var _noises: Array = []
var _noise_cb: Callable


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_noises = []
	_noise_cb = func(pos: Vector3, r: float, kind: StringName) -> void: _noises.append([pos, r, kind])
	EventBus.noise_emitted.connect(_noise_cb)


func after_each() -> void:
	EventBus.noise_emitted.disconnect(_noise_cb)
	PlayerFixture.release_all()
	_world.free()


func _vending(pos: Vector3 = Vector3(0, 0, -3)) -> Vending:
	var v := (load(VENDING) as PackedScene).instantiate() as Vending
	v.position = pos  # before the tree: a body added at the origin would push the player
	_world.add_child(v)
	return v


func _payphone(pos: Vector3 = Vector3(0, 0, -3)) -> Payphone:
	var ph := (load(PAYPHONE) as PackedScene).instantiate() as Payphone
	ph.position = pos
	_world.add_child(ph)
	return ph


# --- vending ----------------------------------------------------------------------------------

func test_vending_offers_use_once() -> void:
	var v := _vending()
	assert_true(v.interactable.can_interact(_p))
	assert_eq(v.interactable.prompt_text(), "USE")
	assert_eq(v.collider.collision_layer & PlayerLayers.INTERACTABLE_MASK, PlayerLayers.INTERACTABLE_MASK)
	assert_true(v.use())
	assert_false(v.interactable.can_interact(_p), "once per machine")
	assert_false(v.use())


func test_vending_whirs_8_m_then_dispenses_a_pickup_into_the_tray() -> void:
	var v := _vending()
	var got: Array[Node3D] = []
	v.dispensed.connect(func(n: Node3D) -> void: got.append(n))
	v.use()
	var mech := _noises.filter(func(n: Array) -> bool: return n[2] == &"mech")
	assert_eq(mech.size(), 1)
	assert_approx(float(mech[0][1]), 8.0)
	assert_eq(got.size(), 0, "nothing until the 1.0 s whir ends")
	await get_tree().create_timer(Tuning.VENDING_WHIR_TIME + 0.2).timeout
	assert_eq(got.size(), 1)
	var pk := got[0] as ItemPickup
	assert_not_null(pk)
	assert_ne(v.item, &"")
	assert_eq(pk.kind, v.item)
	assert_approx(pk.global_position.y, 0.3, 0.001, "in the tray")
	assert_lt(pk.global_position.distance_to(v.global_position + Vector3(0, 0.3, -0.5)), 0.3)
	assert_true(pk.interactable.can_interact(_p), "[E] PICK UP")


func test_vending_dispenses_from_the_unlocked_pool_never_a_fuse() -> void:
	var meta := MetaState.new()
	meta.earn(&"glowstick")
	meta.earn(&"flare")
	meta.earn(&"radio")
	meta.earn(&"fuse")
	var pool := RunLevelSetup.item_pool(meta)
	var seen := {}
	for s in 400:
		var k := Vending.pick_kind(pool, make_rng(s))
		assert_ne(k, &"fuse")
		assert_true(pool.has(k))
		seen[k] = int(seen.get(k, 0)) + 1
	for k: StringName in [&"polaroid", &"glowstick", &"chalk", &"flare", &"radio"]:
		assert_true(seen.has(k), "%s can come out" % k)
	assert_gt(int(seen[&"polaroid"]), int(seen[&"radio"]), "by the base weights (3 to 1)")
	assert_eq(Vending.pick_kind([] as Array[StringName], make_rng(1)), &"")


func test_vending_pick_is_seeded_by_the_machine() -> void:
	var a := _vending(Vector3(4, 0, -3))
	var b := _vending(Vector3(-6, 0, 8))
	var pool: Array[StringName] = [&"polaroid", &"chalk", &"glowstick", &"flare", &"radio"]
	assert_eq(Vending.pick_kind(pool, Vending.rng_for(a)), Vending.pick_kind(pool, Vending.rng_for(a)), "deterministic")
	var differ := false
	for x in 10:
		var c := _vending(Vector3(x * 3.0, 0, 20))
		differ = differ or Vending.pick_kind(pool, Vending.rng_for(c)) != Vending.pick_kind(pool, Vending.rng_for(b))
	assert_true(differ, "machines draw differently")


func test_vending_hums() -> void:
	var v := _vending()
	assert_not_null(v._hum)
	assert_true(v._hum.is_valid())
	assert_true(AudioManager.has_sound(Vending.SOUND_HUM))
	assert_true(AudioManager.has_sound(Vending.SOUND_WHIR))


# --- payphone ---------------------------------------------------------------------------------

func test_payphone_offers_answer_only_while_ringing() -> void:
	var ph := _payphone()
	assert_false(ph.interactable.can_interact(_p), "silent: nothing to answer")
	assert_true(ph.ring())
	assert_true(ph.interactable.can_interact(_p))
	assert_eq(ph.interactable.prompt_text(), "ANSWER")
	assert_false(ph.ring(), "already ringing")
	assert_true(ph.answer(_p))
	assert_false(ph.ringing)
	assert_false(ph.interactable.can_interact(_p))
	assert_false(ph.answer(_p))


func test_ringing_is_an_18_m_door_noise_every_six_seconds_for_thirty() -> void:
	var ph := _payphone()
	ph.ring()
	for i in 600:
		ph.tick(0.1)
	var doors := _noises.filter(func(n: Array) -> bool: return n[2] == &"door")
	assert_eq(doors.size(), 5, "at 0, 6, 12, 18 and 24 s; it stops at 30 s")
	assert_approx(float(doors[0][1]), 18.0)
	assert_false(ph.ringing, "30 s unanswered: it gives up")
	assert_eq(Tuning.PAYPHONE_RING_ON_TIME + Tuning.PAYPHONE_RING_OFF_TIME, 6.0)


func test_answering_silences_the_ring_and_plays_the_line() -> void:
	var ph := _payphone()
	ph.ring()
	ph.tick(0.1)
	_noises.clear()
	var heard := [0]
	ph.answered.connect(func() -> void: heard[0] += 1)
	assert_true(ph.answer(_p))
	assert_eq(heard[0], 1)
	for i in 100:
		ph.tick(0.1)
	assert_eq(_noises.size(), 0, "silent after the answer")
	assert_true(AudioManager.has_sound(Payphone.SOUND_LINE))
	assert_approx(Tuning.PAYPHONE_LINE_HUM_TIME, 2.0)


func test_the_director_finds_a_payphone_15_to_40_m_away() -> void:
	var near := _payphone(Vector3(0, 0, -5))
	var mid := _payphone(Vector3(0, 0, -20))
	var far := _payphone(Vector3(0, 0, -60))
	var c := Payphone.candidates(get_tree(), Vector3.ZERO)
	assert_eq(c, [mid] as Array[Payphone])
	mid.ring()
	assert_eq(Payphone.candidates(get_tree(), Vector3.ZERO).size(), 0, "a ringing phone is not a candidate")
	assert_not_null(near)
	assert_not_null(far)


func test_the_player_ray_finds_the_machine() -> void:
	var v := (load(VENDING) as PackedScene).instantiate() as Vending
	v.position = Vector3(0, 0, -2.0)
	v.rotation.y = PI  # the panel faces +Z, the player
	_world.add_child(v)
	await await_physics_frames(4)
	assert_approx(_p.global_position.z, 0.0, 0.01, "nothing pushed the player")
	assert_eq(_p.interactor.target, v.interactable)
	assert_eq(_p.interactor.target.prompt_text(), "USE")


# --- the spawner and the Landing know every kind ---------------------------------------------------

func test_spawner_spawns_every_kind() -> void:
	var l := LevelData.new()
	l.stratum = &"halls"
	l.depth = 1
	var kinds: Array[StringName] = [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse"]
	for i in kinds.size():
		l.add_placement(LevelData.P_ITEM, Vector2i(2 + i, 3), Vector3.ZERO, 0.0, {&"item": kinds[i], &"guaranteed": false})
	l.add_placement(LevelData.P_KEYCARD, Vector2i(9, 9))
	var root := Node3D.new()
	_world.add_child(root)
	var out := ItemSpawner.populate(root, l, make_rng(3), {ItemSpawner.OPT_FOUND: [], ItemSpawner.OPT_STRATUM_REACHED: false})
	var got: Array[StringName] = []
	for n in out:
		if n is ItemPickup:
			got.append((n as ItemPickup).kind)
	for k in kinds:
		assert_true(got.has(k), "%s spawned" % k)
	assert_true(got.has(&"keycard"), "the keycard spawns from its placement")
	assert_eq(got.size(), kinds.size() + 1)
	for n in out:
		if n is KeycardPickup:
			assert_eq((n as KeycardPickup).count, 1)


func test_landing_offers_flare_radio_and_fuse_once_unlocked() -> void:
	var meta := MetaState.new()
	for u in [&"glowstick", &"flare", &"radio", &"fuse"]:
		meta.earn(u)
	var pool := RunLevelSetup.item_pool(meta)
	for k: StringName in [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse"]:
		assert_true(pool.has(k), "%s in the pool" % k)
	var accept_all := func(_k: StringName) -> bool: return true
	var none_held := func(_k: StringName) -> int: return 0
	var offered := {}
	for s in 120:
		for k in RunLevelSetup.landing_choices(pool, accept_all, none_held, make_rng(s)):
			offered[k] = true
	for k: StringName in [&"flare", &"radio", &"fuse"]:
		assert_true(offered.has(k), "the Landing offers %s" % k)
	assert_false(offered.has(&"keycard"))


func test_the_landing_panel_shows_the_new_kinds() -> void:
	var panel := LandingPanel.new()
	_world.add_child(panel)
	panel.setup([&"flare", &"radio"] as Array[StringName], 20.0, false)
	assert_true(panel.choose(1))
	assert_eq(panel.kinds[panel.chosen_index], &"radio")
	panel.free()
