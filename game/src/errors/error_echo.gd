class_name ErrorEcho
extends ErrorBase
## Echo (08 §6). Rule: it follows the trail of the player's footsteps, at the player's
## speed, 800 ms late. Counter: stop; crouch-walk; throw a noise elsewhere. Tell: the
## player's own footsteps behind them, late, and the shimmer at 4 m (EchoPresent). Cost:
## 25 on contact.
##
## Hearing only (blind). Only steps Echo heard enter its trail (EchoTrail). Wander: a heard
## step -> Search toward it; three heard steps within 5 s -> Follow (its Chase), the trail
## starting at the earliest of them. Follow targets the entry 800 ms before the newest heard
## one at that entry's speed kind (wading x0.6), trimming trail points it can reach in a
## straight line; when the player stops it reaches the target and freezes. No heard step for
## the trail-loss timeout (6 s to 4 s by aggression; a `tear` keeps it) -> Search at the last
## heard point, never the point itself nor its cell; 10 s, then Wander (an evasion). Lures:
## an impact, radio or mech noise nearer than the current trail point redirects it until a
## newer step is heard. Contact within 1.0 m through the gates; Satiated walks back along
## its own steps. Contact comes only from Follow; a Relief hint ends a Follow (R12).
## Scene contract: %Body (CharacterBody3D, layer 3) holding %Shimmer
## (MeshInstance3D, echo_shimmer shader) and %Agent (NavigationAgent3D); %Senses.

## Lure kinds (08 §6): a thrown glowstick or flare lands as `impact`; the radio is `radio`
## (08) and emits `mech` (09), so both count.
const LURE_KINDS: Array[StringName] = [Tuning.NOISE_KIND_IMPACT, &"radio", Tuning.NOISE_KIND_MECH]

@onready var body: CharacterBody3D = %Body
@onready var agent: NavigationAgent3D = %Agent
@onready var shimmer: MeshInstance3D = %Shimmer

## The heard steps (08 §6), on Echo's clock.
var trail := EchoTrail.new()
## Echo's clock: seconds awake (heard entries are stamped with it).
var clock: float = 0.0
## Seconds since the last heard step (or tear) in Follow.
var loss_time: float = 0.0
## Where the last heard noise was (the trail end, a lure, a loud noise).
var last_heard: Vector3 = Vector3.ZERO
## A lure (08 §6) Echo is walking to in Follow; INF when none.
var lure: Vector3 = Vector3.INF
## Shimmer presence 0..1 (EchoPresent); counters for tests and the bench.
var presence: float = 0.0
var steps_played: int = 0
var breaths: int = 0

var _breath_acc: float = 0.0
var _stride: float = 0.0
var _surface: StringName = &""
var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _repath_acc: float = 0.0
var _safe_velocity: Vector3 = Vector3.ZERO
var _safe_frame: int = -100
var _goal_index: int = -1
var _search_point: Vector3 = Vector3.ZERO
var _search_arrived: bool = false
var _inspect: Array[Vector3] = []
## Echo's own step positions (the Satiated walk-back) and the walk-back queue.
var _own_steps: Array[Vector3] = []
var _walk_back: Array[Vector3] = []
var _doors: Array[Door] = []
var _doors_bound: bool = false


func _configure() -> void:
	error_id = &"echo"
	senses.sight_range = 0.0
	senses.hearing_mult = Tuning.ECHO_HEARING_MULT_LOW
	body.collision_layer = 1 << (Tuning.LAYER_ERRORS - 1)
	# 08 §6: collides with the world and with the player, not with Still (layer 3).
	body.collision_mask = (1 << (Tuning.LAYER_WORLD - 1)) | (1 << (Tuning.LAYER_PLAYER - 1))
	shimmer.mesh = EchoPresent.shimmer_mesh()
	shimmer.position = Vector3.UP * Tuning.ECHO_CAPSULE_HEIGHT * 0.5
	shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	agent.radius = Tuning.NAV_AGENT_RADIUS
	agent.height = Tuning.NAV_AGENT_HEIGHT
	agent.path_desired_distance = Tuning.ERROR_WAYPOINT_DIST
	agent.target_desired_distance = Tuning.ECHO_ENTRY_ARRIVE_DIST
	agent.avoidance_enabled = true
	agent.velocity_computed.connect(_on_safe_velocity)
	EchoPresent.set_presence(self, 0.0)


func body_position() -> Vector3:
	return body.global_position if body != null and body.is_inside_tree() else global_position


func body_rids() -> Array[RID]:
	return [body.get_rid()]


func place_at(pos: Vector3) -> void:
	global_position = pos
	if body != null:
		body.position = Vector3.ZERO
		body.velocity = Vector3.ZERO


