extends TestCase
## 09 §1, §10: the belt. Four kinds, each stacking to its cap, swap, selection, the HUD
## contract (04 additions: changed(slots, selected), slots, selected), item_used / item_picked.

var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()
	add_child(inv)


func after_each() -> void:
	inv.free()


func test_starts_empty_with_four_slots() -> void:
	assert_eq(inv.slots.size(), 4)
	for s in inv.slots:
		assert_null(s)
	assert_eq(inv.selected, 0)
	assert_false(inv.has(&"polaroid"))
	assert_eq(inv.selected_kind(), &"")


func test_four_kinds_and_no_fifth() -> void:
	assert_eq(inv.add(&"polaroid"), 1)
	assert_eq(inv.add(&"glowstick"), 1)
	assert_eq(inv.add(&"chalk", 8), 8)
	assert_eq(inv.add(&"radio"), 1)
	assert_eq(inv.add(&"flare"), 0, "09 §1: a fifth kind needs a swap")
	assert_false(inv.can_accept(&"flare"))
	assert_true(inv.can_accept(&"polaroid"), "a kind already held still stacks")
	assert_eq(inv.first_free_slot(), -1)


func test_caps_come_from_item_data() -> void:
	assert_eq(inv.add(&"polaroid", 5), 3, "Polaroid cap 3")
	assert_eq(inv.add(&"polaroid", 1), 0)
	assert_false(inv.can_accept(&"polaroid"))
	assert_eq(inv.add(&"glowstick", 9), 4, "Glowstick cap 4")
	assert_eq(inv.add(&"radio", 2), 1, "Radio cap 1")
	for kind in Tuning.ITEM_KINDS:
		assert_eq(Inventory.cap_of(kind), int(Tuning.ITEM_CAP[kind]), "cap of %s" % kind)


func test_chalk_is_one_stack_of_twenty_uses() -> void:
	assert_eq(inv.add(&"chalk", 8), 8)
	assert_eq(inv.add(&"chalk", 8), 8)
	assert_eq(inv.add(&"chalk", 8), 4, "the third pickup tops the stack up to 20")
	assert_eq(inv.count_of(&"chalk"), 20)
	assert_eq(inv.add(&"chalk", 8), 0)
	var used := 0
	for i in inv.slots:
		if i != null:
			used += 1
	assert_eq(used, 1, "one slot")


func test_keycard_is_not_a_belt_item() -> void:
	assert_eq(inv.add(&"keycard"), 0)
	assert_false(inv.has(&"keycard"))
	assert_eq(inv.add(&"nonsense"), 0)


func test_remove_clears_the_slot_at_zero() -> void:
	inv.add(&"glowstick", 3)
	assert_eq(inv.remove(&"glowstick", 2), 2)
	assert_eq(inv.count_of(&"glowstick"), 1)
	assert_eq(inv.remove(&"glowstick", 5), 1, "removes what there is")
	assert_false(inv.has(&"glowstick"))
	assert_null(inv.slots[0])
	assert_eq(inv.remove(&"glowstick"), 0)


func test_consume_announces_item_used() -> void:
	var seen: Array[StringName] = []
	var cb := func(k: StringName) -> void: seen.append(k)
	EventBus.item_used.connect(cb)
	inv.add(&"chalk", 8)
	inv.consume(&"chalk")
	inv.remove(&"chalk")
	EventBus.item_used.disconnect(cb)
	assert_eq(seen, [&"chalk"] as Array[StringName], "consume announces, remove does not")
	assert_eq(inv.count_of(&"chalk"), 6)


func test_swap_replaces_the_selected_slot_and_returns_the_old_stack() -> void:
	inv.add(&"polaroid", 2)
	inv.add(&"glowstick", 3)
	inv.add(&"chalk", 8)
	inv.add(&"radio")
	inv.select(1)
	var old := inv.swap_in(&"flare", 2)
	assert_not_null(old)
	assert_eq(old.kind, &"glowstick")
	assert_eq(old.count, 3)
	assert_eq(inv.count_of(&"flare"), 2)
	assert_false(inv.has(&"glowstick"))
	assert_eq(inv.slots[1].kind, &"flare", "the new kind takes the same slot")


