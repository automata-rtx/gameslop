class_name PlayerLocomotion
extends RefCounted
## Walking, sprinting, crouching, steps and stamina for the Player (06 §3, §4, §6) with
## their Feedback Contract rows (11 §2). A helper the Player owns and drives every physics
## frame; split out of player.gd to keep each script focused (14 §6).

signal sprint_changed(on: bool)
signal stamina_exhausted

const MOVING_EPSILON := 0.2  # m/s below which the player counts as still (bob 0)
## Seconds over which the 1.5 m contact push is applied (fast, but it respects walls).
const PUSH_TIME := 0.15
## Steps the trail keeps (08 §6 Echo): about 5 s of sprinting, 13 s of walking.
const STEP_TRAIL_CAPACITY := 64
const BOB_CUT_SCALE := 1.0 - Tuning.FEEDBACK_STAMINA_EMPTY_BOB_CUT
## Crouch-up probe margins: a slimmer, shorter standing capsule lifted off the floor.
const STAND_PROBE_RADIUS_INSET := 0.02
const STAND_PROBE_HEIGHT_INSET := 0.1
const STAND_PROBE_LIFT := 0.05

var stamina := Stamina.new()
var noise := NoiseModel.new()
var crouched: bool = false
var sprinting: bool = false

var _p: Player
var _shape_stand: CapsuleShape3D
var _shape_crouch: CapsuleShape3D
var _step_odd: bool = false
var _bob_cut_left: float = 0.0
var _push_dir: Vector3 = Vector3.ZERO
## Push distance still to travel (m). The push is its own displacement, moved and slid
## separately from the walking velocity, so it never feeds back into the velocity.
var _push_left: float = 0.0
## Every step event, oldest first (08 Interfaces: Player.step_trail()).
var trail := RingBuffer.new(STEP_TRAIL_CAPACITY)
## Set when physics_update ran this frame; end_frame() ticks stamina otherwise.
var _moved_this_frame: bool = false


func _init(player: Player) -> void:
	_p = player
	_shape_stand = _capsule(Tuning.PLAYER_CAPSULE_HEIGHT)
	_shape_crouch = _capsule(Tuning.PLAYER_CAPSULE_HEIGHT_CROUCH)
	stamina.exhausted.connect(_on_stamina_exhausted)


func setup() -> void:
	_set_shape(false)
	_p.rig.set_eye_height(Tuning.PLAYER_CAMERA_HEIGHT, false)


func reset() -> void:
	halt()
	stamina.reset()
	_bob_cut_left = 0.0
	trail.clear()
	noise.reset_stride()
	if crouched:
		_set_crouched(false)


## Every loss of agency (hide, Landing, drop, noclip pass, dissolve, stun): stop dead and
## end the sprint properly (sprint_changed, the sprint FOV hold released, the breath
## loop fading out). A toggled sprint does not resume by itself afterwards.
func halt() -> void:
	_p.velocity = Vector3.ZERO
	_push_left = 0.0
	_p.input.clear_sprint_latch()
	_set_sprinting(false)


func tick_timers(dt: float) -> void:
	_bob_cut_left = maxf(0.0, _bob_cut_left - dt)
	if _p.is_stunned():
		_p.rig.set_bob_scale(0.0)  # 11 §3: stun with bob off
	elif _bob_cut_left > 0.0:
		_p.rig.set_bob_scale(BOB_CUT_SCALE)
	else:
		_p.rig.set_bob_scale(1.0)


## 06 §9: pushed 1.5 m away from the error (over PUSH_TIME; walls stop it).
func push(dir: Vector3) -> void:
	dir.y = 0.0
	_push_dir = dir.normalized() if dir.length_squared() > 0.0001 else _p.global_transform.basis.z
	_push_left = Tuning.CONTACT_PUSH_DIST


func is_pushing() -> bool:
	return _push_left > 0.0


func current_gait() -> StringName:
	if crouched:
		return NoiseModel.GAIT_CROUCH
	if _p.input.sprint and _p.input.move != Vector2.ZERO and can_sprint():
		return NoiseModel.GAIT_SPRINT
	return NoiseModel.GAIT_WALK


func can_sprint() -> bool:
	return stamina.can_sprint() and not _p.is_speed_capped() and not crouched


