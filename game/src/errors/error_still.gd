class_name ErrorStill
extends ErrorBase
## Still (08 §4). Rule: it moves only when the player is not observing it. Counter: keep
## it in a lit view and back away; break line of sight and hide; noclip through a wall.
## Tell: the room goes quiet within 8 m (AudioManager, from error_proximity) and a
## matte-black column. Cost: 35 on contact.
##
## Every physics frame, if Player.is_observing(self) (frustum, <= 30 m, unoccluded, lit:
## the Player's observation API owns the lit predicate) the body's velocity is zero and the
## navigation agent pauses. Observed for 2 s continuously: the render-line tick (a 1 px
## white line for 100 ms and the 6 kHz blip), once per 2 s.
## Scene contract: %Body (CharacterBody3D, layer 3) holding %Column (MeshInstance3D with
## the still_column shader) and %Agent (NavigationAgent3D); %Senses.

const TICK_SOUND := &"still_tick"
const CONTACT_SOUND := &"still_contact"
const COLUMN_CENTRE := Tuning.STILL_CAPSULE_HEIGHT * 0.5

@onready var body: CharacterBody3D = %Body
@onready var agent: NavigationAgent3D = %Agent
@onready var column: MeshInstance3D = %Column

## True this physics frame when the player observes the column.
var observed: bool = false
## Continuous seconds observed.
var observed_time: float = 0.0
var unobserved_time: float = 0.0
## Seconds left of the visible render line (0: hidden).
var tick_left: float = 0.0
## Render ticks played (tests and the arena read it).
var ticks: int = 0

var _next_tick_at: float = Tuning.STILL_RENDER_TICK_AFTER
var _wander_ticked: bool = false
var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _repath_acc: float = 0.0
var _skip_cooldown: float = 0.0
var _safe_velocity: Vector3 = Vector3.ZERO
var _safe_frame: int = -100
var _search_arrived: bool = false
var _search_known_time: float = -1.0
## Inspect queue: {pos: Vector3, spot: HideSpot or null}.
var _inspect: Array[Dictionary] = []


func _configure() -> void:
	error_id = &"still"
	senses.sight_range = Tuning.STILL_SIGHT_RANGE
	senses.hearing_mult = Tuning.STILL_HEARING_MULT
	body.collision_layer = 1 << (Tuning.LAYER_ERRORS - 1)
	body.collision_mask = 1 << (Tuning.LAYER_WORLD - 1)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	agent.radius = Tuning.NAV_AGENT_RADIUS
	agent.height = Tuning.NAV_AGENT_HEIGHT
	agent.path_desired_distance = Tuning.ERROR_ARRIVE_DIST
	agent.target_desired_distance = Tuning.ERROR_ARRIVE_DIST
	agent.avoidance_enabled = true
	agent.velocity_computed.connect(_on_safe_velocity)
	_set_line(false)


# --- body ---------------------------------------------------------------------------------

func body_position() -> Vector3:
	return body.global_position if body != null and body.is_inside_tree() else global_position


func body_rids() -> Array[RID]:
	return [body.get_rid()]


## PlayerObservation reads these: the column's centre and (near) its top.
func observe_points() -> Array[Vector3]:
	var p := body_position()
	return [p + Vector3.UP * COLUMN_CENTRE,
		p + Vector3.UP * (Tuning.STILL_CAPSULE_HEIGHT - Tuning.STILL_EYE_POINT_TOP)]


## Places the column (Director spawns, Skip relocation, tests).
func place_at(pos: Vector3) -> void:
	global_position = pos
	if body != null:
		body.position = Vector3.ZERO
		body.velocity = Vector3.ZERO


func _set_body_active(on: bool) -> void:
	if body == null:
		return
	# 08 §2: movers freeze their CharacterBody3D processing when Dormant.
	body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


# --- 08 §8 aggression mapping --------------------------------------------------------------

func speed_mult() -> float:
	return aggr_lerp(Tuning.STILL_SPEED_MULT_LOW, Tuning.STILL_SPEED_MULT_HIGH, aggression)


func reaction_window() -> float:
	return aggr_lerp(Tuning.ERROR_REACTION_WINDOW_LOW, Tuning.ERROR_REACTION_WINDOW_HIGH, aggression)


func hide_check_chance() -> float:
	return aggr_lerp(Tuning.STILL_HIDE_CHECK_CHANCE_LOW, Tuning.STILL_HIDE_CHECK_CHANCE_HIGH, aggression)


