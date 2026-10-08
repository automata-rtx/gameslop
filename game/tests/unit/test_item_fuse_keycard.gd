extends TestCase
## 09 §2, §5, §10: the Fuse (carried, inserted into and pulled from a Variant B breaker) and
## the Keycard (not a belt item; picked up, swiped at the reader).

const BREAKER := "res://scenes/interactables/breaker.tscn"
const READER := "res://scenes/interactables/card_reader.tscn"

var _world: Node3D
var _p: Player
var _inv: Inventory


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func _breaker(variant: StringName) -> Breaker:
	var b := (load(BREAKER) as PackedScene).instantiate() as Breaker
	b.variant = variant
	b.position = Vector3(0, 0, -3)
	_world.add_child(b)
	return b


func test_fuse_is_a_one_stack_belt_item_with_a_world_scene() -> void:
	var data := DataRegistry.item(&"fuse")
	assert_eq(data.cap, 1)
	assert_approx(data.use_time, 0.8)
	assert_not_null(data.world_scene)
	assert_eq(_inv.add(&"fuse", 2), 1)
	assert_eq(_inv.count_of(&"fuse"), 1)


func test_variant_b_prompts_follow_the_belt() -> void:
	var b := _breaker(Breaker.VARIANT_B)
	assert_false(b.fuse_in)
	assert_true(b.interactable.can_interact(_p))
	assert_eq(b.interactable.prompt_text(), Strings.PROMPT_FUSE_MISSING)
	assert_approx(b.interactable.hold_time, 0.0, 0.0001, "FUSE MISSING is a keyless notice")
	_inv.add(&"fuse")
	assert_true(b.interactable.can_interact(_p))
	assert_eq(b.interactable.prompt_text(), Strings.PROMPT_INSERT_FUSE)
	assert_approx(b.interactable.hold_time, Tuning.FUSE_INSERT_TIME)


func test_insert_takes_the_fuse_and_arms_the_lever() -> void:
	var b := _breaker(Breaker.VARIANT_B)
	assert_false(b.insert_fuse(_p), "nothing to insert")
	_inv.add(&"fuse")
	var used := []
	var cb := func(k: StringName) -> void: used.append(k)
	EventBus.item_used.connect(cb)
	assert_true(b.insert_fuse(_p))
	EventBus.item_used.disconnect(cb)
	assert_eq(used, [&"fuse"])
	assert_true(b.fuse_in)
	assert_false(_inv.has(&"fuse"))
	assert_eq(b.interactable.prompt_text(), Strings.PROMPT_FLIP_BREAKER)
	assert_true(b.throw_breaker())


func test_pull_gives_the_fuse_back_until_the_lever_is_thrown() -> void:
	var b := _breaker(Breaker.VARIANT_B)
	assert_false(b.socket_interactable.can_interact(_p), "an empty socket offers nothing to pull")
	_inv.add(&"fuse")
	b.insert_fuse(_p)
	assert_true(b.socket_interactable.can_interact(_p))
	assert_eq(b.socket_interactable.prompt_text(), Strings.PROMPT_PULL_FUSE)
	assert_approx(b.socket_interactable.hold_time, Tuning.FUSE_INSERT_TIME, 0.0001, "0.8 s out as well as in")
	assert_eq(b.socket.collision_layer & PlayerLayers.INTERACTABLE_MASK, PlayerLayers.INTERACTABLE_MASK)
	assert_true(b.pull_fuse(_p))
	assert_false(b.fuse_in)
	assert_true(_inv.has(&"fuse"))
	assert_false(b.throw_breaker(), "no fuse, no lever")
	_inv.consume(&"fuse", 1)
	_inv.add(&"fuse")
	b.insert_fuse(_p)
	b.throw_breaker()
	assert_false(b.pull_fuse(_p), "thrown: the fuse stays")
	assert_eq(b.socket.collision_layer, 0)


func test_pull_needs_room_on_the_belt() -> void:
	var b := _breaker(Breaker.VARIANT_B)
	_inv.add(&"fuse")
	b.insert_fuse(_p)
	_inv.add(&"polaroid")
	_inv.add(&"chalk")
	_inv.add(&"glowstick")
	_inv.add(&"radio")
	assert_false(b.socket_interactable.can_interact(_p), "four other kinds: nowhere to put it")
	assert_false(b.pull_fuse(_p))
	assert_true(b.fuse_in)


func test_variant_a_has_no_socket() -> void:
	var b := _breaker(Breaker.VARIANT_A)
	assert_true(b.fuse_in)
	assert_eq(b.socket.collision_layer, 0)
	assert_false(b.socket_interactable.can_interact(_p))
	assert_false(b.pull_fuse(_p))


