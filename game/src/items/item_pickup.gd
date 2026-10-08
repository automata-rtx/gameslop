class_name ItemPickup
extends Node3D
## An item lying in the world (09 §2, §5 "Item"): a primitive model that bobs 2 cm at 0.2 Hz,
## lit by a faint OmniLight3D of its colour (energy 0.15, range 1 m) so it can be found in the
## dark. `[E] PICK UP X` puts it on the belt (the model flies to the lower right in 0.3 s with
## the pickup tick); with four other kinds on the belt it reads `[E] SWAP FOR X` and puts the
## selected slot's stack on the floor at the player's feet. A stack at its cap cannot be taken.
## Scene contract (%UniqueName): Body (StaticBody3D on layers 4 interactable + 5 items, the
## collider the interaction ray hits), Interactable (child of Body), Bob (Node3D holding the
## model and %Light). One scene per kind: scenes/items/pickup_<kind>.tscn.

const GROUP := &"pickups"
## 06 §7: the interaction ray accepts layer 4; 14 §7 puts world items on layer 5. Both bits.
const BODY_LAYERS := PlayerLayers.INTERACTABLE_MASK | (1 << 4)
const SOUND_PICKUP := &"item_pickup"

@export var kind: StringName = &""
## 0 = the ItemData's pickup_count (chalk 8, everything else 1).
@export var count: int = 0
## Per-instance state that travels with the item (Polaroid: `images`, the photo indices).
var state: Dictionary = {}
var picked: bool = false

@onready var body: StaticBody3D = %Body
@onready var interactable: Interactable = %Interactable
@onready var bob: Node3D = %Bob
@onready var light: OmniLight3D = %Light

var _phase: float = 0.0
## Bob centre height: the model's lowest point rests ITEM_WORLD_REST_HEIGHT above the floor
## at the bottom of the bob.
var _base_height: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	var data := DataRegistry.item(kind)
	if count <= 0:
		count = data.pickup_count if data != null else 1
	if data != null:
		light.light_color = data.world_light_color
	light.light_energy = Tuning.ITEM_WORLD_LIGHT_ENERGY
	light.omni_range = Tuning.ITEM_WORLD_LIGHT_RANGE
	light.shadow_enabled = false
	body.collision_layer = BODY_LAYERS
	var model := ItemModels.world(kind)
	bob.add_child(model)
	_base_height = Tuning.ITEM_WORLD_REST_HEIGHT + Tuning.ITEM_WORLD_BOB_AMPLITUDE - model_bottom(model)
	bob.position.y = _base_height
	interactable.condition = _can_use
	interactable.interacted.connect(_on_interacted)
	_refresh_prompt(null)
	# Desynchronise neighbours without randomness: phase from the position.
	_phase = fposmod(global_position.x * 1.7 + global_position.z * 2.3, 1.0)


func _process(delta: float) -> void:
	if picked:
		return
	_phase = fposmod(_phase + delta * Tuning.ITEM_WORLD_BOB_HZ, 1.0)
	bob.position.y = _base_height + sin(_phase * TAU) * Tuning.ITEM_WORLD_BOB_AMPLITUDE


## Lowest point of `model` in its parent's space (the mesh AABBs' corners, rotated).
static func model_bottom(model: Node3D) -> float:
	var low := INF
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != model.get_parent():
			xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var box := mi.mesh.get_aabb()
		for i in 8:
			low = minf(low, (xf * box.get_endpoint(i)).y)
	return 0.0 if low == INF else low


## Assigns the Polaroid photo (PolaroidPainter index) this pickup holds.
func set_polaroid_image(index: int) -> void:
	state[&"images"] = [PolaroidPainter.index_for(index)]


func display_name() -> String:
	var data := DataRegistry.item(kind)
	return data.display_name if data != null else String(kind).to_upper()


## The prompt wording for this belt (also what the tests read).
func prompt_for(inv: Inventory) -> String:
	if inv != null and inv.can_accept(kind):
		return Strings.PROMPT_PICK_UP.replace("{item}", display_name())
	return Strings.PROMPT_SWAP.replace("{item}", display_name())


## True when the belt can take at least one, or swap the selected slot for it.
func can_take(inv: Inventory) -> bool:
	if inv == null or picked or Inventory.cap_of(kind) <= 0:
		return false
	if inv.can_accept(kind):
		return true
	# A swap puts the selected stack on the floor, so its kind needs a world scene.
	return not inv.has(kind) and inv.first_free_slot() == -1 and inv.selected_slot() != null \
			and inv.can_swap_out()


func _can_use(player: Node) -> bool:
	var inv := Inventory.of(player)
	_refresh_prompt(inv)
	return can_take(inv)


func _refresh_prompt(inv: Inventory) -> void:
	interactable.prompt = prompt_for(inv)


func _on_interacted(player: Node) -> void:
	take(player)


## Takes the item onto the belt (or swaps). Returns true when the pickup is spent.
func take(player: Node) -> bool:
	var inv := Inventory.of(player)
	if not can_take(inv):
		return false
	var spent := false
	if inv.can_accept(kind):
		var accepted := inv.add(kind, count, state)
		count -= accepted
		# Only the accepted items' state (Polaroid photos) went to the belt; the rest stays.
		state = ItemSlot.remaining_state(state, accepted)
		spent = count <= 0
	else:
		var old := inv.swap_in(kind, count, state)
		if old == null:
			return false
		_drop_old(old, player)
		spent = true
	EventBus.item_picked.emit(kind)
	AudioManager.play_2d(SOUND_PICKUP)
	if spent:
		_fly_to_belt(player)
	return spent


## 09 §1 swap: the old stack lands at the player's feet as a pickup of its own.
func _drop_old(old: ItemSlot, player: Node) -> void:
	var pos := global_position
	if player is Node3D:
		var p := player as Node3D
		var f := -p.global_transform.basis.z
		f.y = 0.0
		pos = p.global_position + f.normalized() * 0.6
	var parent := get_parent()
	if parent != null:
		ItemPickup.spawn(parent, old.kind, old.count, old.state, pos)


## Instantiates the world scene of `kind` under `parent` at `pos` (floor point). Null when the
## kind has no world scene yet.
static func spawn(parent: Node, k: StringName, n: int, s: Dictionary, pos: Vector3) -> ItemPickup:
	var data := DataRegistry.item(k)
	if data == null or data.world_scene == null:
		return null
	var p := data.world_scene.instantiate() as ItemPickup
	p.count = n
	p.state = s.duplicate(true)
	parent.add_child(p)
	p.global_position = pos
	return p


## 0.3 s: the model flies to the lower right of the view, shrinking, then the pickup is freed.
func _fly_to_belt(player: Node) -> void:
	picked = true
	interactable.enabled = false
	body.set_deferred(&"collision_layer", 0)
	light.visible = false
	var cam: Camera3D = null
	if player != null:
		var rig: Variant = player.get(&"rig")
		if rig is CameraRig:
			cam = (rig as CameraRig).camera
	if cam == null or not is_inside_tree():
		queue_free()
		return
	var start := bob.global_position
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(t: float) -> void:
		var target := cam.global_transform * Vector3(0.3, -0.25, -0.35)
		bob.global_position = start.lerp(target, t)
		bob.scale = Vector3.ONE * lerpf(1.0, 0.3, t),
		0.0, 1.0, float(Tuning.ITEM_PICKUP_TWEEN_MS) / 1000.0)
	tw.tween_callback(queue_free)
