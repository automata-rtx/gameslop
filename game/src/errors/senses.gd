class_name Senses
extends Node
## The honest senses of an error (08 §2): the only thing that can start a chase.
## A child component of an ErrorBase (14 §6 composition). It never reads the Director.
##
## Hearing: a noise on EventBus.noise_emitted is heard when the ear is within
## `radius x hearing_mult` after wall attenuation (06 §6, NoiseModel). Heard noises
## update `last_known_pos` and add to `suspicion` (+0.6 per step, +1.0 per tear, door
## or mech). Sight (Still only in v1): a world-layer ray from the error's eye (1.6 m) to
## the player's eye, within `sight_range`, never an Area3D; a hidden player is not seen.
## Suspicion decays 0.5 per second and grows 0.67 per second seen.

signal heard(pos: Vector3, radius: float, kind: StringName)

## 08 §8: Still 1.0, Echo 1.0..1.4 by aggression, Flicker 0.8.
@export var hearing_mult: float = 1.0
## 0 means blind (Static, Echo). Still: 25 m.
@export var sight_range: float = 0.0

## The error this belongs to: ears and eye are measured from its body.
var error: Node3D
var suspicion: float = 0.0
var last_known_pos: Vector3 = Vector3.ZERO
## Seconds on the error's own clock; < 0 while nothing is known.
var last_known_time: float = -1.0
## Continuous seconds the player has been visible (resets when sight breaks).
var seen_time: float = 0.0
## Continuous seconds without sight of the player.
var unseen_time: float = 0.0
var sees_player: bool = false
## The error's clock in seconds (advanced by tick()).
var clock: float = 0.0
var _listening: bool = false


func _exit_tree() -> void:
	listen(false)


## Hearing is on only while the error is awake (Dormant errors run a 1 s timer only).
func listen(on: bool) -> void:
	if on == _listening:
		return
	_listening = on
	if on:
		EventBus.noise_emitted.connect(_on_noise)
	else:
		EventBus.noise_emitted.disconnect(_on_noise)


func is_listening() -> bool:
	return _listening


func has_last_known() -> bool:
	return last_known_time >= 0.0


func forget() -> void:
	suspicion = 0.0
	seen_time = 0.0
	last_known_time = -1.0


func ear_position() -> Vector3:
	if error != null and error.has_method(&"ear_position"):
		return error.call(&"ear_position")
	return error.global_position if error != null else Vector3.ZERO


## 08 §2 suspicion per heard noise kind.
static func suspicion_for(kind: StringName) -> float:
	if kind == Tuning.NOISE_KIND_STEP:
		return Tuning.ERROR_SUSPICION_STEP
	if kind == Tuning.NOISE_KIND_TEAR or kind == Tuning.NOISE_KIND_DOOR or kind == Tuning.NOISE_KIND_MECH:
		return Tuning.ERROR_SUSPICION_LOUD
	return 0.0


## True when a noise at `pos` of `radius` reaches the ear (straight line, walls -35% each).
func can_hear(pos: Vector3, radius: float) -> bool:
	var ear := ear_position()
	var r := radius * hearing_mult
	if pos.distance_to(ear) >= r:
		return false
	var space := _space()
	if space == null:
		return true
	return NoiseModel.can_hear(space, pos, ear, r, _exclude())


func _on_noise(pos: Vector3, radius: float, kind: StringName) -> void:
	if can_hear(pos, radius):
		register_noise(pos, radius, kind)


## A heard noise: memory and suspicion, then the error decides (signals up).
func register_noise(pos: Vector3, radius: float, kind: StringName) -> void:
	last_known_pos = pos
	last_known_time = clock
	suspicion = minf(suspicion + suspicion_for(kind), Tuning.ERROR_SUSPICION_CHASE_AT * 2.0)
	heard.emit(pos, radius, kind)


## One sense step: clock, decay, and sight of `player` (null or blind: no sight).
func tick(delta: float, player: Node3D) -> void:
	clock += delta
	var see := sight_range > 0.0 and player != null and can_see(player)
	sees_player = see
	if see:
		seen_time += delta
		unseen_time = 0.0
		suspicion = minf(suspicion + Tuning.ERROR_SUSPICION_SEEN_PER_S * delta, Tuning.ERROR_SUSPICION_CHASE_AT * 2.0)
		last_known_pos = player.global_position
		last_known_time = clock
	else:
		seen_time = 0.0
		unseen_time += delta
		suspicion = maxf(suspicion - Tuning.ERROR_SUSPICION_DECAY_PER_S * delta, 0.0)


## 08 §2 sight: within range, the player not hidden, a clear world-layer ray eye to eye.
func can_see(player: Node3D) -> bool:
	if error == null or not error.is_inside_tree() or not player.is_inside_tree():
		return false
	if player.has_method(&"is_hidden") and bool(player.call(&"is_hidden")):
		return false
	var eye := ear_position()
	var target: Vector3 = player.call(&"eye_position") if player.has_method(&"eye_position") else player.global_position
	if eye.distance_to(target) > sight_range:
		return false
	var space := _space()
	if space == null:
		return false
	var exclude := _exclude()
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(eye, target, PlayerLayers.WORLD_MASK, exclude)
	return space.intersect_ray(q).is_empty()


func _space() -> PhysicsDirectSpaceState3D:
	if error == null or not error.is_inside_tree():
		return null
	return error.get_world_3d().direct_space_state


func _exclude() -> Array[RID]:
	var out: Array[RID] = []
	if error != null and error.has_method(&"body_rids"):
		out.append_array(error.call(&"body_rids"))
	return out