## One physics frame of locomotion.
func physics_update(delta: float) -> void:
	_moved_this_frame = true
	_update_crouch()
	var before := _p.global_position
	_move(delta)
	_apply_push(delta)
	var moved := Vector3(_p.global_position.x - before.x, 0.0, _p.global_position.z - before.z).length()
	_after_move(moved, delta)


## Called by the Player at the end of every physics frame: stamina ticks every frame,
## so regeneration continues while hidden, passing, landing or dissolving (06 §4).
func end_frame(delta: float) -> void:
	if not _moved_this_frame:
		stamina.tick(delta, false, _p.is_wading())
		if sprinting:
			_set_sprinting(false)
	_moved_this_frame = false


func _move(delta: float) -> void:
	var gait := current_gait()
	var speed := PlayerMovement.max_speed(gait, _p.is_speed_capped(), _p.is_wading())
	var wish := PlayerMovement.wish_dir(_p.input.move, _p.global_transform.basis)
	var h := PlayerMovement.approach(_p.velocity, wish, speed, delta)
	_p.velocity.x = h.x
	_p.velocity.z = h.z
	if _p.is_on_floor():
		_p.velocity.y = 0.0
	else:
		_p.velocity.y -= Tuning.PLAYER_GRAVITY * delta
	var intended := Vector3(_p.velocity.x, 0.0, _p.velocity.z) * delta
	_p.move_and_slide()
	if _p.is_on_wall():
		var lift := PlayerMovement.try_step_up(_p, intended)
		if lift > 0.0:
			_p.rig.absorb_step(lift)


## The contact push as a displacement of its own: moved and slid along walls, its
## distance counted whether or not a wall ate it, and never added to the velocity, so
## a slide can never turn it into a velocity back into the wall.
func _apply_push(delta: float) -> void:
	if _push_left <= 0.0:
		return
	var step := minf(_push_left, Tuning.CONTACT_PUSH_DIST / PUSH_TIME * delta)
	_push_left -= step
	var motion := _push_dir * step
	for i in 3:
		var col := _p.move_and_collide(motion)
		if col == null:
			break
		var n := col.get_normal()
		n.y = 0.0
		motion = col.get_remainder()
		if n.length_squared() > 0.0001:
			motion = motion.slide(n.normalized())  # a wall: slide along it
		motion.y = 0.0  # a floor touch: carry on level
		if motion.length_squared() < 0.000001:
			break


func _after_move(moved: float, delta: float) -> void:
	var gait := current_gait()
	var flat_speed := Vector3(_p.velocity.x, 0.0, _p.velocity.z).length()
	var moving := flat_speed > MOVING_EPSILON
	var now_sprinting := gait == NoiseModel.GAIT_SPRINT and moving
	stamina.tick(delta, now_sprinting, _p.is_wading())
	_set_sprinting(now_sprinting and stamina.can_sprint())
	var sm := _p.state_machine
	if PlayerStateMachine.is_locomotion(sm.state):
		var s := PlayerStateMachine.IDLE
		if crouched:
			s = PlayerStateMachine.CROUCH
		elif moving:
			s = PlayerStateMachine.SPRINT if sprinting else PlayerStateMachine.WALK
		if s != sm.state:
			sm.transition_to(s)
	if noise.advance(moved, gait):
		_step_odd = not _step_odd
		_step(gait)
	var amp := 0.0
	if moving:
		amp = Tuning.CAMERA_BOB_SPRINT_MULT if sprinting else 1.0
	var lateral := _p.global_transform.basis.x.dot(_p.velocity) / Tuning.PLAYER_WALK_SPEED
	_p.rig.feed_motion(noise.stride_phase(gait), _step_odd, amp, clampf(lateral, -1.0, 1.0))


## One step (06 §6, 11 §2 walk step): the noise event (AudioManager plays the surface
## sample from it), the trail entry Echo reads (08 §6), and the bob (fed by _after_move).
func _step(gait: StringName) -> void:
	var pos := _p.global_position
	var surface := step_surface()
	# AudioManager plays foot_<surface> from the step noise itself (03 Interfaces).
	AudioManager.set_step_surface(surface)
	NoiseModel.emit(pos, step_radius(gait), Tuning.NOISE_KIND_STEP)
	trail.push({
		&"position": pos,
		&"time": Time.get_ticks_usec() / 1_000_000.0,
		&"surface": surface,
		&"speed_kind": gait,
	})
	# TODO(M2): 11 §2 walk step image channel, dust stir near the feet in Halls, Garage and
	# Offices: a one-shot GPUParticles3D at `pos` chosen by `surface` (godot-particles).


