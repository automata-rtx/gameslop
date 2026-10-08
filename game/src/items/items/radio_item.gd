class_name RadioItem
extends ItemBase
## The Radio belt item (09 §2, 11 §2). A tap toggles it on and off. On, it plays static that
## swells and pings faster as the player faces the exit (the angle between the view and the
## exit within 20 degrees: fast ping; within 60: slow; otherwise only noise), emits a 10 m
## `mech` noise every second (Echo follows it, 08 §6), and spends its charge: 3 charges of
## 30 s, 90 s in all, kept in the slot (`state.charge`, seconds left; `state.on`). A spent
## radio leaves the belt. Reading (09 says toggle; the brief says lure): holding use_item 0.5 s
## sets it down where it stands, still playing, as a RadioPickup that can be taken again
## (taking it switches it off). The radio is switched off when the level is left.

const ON := &"on"
const CHARGE := &"charge"
const SOUND_TOGGLE := &"radio_ping"
const SOUND_STATIC := &"radio_static"
const SOUND_PING := &"radio_ping"
const BAND_FAST := &"fast"
const BAND_SLOW := &"slow"
const BAND_NOISE := &"noise"

var _held_for: float = -1.0
var _noise_left: float = 0.0
var _ping_left: float = 0.0
var _loop: AudioLoop = null


static func full_charge() -> float:
	return Tuning.RADIO_CHARGES * Tuning.RADIO_CHARGE_TIME


static func charge_of(slot: ItemSlot) -> float:
	return float(slot.state.get(CHARGE, full_charge())) if slot != null else 0.0


static func is_on(slot: ItemSlot) -> bool:
	return slot != null and bool(slot.state.get(ON, false))


## 09 §2 ping bands by the angle (degrees, 0 = facing the exit) between the view and the exit.
static func band(angle_deg: float) -> StringName:
	var a := absf(angle_deg)
	if a <= Tuning.RADIO_PING_FAST_DEG:
		return BAND_FAST
	if a <= Tuning.RADIO_PING_SLOW_DEG:
		return BAND_SLOW
	return BAND_NOISE


## Seconds between pings in a band; 0 = no ping (noise only).
static func ping_interval(b: StringName) -> float:
	match b:
		BAND_FAST:
			return Tuning.RADIO_PING_FAST_INTERVAL
		BAND_SLOW:
			return Tuning.RADIO_PING_SLOW_INTERVAL
	return 0.0


## The static's level in dB under full: quietest facing away (60 degrees and past), full
## within 20 degrees, a straight blend between.
static func gain_db(angle_deg: float) -> float:
	var a := absf(angle_deg)
	var t := clampf(1.0 - (a - Tuning.RADIO_PING_FAST_DEG) / (Tuning.RADIO_PING_SLOW_DEG - Tuning.RADIO_PING_FAST_DEG), 0.0, 1.0)
	return lerpf(Tuning.RADIO_GAIN_FAR_DB, 0.0, t)


## Angle in degrees between the horizontal `facing` and the direction from `from` to `target`
## (180 when there is no target).
static func angle_between(facing: Vector3, from: Vector3, target: Vector3) -> float:
	var f := Vector2(facing.x, facing.z)
	var d := Vector2(target.x - from.x, target.z - from.z)
	if f.length() < 0.001 or d.length() < 0.001:
		return 180.0
	return rad_to_deg(absf(f.angle_to(d)))


func _ready() -> void:
	EventBus.level_left.connect(_on_level_left)


func _slot() -> ItemSlot:
	var i := inventory.slot_of(kind) if inventory != null else -1
	return inventory.slots[i] as ItemSlot if i != -1 else null


# --- input -------------------------------------------------------------------------------

func input(slot: ItemSlot, pressed: bool, held_key: bool, dt: float) -> void:
	if pressed and _held_for < 0.0:
		_held_for = 0.0
		return
	if _held_for < 0.0:
		return
	if held_key:
		_held_for += dt
		if _held_for >= Tuning.RADIO_PUT_DOWN_HOLD:
			_held_for = -1.0
			put_down(slot)
	else:
		_held_for = -1.0
		toggle(slot)


func abort_hold() -> void:
	_held_for = -1.0


func use(slot: ItemSlot) -> bool:
	return toggle(slot)