func _set_body_active(on: bool) -> void:
	if body == null:
		return
	body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on and not _doors_bound and is_inside_tree():
		_doors_bound = true
		_doors = EchoNav.bind_doors(self)
	if not on:
		EchoPresent.set_presence(self, 0.0)


func _on_door_opened(open: bool, door: Door) -> void:
	EchoNav.on_door_opened(open, self, door)


# --- 08 §8 aggression ----------------------------------------------------------------------

func _on_aggression() -> void:
	senses.hearing_mult = aggr_lerp(Tuning.ECHO_HEARING_MULT_LOW, Tuning.ECHO_HEARING_MULT_HIGH, aggression)


func trail_loss_time() -> float:
	return aggr_lerp(Tuning.ECHO_TRAIL_LOSS_TIME_LOW, Tuning.ECHO_TRAIL_LOSS_TIME_HIGH, aggression)


## The speed Echo walks at now (Follow: the recorded speed kind of the entry it walks to).
func current_speed() -> float:
	var s := 0.0
	match state:
		Tuning.ERROR_STATE_WANDER:
			s = Tuning.ECHO_WANDER_SPEED
		Tuning.ERROR_STATE_SEARCH, Tuning.ERROR_STATE_SATIATED:
			s = Tuning.ECHO_SEARCH_SPEED
		Tuning.ERROR_STATE_FOLLOW:
			if lure != Vector3.INF or _goal_index < 0 or _goal_index >= trail.size():
				s = Tuning.ECHO_SEARCH_SPEED
			else:
				s = EchoTrail.speed_for(trail.entries[_goal_index][&"speed_kind"])
	if s > 0.0 and EchoNav.wading_at(self, body_position()):
		s *= Tuning.PLAYER_WADE_SPEED_MULT
	return s


# --- hearing (the only sense) ------------------------------------------------------------------

func _on_heard(pos: Vector3, _radius: float, kind: StringName) -> void:
	if state == Tuning.ERROR_STATE_SATIATED or state == Tuning.ERROR_STATE_DORMANT:
		return
	if kind == Tuning.NOISE_KIND_STEP:
		_heard_step(pos)
	elif kind == Tuning.NOISE_KIND_TEAR and state == Tuning.ERROR_STATE_FOLLOW:
		# 08 §6: the tear (20 m) keeps it in Follow; the trail resumes on the far side.
		loss_time = 0.0
	elif LURE_KINDS.has(kind) and state == Tuning.ERROR_STATE_FOLLOW:
		# Reading: "the current trail point" is the entry Echo is walking to. Standing at its
		# target (the player stopped) it has none, so any heard lure wins: stopping and then
		# throwing a noise elsewhere is the combined counter.
		var walking := _has_target and lure == Vector3.INF and not trail.at_target()
		if not walking or EchoNav.flat(body_position(), pos) < EchoNav.flat(body_position(), _target):
			lure = pos
			last_heard = pos
			_goal_index = -1
			_has_target = false
	elif state == Tuning.ERROR_STATE_SEARCH and (LURE_KINDS.has(kind) or senses.suspicion >= Tuning.ERROR_SUSPICION_CHASE_AT):
		_search_toward(pos)
	elif state == Tuning.ERROR_STATE_WANDER and senses.suspicion >= Tuning.ERROR_SUSPICION_CHASE_AT:
		# 08 §2: a blind error goes to a loud noise (tear, door, mech; the payphone).
		last_heard = pos
		_search_point = pos
		transition_to(Tuning.ERROR_STATE_SEARCH, "heard %s" % kind)


func _heard_step(pos: Vector3) -> void:
	last_heard = pos
	match state:
		Tuning.ERROR_STATE_WANDER:
			_search_point = pos
			transition_to(Tuning.ERROR_STATE_SEARCH, "heard a step")
			trail.add(pos, clock)
		Tuning.ERROR_STATE_SEARCH:
			trail.add(pos, clock)
			if _engaged:
				# 08 §6 hiding: leaving within the search window, the steps are heard and
				# Follow resumes immediately (the same engagement).
				_follow("steps again")
			elif trail.count_since(clock - Tuning.ECHO_FOLLOW_STEPS_WINDOW) >= Tuning.ECHO_FOLLOW_STEPS:
				_follow("%d steps in %.0f s" % [Tuning.ECHO_FOLLOW_STEPS, Tuning.ECHO_FOLLOW_STEPS_WINDOW])
			else:
				_search_toward(pos)
		Tuning.ERROR_STATE_FOLLOW:
			trail.add(pos, clock)
			loss_time = 0.0
			# A newer step ends a lure: the trail is fresher.
			if lure != Vector3.INF:
				lure = Vector3.INF
				_has_target = false