func _set_sprinting(on: bool) -> void:
	if on == sprinting:
		return
	sprinting = on
	# 11 §2 sprint start/stop: FOV +4 over 200 ms / back over 300 ms; bob x1.6 (fed by
	# _after_move); breath loop fades in over 2 s / out over 1 s (03).
	if on:
		_p.rig.fov_hold(Tuning.FEEDBACK_SPRINT_FOV_DEG, Tuning.FEEDBACK_SPRINT_FOV_UP_MS, CameraRig.HOLD_SPRINT)
		_p.sounds.start_loop(PlayerAudio.LOOP_SPRINT_BREATH, &"sprint_breath_loop", Tuning.FEEDBACK_SPRINT_BREATH_IN)
	else:
		var back_ms: float = float(Tuning.FEEDBACK_SPRINT_FOV_DOWN_MS) if stamina.can_sprint() else 0.0
		_p.rig.fov_hold(0.0, back_ms, CameraRig.HOLD_SPRINT)
		_p.sounds.stop_loop(PlayerAudio.LOOP_SPRINT_BREATH, Tuning.FEEDBACK_SPRINT_BREATH_OUT)
	sprint_changed.emit(on)


func _on_stamina_exhausted() -> void:
	# 11 §2 stamina empty: gasp; FOV snaps back; bob -20% for 2 s; the HUD arc turns danger.
	_p.input.clear_sprint_latch()
	_p.rig.fov_hold(0.0, 0.0, CameraRig.HOLD_SPRINT)
	_bob_cut_left = Tuning.FEEDBACK_STAMINA_EMPTY_BOB_TIME
	_p.sounds.play(&"stamina_empty_gasp")
	stamina_exhausted.emit()


# --- surfaces (06 §6) ------------------------------------------------------------------

## 06 §6 step radius for the current floor, water and gait.
func step_radius(gait: StringName) -> float:
	return NoiseModel.step_radius(floor_surface(), gait, _p.water_depth > 0.0, _p.is_wading())


## The surface a step sounds on: water when standing in it, else the floor's.
func step_surface() -> StringName:
	return NoiseModel.SURFACE_WATER if _p.water_depth > 0.0 else floor_surface()


func floor_surface() -> StringName:
	for i in _p.get_slide_collision_count():
		var c := _p.get_slide_collision(i)
		if c.get_normal().y > 0.7 and c.get_collider() != null:
			var col := c.get_collider()
			if col.has_meta(&"surface"):
				return StringName(col.get_meta(&"surface"))
	return _p.default_surface


# --- crouch (06 §3) --------------------------------------------------------------------

func _update_crouch() -> void:
	if _p.input.crouch and not crouched:
		_set_crouched(true)
	elif not _p.input.crouch and crouched and can_stand():
		_set_crouched(false)


func _set_crouched(on: bool) -> void:
	crouched = on
	_set_shape(on)
	# 11 §2 crouch/stand: cloth rustle; camera height 120 ms with a 0.05 m dip.
	_p.rig.set_eye_height(Tuning.PLAYER_CAMERA_HEIGHT_CROUCH if on else Tuning.PLAYER_CAMERA_HEIGHT)
	_p.sounds.play(&"crouch")


## 06 §3: standing is blocked under a low ceiling (a shape query of the standing capsule).
func can_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = Tuning.PLAYER_CAPSULE_RADIUS - STAND_PROBE_RADIUS_INSET
	probe.height = Tuning.PLAYER_CAPSULE_HEIGHT - STAND_PROBE_HEIGHT_INSET
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY,
			_p.global_position + Vector3.UP * (probe.height * 0.5 + STAND_PROBE_LIFT))
	q.collision_mask = PlayerLayers.WORLD_MASK
	q.exclude = [_p.get_rid()]
	return _p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func eye_height() -> float:
	return Tuning.PLAYER_CAMERA_HEIGHT_CROUCH if crouched else Tuning.PLAYER_CAMERA_HEIGHT


func _capsule(h: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = Tuning.PLAYER_CAPSULE_RADIUS
	c.height = h
	return c


func _set_shape(crouch: bool) -> void:
	var s := _shape_crouch if crouch else _shape_stand
	_p.collision.shape = s
	_p.collision.position = Vector3(0.0, s.height * 0.5, 0.0)
