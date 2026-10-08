class_name FlareItem
extends ItemBase
## The Flare belt item (09 §2, 11 §2). use_item strikes it: the flare burns 40 s in the hand
## (a Flare node follows the hand's tip; it joins `flares_burning`); use_item again throws it
## (the Glowstick's arc, 8 m at 45 degrees, a 6 m impact noise on landing). The burn lives in
## the slot (`state.burn`, seconds left), so it is the same through a belt change; a flare
## does not survive leaving the level. A burnt-out flare is spent. Nothing here changes
## ItemData: one flare of the stack burns at a time.

const BURN := &"burn"
## Where the tip rests when another kind is in hand: low at the right hip (camera space).
const HIP_TIP := Vector3(0.28, -0.5, -0.32)
const DEFAULT_TIP := Vector3(0.28, 0.9, -0.3)

var flare: Flare = null
var _strike_left: float = 0.0


func _ready() -> void:
	EventBus.level_left.connect(_on_level_left)


static func is_burning(slot: ItemSlot) -> bool:
	return slot != null and float(slot.state.get(BURN, 0.0)) > 0.0


func _slot() -> ItemSlot:
	var i := inventory.slot_of(kind) if inventory != null else -1
	return inventory.slots[i] as ItemSlot if i != -1 else null


## Press: strike an unlit flare, throw a burning one.
func use(slot: ItemSlot) -> bool:
	if slot == null or slot.count <= 0:
		return false
	if is_burning(slot):
		return _strike_left <= 0.0 and throw(slot) != null
	return strike(slot)


## Strikes one flare of the stack: it burns in the hand for FLARE_BURN_TIME.
func strike(slot: ItemSlot) -> bool:
	if slot == null or slot.count <= 0 or is_burning(slot):
		return false
	slot.state[BURN] = Tuning.FLARE_BURN_TIME
	_strike_left = Tuning.FLARE_STRIKE_LOCKOUT
	_ensure_flare(slot)
	AudioManager.play_3d(Flare.SOUND_IGNITE, flare.global_position)
	var p := player()
	if p != null:
		p.rig.nod(Tuning.FEEDBACK_THROW_RECOIL_DEG * 0.25)
	flick(Vector3(0.0, 0.03, -0.05), 0.08, 0.25)
	EventBus.item_used.emit(kind)
	return true


## Throws the burning flare. Returns it, or null when nothing burns.
func throw(slot: ItemSlot) -> Flare:
	if not is_burning(slot):
		return null
	_ensure_flare(slot)
	var f := flare
	var plan := ItemThrow.plan(player())
	flare = null
	f.burnt_out.disconnect(_on_burnt_out)
	slot.state.erase(BURN)
	f.launch(plan[&"origin"], plan[&"velocity"])
	var p := player()
	if p != null:
		p.rig.nod(Tuning.FEEDBACK_THROW_RECOIL_DEG)
	flick(Vector3(-0.03, 0.0, -0.12), 0.08, 0.25)
	inventory.remove(kind, 1)
	return f


## The belt lost the stack (a swap, a reset): the flare in hand is put out.
func cancel() -> void:
	busy = false
	var slot := _slot()
	if slot != null:
		slot.state.erase(BURN)
	_free_flare()


func _free_flare() -> void:
	if flare != null and is_instance_valid(flare):
		flare.burnt_out.disconnect(_on_burnt_out)
		flare.queue_free()
	flare = null


func _physics_process(dt: float) -> void:
	_strike_left = maxf(_strike_left - dt, 0.0)
	var slot := _slot()
	if not is_burning(slot):
		_free_flare()
		return
	_ensure_flare(slot)
	slot.state[BURN] = flare.remaining


func _ensure_flare(slot: ItemSlot) -> void:
	if flare != null and is_instance_valid(flare):
		return
	var f := Flare.new()
	f.remaining = float(slot.state.get(BURN, Tuning.FLARE_BURN_TIME))
	var tree := inventory.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(f)
	f.set_carried(true, _tip)
	f.global_position = _tip.call()
	f.burnt_out.connect(_on_burnt_out)
	flare = f


## Where the flare's tip is: on the raised model, else low at the hip.
func _tip() -> Vector3:
	var m := held()
	if m != null and m.is_inside_tree():
		return m.to_global(ItemModels.flare_tip())
	var cam := camera()
	return cam.global_transform * HIP_TIP if cam != null else DEFAULT_TIP


func _on_burnt_out() -> void:
	flare = null
	_spend()


func _spend() -> void:
	var slot := _slot()
	if slot != null:
		slot.state.erase(BURN)
	inventory.remove(kind, 1)


func _on_level_left(_proper: bool) -> void:
	if is_burning(_slot()):
		_free_flare()
		_spend()