func _follow(reason: String) -> void:
	# The trail starts at the earliest heard step of the window.
	trail.drop_before(clock - Tuning.ECHO_FOLLOW_STEPS_WINDOW)
	trail.next_index = 0
	transition_to(Tuning.ERROR_STATE_FOLLOW, reason)
	# 08 §2: Echo's notice is entering Follow (once per engagement). A Follow the Director
	# retreated at once (Calm, Relief) is not an encounter.
	if state == Tuning.ERROR_STATE_FOLLOW:
		_notice()


func _search_toward(pos: Vector3) -> void:
	last_heard = pos
	_search_point = pos
	_search_arrived = false
	_inspect.clear()
	_has_target = false
	state_time = 0.0


# --- the rule ---------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	clock += delta
	if has_player():
		trail.resolve(player.step_trail(), AudioManager.step_surface())
	_think(delta)
	_move(delta)
	EchoPresent.tick(self, delta)
	# Contact only from Follow (ErrorBase.can_contact): a Search or Wander walk that meets
	# the player is not a contact (R12, pillar 2).
	contact_step(Tuning.ECHO_CONTACT_RADIUS, Tuning.ECHO_CONTACT_COST)


func _dormant_tick() -> void:
	EchoPresent.set_presence(self, 0.0)


func _think(delta: float) -> void:
	match state:
		Tuning.ERROR_STATE_FOLLOW:
			loss_time += delta
			if loss_time >= trail_loss_time():
				# 08 §6: the trail ends; Search at the last heard point.
				_search_point = last_heard
				transition_to(Tuning.ERROR_STATE_SEARCH, "trail lost %.0f s" % loss_time)
		Tuning.ERROR_STATE_SATIATED:
			_satiated_left -= delta
			if _satiated_left <= 0.0:
				transition_to(Tuning.ERROR_STATE_WANDER, "satiated over")


func _enter_state(to: StringName, from: StringName) -> void:
	_has_target = false
	_repath_acc = INF
	_goal_index = -1
	match to:
		Tuning.ERROR_STATE_WANDER:
			senses.suspicion = 0.0
			trail.clear()
			lure = Vector3.INF
		Tuning.ERROR_STATE_SEARCH:
			senses.suspicion = 0.0
			_search_arrived = false
			_inspect.clear()
			lure = Vector3.INF
			if from == Tuning.ERROR_STATE_FOLLOW:
				# Steps heard from here on start the trail again.
				trail.clear()
		Tuning.ERROR_STATE_FOLLOW:
			loss_time = 0.0
			lure = Vector3.INF
		Tuning.ERROR_STATE_SATIATED:
			senses.suspicion = 0.0
			trail.clear()
			lure = Vector3.INF
			# 08 §6: Echo walks back along its own trail, playing the steps.
			_walk_back = _own_steps.duplicate()
			_walk_back.reverse()
			_own_steps.clear()
		Tuning.ERROR_STATE_DORMANT:
			body.velocity = Vector3.ZERO


## 10 §2 Relief (hint(pos, true)): Wander walks there now; Search inspects it now (a newer
## heard noise still pulls the Search back: the senses stay honest).
func _retarget_to_hint() -> void:
	var dest := EchoNav.snap(self, _hint)
	_has_hint = false
	if state == Tuning.ERROR_STATE_SEARCH:
		_search_arrived = true
		state_time = 0.0
		_inspect = [dest]
	_target = dest
	_has_target = true
	_repath_acc = INF


## 10 §2 Relief entry (hint(pos, true)) in Follow: the trail is dropped and Echo walks to
## the hint in Wander (R12). The engagement closes without an evasion (the player did not
## break the trail); steps heard from there start over (Search, then three for Follow).
func _release_for_hint() -> void:
	_engaged = false
	transition_to(Tuning.ERROR_STATE_WANDER, "hinted away")


func _on_player_gone() -> void:
	if body != null:
		body.velocity = Vector3.ZERO


func _on_contact() -> void:
	AudioManager.play_3d(&"error_contact_hit", body_position() + Vector3.UP * Tuning.ERROR_EYE_HEIGHT, EchoPresent.BUS)


# --- movement (EchoWalk) -------------------------------------------------------------------------

func _move(delta: float) -> void:
	EchoWalk.move(self, delta)


func _arrived() -> bool:
	return EchoWalk.arrived(self)


func _give_up() -> void:
	transition_to(Tuning.ERROR_STATE_WANDER, "search over")
	_evade()


func _on_safe_velocity(v: Vector3) -> void:
	_safe_velocity = Vector3(v.x, 0.0, v.z)
	_safe_frame = Engine.get_physics_frames()


func debug_info() -> Dictionary:
	var d := super.debug_info()
	d["echo trail"] = "%d heard, next %d, target %d, loss %.1f s" % [trail.size(), trail.next_index,
		trail.target_index(), loss_time]
	return d
