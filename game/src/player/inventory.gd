class_name Inventory
extends Node
## The belt (09 §1): four slots, one kind per slot, each kind stacking to its cap. A child of
## the Player (it also works alone, for tests). Satisfies the HUD contract (04 Interfaces
## additions): `changed(slots, selected)`, `slots`, `selected`.
## Slots are positional: `slots[i]` is an ItemSlot or null (an empty slot). Keys 1 to 4 and the
## wheel select; use_item uses the selected kind through its ItemBase behaviour.
## Held models (09 §3) hang off the player's camera and share the flashlight's bob at 60%.

signal changed(slots: Array, selected: int)

const SLOT_COUNT := Tuning.ITEM_BELT_SLOTS
## Where a raised held item rests, camera space: lower right, beside the flashlight (02 §9).
const HELD_REST := Vector3(0.31, -0.15, -0.38)
const HELD_LOWERED_DROP := 0.32
const HELD_BOB := 0.006
const SOUND_SELECT := &"ui_move"

## Array of ItemSlot-or-null, always SLOT_COUNT long.
var slots: Array = []
var selected: int = 0
var player: Player = null

var _behaviors: Dictionary = {}
var _light_query: Callable
var _hand: HeldHand


func _init() -> void:
	_hand = HeldHand.new(self)
	_clear_slots()


func _ready() -> void:
	var parent := get_parent()
	if parent is Player:
		player = parent as Player
		# 06 Interfaces: a glowstick within 4 m (a flare within 8 m) lights a node for Still.
		_light_query = _lit_by_chemical_light
		player.add_light_query(_light_query)
	changed.emit(slots, selected)


func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and _light_query.is_valid():
		player.remove_light_query(_light_query)
	_hand.kill()


func _lit_by_chemical_light(pos: Vector3) -> bool:
	return Glowstick.is_lit(get_tree(), pos)


## The Inventory on a player-like node (property, else a child named Inventory), or null.
static func of(node: Node) -> Inventory:
	if node == null:
		return null
	var v: Variant = node.get(&"inventory")
	if v is Inventory:
		return v as Inventory
	return node.get_node_or_null("Inventory") as Inventory


# --- the belt ----------------------------------------------------------------------------

## Stack cap of a kind: its ItemData, else the Tuning table; 0 for anything that is not a belt item.
static func cap_of(kind: StringName) -> int:
	var data := DataRegistry.item(kind)
	if data != null:
		return data.cap if data.belt_item else 0
	return int(Tuning.ITEM_CAP.get(kind, 0))


## Index of the slot holding `kind`, or -1.
func slot_of(kind: StringName) -> int:
	for i in SLOT_COUNT:
		var s := slots[i] as ItemSlot
		if s != null and s.kind == kind:
			return i
	return -1


func has(kind: StringName) -> bool:
	return slot_of(kind) != -1


func count_of(kind: StringName) -> int:
	var i := slot_of(kind)
	return (slots[i] as ItemSlot).count if i != -1 else 0


func first_free_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


## True when at least one of `kind` would fit (09 §1: a stack below its cap, or a free slot).
func can_accept(kind: StringName) -> bool:
	var cap := cap_of(kind)
	if cap <= 0:
		return false
	var i := slot_of(kind)
	if i != -1:
		return (slots[i] as ItemSlot).count < cap
	return first_free_slot() != -1


## Puts up to `count` of `kind` on the belt; returns how many were accepted (0 when the stack
## is at its cap, the belt holds four other kinds, or the kind is not a belt item). `state` is
## folded into the slot (Polaroid image indices).
func add(kind: StringName, count: int = 1, state: Dictionary = {}) -> int:
	var cap := cap_of(kind)
	if cap <= 0 or count <= 0:
		return 0
	var i := slot_of(kind)
	var s: ItemSlot
	if i != -1:
		s = slots[i]
	else:
		i = first_free_slot()
		if i == -1:
			return 0
		s = ItemSlot.new(kind, 0)
	var accepted := mini(count, cap - s.count)
	if accepted <= 0:
		return 0
	var in_hand_was_empty := slots[selected] == null
	s.count += accepted
	s.merge_state(ItemSlot.accepted_state(state, accepted))
	slots[i] = s
	# The first item on an empty belt (or into an empty selected slot) is the one in hand.
	if in_hand_was_empty:
		selected = i
	_changed()
	return accepted


## 09 §1 swap: the stack in slot `index` (default the selected one) can be put back in the
## world only when its kind has a world scene; otherwise a swap would destroy it.
func can_swap_out(index: int = -1) -> bool:
	var i := selected if index < 0 else clampi(index, 0, SLOT_COUNT - 1)
	var s := slots[i] as ItemSlot
	if s == null:
		return false
	var data := DataRegistry.item(s.kind)
	return data != null and data.world_scene != null


## Removes up to `count` of `kind`; returns how many were removed.
func remove(kind: StringName, count: int = 1) -> int:
	var i := slot_of(kind)
	if i == -1 or count <= 0:
		return 0
	var s := slots[i] as ItemSlot
	var removed := mini(count, s.count)
	s.count -= removed
	if s.count <= 0:
		slots[i] = null
		_cancel_behavior(kind)
	_changed()
	return removed


## A use spent `count` of `kind`: remove them and announce EventBus.item_used.
func consume(kind: StringName, count: int = 1) -> int:
	var removed := remove(kind, count)
	if removed > 0:
		EventBus.item_used.emit(kind)
	return removed