## 08 §4 speeds × lerp(0.9, 1.15, aggression); Chase capped at 5.4 m/s.
func speed_for(s: StringName) -> float:
	match s:
		Tuning.ERROR_STATE_CHASE:
			return minf(Tuning.STILL_CHASE_SPEED * speed_mult(), Tuning.STILL_CHASE_SPEED_CAP)
		Tuning.ERROR_STATE_SEARCH, Tuning.ERROR_STATE_SATIATED:
			return Tuning.STILL_SEARCH_SPEED * speed_mult()
		Tuning.ERROR_STATE_WANDER:
			return Tuning.STILL_WANDER_SPEED * speed_mult()
	return 0.0


# --- the rule -------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	observed = player != null and player.is_inside_tree() and player.is_observing(self)
	_render_tick(delta)
	_think(delta)
	if observed:
		# 08 §4: velocity zero, the agent pauses. Not a millimetre.
		body.velocity = Vector3.ZERO
		if agent.avoidance_enabled:
			agent.velocity = Vector3.ZERO
		unobserved_time = 0.0
	else:
		unobserved_time += delta
		_skip_cooldown = maxf(_skip_cooldown - delta, 0.0)
		_move(delta)
	if state != Tuning.ERROR_STATE_SATIATED:
		contact_step(Tuning.STILL_CONTACT_RADIUS, Tuning.STILL_CONTACT_COST)


func _think(delta: float) -> void:
	match state:
		Tuning.ERROR_STATE_WANDER, Tuning.ERROR_STATE_SEARCH:
			if senses.seen_time >= reaction_window():
				_chase("seen %.1f s" % senses.seen_time)
			elif senses.suspicion >= Tuning.ERROR_SUSPICION_CHASE_AT:
				_chase("heard")
		Tuning.ERROR_STATE_CHASE:
			# 08 §4 noclip: line of sight broken for 2 s drops Still to Search at the last
			# place it saw (or heard) the player.
			if senses.unseen_time >= Tuning.STILL_NOCLIP_LOS_BREAK_TIME:
				transition_to(Tuning.ERROR_STATE_SEARCH, "lost sight %.0f s" % senses.unseen_time)
		Tuning.ERROR_STATE_SATIATED:
			_satiated_left -= delta
			if _satiated_left <= 0.0:
				transition_to(Tuning.ERROR_STATE_WANDER, "satiated over")


func _chase(reason: String) -> void:
	transition_to(Tuning.ERROR_STATE_CHASE, reason)


func _enter_state(to: StringName, _from: StringName) -> void:
	_has_target = false
	_repath_acc = INF
	match to:
		Tuning.ERROR_STATE_WANDER:
			_wander_ticked = false
			senses.suspicion = 0.0
		Tuning.ERROR_STATE_CHASE:
			# 08 §2: noticed once per engagement (a re-chase from Search is the same one).
			_notice()
		Tuning.ERROR_STATE_SEARCH:
			senses.suspicion = 0.0
			_search_arrived = false
			_search_known_time = senses.last_known_time
			_inspect.clear()
		Tuning.ERROR_STATE_SATIATED:
			senses.suspicion = 0.0
			_target = _retreat_point()
			_has_target = true
		Tuning.ERROR_STATE_DORMANT:
			body.velocity = Vector3.ZERO


func _on_contact() -> void:
	AudioManager.play_3d(CONTACT_SOUND, body_position() + Vector3.UP * COLUMN_CENTRE)


# --- movement ---------------------------------------------------------------------------------

