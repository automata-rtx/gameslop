class_name PlayerInput
extends RefCounted
## One snapshot of the player's actions per physics frame (06 §2). The only place that
## applies the Hold/Toggle settings for sprint and crouch (12 §5), and the only place
## that derives press edges, so simulated input (Input.action_press) behaves like keys.

## Settings keys (12 §5). Values: &"hold" (default) or &"toggle".
const SETTING_SPRINT_MODE := &"sprint_mode"
const SETTING_CROUCH_MODE := &"crouch_mode"
const MODE_TOGGLE := &"toggle"

const EDGE_ACTIONS: Array[StringName] = [
	&"sprint", &"crouch", &"interact", &"flashlight", &"crank", &"noclip", &"use_item",
]

var move: Vector2 = Vector2.ZERO          # x = right, y = forward; length <= 1
var sprint: bool = false
var crouch: bool = false
var interact_held: bool = false
var interact_pressed: bool = false
var flashlight_pressed: bool = false
var crank: bool = false
var noclip: bool = false
var use_item_pressed: bool = false

var _prev: Dictionary = {}
var _sprint_latched: bool = false
var _crouch_latched: bool = false


## Reads the InputMap. When `locked` (dissolving, cinematic) everything reads released.
func poll(locked: bool = false) -> void:
	var now: Dictionary = {}
	for a in EDGE_ACTIONS:
		now[a] = (not locked) and InputMap.has_action(a) and Input.is_action_pressed(a)
	var just := func(a: StringName) -> bool: return bool(now[a]) and not bool(_prev.get(a, false))
	if locked:
		move = Vector2.ZERO
	else:
		# 06 §3: digital keys, no curves; diagonal normalised; strafe equals forward.
		var raw := Vector2(_axis(&"move_left", &"move_right"), _axis(&"move_back", &"move_forward"))
		move = raw.normalized() if raw.length() > 1.0 else raw
	if just.call(&"sprint"):
		_sprint_latched = not _sprint_latched
	if just.call(&"crouch"):
		_crouch_latched = not _crouch_latched
	sprint = _sprint_latched if _mode(SETTING_SPRINT_MODE) == MODE_TOGGLE else bool(now[&"sprint"])
	crouch = _crouch_latched if _mode(SETTING_CROUCH_MODE) == MODE_TOGGLE else bool(now[&"crouch"])
	interact_held = now[&"interact"]
	interact_pressed = just.call(&"interact")
	flashlight_pressed = just.call(&"flashlight")
	crank = now[&"crank"]
	noclip = now[&"noclip"]
	use_item_pressed = just.call(&"use_item")
	_prev = now


## Toggle sprint ends when stamina runs out, so it does not resume by itself (12 §7).
func clear_sprint_latch() -> void:
	_sprint_latched = false


func clear_crouch_latch() -> void:
	_crouch_latched = false


func _axis(neg: StringName, pos: StringName) -> float:
	var v := 0.0
	if InputMap.has_action(pos) and Input.is_action_pressed(pos):
		v += 1.0
	if InputMap.has_action(neg) and Input.is_action_pressed(neg):
		v -= 1.0
	return v


static func _mode(key: StringName) -> StringName:
	var v: Variant = SettingsManager.get_value(key)
	return StringName(v) if v is StringName or v is String else &"hold"