func cancel() -> void:
	busy = false
	_held_for = -1.0
	_stop_static()


## Switches the radio. A spent radio does nothing. Returns true when the state changed.
func toggle(slot: ItemSlot) -> bool:
	if slot == null or slot.count <= 0 or charge_of(slot) <= 0.0:
		return false
	var on := not is_on(slot)
	slot.state[ON] = on
	slot.state[CHARGE] = charge_of(slot)
	AudioManager.play_3d(SOUND_TOGGLE, _pos() + Vector3(0.0, 1.4, 0.0))
	var p := player()
	if p != null:
		p.rig.nod(0.3)
	flick(Vector3(0.0, -0.012, 0.0), 0.05, 0.12)
	if on:
		_noise_left = 0.0
		_ping_left = 0.0
		_start_static()
		EventBus.item_used.emit(kind)
	else:
		_stop_static()
	_refresh_led(on)
	inventory.changed.emit(inventory.slots, inventory.selected)
	return true


## Sets the radio down at the feet as a pickup that keeps its state (on or off, the charge).
func put_down(slot: ItemSlot) -> Node3D:
	if slot == null or slot.count <= 0:
		return null
	var p := player()
	var pos := Vector3(0.0, 0.0, -0.4)
	var yaw := 0.0
	if p != null:
		var f := -p.global_transform.basis.z
		f.y = 0.0
		pos = p.global_position + f.normalized() * 0.5
		yaw = p.global_rotation.y
	var st := slot.state.duplicate(true)
	st[CHARGE] = charge_of(slot)
	_stop_static()
	var tree := inventory.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var placed := ItemPickup.spawn(parent, kind, 1, st, pos)
	if placed != null:
		placed.rotation.y = yaw
	slot.state.erase(ON)
	inventory.remove(kind, 1)
	return placed


# --- the radio on ---------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var slot := _slot()
	if not is_on(slot):
		if _loop != null:
			_stop_static()
		return
	if _loop == null:
		_start_static()
	var left := charge_of(slot) - dt
	slot.state[CHARGE] = maxf(left, 0.0)
	if left <= 0.0:
		_spent(slot)
		return
	var pos := _pos()
	_noise_left -= dt
	if _noise_left <= 0.0:
		_noise_left += Tuning.RADIO_NOISE_INTERVAL
		NoiseModel.emit(pos, Tuning.RADIO_NOISE_RADIUS, Tuning.NOISE_KIND_RADIO)
	var angle := angle_to_exit()
	if _loop != null:
		_loop.set_volume(gain_db(angle))
	var every := ping_interval(band(angle))
	_ping_left -= dt
	if every > 0.0:
		if _ping_left <= 0.0:
			_ping_left = every
			AudioManager.play_2d(SOUND_PING)
	else:
		_ping_left = 0.0


## Degrees between the view and the exit (180 with no exit in the level).
func angle_to_exit() -> float:
	var exit := get_tree().get_first_node_in_group(&"exits") as Node3D if get_tree() != null else null
	if exit == null:
		return 180.0
	var p := player()
	var facing := Vector3(0.0, 0.0, -1.0)
	if p != null:
		facing = -(p.rig.camera.global_transform.basis.z if p.rig != null else p.global_transform.basis.z)
	return angle_between(facing, _pos(), exit.global_position)


func _pos() -> Vector3:
	var p := player()
	return p.global_position if p != null else Vector3.ZERO


func _spent(slot: ItemSlot) -> void:
	slot.state.erase(ON)
	_stop_static()
	inventory.remove(kind, 1)


func _start_static() -> void:
	if _loop == null:
		_loop = AudioManager.loop(SOUND_STATIC).start()


func _stop_static() -> void:
	if _loop != null:
		_loop.stop(0.1)
		_loop = null


func on_equipped(model: Node3D) -> void:
	ItemModels.set_radio_led(model, is_on(_slot()))


func _refresh_led(on: bool) -> void:
	var m := held()
	if m != null:
		ItemModels.set_radio_led(m, on)


func _on_level_left(_proper: bool) -> void:
	var slot := _slot()
	if is_on(slot):
		slot.state[ON] = false
		_stop_static()


func _exit_tree() -> void:
	if _loop != null:
		_loop.release()
		_loop = null
