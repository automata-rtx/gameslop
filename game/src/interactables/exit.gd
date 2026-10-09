class_name Exit
extends Node3D
## The level's sanctioned way down (07 §6, 09 §5 "Exit", GLOSSARY). Shared by every exit
## prefab (Halls and Offices elevator, Pools drain hatch, Garage stairwell door, Server floor
## hatch; the Substrate Threshold is M2.15's): a lock, a status, open()/seal(), a walk-in
## trigger volume, and a "seen" detector (frustum + 25 m + unoccluded) that moves the HUD
## status off UNKNOWN.
## Locks (07 §6): Open (walk in); Powered (dark and dead until power(): the breaker's power
## wave calls it when it reaches the exit); Keyed (the exit owns a CardReader at %ReaderMount,
## whose `swiped` opens it); Cycled (sealed CYCLED_SEALED_TIME, open CYCLED_OPEN_TIME, the
## long tone CYCLED_WARNING_TIME before each opening; the run starts the clock on arrival with
## start_cycle(); %Display shows the countdown on the frame).
## Signals up: `entering(player)` when the player walks into the open exit; the run plays
## the 0.6 s entering tween and calls GameState.descend(true) (14 §5: the run owns the
## level change). EventBus.exit_status_changed(status, timer) carries the status once the
## exit is known (timer: seconds left in a Cycled phase, else 0).
## Scene contract: %Light (OmniLight3D), %SightPoint, %Trigger (Area3D, mask = player layer,
## its CollisionShape3D is the walk-in volume). Optional: %DoorL and %DoorR (sliding leaves,
## `leaf_motion` slide), %Leaf (a hinge pivot, `leaf_motion` hinge, rotated to
## `hinge_open_deg`), %Leaves (StaticBody3D that blocks while closed), %Interior, %Lamp,
## %CallButton (world-shader meshes whose `emission_strength` follows the state), %Display
## (Label3D, Cycled only), %ReaderMount (where a Keyed exit's reader stands), %ReaderPost
## (shown only on a Keyed exit).

signal status_changed(status: StringName)
signal seen
signal entering(player: Node3D)

const MOTION_SLIDE := &"slide"
const MOTION_HINGE := &"hinge"
const READER_SCENE := "res://scenes/interactables/card_reader.tscn"
## 11 §3 "Exit seen": the latch (Open, Powered, Keyed) or the long tone (Cycled).
const SOUND_LATCH := &"exit_latch"
const SOUND_TONE := &"exit_tone"
## 02 §6 / 11 §3: the lamp's seen pulse.
const LAMP_PULSE := 8.0
const PULSE_TIME := 0.5
const DOOR_OPEN_TIME := 0.8
## Seconds between "seen" checks (the check is a frustum test and one ray).
const SEEN_INTERVAL := 0.1

@export var lock: StringName = Tuning.LOCK_OPEN
## The placement's `exit_kind` (07 §5): elevator, drain_hatch, stairwell_door, floor_hatch.
@export var exit_kind: StringName = &"elevator"
## The prefab's own opening sound (03 §4 world table; one per prefab family).
@export var sound_open: StringName = &"exit_open"
@export var leaf_motion: StringName = MOTION_SLIDE
@export var slide_open_x: float = 0.9
@export var slide_closed_x: float = 0.3
@export var hinge_open_deg: Vector3 = Vector3(0.0, -95.0, 0.0)
## Glow when lit (emission_strength of the world-shader materials).
@export var lamp_on: float = 3.0
@export var interior_on: float = 1.2
@export var button_on: float = 2.0
@export var light_on: float = 0.6
## Where the entering tween carries the player, in the exit's space.
@export var entry_offset: Vector3 = Vector3(0.0, 0.0, -0.2)

@onready var door_l: Node3D = get_node_or_null(^"%DoorL")
@onready var door_r: Node3D = get_node_or_null(^"%DoorR")
@onready var leaf: Node3D = get_node_or_null(^"%Leaf")
@onready var leaves: StaticBody3D = get_node_or_null(^"%Leaves")
@onready var interior: MeshInstance3D = get_node_or_null(^"%Interior")
@onready var lamp: MeshInstance3D = get_node_or_null(^"%Lamp")
@onready var call_button: MeshInstance3D = get_node_or_null(^"%CallButton")
@onready var display: Label3D = get_node_or_null(^"%Display")
@onready var reader_mount: Node3D = get_node_or_null(^"%ReaderMount")
@onready var reader_post: Node3D = get_node_or_null(^"%ReaderPost")
@onready var light: OmniLight3D = %Light
@onready var sight_point: Node3D = %SightPoint
@onready var trigger: Area3D = %Trigger

