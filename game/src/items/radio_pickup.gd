class_name RadioPickup
extends ItemPickup
## A radio in the world (09 §2). Lying off, it is an ordinary pickup. Set down on (RadioItem
## holds use_item 0.5 s) it keeps playing: its static is positional, its LED is lit, and it
## emits the 10 m `radio` noise every second until its charge runs out (the Echo lure, 08 §6).
## `[E] PICK UP` takes it back with what is left of the charge, switched off. A spent radio is
## a dead prop and cannot be taken.

const SOUND_STATIC := RadioItem.SOUND_STATIC
## The placed radio's static level (dB under full): it carries, but is not shouting.
const PLACED_GAIN_DB := -6.0

var _loop: AudioLoop = null
var _noise_left: float = 0.0
var _led: Node


func _ready() -> void:
	super()
	_led = bob.find_child("Led", true, false)
	_refresh()


func is_on() -> bool:
	return bool(state.get(RadioItem.ON, false)) and charge() > 0.0


func charge() -> float:
	return float(state.get(RadioItem.CHARGE, RadioItem.full_charge()))


func can_take(inv: Inventory) -> bool:
	return charge() > 0.0 and super.can_take(inv)


## Taking it back switches it off.
func take(player: Node) -> bool:
	if not can_take(Inventory.of(player)):
		return false
	state[RadioItem.ON] = false
	_refresh()
	return super.take(player)


func _physics_process(dt: float) -> void:
	if picked or not is_on():
		return
	state[RadioItem.CHARGE] = maxf(charge() - dt, 0.0)
	if charge() <= 0.0:
		state[RadioItem.ON] = false
		_refresh()
		interactable.enabled = false
		return
	_noise_left -= dt
	if _noise_left <= 0.0:
		_noise_left += Tuning.RADIO_NOISE_INTERVAL
		NoiseModel.emit(global_position, Tuning.RADIO_NOISE_RADIUS, Tuning.NOISE_KIND_RADIO)


## Switches the placed radio's sound and LED to match `state`.
func _refresh() -> void:
	if _led != null and _led.get_parent() != null:
		ItemModels.set_radio_led(_led.get_parent(), is_on())
	if is_on() and _loop == null:
		_loop = AudioManager.loop(SOUND_STATIC, self).start()
		_loop.set_volume(PLACED_GAIN_DB)
		_noise_left = 0.0
	elif not is_on() and _loop != null:
		_loop.release()
		_loop = null
	if charge() <= 0.0:
		interactable.enabled = false
		light.visible = false


func _exit_tree() -> void:
	if _loop != null:
		_loop.release()
		_loop = null