func _move(delta: float) -> void:
	var speed := speed_for(state)
	match state:
		Tuning.ERROR_STATE_WANDER:
			# 08 §4: Still does not run during the reaction window; it stands.
			if senses.sees_player:
				speed = 0.0
			elif not _has_target or _arrived():
				_target = _wander_point()
				_has_target = true
				_repath_acc = INF
		Tuning.ERROR_STATE_CHASE:
			_target = senses.last_known_pos
			_has_target = true
			_try_skip()
		Tuning.ERROR_STATE_SEARCH:
			_search_step(delta)
		Tuning.ERROR_STATE_SATIATED:
			if _arrived():
				speed = 0.0
	_repath_acc += delta
	if _has_target and _repath_acc >= Tuning.ERROR_NAV_REPATH_INTERVAL:
		_repath_acc = 0.0
		agent.target_position = _target
		_open_doors_near()
	var desired := Vector3.ZERO
	if _has_target and speed > 0.0 and not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var to := next - body.global_position
		to.y = 0.0
		if to.length() > 0.01:
			desired = to.normalized() * speed
	agent.max_speed = maxf(speed, 0.01)
	var v := desired
	if agent.avoidance_enabled:
		agent.velocity = desired
		# The safe velocity arrives after the physics step; use it when it is fresh.
		if Engine.get_physics_frames() - _safe_frame <= 2:
			v = _safe_velocity.limit_length(speed)
	var fall := body.velocity.y
	v.y = 0.0 if body.is_on_floor() else fall - Tuning.PLAYER_GRAVITY * delta
	body.velocity = v
	body.move_and_slide()
	_sync_root()


func _on_safe_velocity(v: Vector3) -> void:
	_safe_velocity = Vector3(v.x, 0.0, v.z)
	_safe_frame = Engine.get_physics_frames()


## The root follows the body, so global_position is where Still stands (Player.contact
## pushes away from it; the Director measures it).
func _sync_root() -> void:
	var p := body.global_position
	global_position = p
	body.position = Vector3.ZERO


func _arrived() -> bool:
	var a := body_position()
	return Vector2(a.x - _target.x, a.z - _target.z).length() <= Tuning.ERROR_ARRIVE_DIST \
			or (agent.is_navigation_finished() and _repath_acc < INF and _repath_acc > 0.0)


func _nav_map() -> RID:
	return agent.get_navigation_map()


func _snap(p: Vector3) -> Vector3:
	var map := _nav_map()
	if not map.is_valid():
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


## A hint (Director) or a seeded random navmesh point within 14 m.
func _wander_point() -> Vector3:
	if _has_hint:
		_has_hint = false
		return _snap(_hint)
	return _random_point_near(body_position(), Tuning.STILL_WANDER_RADIUS)