var status: StringName = Tuning.EXIT_STATUS_OPEN
var powered: bool = true
var is_seen: bool = false
var is_entering: bool = false
## When false the trigger is ignored (the run is already leaving, or the player is dead).
var accepting: bool = true
## Keyed: the reader this exit owns (null otherwise).
var reader: CardReader
## Cycled: true once start_cycle() ran; seconds left in the current phase.
var cycle_running: bool = false
var cycle_left: float = 0.0

var _seen_t: float = 0.0
var _tone_played: bool = false
var _materials: Dictionary = {}
var _doors: Tween
var _pulse: Tween
var _power_wave: Tween


func _ready() -> void:
	add_to_group(&"exits")
	for mi: MeshInstance3D in _glow_meshes():
		var m := mi.material_override.duplicate() as Material
		mi.material_override = m
		_materials[mi] = m
	trigger.body_entered.connect(_on_body_entered)
	set_lock(lock)


func _glow_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in [interior, lamp, call_button]:
		if mi != null and mi.material_override != null:
			out.append(mi)
	return out


## Sets the lock and the matching initial state (07 §6). Powered starts dark and sealed;
## Keyed starts lit and closed behind its reader; Cycled starts sealed with a full sealed phase.
func set_lock(kind: StringName) -> void:
	lock = kind
	if not is_node_ready():
		return
	cycle_running = false
	cycle_left = Tuning.CYCLED_SEALED_TIME if kind == Tuning.LOCK_CYCLED else 0.0
	_tone_played = false
	_sync_reader(kind == Tuning.LOCK_KEYED)
	if display != null:
		display.visible = kind == Tuning.LOCK_CYCLED
	match kind:
		Tuning.LOCK_POWERED:
			powered = false
			_set_status(Tuning.EXIT_STATUS_POWERED)
			_apply_closed(0.0)
		Tuning.LOCK_KEYED:
			powered = true
			_set_status(Tuning.EXIT_STATUS_KEYED)
			_apply_closed(0.0)
		Tuning.LOCK_CYCLED:
			powered = true
			_set_status(Tuning.EXIT_STATUS_SEALED)
			_apply_closed(0.0)
		_:
			powered = true
			_set_status(Tuning.EXIT_STATUS_OPEN)
			_apply_open(0.0, false)
	_render_display()


func is_open() -> bool:
	return status == Tuning.EXIT_STATUS_OPEN


## 07 §6 open(): unlocks the exit (latch and hiss, light steady warm, EXIT: OPEN).
func open() -> void:
	if is_open():
		return
	powered = true
	_set_status(Tuning.EXIT_STATUS_OPEN)
	_apply_open(DOOR_OPEN_TIME, true)
	# A player already standing in the volume when the doors open walks in (no new entry event).
	_take_overlapping.call_deferred()


func _take_overlapping() -> void:
	if not is_inside_tree() or not trigger.monitoring:
		return
	for b in trigger.get_overlapping_bodies():
		_on_body_entered(b)


## 07 §6 seal(): closes the exit (Cycled's sealed phase): the latch, the doors close.
func seal() -> void:
	if not is_open():
		return
	_set_status(Tuning.EXIT_STATUS_SEALED)
	_apply_closed(DOOR_OPEN_TIME)
	AudioManager.play_3d(SOUND_LATCH, sight_point.global_position)


## Powered lock: the breaker's power wave reached the exit.
func power() -> void:
	if lock == Tuning.LOCK_POWERED:
		open()


## The breaker's power wave reaches the exit in `delay` seconds (RunLevelSetup.run_power_wave).
func power_after(delay: float) -> void:
	if _power_wave != null:
		_power_wave.kill()
	_power_wave = create_tween()
	_power_wave.tween_interval(maxf(delay, 0.0))
	_power_wave.tween_callback(power)


## 08 §5 Variant B: the fuse was pulled after the throw. A Powered exit loses its power: any
## wave still on its way is cancelled, and an open exit seals back to EXIT: POWERED (the latch,
## the doors close, dark and dead as before the throw).
func unpower() -> void:
	if _power_wave != null:
		_power_wave.kill()
		_power_wave = null
	if lock != Tuning.LOCK_POWERED:
		return
	var was_open := is_open()
	powered = false
	_set_status(Tuning.EXIT_STATUS_POWERED)
	_apply_closed(DOOR_OPEN_TIME if was_open else 0.0)
	if was_open:
		AudioManager.play_3d(SOUND_LATCH, sight_point.global_position)


