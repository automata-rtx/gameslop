class_name ErrorNull
extends ErrorBase
## Null (08 §7). Rule: after the calm window it walks straight at the player at 2.4 m/s
## (Cycle 2: 2.8) through all geometry, and within 12 m of it (24 m from depth 12) the world
## is not rendered. Counter: keep moving, route around it with the view it gives through
## unrendered walls, reach the Threshold. Tell: the unrender radius and the grid tone
## (CoherenceRenderer.set_null each frame; the renderer and AudioManager read it). Cost: 12
## Coherence per second inside its 2 m core.
##
## No body and no collision: it is the drawing boundary, a point (`centre()`, at eye height
## over the floor point the node stands on) that moves in a straight line toward the
## player's current position. No senses (it always knows where the player is; it is the
## only error that cheats openly) and no navigation. States: Dormant (the calm window), then
## Chase, woken only by the Director's Pursuit (`pursue()`, 10 §2). It has no Wander, Search
## or Satiated: `retreat()` and `start_search()` do nothing, and hints are only stored.
## The core is not a contact: no gate, no stun, no push; the drain goes straight through
## Player.apply_coherence (source `null`), hidden or not (06 §10). Walking out is always
## possible: nothing holds the player.
## Notice: once, when it wakes (08 §2). Evasion: never (it is escaped by the Threshold).

const SOURCE := &"null"

## Absolute depth and Cycle (from the bound level's data; tests and benches may set them).
var depth: int = 6
var cycle: int = 1
## Coherence drained so far (tests, the arena).
var drained: float = 0.0
## Seconds the player has spent inside the core (tests, sims).
var core_time: float = 0.0
## The camera jitter Null last asked for (11 §3: 0.004 m in the radius, 0.01 m in the core).
var jitter: float = 0.0

## True while this Null owns CoherenceRenderer's Null slot.
var _feeding: bool = false


func _configure() -> void:
	error_id = SOURCE
	senses.sight_range = 0.0
	senses.hearing_mult = 0.0


func bind_level(p_level: Level) -> void:
	super.bind_level(p_level)
	if level.data != null:
		depth = level.data.depth
		cycle = level.data.cycle


func _exit_tree() -> void:
	_stop_feed()


# --- 08 §7 numbers ------------------------------------------------------------------------------

## 2.4 m/s; Cycle 2 sets 2.8. Null ignores aggression (08 §8).
func speed() -> float:
	return Tuning.NULL_SPEED_CYCLE2 if cycle >= 2 else Tuning.NULL_SPEED_CYCLE1


## 12 m; radius x2 from depth 12 (05 §3, 07 §9).
func radius() -> float:
	return Tuning.NULL_UNRENDER_RADIUS_CYCLE2 if depth >= Tuning.NULL_CYCLE2_RADIUS_FROM_DEPTH \
		else Tuning.NULL_UNRENDER_RADIUS


## The centre of the unrender sphere and of the 2 m core: eye height over the floor point.
## The post core, the audio core mute and the drain all measure from here to the camera.
func centre() -> Vector3:
	return global_position + Vector3.UP * Tuning.ERROR_EYE_HEIGHT


## The player's eye (the camera) distance to the centre; INF without a player.
func eye_distance() -> float:
	if not has_player():
		return INF
	return centre().distance_to(player.eye_position())


func in_core() -> bool:
	return eye_distance() <= Tuning.NULL_CORE_RADIUS


func in_radius() -> bool:
	return eye_distance() <= radius()


# --- the Director link (10 §2 Pursuit) ----------------------------------------------------------

## The Pursuit's entry point (DirectorHunters.wake_null).
func pursue() -> void:
	wake()


## Dormant -> Chase. Before the level's navigation is ready the wake is remembered (07 §3:
## errors stay dormant until it, as every error).
func wake() -> void:
	if not navigation_ready:
		_wake_pending = true
		return
	if state == Tuning.ERROR_STATE_DORMANT:
		transition_to(Tuning.ERROR_STATE_CHASE, "pursuit")


## Null has no Search (10 §7 rule 9: never an awake arrival).
func start_search(_pos: Vector3) -> void:
	pass


## Null never contacts (08 §7: the core is a drain, not a contact). It never calls
## contact_step/try_contact; this also answers the base's contact predicate (R12).
func can_contact() -> bool:
	return false


## Null has no Satiated: nothing sends it away (08 §7).
func retreat(_seconds: float) -> void:
	pass


# --- state machine ------------------------------------------------------------------------------

func _enter_state(to: StringName, _from: StringName) -> void:
	if to == Tuning.ERROR_STATE_CHASE:
		_notice()
		_feed()
	elif to == Tuning.ERROR_STATE_DORMANT:
		_stop_feed()


func _tick(delta: float) -> void:
	if state != Tuning.ERROR_STATE_CHASE or not has_player():
		return
	# The rule: straight at the player's current position, through everything.
	global_position = global_position.move_toward(player.global_position, speed() * delta)
	_feed()
	if in_core():
		# The cost: 10 per second in the core (not a contact).
		var loss := Tuning.NULL_DRAIN_PER_S * delta
		core_time += delta
		drained += loss
		player.apply_coherence(-loss, SOURCE)


func _on_player_gone() -> void:
	_stop_feed()


# --- the tell: the renderer's Null slot and the 11 §3 jitter ------------------------------------

func _feed() -> void:
	_feeding = true
	CoherenceRenderer.set_null(centre(), radius())
	_set_jitter(Tuning.FEEDBACK_NULL_CORE_JITTER if in_core()
		else (Tuning.FEEDBACK_NULL_RADIUS_JITTER if in_radius() else 0.0))


func _stop_feed() -> void:
	if _feeding:
		_feeding = false
		CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	_set_jitter(0.0)


## The rig holds one jitter value; Static's field (0.002 m) shares it, so the larger wins
## and leaving Null's radius hands it back to Static's.
func _set_jitter(m: float) -> void:
	var p := live_player()
	if m == 0.0 and jitter == 0.0:
		return
	jitter = m
	if p == null or p.rig == null:
		return
	var static_j := Tuning.FEEDBACK_STATIC_JITTER if StaticFeed.strongest() > 0.0 else 0.0
	p.rig.set_jitter(maxf(m, static_j))


func debug_info() -> Dictionary:
	var d := super.debug_info()
	d["null core"] = "%s %.1f drained" % ["in" if in_core() else "out", drained]
	return d