## 09 §1 swap: replaces the slot `index` (default the selected one) with `count` of `kind` and
## returns the ItemSlot that was there (the caller puts it back in the world). Null when that
## slot is empty (use add()), the kind is not a belt item, or the old kind cannot lie in the
## world (no world scene: can_swap_out).
func swap_in(kind: StringName, count: int, state: Dictionary = {}, index: int = -1) -> ItemSlot:
	var cap := cap_of(kind)
	if cap <= 0 or count <= 0:
		return null
	var i := selected if index < 0 else clampi(index, 0, SLOT_COUNT - 1)
	var old := slots[i] as ItemSlot
	if old == null or not can_swap_out(i):
		return null
	_cancel_behavior(old.kind)
	slots[i] = ItemSlot.new(kind, mini(count, cap), state)
	selected = i
	_changed()
	return old


## Empties the belt (a new Descent), then gives the loadout's `{kind: count}` (05 §7).
func reset(items: Dictionary = {}) -> void:
	for b: ItemBase in _behaviors.values():
		b.cancel()
	_clear_slots()
	selected = 0
	for kind: Variant in items:
		add(StringName(kind), int(items[kind]))
	_changed()


## A copy of the belt for the run state (`RunState.items`): ItemSlot copies, null for empty.
func snapshot() -> Array:
	var out: Array = []
	for s: Variant in slots:
		out.append((s as ItemSlot).copy() if s != null else null)
	return out


# --- selection ---------------------------------------------------------------------------

func selected_slot() -> ItemSlot:
	return slots[selected] as ItemSlot


func selected_kind() -> StringName:
	var s := selected_slot()
	return s.kind if s != null else &""


func is_busy() -> bool:
	for b: ItemBase in _behaviors.values():
		if b.busy:
			return true
	return false


## Selects slot `index` (0 to 3). Refused mid-use. Plays the select tick (11 §2).
func select(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT or index == selected or is_busy():
		return false
	selected = index
	AudioManager.play_2d(SOUND_SELECT)
	_changed()
	_select_feedback()
	return true


## 11 §2 item select, motion channel: the hand bobs one cycle (HeldHand) and the view
## nods once (CameraRig.nod through the Player's rig; no Player change needed).
func _select_feedback() -> void:
	if player != null and player.rig != null:
		player.rig.nod(Tuning.FEEDBACK_ITEM_SELECT_NOD_DEG)
	_hand.bob_once()


## Wheel: +1 / -1 around the belt.
func select_step(step: int) -> bool:
	return select(posmod(selected + step, SLOT_COUNT))


func _unhandled_input(event: InputEvent) -> void:
	if player != null and player.is_dissolving():
		return
	for i in SLOT_COUNT:
		if event.is_action_pressed(StringName("item_%d" % (i + 1))):
			select(i)
			return
	if event.is_action_pressed(&"item_next"):
		select_step(1)
	elif event.is_action_pressed(&"item_prev"):
		select_step(-1)


# --- use ---------------------------------------------------------------------------------

## Uses the selected kind now (press semantics). False when nothing is selected, a use is in
## progress, the Player refuses (06 §5: cranking, no agency), or the item's own lockout holds.
func use_selected() -> bool:
	var s := selected_slot()
	if s == null or is_busy():
		return false
	if player != null and not player.can_use_item():
		return false
	var b := behavior_for(s.kind)
	return b != null and b.use(s)


## The use_item key for this frame (the Player calls it every physics frame).
## `allowed` false (cranking, no agency) feeds released input so hold timers reset.
func feed_use(pressed: bool, held: bool, dt: float, allowed: bool = true) -> void:
	var s := selected_slot()
	if s == null:
		return
	var b := behavior_for(s.kind)
	if b == null:
		return
	if not allowed or (player != null and not player.can_use_item()):
		b.abort_hold()
		return
	if b.busy:
		return
	b.input(s, pressed, held, dt)


func behavior_for(kind: StringName) -> ItemBase:
	if _behaviors.has(kind):
		return _behaviors[kind]
	var b := _new_behavior(kind)
	if b == null:
		return null
	b.name = String(kind).capitalize()
	b.setup(self, kind)
	_behaviors[kind] = b
	add_child(b)
	return b


## The behaviours that exist so far; Flare, Radio and Fuse land with M2.8.
static func _new_behavior(kind: StringName) -> ItemBase:
	match kind:
		&"polaroid":
			return PolaroidItem.new()
		&"chalk":
			return ChalkItem.new()
		&"glowstick":
			return GlowstickItem.new()
	return null


func _cancel_behavior(kind: StringName) -> void:
	if _behaviors.has(kind):
		(_behaviors[kind] as ItemBase).cancel()


# --- internals ---------------------------------------------------------------------------

func _clear_slots() -> void:
	slots = []
	for i in SLOT_COUNT:
		slots.append(null)


func _changed() -> void:
	_refresh_held()
	changed.emit(slots, selected)


# --- held model (09 §3): HeldHand -------------------------------------------------------

func held_root() -> Node3D:
	return _hand.ensure_root()


func held_model() -> Node3D:
	return _hand.model


func _process(delta: float) -> void:
	_hand.process(delta)


func _refresh_held() -> void:
	_hand.refresh()
