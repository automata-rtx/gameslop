class_name Interactor
extends Node
## The interaction ray (06 §7): from the camera, 2.2 m, every physics frame. It hits the
## world and interactable layers so walls occlude, and accepts colliders that carry an
## Interactable. Press interactions fire on press; hold ones fill over hold_time (0.6 s)
## with a tick every 0.2 s (11 §2). `forced` pins a target (the hide spot while hidden).

## Text is "" when there is no valid target. hold_time > 0 means a hold prompt.
signal prompt_changed(text: String, hold_time: float)
signal prompt_progress(fraction: float)
signal hold_tick
signal interacted(target: Interactable)

## Accessibility (12 §6): every hold interaction becomes a press.
const SETTING_HOLD_TO_PRESS := &"hold_to_press"

@export var camera: Camera3D
@export var body: CollisionObject3D

var target: Interactable = null
var forced: Interactable = null
var _progress: float = 0.0
var _tick: float = 0.0
var _last_text: String = ""
var _last_hold: float = -1.0
## Holds need a fresh press: a hold that completes does not repeat while the key stays down.
var _armed: bool = false


## `player` is passed to the Interactable; `active` false clears the target (no agency).
func physics_update(player: Node, held: bool, pressed: bool, dt: float, active: bool = true) -> void:
	var t: Interactable = null
	if active:
		t = forced if forced != null else _ray_target()
	if t != null and not t.can_interact(player):
		t = null
	if t != target:
		target = t
		_reset_hold()
	_announce()
	if target == null:
		return
	if pressed:
		_armed = true
	var hold := effective_hold(target)
	if hold <= 0.0:
		if pressed:
			_fire(player)
		return
	if not held or not _armed:
		if _progress > 0.0:
			_reset_hold()
		return
	_progress += dt
	_tick += dt
	if _tick >= Tuning.FEEDBACK_INTERACT_HOLD_TICK:
		_tick -= Tuning.FEEDBACK_INTERACT_HOLD_TICK
		hold_tick.emit()
	prompt_progress.emit(clampf(_progress / hold, 0.0, 1.0))
	if _progress >= hold:
		_fire(player)


static func effective_hold(i: Interactable) -> float:
	var v: Variant = SettingsManager.get_value(SETTING_HOLD_TO_PRESS)
	if v is bool and v:
		return 0.0
	return i.hold_time


func clear() -> void:
	target = null
	forced = null
	_reset_hold()
	_announce()


func _fire(player: Node) -> void:
	var t := target
	_reset_hold()
	_armed = false
	interacted.emit(t)
	t.interact(player)
	# The target may have changed what it offers (a hide spot's HIDE becomes LEAVE).
	_last_hold = -1.0


func _reset_hold() -> void:
	if _progress > 0.0:
		prompt_progress.emit(0.0)
	_progress = 0.0
	_tick = 0.0


func _announce() -> void:
	var text := target.prompt_text() if target != null else ""
	var hold := effective_hold(target) if target != null else 0.0
	if text != _last_text or not is_equal_approx(hold, _last_hold):
		_last_text = text
		_last_hold = hold
		prompt_changed.emit(text, hold)


func _ray_target() -> Interactable:
	if camera == null or not camera.is_inside_tree():
		return null
	var space := camera.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * Tuning.INTERACT_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to,
			PlayerLayers.WORLD_MASK | PlayerLayers.INTERACTABLE_MASK)
	q.collide_with_areas = true
	if body != null:
		q.exclude = [body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Object = hit["collider"]
	if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & PlayerLayers.INTERACTABLE_MASK) == 0:
		return null
	return Interactable.find_on(col)
