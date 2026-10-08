class_name FeedbackRecipesPlayer
extends FeedbackRecipesBase
## Recipes for the player's own actions (11 §2): moving, the light, the belt, interaction,
## hiding and noclip. Input goes through Input.action_press like keys do.


# --- moving ---------------------------------------------------------------------------------

func walk_step(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.anchor_on(EventBus.noise_emitted, func(_pos: Vector3, _r: float, kind: StringName) -> bool:
		return kind == Tuning.NOISE_KIND_STEP)
	b.press(&"move_forward")
	await b.until(b.is_anchored, 240)


func sprint_start(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.anchor_on(b.player().sprint_changed, func(on: bool) -> bool: return on)
	b.press(&"move_forward")
	b.press(&"sprint")
	await b.until(b.is_anchored, 240)


func sprint_stop(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.press(&"move_forward")
	b.press(&"sprint")
	await b.until(func() -> bool: return b.player().locomotion.sprinting, 240)
	# Past the breath's 2 s fade-in; teleport back along the corridor so a wall never ends it.
	var start := b.player().global_position
	for i in 7:
		await b.ticks(20)
		if b.player().global_position.distance_to(start) > 6.0:
			b.player().global_position = start
	b.anchor_on(b.player().sprint_changed, func(on: bool) -> bool: return not on)
	b.release(&"sprint")
	await b.until(b.is_anchored, 240)


func stamina_empty(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.player().locomotion.stamina.value = 8.0
	b.anchor_on(b.player().stamina_exhausted)
	b.press(&"move_forward")
	b.press(&"sprint")
	await b.until(b.is_anchored, 400)


func crouch(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.anchor()
	b.press(&"crouch")
	await b.ticks(2)


func stand(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.press(&"crouch")
	await b.ticks(20)
	await b.arm()
	b.anchor()
	b.release(&"crouch")
	await b.ticks(2)


# --- the light --------------------------------------------------------------------------------

func flashlight_on(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.player().flashlight.set_on(false, true)
	await b.arm()
	b.anchor()
	await press_tap(b, &"flashlight")


func flashlight_off(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.player().flashlight.set_on(true, true)
	await b.arm()
	b.anchor()
	await press_tap(b, &"flashlight")


func crank(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.player().flashlight.set_on(false, true)
	b.player().flashlight.set_charge(40.0)
	await b.arm()
	b.anchor()
	b.press(&"crank")
	await b.ticks(4)


func crank_full(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.player().flashlight.set_on(false, true)
	b.player().flashlight.set_charge(95.0)
	await b.arm()
	b.anchor_on(b.player().flashlight.crank_full)
	b.press(&"crank")
	await b.until(b.is_anchored, 240)


# --- the belt ---------------------------------------------------------------------------------

func item_select(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.player().inventory.select(0)
	await b.ticks(40)
	await b.arm()
	b.anchor()
	_action_event(&"item_2")
	await b.ticks(2)


func item_polaroid(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await _select(b, &"polaroid")
	b.set_coherence(50.0)
	await b.arm()
	b.anchor()
	await press_tap(b, &"use_item", 2)


func item_glowstick(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await _select(b, &"glowstick")
	await b.arm()
	b.anchor_on(b.player().inventory.changed)
	await press_tap(b, &"use_item", 2)
	await b.until(b.is_anchored, 60)


func chalk_stamp(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await _select(b, &"chalk")
	await face_edge(b, noclip_spots(b)[&"good"])  # a wall within 2 m, a little down
	await b.arm()
	b.anchor()
	await press_tap(b, &"use_item", 2)


func _select(b: FeedbackBench, kind: StringName) -> void:
	var inv := b.player().inventory
	if inv.selected_kind() != kind:
		inv.select(inv.slot_of(kind))
		await b.ticks(40)


func _action_event(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


# --- interaction ------------------------------------------------------------------------------

func interact_press(b: FeedbackBench) -> void:
	var door := _nearest(b, &"doors")
	if door == null or not await face_interactable(b, (door as Door).interactable, 1.0):
		push_warning("interact_press: no door in reach")
		return
	var d := door as Door
	probe(b, &"I", "door", func() -> Variant: return d.hinge.rotation)
	await b.arm()
	b.anchor()
	await press_tap(b, &"interact", 2)


func interact_hold(b: FeedbackBench) -> void:
	var br := b.run.breaker
	if br == null or not await face_interactable(b, br.interactable, 1.4):
		push_warning("interact_hold: no breaker in reach")
		return
	await b.arm()
	b.anchor_on(b.player().interactor.hold_tick)
	b.press(&"interact")
	await b.until(b.is_anchored, 120)
	b.release(&"interact")


func _nearest(b: FeedbackBench, group: StringName) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in b.get_tree().get_nodes_in_group(group):
		var n3 := n as Node3D
		if n3 == null or not b.run.level.is_ancestor_of(n3):
			continue
		var d := n3.global_position.distance_to(b.player().global_position)
		if d < best_d:
			best_d = d
			best = n3
	return best


# --- hiding -----------------------------------------------------------------------------------

func hide_enter(b: FeedbackBench) -> void:
	var spot := _nearest(b, &"hide_spots") as HideSpot
	if spot == null or not await face_interactable(b, spot.interactable, 1.0):
		push_warning("hide_enter: no hide spot in reach")
		return
	probe(b, &"I", "hide_mask", func() -> Variant:
		var mask: CanvasLayer = spot.get(&"_mask")
		return mask != null and mask.visible)
	await b.arm()
	b.anchor_on(b.player().hidden_changed, func(on: bool) -> bool: return on)
	await press_tap(b, &"interact", 2)
	await b.until(b.is_anchored, 60)


func hide_leave(b: FeedbackBench) -> void:
	var spot := _nearest(b, &"hide_spots") as HideSpot
	if spot == null:
		return
	if not b.player().is_hidden():
		if not await face_interactable(b, spot.interactable, 1.0):
			push_warning("hide_leave: no hide spot in reach")
			return
		await press_tap(b, &"interact", 2)
	await b.until(func() -> bool: return b.player().is_hidden(), 120)
	await b.ticks(50)
	probe(b, &"I", "hide_mask", func() -> Variant:
		var mask: CanvasLayer = spot.get(&"_mask")
		return mask != null and mask.visible)
	await b.arm()
	b.anchor_on(b.player().hidden_changed, func(on: bool) -> bool: return not on)
	b.press(&"interact")
	await b.until(b.is_anchored, 120)
	b.release(&"interact")
	await b.until(func() -> bool: return not b.player().is_hidden(), 120)
