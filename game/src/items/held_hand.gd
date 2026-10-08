class_name HeldHand
extends RefCounted
## The Inventory's held model (09 §3, 02 §9): the selected kind's model hangs off the
## player's camera at the lower right, shares the flashlight's bob at 60%, and swaps with a
## 0.5 s lower-in / raise-out. On select it bobs one cycle (11 §2). Owned by the Inventory.

var inventory: Inventory
var root: Node3D = null
var model: Node3D = null
var kind: StringName = &""
var _tween: Tween = null
## 0..1 through the select bob cycle; 1 = at rest.
var _select_bob: float = 1.0


func _init(inv: Inventory) -> void:
	inventory = inv


## The node the held models hang under (camera space); built on first need.
func ensure_root() -> Node3D:
	var p := inventory.player
	if root == null and p != null and p.rig != null:
		root = Node3D.new()
		root.name = "HeldItems"
		root.position = Inventory.HELD_REST
		p.rig.camera.add_child(root)
	return root


## Starts the one-cycle select bob.
func bob_once() -> void:
	_select_bob = 0.0


## The hand's select-bob offset in metres (one down-and-up cycle; 0 at rest).
func select_bob_offset() -> float:
	return -sin(_select_bob * PI) * Tuning.FEEDBACK_ITEM_SELECT_BOB


func process(delta: float) -> void:
	var r := ensure_root()
	if r == null:
		return
	_select_bob = minf(1.0, _select_bob + delta * 1000.0 / Tuning.FEEDBACK_ITEM_SELECT_BOB_MS)
	var rig := inventory.player.rig
	var bob := -absf(sin(rig.bob_phase())) * Inventory.HELD_BOB * rig.bob_amount() * Tuning.ITEM_HELD_BOB_SCALE
	r.position = Inventory.HELD_REST + Vector3(0.0, bob + select_bob_offset(), 0.0)


## Lowers the model in hand and raises the selected kind's (0.5 s in all, 09 §3).
func refresh() -> void:
	var r := ensure_root()
	if r == null:
		return
	var want := inventory.selected_kind()
	if want == kind and (want == &"" or model != null):
		return
	kind = want
	if _tween != null:
		_tween.kill()
	var half := float(Tuning.ITEM_HELD_TWEEN_MS) / 2000.0
	var old := model
	model = null
	if old != null:
		var ob := inventory._behaviors.get(old.get_meta(&"kind", &"")) as ItemBase
		if ob != null:
			ob.on_unequipped()
	if want != &"":
		var b := inventory.behavior_for(want)
		model = b.build_held() if b != null else ItemModels.held(want)
		model.position = Vector3(0.0, -Inventory.HELD_LOWERED_DROP, 0.0)
		model.set_meta(&"kind", want)
		r.add_child(model)
		if b != null:
			b.on_equipped(model)
	if not inventory.is_inside_tree():
		if old != null:
			old.queue_free()
		if model != null:
			model.position.y = 0.0
		return
	_tween = inventory.create_tween()
	if old != null:
		_tween.tween_property(old, "position:y", -Inventory.HELD_LOWERED_DROP, half).set_ease(Tween.EASE_IN)
		_tween.tween_callback(old.queue_free)
	if model != null:
		_tween.tween_property(model, "position:y", 0.0, half).set_ease(Tween.EASE_OUT)


func kill() -> void:
	if _tween != null:
		_tween.kill()
