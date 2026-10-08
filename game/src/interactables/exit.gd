class_name Exit
extends Node3D
## The level's sanctioned way down (07 §6, 09 §5 "Exit", GLOSSARY). Shared by every exit
## prefab: a lock, a status, open()/seal(), a walk-in trigger volume, and a "seen"
## detector (frustum + 25 m + unoccluded) that moves the HUD status off UNKNOWN.
## Locks here: Open (walk in) and Powered (dark and dead until power(); the breaker's power
## wave calls it when it reaches the exit). Keyed and Cycled arrive with M2.9.
## Signals up: `entering(player)` when the player walks into the open exit; the run plays
## the 0.6 s entering tween and calls GameState.descend(true) (14 §5: the run owns the
## level change). EventBus.exit_status_changed carries the status once the exit is known.
## Scene contract: %DoorL, %DoorR (leaves), %Leaves (their StaticBody3D), %Interior (the lit
## car), %Lamp (the light above the frame), %CallButton, %Light (OmniLight3D), %SightPoint,
## %Trigger (Area3D, mask = player layer).

signal status_changed(status: StringName)
signal seen
signal entering(player: Node3D)

## 02 §6 / 11 §3: how bright the car and lamp glow when open, and the seen pulse.
const LAMP_ON := 3.0
const LAMP_PULSE := 8.0
const INTERIOR_ON := 1.2
const BUTTON_ON := 2.0
const LIGHT_ON := 0.6
const PULSE_TIME := 0.5
const DOOR_OPEN_TIME := 0.8
const DOOR_OPEN_X := 0.9
const DOOR_CLOSED_X := 0.3
## Seconds between "seen" checks (the check is a frustum test and one ray).
const SEEN_INTERVAL := 0.1

@export var lock: StringName = Tuning.LOCK_OPEN

@onready var door_l: Node3D = %DoorL
@onready var door_r: Node3D = %DoorR
@onready var leaves: StaticBody3D = %Leaves
@onready var interior: MeshInstance3D = %Interior
@onready var lamp: MeshInstance3D = %Lamp
@onready var call_button: MeshInstance3D = %CallButton
@onready var light: OmniLight3D = %Light
@onready var sight_point: Node3D = %SightPoint
@onready var trigger: Area3D = %Trigger

var status: StringName = Tuning.EXIT_STATUS_OPEN
var powered: bool = true
var is_seen: bool = false
var is_entering: bool = false
## When false the trigger is ignored (the run is already leaving, or the player is dead).
var accepting: bool = true

var _seen_t: float = 0.0
var _materials: Dictionary = {}
var _doors: Tween
var _pulse: Tween


func _ready() -> void:
	add_to_group(&"exits")
	for mi: MeshInstance3D in [interior, lamp, call_button]:
		var m := mi.material_override.duplicate() as Material
		mi.material_override = m
		_materials[mi] = m
	trigger.body_entered.connect(_on_body_entered)
	set_lock(lock)


## Sets the lock and the matching initial state (07 §6). Powered starts dark and sealed.
func set_lock(kind: StringName) -> void:
	lock = kind
	if not is_node_ready():
		return
	if kind == Tuning.LOCK_POWERED:
		powered = false
		_set_status(Tuning.EXIT_STATUS_POWERED)
		_apply_closed(0.0)
	else:
		powered = true
		_set_status(Tuning.EXIT_STATUS_OPEN)
		_apply_open(0.0, false)


func is_open() -> bool:
	return status == Tuning.EXIT_STATUS_OPEN


## 07 §6 open(): unlocks the exit (latch and hiss, light steady warm, EXIT: OPEN).
func open() -> void:
	if is_open():
		return
	powered = true
	_set_status(Tuning.EXIT_STATUS_OPEN)
	_apply_open(DOOR_OPEN_TIME, true)


## 07 §6 seal(): closes the exit (Cycled's sealed phase; M2.9 adds its timer).
func seal() -> void:
	if not is_open():
		return
	_set_status(Tuning.EXIT_STATUS_SEALED)
	_apply_closed(DOOR_OPEN_TIME)


## Powered lock: the breaker's power wave reached the exit.
func power() -> void:
	if lock == Tuning.LOCK_POWERED:
		open()


