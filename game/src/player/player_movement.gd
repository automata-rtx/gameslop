class_name PlayerMovement
extends RefCounted
## Movement rules of 06 §3 as pure functions, plus the step-up helper the body uses.
## Feel rules (law): digital input, no acceleration curves on input, strafe equals
## forward, diagonal normalised, grounded and immediate.

## Metres of air left under the body after a step-up; floor snap settles it.
const STEP_CLEARANCE := 0.01


## Top speed for a gait. `capped` = cranking, charging noclip, or stunned (crouch speed).
static func max_speed(gait: StringName, capped: bool, wading: bool) -> float:
	var s: float
	match gait:
		NoiseModel.GAIT_SPRINT:
			s = Tuning.PLAYER_SPRINT_SPEED
		NoiseModel.GAIT_CROUCH:
			s = Tuning.PLAYER_CROUCH_SPEED
		_:
			s = Tuning.PLAYER_WALK_SPEED
	if capped:
		s = minf(s, Tuning.PLAYER_CROUCH_SPEED)
	if wading:
		s *= Tuning.PLAYER_WADE_SPEED_MULT
	return s


## Wish direction in world space from the input vector (x right, y forward) and body yaw basis.
static func wish_dir(move: Vector2, basis: Basis) -> Vector3:
	var forward := -basis.z
	forward.y = 0.0
	var right := basis.x
	right.y = 0.0
	var d := forward.normalized() * move.y + right.normalized() * move.x
	return d if d.length() <= 1.0 else d.normalized()


## Horizontal velocity after one step: 12 m/s^2 toward the target while there is input,
## 16 m/s^2 toward rest when there is none (snappy, no slide).
static func approach(current: Vector3, wish: Vector3, speed: float, dt: float) -> Vector3:
	var flat := Vector3(current.x, 0.0, current.z)
	var target := wish * speed
	var rate := Tuning.PLAYER_ACCEL if wish.length_squared() > 0.0 else Tuning.PLAYER_DECEL
	# Above the cap (sprint released, crank started) slow down at the deceleration rate.
	if flat.length() > speed + 0.001:
		rate = maxf(rate, Tuning.PLAYER_DECEL)
	return flat.move_toward(target, rate * dt)


## 06 §3 step height 0.3 m: when the body is blocked horizontally, look for a walkable
## surface no higher than the step height one capsule radius ahead (so the probe lands
## past the step's edge, not on its rounded corner) and lift the body onto it, then make
## the blocked motion. Returns the lift (0 when no step was taken).
static func try_step_up(body: CharacterBody3D, horizontal: Vector3) -> float:
	if horizontal.length_squared() < 0.0001 or not body.is_on_floor():
		return 0.0
	var start := body.global_transform
	var up := Vector3.UP * Tuning.PLAYER_STEP_HEIGHT
	if body.test_move(start, up):
		return 0.0
	var raised := start.translated(up)
	var probe := horizontal.normalized() * maxf(horizontal.length(), Tuning.PLAYER_CAPSULE_RADIUS)
	if body.test_move(raised, probe):
		return 0.0
	var col := KinematicCollision3D.new()
	if not body.test_move(raised.translated(probe), -up, col):
		return 0.0  # nothing to stand on: not a step
	if col.get_normal().angle_to(Vector3.UP) > deg_to_rad(Tuning.PLAYER_FLOOR_MAX_ANGLE):
		return 0.0
	var lift := up.y - col.get_travel().length() + STEP_CLEARANCE
	if lift <= STEP_CLEARANCE * 2.0:
		return 0.0
	var lifted := start.translated(Vector3.UP * lift)
	if body.test_move(lifted, horizontal):
		return 0.0
	body.global_transform = lifted.translated(horizontal)
	return lift
