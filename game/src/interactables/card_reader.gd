class_name CardReader
extends Node3D
## The card reader on a Keyed exit (09 §5, 07 §6). The Exit owns it (M2.9: `swiped` opens it):
## `[E] SWIPE` when the player carries the Keycard (Inventory.keycard), else `NO CARD` in
## ui_dim. A swipe with the card plays the accept beep (1.5 kHz), lights the indicator, and
## emits `swiped(player)` once; without it, the two-beep reject plays and the indicator blinks
## red twice with the beeps (the prompt already reads NO CARD); nothing else happens.
## The reader does not open anything itself and does not take the card (it is dropped when the
## level ends, 09 §2). Scene contract: %Body (StaticBody3D on interactable) with %Interactable,
## %Indicator (MeshInstance3D; the world-shader material gets `emission_strength`).

signal swiped(player: Node)
signal rejected(player: Node)

const GROUP := &"card_readers"
const SOUND_ACCEPT := &"keycard_accept"
const SOUND_REJECT := &"keycard_reject"
const INDICATOR_OFF := 0.0
const INDICATOR_ON := 3.0
## The reject blink: two red flashes in time with the two 400 Hz beeps (03 keycard_reject).
const REJECT_COLOR := Color(1.0, 0.231, 0.231)
const REJECT_FLASH := 0.1
const REJECT_GAP := 0.08

@onready var body: StaticBody3D = %Body
@onready var interactable: Interactable = %Interactable
@onready var indicator: MeshInstance3D = %Indicator

## True once a swipe was accepted.
var accepted: bool = false
var _mat: ShaderMaterial
var _accept_color: Color = Color.WHITE
var _blink: Tween


func _ready() -> void:
	add_to_group(GROUP)
	body.set_meta(&"wall_kind", &"PROP")
	if indicator.material_override is ShaderMaterial:
		_mat = (indicator.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		indicator.material_override = _mat
		_mat.set_shader_parameter(&"emission_strength", INDICATOR_OFF)
		_accept_color = _mat.get_shader_parameter(&"emission")
	interactable.condition = _offers
	interactable.interacted.connect(_on_interacted)
	_refresh(null)


static func has_card(player: Node) -> bool:
	var inv := Inventory.of(player) if player != null else null
	return inv != null and inv.keycard


func _offers(player: Node) -> bool:
	if accepted:
		return false
	_refresh(player)
	return true


func _refresh(player: Node) -> void:
	interactable.prompt = Strings.PROMPT_SWIPE if has_card(player) else Strings.PROMPT_NO_CARD


func _on_interacted(player: Node) -> void:
	swipe(player)


## Swipes `player`'s card. Returns true when accepted.
func swipe(player: Node) -> bool:
	if accepted:
		return false
	var at := global_position
	if not has_card(player):
		AudioManager.play_3d(SOUND_REJECT, at)
		_blink_reject()
		rejected.emit(player)
		return false
	accepted = true
	AudioManager.play_3d(SOUND_ACCEPT, at)
	if _blink != null:
		_blink.kill()
	if _mat != null:
		_mat.set_shader_parameter(&"emission", _accept_color)
		_mat.set_shader_parameter(&"emission_strength", INDICATOR_ON)
	interactable.enabled = false
	swiped.emit(player)
	return true


func _blink_reject() -> void:
	if _mat == null:
		return
	if _blink != null:
		_blink.kill()
	_mat.set_shader_parameter(&"emission", REJECT_COLOR)
	_blink = create_tween()
	for i in 2:
		_blink.tween_callback(_mat.set_shader_parameter.bind(&"emission_strength", INDICATOR_ON))
		_blink.tween_interval(REJECT_FLASH)
		_blink.tween_callback(_mat.set_shader_parameter.bind(&"emission_strength", INDICATOR_OFF))
		_blink.tween_interval(REJECT_GAP)
	_blink.tween_callback(_mat.set_shader_parameter.bind(&"emission", _accept_color))


## The indicator's current glow (tests and the feedback spy).
func indicator_glow() -> float:
	return float(_mat.get_shader_parameter(&"emission_strength")) if _mat != null else 0.0
