class_name PlayerHiding
extends RefCounted
## Hiding for the Player (06 §10, 09 §6, 11 §2). Inside: the eye slides 0.6 s to the
## spot's view point, the body leaves the physics world (no collision), movement stops,
## look is limited to the spot's yaw, and `hidden_changed` / EventBus.hide_state announce
## it, and the breath loop plays. Leaving is the spot's 0.6 s hold; the spot's sound and
## cloth play and the eye slides back to the exit point.
## Hiding is silent to errors (no noise event) and does not stop Static or Null drain.

## The spot occupied (also while sliding out).
var spot: HideSpot = null
var leaving: bool = false

const CLOTH := &"crouch"                  # the cloth rustle (03)
## The hidden breath: the breath loop sample under the hide-breath key (03 has one breath).
const BREATH := &"sprint_breath_loop"

var _p: Player
var _saved_layers := Vector2i.ZERO


func _init(player: Player) -> void:
	_p = player


func is_hidden() -> bool:
	return spot != null and not leaving


func enter(s: HideSpot) -> void:
	if spot != null or not _p.state_machine.transition_to(PlayerStateMachine.HIDDEN):
		return
	spot = s
	_p.velocity = Vector3.ZERO
	_saved_layers = Vector2i(_p.collision_layer, _p.collision_mask)
	_p.collision_layer = 0
	_p.collision_mask = 0
	# 11 §2 enter hide spot: camera slides 0.6 s; view mask (spot); cloth + the spot's sound;
	# HUD dims with the eye glyph (hidden_changed).
	_p.rig.anchor_to(s.view_transform(), Tuning.HIDE_CAMERA_SLIDE_TIME)
	_p.global_position = s.global_position
	_p.interactor.forced = s.interactable
	s.set_occupant(_p)
	_p.sounds.play(CLOTH)
	_p.sounds.play_at(s.sound_id(), s.global_position, &"World")
	# 06 §10, 09 §6: breathing is audible inside (Player bus; never a noise event).
	_p.sounds.start_loop(PlayerAudio.LOOP_HIDE_BREATH, BREATH, Tuning.HIDE_CAMERA_SLIDE_TIME)
	_p.hidden_changed.emit(true)
	EventBus.hide_state.emit(true)


## 11 §2 leave hide spot: view mask lifts, the spot's sound then cloth (the entry in
## reverse order), camera slides out 0.6 s, HUD restores (hidden_changed).
func leave() -> void:
	if spot != null and not leaving:
		_p.sounds.play_at(spot.sound_id(), spot.global_position, &"World")
		_p.sounds.play(CLOTH)
		_end(Tuning.HIDE_CAMERA_SLIDE_TIME)


## Out at once (a contact found the hider).
func eject() -> void:
	if spot != null:
		_end(0.0)


func _end(seconds: float) -> void:
	var s := spot
	leaving = true
	_p.sounds.stop_loop(PlayerAudio.LOOP_HIDE_BREATH, Tuning.FEEDBACK_SPRINT_BREATH_OUT)
	var ex := s.exit_transform()
	_p.global_position = ex.origin
	_p.rotation = Vector3(0.0, ex.basis.get_euler().y, 0.0)
	_p.collision_layer = _saved_layers.x
	_p.collision_mask = _saved_layers.y
	_p.hidden_changed.emit(false)
	EventBus.hide_state.emit(false)
	var h := _p.locomotion.eye_height()
	var eye := Transform3D(_p.global_transform.basis, _p.global_position + Vector3.UP * h)
	if seconds <= 0.0:
		_p.rig.release_to(eye, h, 0.001)
		_finish(s)
	else:
		_p.rig.release_to(eye, h, seconds).finished.connect(_finish.bind(s))


func _finish(s: HideSpot) -> void:
	if spot != s:
		return
	spot = null
	leaving = false
	_p.interactor.forced = null
	s.set_occupant(null)
	var sm := _p.state_machine
	if sm.is_in(PlayerStateMachine.HIDDEN):
		sm.transition_to(PlayerStateMachine.CROUCH if _p.locomotion.crouched else PlayerStateMachine.IDLE)