## Seconds left in the Cycled phase the status names (0 for every other lock).
func status_timer() -> float:
	return cycle_left if lock == Tuning.LOCK_CYCLED else 0.0


func _set_status(s: StringName) -> void:
	if status == s:
		return
	status = s
	status_changed.emit(s)
	# 11 §3 breaker row: a Powered or Keyed unlock is announced even before the exit was seen.
	var unlock := s == Tuning.EXIT_STATUS_OPEN and (lock == Tuning.LOCK_POWERED or lock == Tuning.LOCK_KEYED)
	if is_seen or unlock:
		EventBus.exit_status_changed.emit(s, status_timer())


# --- Keyed (07 §6, 09 §5 card reader) ----------------------------------------------------------

func _sync_reader(keyed: bool) -> void:
	if reader_post != null:
		reader_post.visible = keyed
		for b in reader_post.find_children("*", "CollisionObject3D", true, false):
			(b as CollisionObject3D).process_mode = Node.PROCESS_MODE_INHERIT if keyed else Node.PROCESS_MODE_DISABLED
	if not keyed:
		if reader != null:
			reader.queue_free()
			reader = null
		return
	if reader != null:
		return
	reader = (load(READER_SCENE) as PackedScene).instantiate() as CardReader
	reader.name = "CardReader"
	if reader_mount != null:
		reader_mount.add_child(reader)
	else:
		reader.position = Vector3(1.0, 0.0, 0.0)
		add_child(reader)
	# M2.9: the reader's accepted swipe opens the exit (09 Interfaces).
	reader.swiped.connect(_on_swiped)


func _on_swiped(_player: Node) -> void:
	if lock == Tuning.LOCK_KEYED:
		open()


# --- Cycled (07 §6) --------------------------------------------------------------------------

## Starts the Cycled clock (the run calls it on arrival): a full sealed phase, then open.
func start_cycle() -> void:
	if lock != Tuning.LOCK_CYCLED or cycle_running:
		return
	cycle_running = true
	cycle_left = Tuning.CYCLED_SEALED_TIME
	_tone_played = false
	if is_seen:
		EventBus.exit_status_changed.emit(status, status_timer())
	_render_display()


## Advances the Cycled clock by `dt` seconds (the exit's _process; tests call it directly).
## While the player is being carried in, the exit does not seal on them.
func advance_cycle(dt: float) -> void:
	if not cycle_running or is_entering:
		return
	cycle_left -= dt
	var guard := 4
	while cycle_left <= 0.0 and guard > 0:
		guard -= 1
		if is_open():
			cycle_left += Tuning.CYCLED_SEALED_TIME
			_tone_played = false
			seal()
		else:
			cycle_left += Tuning.CYCLED_OPEN_TIME
			open()
	if not is_open() and not _tone_played and cycle_left <= Tuning.CYCLED_WARNING_TIME:
		# 07 §6: the long tone 5 s before opening, max_distance 60 m, heard through walls.
		_tone_played = true
		AudioManager.play_3d(SOUND_TONE, sight_point.global_position)
	_render_display()


func _process(delta: float) -> void:
	if cycle_running:
		advance_cycle(delta)


func _render_display() -> void:
	if display == null or not display.visible:
		return
	display.text = HudDepth.format_time(cycle_left)
	display.modulate = UiTokens.UI_FG if is_open() else UiTokens.UI_ACCENT


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


## True when the exit is in `cam`'s frustum, within 25 m and not occluded by the world (the
## exit's own bodies, its leaves, frame or reader, do not occlude it).
func check_seen(cam: Camera3D) -> bool:
	var p := sight_point.global_position
	var from := cam.global_position
	if from.distance_to(p) > Tuning.EXIT_SEEN_DIST or not cam.is_position_in_frustum(p):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, p, PlayerLayers.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var collider := hit["collider"] as Node
	return collider != null and (collider == leaves or is_ancestor_of(collider))


## 11 §3 "Exit seen": the lamp pulses once, the latch (Cycled: the long tone) sounds, the
## status shutters in.
func mark_seen() -> void:
	if is_seen:
		return
	is_seen = true
	EventBus.exit_status_changed.emit(status, status_timer())
	AudioManager.play_3d(SOUND_TONE if lock == Tuning.LOCK_CYCLED else SOUND_LATCH, sight_point.global_position)
	_pulse_lamp()
	seen.emit()