func test_the_player_ray_finds_the_socket() -> void:
	var b := _breaker(Breaker.VARIANT_B)
	b.rotation.y = PI  # the front faces +Z, towards the player
	b.global_position = Vector3(0, 0, -3.0)
	_inv.add(&"fuse")
	b.insert_fuse(_p)
	_p.global_position = Vector3(0.11, 0.05, -1.2)
	_p.rotation = Vector3.ZERO
	_p.rig.reset_pitch()
	_p.rig.add_pitch(atan2(1.2 - 1.68, 1.5))
	await await_physics_frames(4)
	assert_eq(_p.interactor.target, b.socket_interactable, "the small socket box is its own target")
	assert_eq(_p.interactor.target.prompt_text(), Strings.PROMPT_PULL_FUSE)


func test_the_keycard_is_not_a_belt_item() -> void:
	var data := DataRegistry.item(&"keycard")
	assert_false(data.belt_item)
	assert_eq(_inv.add(&"keycard"), 0)
	assert_false(_inv.can_accept(&"keycard"))
	assert_false(_inv.has(&"keycard"))
	assert_eq(Inventory.cap_of(&"keycard"), 0)
	assert_not_null(data.world_scene, "it lies in the world")


func test_keycard_pickup_sets_the_card_not_a_slot() -> void:
	var card := ItemPickup.spawn(_world, &"keycard", 0, {}, Vector3(0, 0, -2)) as KeycardPickup
	assert_not_null(card)
	assert_eq(card.prompt_for(_inv), "PICK UP KEYCARD")
	var seen := []
	var cb := func(has: bool) -> void: seen.append(has)
	_inv.keycard_changed.connect(cb)
	var picked := []
	var cb2 := func(k: StringName) -> void: picked.append(k)
	EventBus.item_picked.connect(cb2)
	assert_true(card.take(_p))
	EventBus.item_picked.disconnect(cb2)
	assert_true(_inv.keycard)
	assert_eq(seen, [true])
	assert_eq(picked, [&"keycard"])
	for s in _inv.slots:
		assert_null(s, "no belt slot is used")
	assert_true(card.picked)
	await get_tree().create_timer(0.5).timeout


func test_keycard_is_dropped_when_the_level_ends() -> void:
	_inv.set_keycard(true)
	EventBus.level_left.emit(true)
	assert_false(_inv.keycard)
	_inv.set_keycard(true)
	_inv.reset()
	assert_false(_inv.keycard, "a new Descent starts without it")


func test_keycard_glows_in_the_accent_colour_out_to_twenty_metres() -> void:
	var card := ItemPickup.spawn(_world, &"keycard", 0, {}, Vector3(0, 0, -2)) as KeycardPickup
	var meshes := card.bob.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for m in meshes:
		assert_approx((m as MeshInstance3D).visibility_range_end, Tuning.KEYCARD_VISIBLE_DIST)
	var lo := 1e9
	var hi := -1e9
	var cardm := (card.bob.find_child("Card", true, false) as MeshInstance3D).material_override as ShaderMaterial
	for i in 60:
		card._process(0.05)
		var e := float(cardm.get_shader_parameter(&"emission_strength"))
		lo = minf(lo, e)
		hi = maxf(hi, e)
	assert_gt(hi - lo, 1.0, "it pulses")
	var col := cardm.get_shader_parameter(&"emission") as Color
	assert_eq(col.to_html(false), UiTokens.UI_ACCENT.to_html(false))


func test_card_reader_stub_offers_swipe_or_no_card() -> void:
	var r := (load(READER) as PackedScene).instantiate() as CardReader
	_world.add_child(r)
	r.global_position = Vector3(0, 0, -3)
	assert_true(r.interactable.can_interact(_p))
	assert_eq(r.interactable.prompt_text(), Strings.PROMPT_NO_CARD)
	assert_true(Strings.NOTICE_PROMPTS.has(r.interactable.prompt_text()), "dim and keyless")
	var swiped := []
	r.swiped.connect(func(pl: Node) -> void: swiped.append(pl))
	var rejected := [0]
	r.rejected.connect(func(_pl: Node) -> void: rejected[0] += 1)
	assert_false(r.swipe(_p))
	assert_eq(rejected[0], 1)
	assert_eq(swiped.size(), 0)
	_inv.set_keycard(true)
	assert_true(r.interactable.can_interact(_p))
	assert_eq(r.interactable.prompt_text(), Strings.PROMPT_SWIPE)
	assert_true(r.swipe(_p))
	assert_eq(swiped, [_p])
	assert_true(r.accepted)
	assert_true(_inv.keycard, "the reader does not take the card")
	assert_false(r.interactable.can_interact(_p), "once")
	assert_false(r.swipe(_p))