func test_swap_into_an_empty_slot_is_refused() -> void:
	assert_null(inv.swap_in(&"polaroid", 1))


func test_first_item_goes_in_hand() -> void:
	inv.add(&"chalk", 8)
	inv.add(&"polaroid")
	assert_eq(inv.selected, 0)
	assert_eq(inv.selected_kind(), &"chalk")
	inv.select(1)
	inv.remove(&"polaroid")
	inv.add(&"glowstick")
	assert_eq(inv.selected, 1, "an empty hand takes the next item that arrives")


func test_selection_by_index_and_wheel() -> void:
	inv.add(&"polaroid")
	inv.add(&"glowstick")
	assert_true(inv.select(1))
	assert_eq(inv.selected, 1)
	assert_false(inv.select(1), "already selected")
	assert_false(inv.select(4))
	assert_false(inv.select(-1))
	assert_true(inv.select_step(1))
	assert_eq(inv.selected, 2, "empty slots can be selected (empty hand)")
	inv.select(3)
	inv.select_step(1)
	assert_eq(inv.selected, 0, "the wheel wraps")
	inv.select_step(-1)
	assert_eq(inv.selected, 3)


func test_changed_signal_carries_slots_and_selected() -> void:
	var log := []
	inv.changed.connect(func(s: Array, sel: int) -> void: log.append([s.size(), sel]))
	inv.add(&"polaroid")
	inv.add(&"glowstick")
	inv.select(1)
	assert_eq(log.size(), 3)
	assert_eq(log[2], [4, 1])


func test_reset_gives_the_loadout() -> void:
	inv.add(&"radio")
	inv.reset({&"polaroid": 1, &"chalk": 8})
	assert_false(inv.has(&"radio"))
	assert_eq(inv.count_of(&"polaroid"), 1)
	assert_eq(inv.count_of(&"chalk"), 8)
	inv.reset()
	assert_eq(inv.snapshot(), [null, null, null, null])


func test_snapshot_copies() -> void:
	inv.add(&"chalk", 8)
	var snap := inv.snapshot()
	inv.consume(&"chalk")
	assert_eq((snap[0] as ItemSlot).count, 8)
	assert_eq(inv.count_of(&"chalk"), 7)


func test_polaroid_images_ride_in_the_slot_state() -> void:
	inv.add(&"polaroid", 1, {&"images": [3]})
	inv.add(&"polaroid", 1, {&"images": [5]})
	assert_eq(inv.slots[0].state[&"images"], [3, 5])
	assert_eq(inv.slots[0].count, 2)


func test_slot_state_is_not_shared_with_the_resource() -> void:
	var data := DataRegistry.item(&"radio")
	inv.add(&"radio", 1, {&"charge": 90.0})
	(inv.slots[0] as ItemSlot).state[&"charge"] = 10.0
	assert_not_null(data)
	assert_null(data.get(&"state"), "per-instance state lives in the slot, never in ItemData (09 §1)")
	assert_eq(DataRegistry.item(&"radio").cap, 1)


func test_hud_binds_to_the_inventory() -> void:
	UiMotion.manual_clock = true
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.bind_inventory(inv)
	inv.add(&"chalk", 8)
	inv.add(&"polaroid")
	assert_eq(hud.belt.slot(0).kind, &"chalk")
	assert_eq(hud.belt.slot(0).count, 8)
	assert_eq(hud.belt.slot(1).kind, &"polaroid")
	assert_true(hud.belt.slot(0).selected)
	inv.select(1)
	assert_true(hud.belt.slot(1).selected)
	inv.consume(&"chalk")
	assert_eq(hud.belt.slot(0).count, 7)
	hud.free()
	UiMotion.manual_clock = false
