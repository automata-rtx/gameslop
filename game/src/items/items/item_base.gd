class_name ItemBase
extends Node
## One item kind's behaviour (09 §2), a child of the Inventory. The Inventory owns the belt
## and the slot; the behaviour owns what using the kind does. Subclasses override use() and,
## for kinds with a hold action, input(). Nothing here mutates ItemData (09 §1).

## True while a use is in progress; the belt will not change selection and no second use starts.
var busy: bool = false
var inventory: Inventory
var kind: StringName = &""


func setup(inv: Inventory, k: StringName) -> void:
	inventory = inv
	kind = k


## The player node, or null (unit tests drive an Inventory alone).
func player() -> Player:
	return inventory.player if inventory != null else null


func camera() -> Camera3D:
	var p := player()
	return p.rig.camera if p != null and p.rig != null else null


## The use_item key's per-frame state for the selected slot of this kind. Default: use on press.
func input(slot: ItemSlot, pressed: bool, _held: bool, _dt: float) -> void:
	if pressed:
		use(slot)


## The key is no longer usable (cranking, no agency): a hold in progress ends without acting.
func abort_hold() -> void:
	pass


## Begins a use. Returns true when it started. Overrides check their own lockouts.
func use(_slot: ItemSlot) -> bool:
	return false


## Aborts a use in progress (stunned, belt emptied, run ended). Nothing is consumed.
func cancel() -> void:
	busy = false


## Called when the held model of this kind is raised (selected) or lowered.
func on_equipped(_model: Node3D) -> void:
	pass


func on_unequipped() -> void:
	pass


## The held model (09 §3); primitives only.
func build_held() -> Node3D:
	return ItemModels.held(kind)


## The raised held model of this kind, or null (another kind is in hand, or nothing).
func held() -> Node3D:
	var m := inventory.held_model() if inventory != null else null
	return m if m != null and is_instance_valid(m) and m.get_meta(&"kind", &"") == kind else null


var _flick: Tween = null


## The hand jabs `offset` metres (model space) and comes back: feedback for a use that has no
## other motion (a strike, a toggle). Out `out_s` seconds, back `back_s`.
func flick(offset: Vector3, out_s: float = 0.08, back_s: float = 0.2) -> void:
	var m := held()
	if m == null or not inventory.is_inside_tree():
		return
	if _flick != null:
		_flick.kill()
	_flick = inventory.create_tween().set_trans(Tween.TRANS_QUAD)
	_flick.tween_property(m, "position", offset, out_s).set_ease(Tween.EASE_OUT)
	_flick.tween_property(m, "position", Vector3.ZERO, back_s).set_ease(Tween.EASE_IN_OUT)
