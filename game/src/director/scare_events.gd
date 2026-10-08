class_name ScareEvents
extends RefCounted
## The world side of 10 §5's scares: each executor finds its place on the Director's level,
## runs the event and returns true, or returns false when the level has nowhere for it (no
## closed door 20 to 40 m out of view, no payphone 15 to 40 m away, no awake Static, no
## powered fixture 12 to 40 m away, no Echo dormant or wandering 25 m off). Nothing here
## costs Coherence, spawns anything or names the player's position to an error: the only
## gameplay trace is a noise at a door or a payphone, which errors hear like any other.
## Ongoing events (the payphone's ring, the swell) end when the phase leaves Build
## (`stop_ongoing`), so no scare plays on into Peak or Relief.

const SWELL_META := &"audio_swell_db"

var director: Director
## Payphones this level's scares rang (silenced when Build ends).
var _rung: Array[Payphone] = []
## Static hum player -> the time its +4 dB swell ends (Director clock).
var _swells: Dictionary = {}


func bind(d: Director, scares: Scares) -> void:
	director = d
	scares.executors = {
		Scares.DOOR_SLAM: door_slam,
		Scares.PAYPHONE: payphone,
		Scares.STATIC_SWELL: static_swell,
		Scares.FIXTURE_DROPOUT: fixture_dropout,
		Scares.PRE_ECHO: pre_echo,
	}


func _player_ok() -> bool:
	var p := director.player if director != null else null
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _tree() -> SceneTree:
	return director.get_tree() if director != null and director.is_inside_tree() else null


## Nodes of `group` under the Director's level (all of them without a level).
func _level_nodes(group: StringName) -> Array[Node]:
	var out: Array[Node] = []
	var tree := _tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(group):
		if director.level == null or director.level.is_ancestor_of(n):
			out.append(n)
	return out


# --- pure choices (tested without a level) ------------------------------------------------

## Index of the nearest point `dmin`..`dmax` m (flat) from the player and outside the view
## cone from `eye` along `forward`; -1 when none.
static func pick_far_out_of_view(points: Array[Vector3], player_pos: Vector3, eye: Vector3, forward: Vector3,
		half_fov: float, dmin: float, dmax: float) -> int:
	var best := -1
	var best_d := INF
	for i in points.size():
		var d := DirectorSpawn.flat_dist(points[i], player_pos)
		if d < dmin or d > dmax or d >= best_d:
			continue
		if DirectorSpawn.in_cone(eye, forward, half_fov, points[i] + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT):
			continue
		best = i
		best_d = d
	return best


## Index of the nearest point `dmin`..`dmax` m (flat) from the player; -1 when none.
static func pick_far(points: Array[Vector3], player_pos: Vector3, dmin: float, dmax: float) -> int:
	var best := -1
	var best_d := INF
	for i in points.size():
		var d := DirectorSpawn.flat_dist(points[i], player_pos)
		if d >= dmin and d <= dmax and d < best_d:
			best = i
			best_d = d
	return best


## 10 §5 pre-echo: Echo dormant or wandering, at least 25 m from the player.
static func pre_echo_ok(state: StringName, distance: float) -> bool:
	return (state == Tuning.ERROR_STATE_DORMANT or state == Tuning.ERROR_STATE_WANDER) \
		and distance >= Tuning.SCARE_PRE_ECHO_MIN_DIST


# --- the five events -----------------------------------------------------------------------

## A closed door 20 to 40 m away and out of the frustum slams open: door_slam and its 18 m
## `door` noise (Door.open(slam)), which can pull a hunter to the door, not to the player.
func door_slam() -> bool:
	if not _player_ok():
		return false
	var doors: Array[Door] = []
	var points: Array[Vector3] = []
	for n in _level_nodes(&"doors"):
		var d := n as Door
		if d != null and not d.is_open:
			doors.append(d)
			points.append(d.global_position)
	var cam := director.player.rig.camera
	var half := DirectorSpawn.half_fov_h(cam.fov, 16.0 / 9.0)
	var i := pick_far_out_of_view(points, director.player.global_position, director.player.eye_position(),
		-cam.global_transform.basis.z, half, Tuning.SCARE_DOOR_SLAM_MIN_DIST, Tuning.SCARE_DOOR_SLAM_MAX_DIST)
	if i < 0:
		return false
	doors[i].open(true)
	return true


## A payphone 15 to 40 m away rings (Payphone.candidates, nearest first) until answered or
## 30 s; its ring is the payphone's own 18 m noise every 6 s.
func payphone() -> bool:
	if not _player_ok() or _tree() == null:
		return false
	for p in Payphone.candidates(_tree(), director.player.global_position):
		if director.level != null and not director.level.is_ancestor_of(p):
			continue
		if p.ring():
			_rung.append(p)
			return true
	return false


