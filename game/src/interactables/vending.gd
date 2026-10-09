class_name Vending
extends Node3D
## The vending machine (09 §5, Halls prop `vending`). `[E] USE`, once per machine: a 1.0 s whir
## (an 8 m `mech` noise), then it dispenses one item from the pool into the tray, as an
## ordinary pickup (`[E] PICK UP`). The machine hums. The item is drawn from the unlocked
## pool by the base weights (RunLevelSetup.item_pool), excluding the fuse (a stray fuse
## tells the player nothing about whether this level has a Variant B breaker; the fuse is
## placed by the generator, 07 §6) with a seeded rng: the level seed and the machine's cell.
## Scene contract: %Collider (StaticBody3D, set to world + interactable here) with %Interactable;
## a Marker3D %TrayPoint where the item appears (facing -Z, the panel's side).

signal dispensed(pickup: Node3D)

const GROUP := &"vending_machines"
const SOUND_HUM := &"vending_hum"
const SOUND_WHIR := &"vending_whir"
const SEED_LABEL := "vending:%d:%d"
## Never dispensed (see above).
const EXCLUDED: Array[StringName] = [&"fuse"]

@onready var collider: StaticBody3D = %Collider
@onready var interactable: Interactable = %Interactable
@onready var tray: Marker3D = %TrayPoint

var used: bool = false
var item: StringName = &""
var _hum: AudioLoop = null


func _ready() -> void:
	add_to_group(GROUP)
	collider.collision_layer = PlayerLayers.WORLD_MASK | PlayerLayers.INTERACTABLE_MASK
	interactable.prompt = Strings.PROMPT_USE
	interactable.interacted.connect(_on_interacted)
	_hum = AudioManager.loop(SOUND_HUM, self).start()
	AudioCull.mark(_hum)  # M3.5: silent beyond its max_distance


func _on_interacted(_player: Node) -> void:
	use()


## Starts the whir. False when this machine was already used.
func use() -> bool:
	if used:
		return false
	used = true
	interactable.enabled = false
	AudioManager.play_3d(SOUND_WHIR, global_position + Vector3(0.0, 1.0, 0.0))
	NoiseModel.emit(global_position, Tuning.NOISE_VENDING_RADIUS, Tuning.NOISE_KIND_MECH)
	if is_inside_tree():
		get_tree().create_timer(Tuning.VENDING_WHIR_TIME).timeout.connect(dispense)
	return true


## Puts the item in the tray (also what the whir timer calls; public so tests need no wait).
func dispense() -> ItemPickup:
	if not is_inside_tree() or item != &"":
		return null
	var rng := rng_for(self)
	item = pick_kind(RunLevelSetup.item_pool(GameState.meta), rng)
	if item == &"":
		return null
	var parent := get_parent()
	var at := tray.global_position + global_transform.basis * Vector3(0.0, 0.0, -0.1)
	var pickup := ItemPickup.spawn(parent, item, 0, {}, at)
	if pickup == null:
		return null
	pickup.rotation.y = global_rotation.y
	if item == &"polaroid":
		pickup.set_polaroid_image(rng.randi_range(0, Tuning.POLAROID_IMAGE_COUNT - 1))
	dispensed.emit(pickup)
	return pickup


## The seeded rng of one machine: the level seed (0 outside a level) and its position.
static func rng_for(machine: Node3D) -> RandomNumberGenerator:
	var level_seed := 0
	var tree := machine.get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group(Level.GROUP):
			var l := n as Level
			if l != null and l.data != null:
				level_seed = l.data.level_seed
				break
	var at := machine.global_position
	return Seeds.rng(Seeds.derive(level_seed, SEED_LABEL % [roundi(at.x * 10.0), roundi(at.z * 10.0)]))


## One kind from `pool` by the base weights, never an excluded one; &"" with nothing to draw.
static func pick_kind(pool: Array[StringName], rng: RandomNumberGenerator) -> StringName:
	var kinds: Array[StringName] = []
	var total := 0.0
	for k in pool:
		var w := float(Tuning.ITEM_WEIGHT.get(k, 0))
		if w > 0.0 and not EXCLUDED.has(k):
			kinds.append(k)
			total += w
	if kinds.is_empty():
		return &""
	var r := rng.randf() * total
	for k in kinds:
		r -= float(Tuning.ITEM_WEIGHT[k])
		if r <= 0.0:
			return k
	return kinds[kinds.size() - 1]