func _pulse_lamp() -> void:
	if lamp == null:
		return
	if _pulse != null:
		_pulse.kill()
	var rest := lamp_on if (is_open() or (powered and lock != Tuning.LOCK_POWERED)) else 0.0
	_pulse = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_pulse.tween_method(_set_emission.bind(lamp), LAMP_PULSE, rest, PULSE_TIME)


# --- trigger (09 §5: walk-in volume) -----------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		try_enter(body)


## The player stepped into the volume: only an open exit takes them, and only a player
## walking in (a locomotion state, charging a noclip, which then ends silently, or
## stunned at crouch pace): a drop or a pass through the volume is never a proper exit
## (noclip review).
func try_enter(player: Node3D) -> bool:
	if not accepting or is_entering or not is_open():
		return false
	var sm: PlayerStateMachine = (player as Player).state_machine if player is Player else null
	if sm != null and not sm.has_movement():
		return false
	is_entering = true
	AudioManager.play_3d(sound_open, sight_point.global_position)
	entering.emit(player)
	return true


## Where the entering tween carries the player (into the car, down the hatch, through the door).
func entry_transform() -> Transform3D:
	return Transform3D(global_transform.basis.orthonormalized(), to_global(entry_offset))


## The centre of the walk-in volume (tests, benches and the sim bot walk here).
func walk_in_point() -> Vector3:
	for c in trigger.get_children():
		if c is CollisionShape3D:
			var p := (c as Node3D).global_position
			return Vector3(p.x, global_position.y + 0.1, p.z)
	return global_position


## A standing point `dist` metres in front of the exit (its -Z), on the exit's floor.
func approach_point(dist: float) -> Vector3:
	var w := walk_in_point()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return Vector3(w.x, global_position.y, w.z) + fwd.normalized() * dist


# --- visuals ---------------------------------------------------------------------------------

func _apply_open(time: float, audible: bool) -> void:
	if leaves != null:
		leaves.process_mode = Node.PROCESS_MODE_DISABLED
	_move_leaves(true, time)
	_set_emission(interior_on, interior)
	_set_emission(lamp_on, lamp)
	_set_emission(button_on, call_button)
	light.visible = true
	light.light_energy = light_on
	_render_display()
	if audible:
		AudioManager.play_3d(sound_open, sight_point.global_position)
		AudioManager.play_3d(SOUND_LATCH, sight_point.global_position)


func _apply_closed(time: float) -> void:
	if leaves != null:
		leaves.process_mode = Node.PROCESS_MODE_INHERIT
	_move_leaves(false, time)
	var lit := powered
	_set_emission(0.0, interior)
	_set_emission(lamp_on if lit else 0.0, lamp)
	_set_emission(button_on if lit else 0.0, call_button)
	light.visible = false
	_render_display()


func _move_leaves(open_: bool, time: float) -> void:
	if _doors != null:
		_doors.kill()
		_doors = null
	if leaf_motion == MOTION_HINGE:
		if leaf == null:
			return
		var target := hinge_open_deg * (PI / 180.0) if open_ else Vector3.ZERO
		if time <= 0.0:
			leaf.rotation = target
			return
		_doors = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_doors.tween_property(leaf, ^"rotation", target, time)
		return
	if door_l == null or door_r == null:
		return
	var x := slide_open_x if open_ else slide_closed_x
	var lx := -absf(x)
	var rx := absf(x)
	if time <= 0.0:
		door_l.position.x = lx
		door_r.position.x = rx
		return
	_doors = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_doors.tween_property(door_l, ^"position:x", lx, time)
	_doors.tween_property(door_r, ^"position:x", rx, time)


## 0 closed .. 1 open, from the leaves' pose (benches and the feedback spy read it).
func leaf_open_amount() -> float:
	if leaf_motion == MOTION_HINGE:
		if leaf == null or hinge_open_deg.length() <= 0.0:
			return 1.0 if is_open() else 0.0
		return clampf(rad_to_deg(leaf.rotation.length()) / hinge_open_deg.length(), 0.0, 1.0)
	if door_l == null or is_equal_approx(slide_open_x, slide_closed_x):
		return 1.0 if is_open() else 0.0
	return clampf((absf(door_l.position.x) - slide_closed_x) / (slide_open_x - slide_closed_x), 0.0, 1.0)


func _set_emission(v: float, mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var m: Material = _materials.get(mi)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter(&"emission_strength", v)


func emission_of(mi: MeshInstance3D) -> float:
	var m: Material = _materials.get(mi)
	if m is ShaderMaterial:
		return float((m as ShaderMaterial).get_shader_parameter(&"emission_strength"))
	return 0.0