func _random_point_near(centre: Vector3, radius: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	return _snap(centre + Vector3(cos(a) * r, 0.0, sin(a) * r))


## 08 §2: retreat to a hinted point >= 20 m away; without one, the farthest of a few
## seeded candidates 20 to 30 m from the player.
func _retreat_point() -> Vector3:
	var from := player.global_position if player != null else body_position()
	if _has_hint and _hint.distance_to(from) >= Tuning.ERROR_SATIATED_RETREAT_DIST:
		_has_hint = false
		return _snap(_hint)
	var best := body_position()
	var best_d := -1.0
	for i in Tuning.ERROR_RETREAT_SAMPLES:
		var a := rng.randf() * TAU
		var r := Tuning.ERROR_SATIATED_RETREAT_DIST * (1.0 + rng.randf() * 0.5)
		var p := _snap(from + Vector3(cos(a) * r, 0.0, sin(a) * r))
		var d := p.distance_to(from)
		if d > best_d:
			best_d = d
			best = p
	return best


## 08 §2 Memory: go to last_known_pos, then inspect hide spots within 6 m (each with the
## aggression-scaled chance) and up to 3 nearby points, for 10 s, then give up (evasion).
func _search_step(_delta: float) -> void:
	if senses.last_known_time != _search_known_time:
		# A newer noise: go there instead.
		_search_known_time = senses.last_known_time
		_search_arrived = false
		_inspect.clear()
	if not _search_arrived:
		_target = senses.last_known_pos
		_has_target = true
		if _arrived() or state_time > Tuning.ERROR_SEARCH_TIME * 2.0:
			_search_arrived = true
			state_time = 0.0
			_plan_inspection()
			_next_inspect()
		return
	if state_time >= Tuning.ERROR_SEARCH_TIME:
		_give_up()
		return
	if _arrived():
		var cur: Dictionary = _inspect.pop_front() if not _inspect.is_empty() else {}
		var spot: Variant = cur.get("spot")
		if spot != null and is_instance_valid(spot) and player != null and (spot as HideSpot).occupant == player:
			# 08 §4: checking the player's spot is a contact.
			if try_contact(Tuning.STILL_CONTACT_COST):
				return
		if _inspect.is_empty():
			_give_up()
			return
		_next_inspect()


func _plan_inspection() -> void:
	_inspect.clear()
	var at := senses.last_known_pos
	for n in get_tree().get_nodes_in_group(&"hide_spots"):
		var spot := n as HideSpot
		if spot == null or spot.global_position.distance_to(at) > Tuning.STILL_HIDE_SEARCH_RADIUS:
			continue
		if rng.randf() < hide_check_chance():
			_inspect.append({"pos": _snap(spot.exit_point.global_position), "spot": spot})
	for i in Tuning.ERROR_SEARCH_INSPECT_CELLS:
		var p := _random_point_near(at, Tuning.ERROR_SEARCH_INSPECT_RADIUS)
		if _has_hint and i == 0:
			_has_hint = false
			p = _snap(_hint)
		_inspect.append({"pos": p, "spot": null})


func _next_inspect() -> void:
	if _inspect.is_empty():
		return
	_target = _inspect[0]["pos"]
	_has_target = true
	_repath_acc = INF


func _give_up() -> void:
	transition_to(Tuning.ERROR_STATE_WANDER, "search over")
	_evade()


## 08 §4 Skip: in Chase, unobserved > 4 s and > 12 m away, once per 8 s, relocate to the
## navmesh point 6 m closer along the path, never into the player's frustum.
func _try_skip() -> void:
	if _skip_cooldown > 0.0 or unobserved_time <= Tuning.STILL_SKIP_UNOBSERVED_TIME:
		return
	if distance_to_player() <= Tuning.STILL_SKIP_MIN_DIST:
		return
	var path := agent.get_current_navigation_path()
	if path.size() < 2:
		return
	var left := Tuning.STILL_SKIP_STEP
	var at := body_position()
	var dest := at
	for i in range(agent.get_current_navigation_path_index(), path.size()):
		var seg := path[i] - at
		if seg.length() >= left:
			dest = at + seg.normalized() * left
			left = 0.0
			break
		left -= seg.length()
		at = path[i]
		dest = at
	dest = _snap(dest)
	if _in_player_frustum(dest):
		return
	_skip_cooldown = Tuning.STILL_SKIP_INTERVAL
	place_at(dest)
	_repath_acc = INF


func _in_player_frustum(p: Vector3) -> bool:
	if player == null or player.rig == null:
		return false
	var cam := player.rig.camera
	return cam.is_position_in_frustum(p + Vector3.UP * COLUMN_CENTRE) \
			or cam.is_position_in_frustum(p + Vector3.UP * Tuning.STILL_CAPSULE_HEIGHT)


## 08 §2: doors on the path are opened; Chase opens them with a slam.
func _open_doors_near() -> void:
	var p := body_position()
	for n in get_tree().get_nodes_in_group(&"doors"):
		var door := n as Door
		if door == null or door.is_open:
			continue
		var d := door.global_position
		if Vector2(d.x - p.x, d.z - p.z).length() <= Tuning.ERROR_DOOR_OPEN_DIST:
			door.open(state == Tuning.ERROR_STATE_CHASE)


# --- render tick (02 §8, 08 §4) -------------------------------------------------------------

func _render_tick(delta: float) -> void:
	if tick_left > 0.0:
		tick_left -= delta
		if tick_left <= 0.0:
			_set_line(false)
	if not observed:
		observed_time = 0.0
		_next_tick_at = Tuning.STILL_RENDER_TICK_AFTER
		return
	var first := is_zero_approx(observed_time)
	observed_time += delta
	if first and state == Tuning.ERROR_STATE_WANDER and not _wander_ticked:
		# 08 §4: the tick plays once when the player first observes it in Wander.
		_wander_ticked = true
		_play_tick()
	elif observed_time >= _next_tick_at:
		_next_tick_at += Tuning.STILL_RENDER_TICK_INTERVAL
		_play_tick()


func _play_tick() -> void:
	ticks += 1
	tick_left = Tuning.STILL_RENDER_TICK_DURATION_MS / 1000.0
	_set_line(true, rng.randf_range(0.08, 0.92))
	AudioManager.play_3d(TICK_SOUND, body_position() + Vector3.UP * COLUMN_CENTRE)


## The 1 px line across the column at `height01` of its height (instance uniforms).
func _set_line(on: bool, height01: float = 0.5) -> void:
	if column == null:
		return
	column.set_instance_shader_parameter(&"line_on", 1.0 if on else 0.0)
	if on:
		column.set_instance_shader_parameter(&"line_height", height01)