## The nearest awake Static's hum gains +4 dB for 3 s (no gameplay change).
func static_swell() -> bool:
	if not _player_ok():
		return false
	var best: ErrorStatic = null
	var best_d := INF
	for e in director.hunters.live():
		var st := e as ErrorStatic
		if st == null or st.is_dormant():
			continue
		var d := st.distance_to_player()
		if d < best_d:
			best = st
			best_d = d
	if best == null:
		return false
	var hum := _hum_player(best)
	if hum == null:
		return false
	_set_swell(hum, Tuning.SCARE_STATIC_SWELL_DB)
	_swells[hum] = director.now() + Tuning.SCARE_STATIC_SWELL_TIME
	return true


## Static's hum loop: the AudioStreamPlayer3D child AudioManager.loop() made for it.
static func _hum_player(st: ErrorStatic) -> Node:
	for c in st.get_children():
		if c is AudioStreamPlayer3D and c.get_meta(AudioPool.META_ID, &"") == ErrorStatic.HUM:
			return c
	return null


## The swell rides on the loop's base level (AudioLoop: base + fade + occlusion).
func _set_swell(hum: Node, db: float) -> void:
	var prev := float(hum.get_meta(SWELL_META, 0.0))
	var base := float(hum.get_meta(AudioLoop.META_BASE, 0.0)) - prev + db
	hum.set_meta(SWELL_META, db)
	AudioLoop.set_part(hum, AudioLoop.META_BASE, base)


## The nearest powered, steady fixture 12 to 40 m away goes dark for good with the ballast
## tink. Not a flicker (02 §6: flicker means Flicker), so flickering fixtures and the special
## lights (rack LEDs, the exit light, emergency boxes) are never chosen; and none while a
## breaker on the level is still to be thrown (its power wave would light it again).
func fixture_dropout() -> bool:
	if not _player_ok():
		return false
	for n in _level_nodes(&"breakers"):
		if n is Breaker and not (n as Breaker).is_thrown:
			return false
	var fixtures: Array[Fixture] = []
	var points: Array[Vector3] = []
	for n in _level_nodes(&"fixtures"):
		var f := n as Fixture
		if f == null or not f.powered or f.is_flickering() or not f.light_profile.is_empty():
			continue
		fixtures.append(f)
		points.append(f.global_position)
	var i := pick_far(points, director.player.global_position, Tuning.SCARE_FIXTURE_DROPOUT_MIN_DIST,
		Tuning.SCARE_FIXTURE_DROPOUT_MAX_DIST)
	if i < 0:
		return false
	var f := fixtures[i]
	f.set_powered(false)
	f.set_meta(&"dropped_out", true)
	if director.level != null and director.level.light_pool != null:
		director.level.light_pool.reevaluate()
	AudioManager.play_3d(&"fixture_dropout", f.global_position)
	return true


## One of the player's recent steps plays once at a dormant or wandering Echo's feet, 25 m or
## more away: Echo's own tell (the player's surface sample, Errors bus, -3 dB), longer late.
func pre_echo() -> bool:
	if not _player_ok():
		return false
	for e in director.hunters.live():
		if e.error_id != &"echo" or not pre_echo_ok(e.state, e.distance_to_player()):
			continue
		var trail := director.player.step_trail()
		var surface := NoiseModel.DEFAULT_SURFACE
		if trail != null and not trail.is_empty():
			var last: Variant = trail.newest()
			if last is Dictionary:
				surface = StringName((last as Dictionary).get(&"surface", surface))
		var id := StringName("foot_%s" % surface)
		if not AudioManager.has_sound(id):
			id = StringName("foot_%s" % NoiseModel.DEFAULT_SURFACE)
		AudioManager.play_3d(id, e.body_position(), EchoPresent.BUS, Tuning.ECHO_STEP_PLAYBACK_DB)
		return true
	return false


# --- upkeep ---------------------------------------------------------------------------------

## Each Director step: ends swells whose 3 s are up.
func tick(now: float) -> void:
	for hum: Variant in _swells.keys():
		if not is_instance_valid(hum):
			_swells.erase(hum)
		elif now >= float(_swells[hum]):
			_set_swell(hum, 0.0)
			_swells.erase(hum)


## Build ended (or the level did): rung payphones fall silent and swells end now.
func stop_ongoing() -> void:
	for p in _rung:
		if is_instance_valid(p) and p.ringing:
			# Payphone's public limit: the next tick ends the ring (no answer, no line hum).
			p.ring_limit = 0.0
	_rung.clear()
	for hum: Variant in _swells.keys():
		if is_instance_valid(hum):
			_set_swell(hum, 0.0)
	_swells.clear()


func ringing_count() -> int:
	var n := 0
	for p in _rung:
		if is_instance_valid(p) and p.ringing:
			n += 1
	return n