func _set_status(s: StringName) -> void:
	if status == s:
		return
	status = s
	status_changed.emit(s)
	# 11 §3 breaker row: the unlock is announced even before the exit was seen.
	if is_seen or (s == Tuning.EXIT_STATUS_OPEN and lock != Tuning.LOCK_OPEN):
		EventBus.exit_status_changed.emit(s, 0.0)


# --- seen detector (04 §6, 07 §6) ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_seen:
		set_physics_process(false)
		return
	_seen_t -= delta
	if _seen_t > 0.0:
		return
	_seen_t = SEEN_INTERVAL
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and check_seen(cam):
		mark_seen()


## True when the exit is in `cam`'s frustum, within 25 m and not occluded by the world.
func check_seen(cam: Camera3D) -> bool:
	var p := sight_point.global_position
	var from := cam.global_position
	if from.distance_to(p) > Tuning.EXIT_SEEN_DIST or not cam.is_position_in_frustum(p):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, p, PlayerLayers.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["collider"] as Node) == leaves


## 11 §3 "Exit seen": the lamp pulses once, the latch sounds, the status shutters in.
func mark_seen() -> void:
	if is_seen:
		return
	is_seen = true
	EventBus.exit_status_changed.emit(status, 0.0)
	AudioManager.play_3d(&"exit_latch", sight_point.global_position)
	_pulse_lamp()
	seen.emit()


func _pulse_lamp() -> void:
	if _pulse != null:
		_pulse.kill()
	var rest := LAMP_ON if is_open() else 0.0
	_pulse = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_pulse.tween_method(_set_emission.bind(lamp), LAMP_PULSE, rest, PULSE_TIME)


# --- trigger (09 §5: walk-in volume) -----------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		try_enter(body)


## The player stepped into the volume: only an open exit takes them.
func try_enter(player: Node3D) -> bool:
	if not accepting or is_entering or not is_open():
		return false
	is_entering = true
	AudioManager.play_3d(&"exit_open", sight_point.global_position)
	entering.emit(player)
	return true


## Where the entering tween carries the player (into the car, at floor level).
func entry_transform() -> Transform3D:
	return Transform3D(global_transform.basis.orthonormalized(), to_global(Vector3(0.0, 0.0, -0.2)))


# --- visuals ---------------------------------------------------------------------------------

func _apply_open(time: float, audible: bool) -> void:
	leaves.process_mode = Node.PROCESS_MODE_DISABLED
	_slide_doors(DOOR_OPEN_X, time)
	_set_emission(INTERIOR_ON, interior)
	_set_emission(LAMP_ON, lamp)
	_set_emission(BUTTON_ON, call_button)
	light.visible = true
	light.light_energy = LIGHT_ON
	if audible:
		AudioManager.play_3d(&"exit_open", sight_point.global_position)
		AudioManager.play_3d(&"exit_latch", sight_point.global_position)


func _apply_closed(time: float) -> void:
	leaves.process_mode = Node.PROCESS_MODE_INHERIT
	_slide_doors(DOOR_CLOSED_X, time)
	var lit := powered
	_set_emission(INTERIOR_ON if lit else 0.0, interior)
	_set_emission(LAMP_ON if lit else 0.0, lamp)
	_set_emission(BUTTON_ON if lit else 0.0, call_button)
	light.visible = false


func _slide_doors(x: float, time: float) -> void:
	if _doors != null:
		_doors.kill()
	var lx := -absf(x)
	var rx := absf(x)
	if time <= 0.0:
		door_l.position.x = lx
		door_r.position.x = rx
		return
	_doors = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_doors.tween_property(door_l, ^"position:x", lx, time)
	_doors.tween_property(door_r, ^"position:x", rx, time)


func _set_emission(v: float, mi: MeshInstance3D) -> void:
	var m: Material = _materials.get(mi)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter(&"emission_strength", v)


func emission_of(mi: MeshInstance3D) -> float:
	var m: Material = _materials.get(mi)
	if m is ShaderMaterial:
		return float((m as ShaderMaterial).get_shader_parameter(&"emission_strength"))
	return 0.0
