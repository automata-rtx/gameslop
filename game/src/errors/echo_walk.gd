class_name EchoWalk
extends RefCounted
## Echo's movement (08 §2, §6), split out of ErrorEcho (14 §6 400-line limit): where it walks
## in each state and how fast, the navigation agent and the body, and its own steps. Static
## helpers over one ErrorEcho; the rule's decisions (hearing, states) stay in ErrorEcho.

## One physics frame: the state's destination and speed, the agent, the body.
static func move(e: ErrorEcho, delta: float) -> void:
	var speed := e.current_speed()
	match e.state:
		Tuning.ERROR_STATE_WANDER:
			if not e._has_target or arrived(e):
				e._target = wander_point(e)
				e._has_target = true
				e._repath_acc = INF
		Tuning.ERROR_STATE_FOLLOW:
			speed = follow_step(e, speed)
		Tuning.ERROR_STATE_SEARCH:
			search_step(e)
			if not e._has_target:
				speed = 0.0
		Tuning.ERROR_STATE_SATIATED:
			if not e._has_target or arrived(e):
				if not e._walk_back.is_empty():
					e._target = e._walk_back.pop_front()
					e._has_target = true
					e._repath_acc = INF
				elif e._has_hint:
					e._has_hint = false
					e._target = EchoNav.snap(e, e._hint)
					e._has_target = true
					e._repath_acc = INF
				else:
					speed = 0.0
	e._repath_acc += delta
	if e._has_target and e._repath_acc >= Tuning.ERROR_NAV_REPATH_INTERVAL:
		e._repath_acc = 0.0
		e.agent.target_position = e._target
		EchoNav.open_doors_near(e, e._doors)
	var desired := Vector3.ZERO
	if e._has_target and speed > 0.0 and not arrived(e):
		var next := e.agent.get_next_path_position()
		var to := next - e.body.global_position
		to.y = 0.0
		if to.length() > 0.01:
			desired = to.normalized() * speed
	e.agent.max_speed = maxf(speed, 0.01)
	var v := desired
	if e.agent.avoidance_enabled:
		e.agent.velocity = desired
		if Engine.get_physics_frames() - e._safe_frame <= 2 and desired != Vector3.ZERO:
			v = e._safe_velocity.limit_length(speed)
	var fall := e.body.velocity.y
	v.y = 0.0 if e.body.is_on_floor() else fall - Tuning.PLAYER_GRAVITY * delta
	var before := e.body.global_position
	e.body.velocity = v
	e.body.move_and_slide()
	sync_root(e)
	stride_step(e, EchoNav.flat(before, e.body.global_position))


## Follow: the lure, else the trail goal (the target entry or the farthest straight cut to
## it). At the target it stands: speed 0.
static func follow_step(e: ErrorEcho, speed: float) -> float:
	if e.lure != Vector3.INF:
		if not e._has_target:
			e._target = EchoNav.stand_off(e, e.lure)
			e._has_target = true
			e._repath_acc = INF
		return 0.0 if arrived(e) else speed
	var target := e.trail.target_index()
	if target < 0:
		return 0.0
	# Reached the goal entry: advance past it.
	if e._goal_index >= 0 and e._goal_index < e.trail.size() \
			and EchoNav.flat(e.body_position(), e.trail.entries[e._goal_index][&"position"]) <= Tuning.ECHO_ENTRY_ARRIVE_DIST:
		e.trail.advance_to(e._goal_index)
		e._goal_index = -1
	if e.trail.at_target():
		e._has_target = false
		return 0.0
	if e._goal_index < 0 or e._repath_acc >= Tuning.ERROR_NAV_REPATH_INTERVAL:
		var g := EchoNav.trail_goal(e, e.trail, target)
		if g != e._goal_index:
			e._goal_index = g
			e._target = e.trail.entries[g][&"position"]
			e._has_target = true
			e._repath_acc = INF
	return e.current_speed() if e._goal_index >= 0 else 0.0


## 08 §2 Memory with 08 §6's rule: go toward the heard point but stand off it (never the
## point itself nor its cell), then inspect up to 3 points for 10 s, then give up (Wander;
## an evasion when this Search ended a Follow).
static func search_step(e: ErrorEcho) -> void:
	if not e._search_arrived:
		if not e._has_target:
			e._target = EchoNav.stand_off(e, e._search_point)
			e._has_target = true
			e._repath_acc = INF
		if arrived(e) or e.state_time > Tuning.ECHO_SEARCH_TIME * 2.0:
			e._search_arrived = true
			e.state_time = 0.0
			e._inspect = EchoNav.plan_inspection(e, e._search_point)
			next_inspect(e)
		return
	if e.state_time >= Tuning.ECHO_SEARCH_TIME:
		e._give_up()
		return
	if e._has_target and arrived(e):
		if not e._inspect.is_empty():
			e._inspect.pop_front()
		next_inspect(e)


static func next_inspect(e: ErrorEcho) -> void:
	if e._inspect.is_empty():
		e._has_target = false
		return
	e._target = e._inspect[0]
	e._has_target = true
	e._repath_acc = INF


## A hint (Director) or a seeded random navmesh point within 14 m.
static func wander_point(e: ErrorEcho) -> Vector3:
	if e._has_hint:
		e._has_hint = false
		return EchoNav.snap(e, e._hint)
	return EchoNav.random_point_near(e, e.body_position(), Tuning.ECHO_WANDER_RADIUS)


static func arrived(e: ErrorEcho) -> bool:
	var a := e.body_position()
	var reach := Tuning.ECHO_ENTRY_ARRIVE_DIST if e.state == Tuning.ERROR_STATE_FOLLOW and e.lure == Vector3.INF \
			else Tuning.ERROR_ARRIVE_DIST
	return Vector2(a.x - e._target.x, a.z - e._target.z).length() <= reach \
			or (e.agent.is_navigation_finished() and e._repath_acc < INF and e._repath_acc > 0.0)


## The root follows the body, so global_position is where Echo stands.
static func sync_root(e: ErrorEcho) -> void:
	var p := e.body.global_position
	e.global_position = p
	e.body.position = Vector3.ZERO


## Echo's own steps (03, 08 §6): one per step distance of the gait it walks, playing the
## player's recorded surface sample at its position. Recorded for the Satiated walk-back.
static func stride_step(e: ErrorEcho, moved: float) -> void:
	if moved <= 0.0:
		return
	var kind := NoiseModel.GAIT_WALK
	if e.state == Tuning.ERROR_STATE_FOLLOW and e._goal_index >= 0 and e._goal_index < e.trail.size():
		kind = e.trail.entries[e._goal_index][&"speed_kind"]
		e._surface = e.trail.entries[e._goal_index][&"surface"]
	elif not e.trail.is_empty():
		e._surface = e.trail.newest()[&"surface"]
	e._stride += moved
	if e._stride < NoiseModel.step_distance(kind):
		return
	e._stride = 0.0
	if e.state != Tuning.ERROR_STATE_SATIATED:
		e._own_steps.append(e.body_position())
		if e._own_steps.size() > Tuning.ECHO_OWN_TRAIL_CAPACITY:
			e._own_steps.pop_front()
	var surface := e._surface if e._surface != &"" else AudioManager.step_surface()
	EchoPresent.play_step(e, surface)
