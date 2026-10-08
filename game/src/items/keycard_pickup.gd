class_name KeycardPickup
extends ItemPickup
## The Keycard lying in the world (09 §2: not a belt item). `[E] PICK UP KEYCARD` sets
## `Inventory.keycard` (the HUD shows the key glyph beside the depth label; it is dropped when
## the level ends). A pulsing ui_accent emissive card, drawn out to KEYCARD_VISIBLE_DIST, so a
## Keyed level's objective can be found across a room. The reader's side is CardReader.

const PULSE_HZ := 0.8
const PULSE_MIN := 0.6
const PULSE_MAX := 3.2
const KEY := &"keycard"

var _mats: Array[ShaderMaterial] = []
var _pulse: float = 0.0


func _ready() -> void:
	kind = KEY
	super()
	_pulse = _phase
	for n in bob.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = Tuning.KEYCARD_VISIBLE_DIST
		var sm := mi.material_override as ShaderMaterial
		if sm != null:
			_mats.append(sm)


func _process(delta: float) -> void:
	super(delta)
	if picked:
		return
	_pulse = fposmod(_pulse + delta * PULSE_HZ, 1.0)
	var e := lerpf(PULSE_MIN, PULSE_MAX, 0.5 + 0.5 * sin(_pulse * TAU))
	for m in _mats:
		if m.get_shader_parameter(&"emission_strength") != null and float(m.get_shader_parameter(&"emission_strength")) > 0.0:
			m.set_shader_parameter(&"emission_strength", e)
	light.light_energy = Tuning.ITEM_WORLD_LIGHT_ENERGY * (0.6 + 0.4 * e / PULSE_MAX) * 2.0


func prompt_for(_inv: Inventory) -> String:
	return Strings.PROMPT_PICK_UP.replace("{item}", display_name())


func can_take(inv: Inventory) -> bool:
	return inv != null and not picked


## Takes the card: the player carries it for the level. Returns true (the pickup is spent).
func take(player: Node) -> bool:
	var inv := Inventory.of(player)
	if not can_take(inv):
		return false
	inv.set_keycard(true)
	EventBus.item_picked.emit(KEY)
	AudioManager.play_2d(SOUND_PICKUP)
	_fly_to_belt(player)
	return true
