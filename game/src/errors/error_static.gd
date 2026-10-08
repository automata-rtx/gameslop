class_name ErrorStatic
extends ErrorBase
## Static (08 §3). Rule: a drifting field; inside it you lose Coherence; it leans toward
## noise. Counter: go around, wait for it to drift, noclip past; a burning flare pushes it
## back. Tell: the hum through walls (static_hum, 40 m) and the distortion. Cost: 4
## Coherence per second at the centre, full in the inner 60%: smoothstep(r, 0.6 r, d).
##
## Blind; hearing only. Wander: a walkable cell within 10 cells along the grid (doors
## ignored, it is sound), 0.6 m/s (0.9 by aggression), dwell 5 to 15 s. Search (3 heard
## steps within 10 s, or any tear): to last_known_pos at 0.9 to 1.2 m/s, dwell 20 s.
## Never chases, never contacts. Notice: the field first contains the player; evasion:
## the field releases the player after at least 2 s inside. Static ignores hiding.
## Scene contract: %Field (Area3D sphere), %Mesh (MeshInstance3D, static_field shader),
## %Senses. The root stands on the floor; the field is centred STATIC_CENTRE_HEIGHT up.

const HUM := &"static_hum"
const BAND := &"static_band"
const SOURCE := &"static"

## Every Static's current field strength on the player (several share one renderer).
static var _strength_by_error: Dictionary = {}

@onready var field: Area3D = %Field
@onready var mesh: MeshInstance3D = %Mesh

## Field radius r, 3 to 5 m by seed.
var radius: float = Tuning.STATIC_RADIUS_MIN
## The field's strength on the player this frame (0 outside, 1 in the inner 60%).
var strength: float = 0.0
var inside: bool = false
var inside_time: float = 0.0
## Coherence drained so far (tests, the arena).
var drained: float = 0.0

var _path: Array[Vector3] = []
var _dwell_left: float = 0.0
var _steps_heard: Array[float] = []
var _nudge: bool = false
var _hum: AudioLoop
var _band: AudioLoop


func _configure() -> void:
	error_id = SOURCE
	senses.sight_range = 0.0
	senses.hearing_mult = 1.0
	field.monitoring = false
	field.monitorable = false
	field.collision_layer = 0
	field.collision_mask = 0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_radius()


func _on_seeded() -> void:
	radius = rng.randf_range(Tuning.STATIC_RADIUS_MIN, Tuning.STATIC_RADIUS_MAX)
	if is_node_ready():
		_apply_radius()


func _apply_radius() -> void:
	var shape := (field.get_child(0) as CollisionShape3D).shape as SphereShape3D
	shape.radius = radius
	var sphere := mesh.mesh as SphereMesh
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.set_instance_shader_parameter(&"radius", radius)


func _exit_tree() -> void:
	_set_strength(0.0)
	_release_audio()


func centre() -> Vector3:
	return global_position + Vector3.UP * Tuning.STATIC_CENTRE_HEIGHT


func ear_position() -> Vector3:
	return centre()


## 08 §3: 1 inside 0.6 r, 0 at r and beyond, smooth between.
static func falloff(r: float, d: float) -> float:
	return 1.0 - smoothstep(r * Tuning.STATIC_FIELD_FULL_FRACTION, r, d)


func field_strength_at(pos: Vector3) -> float:
	return falloff(radius, pos.distance_to(centre()))


## For the Director's critical-path cut test (08 §3, 10 §7 rule 4).
func covers(pos: Vector3) -> bool:
	return pos.distance_to(centre()) < radius


## 08 §8 drift and search speeds by aggression.
func drift_speed() -> float:
	return aggr_lerp(Tuning.STATIC_DRIFT_SPEED_LOW, Tuning.STATIC_DRIFT_SPEED_HIGH, aggression)


func search_speed() -> float:
	return aggr_lerp(Tuning.STATIC_SEARCH_SPEED_LOW, Tuning.STATIC_SEARCH_SPEED_HIGH, aggression)


## 08 §3 fairness: the Director moves Static off a critical-path cut at 1.2 m/s.
func nudge(destination: Vector3) -> void:
	hint(destination)
	_nudge = true
	if state == Tuning.ERROR_STATE_WANDER:
		_plan_to(destination)


## Static has no Satiated: it never contacts. The Director moves it with nudge().
func retreat(_seconds: float) -> void:
	pass


# --- states -------------------------------------------------------------------------------

func _enter_state(to: StringName, _from: StringName) -> void:
	match to:
		Tuning.ERROR_STATE_WANDER:
			_dwell_left = 0.0
			_path.clear()
			_start_audio()
		Tuning.ERROR_STATE_SEARCH:
			_dwell_left = 0.0
			_plan_to(senses.last_known_pos)
			_start_audio()
		Tuning.ERROR_STATE_DORMANT:
			_path.clear()
			_release_field()
			_stop_audio()


func _on_heard(pos: Vector3, _radius: float, kind: StringName) -> void:
	# 08 §3: Search on 3 heard steps within 10 s, or any tear. It leans toward noise.
	var now := senses.clock
	if kind == Tuning.NOISE_KIND_STEP:
		_steps_heard.append(now)
	while not _steps_heard.is_empty() and now - _steps_heard[0] > Tuning.STATIC_SEARCH_STEPS_WINDOW:
		_steps_heard.remove_at(0)
	var go := kind == Tuning.NOISE_KIND_TEAR or _steps_heard.size() >= Tuning.STATIC_SEARCH_STEPS_HEARD
	if not go:
		return
	_steps_heard.clear()
	if state == Tuning.ERROR_STATE_SEARCH:
		_plan_to(pos)
		_dwell_left = 0.0
	elif state == Tuning.ERROR_STATE_WANDER:
		transition_to(Tuning.ERROR_STATE_SEARCH, "heard %s" % kind)


func _tick(delta: float) -> void:
	_drift(delta)
	_field(delta)


func _drift(delta: float) -> void:
	var push := _flare_push()
	if push != Vector3.ZERO:
		# 08 §3: a burning flare within 6 m pushes it away at 1.2 m/s.
		global_position += push * Tuning.STATIC_FLARE_PUSH_SPEED * delta
		return
	if _path.is_empty():
		if _dwell_left > 0.0:
			_dwell_left -= delta
			return
		match state:
			Tuning.ERROR_STATE_WANDER:
				_nudge = false
				_plan_to(_wander_target())
			Tuning.ERROR_STATE_SEARCH:
				if state_time > 0.0 and _dwell_left <= 0.0 and _searched:
					transition_to(Tuning.ERROR_STATE_WANDER, "search dwell over")
					return
		if _path.is_empty():
			return
	var speed := drift_speed()
	if state == Tuning.ERROR_STATE_SEARCH:
		speed = search_speed()
	if _nudge:
		speed = Tuning.STATIC_FAIR_NUDGE_SPEED
	var target := _path[0]
	var here := global_position
	var to := Vector3(target.x - here.x, 0.0, target.z - here.z)
	var step := speed * delta
	var next := here
	if to.length() <= step:
		next = Vector3(target.x, target.y, target.z)
		_path.remove_at(0)
		if _path.is_empty():
			_arrive()
	else:
		next = here + to.normalized() * step
		next.y = lerpf(here.y, target.y, clampf(step / maxf(to.length(), 0.001), 0.0, 1.0))
	if _blocked_by_flare(next):
		# It cannot cross into a flare's 6 m: wait where it is.
		_path.clear()
		_dwell_left = rng.randf_range(Tuning.STATIC_DWELL_MIN, Tuning.STATIC_DWELL_MAX)
		return
	global_position = next


var _searched: bool = false


func _arrive() -> void:
	if state == Tuning.ERROR_STATE_SEARCH:
		_dwell_left = Tuning.STATIC_SEARCH_DWELL
		_searched = true
	else:
		_dwell_left = rng.randf_range(Tuning.STATIC_DWELL_MIN, Tuning.STATIC_DWELL_MAX)


## A hint, or a seeded walkable cell within 10 cells (grid walking distance).
func _wander_target() -> Vector3:
	if _has_hint:
		_has_hint = false
		return _hint
	if grid == null:
		var a := rng.randf() * TAU
		var r := rng.randf() * Tuning.STATIC_WANDER_CELLS * Tuning.GRID_CELL_SIZE
		return global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var from := grid.cell_of(global_position)
	var dist := grid.distance_field(from)
	var pool: Array[Vector2i] = []
	for i in dist.size():
		if dist[i] > 0 and dist[i] <= Tuning.STATIC_WANDER_CELLS:
			pool.append(grid.cell_at(i))
	if pool.is_empty():
		return global_position
	return grid.world_of(pool[rng.randi_range(0, pool.size() - 1)])


## The cell path (LevelGrid BFS over walkable cells, doors open: it is sound) to `dest`;
## a straight line without a grid.
func _plan_to(dest: Vector3) -> void:
	_path.clear()
	_searched = false
	if grid == null:
		_path.append(dest)
		return
	var from := grid.cell_of(global_position)
	var to := grid.cell_of(dest)
	if not grid.in_bounds(to) or not grid.is_walkable(to) or not grid.is_walkable(from):
		_path.append(Vector3(dest.x, global_position.y, dest.z))
		return
	for c in cell_path(grid, from, to):
		_path.append(grid.world_of(c))


## BFS cell path from `from` to `to` (both included after `from`), empty if unreachable.
static func cell_path(g: LevelGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		out.append(to)
		return out
	var prev := PackedInt32Array()
	prev.resize(g.cell_count())
	prev.fill(-1)
	var start := g.idx(from)
	var goal := g.idx(to)
	prev[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal:
			break
		var c := g.cell_at(i)
		for d in 4:
			if not g.can_step(c, d):
				continue
			var j := g.idx(c + LevelGrid.DIRS[d])
			if prev[j] == -1:
				prev[j] = i
				queue.append(j)
	if prev[goal] == -1:
		return out
	var k := goal
	while k != start:
		out.push_front(g.cell_at(k))
		k = prev[k]
	return out


# --- flares (08 §3) ---------------------------------------------------------------------------

func _flares() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(Tuning.STATIC_FLARE_GROUP):
		var f := n as Node3D
		if f != null and f.is_inside_tree():
			out.append(f)
	return out


## Unit XZ direction away from the nearest burning flare within 6 m, or zero.
func _flare_push() -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for f in _flares():
		var off := global_position - f.global_position
		off.y = 0.0
		var d := off.length()
		if d < Tuning.STATIC_FLARE_RANGE and d < best_d:
			best_d = d
			best = off.normalized() if d > 0.001 else Vector3.RIGHT
	return best


func _blocked_by_flare(next: Vector3) -> bool:
	for f in _flares():
		var a := Vector2(next.x - f.global_position.x, next.z - f.global_position.z).length()
		if a < Tuning.STATIC_FLARE_RANGE:
			return true
	return false


# --- the field -----------------------------------------------------------------------------------

func _field(delta: float) -> void:
	if player == null or not player.is_inside_tree():
		_release_field()
		return
	var s := field_strength_at(player.eye_position())
	var was := inside
	inside = s > 0.0
	strength = s
	if inside:
		inside_time += delta
		var loss := Tuning.STATIC_DRAIN_PER_S * s * delta
		drained += loss
		player.apply_coherence(-loss, SOURCE)
		if not was:
			_notice()
	elif was:
		_on_release()
	_set_strength(s)
	if _band != null:
		_band.set_volume(lerpf(Tuning.STATIC_BAND_OUTSIDE_DB, Tuning.STATIC_BAND_INSIDE_DB, s))


func _on_release() -> void:
	# 08 §2: an evasion when the field lets go after at least 2 s inside.
	if inside_time >= Tuning.STATIC_MIN_EVADE_TIME:
		_evade()
	else:
		_engaged = false
	inside_time = 0.0


func _release_field() -> void:
	if inside:
		inside = false
		_on_release()
	strength = 0.0
	_set_strength(0.0)


## Feeds the renderer (02 §8: grain 0.6, CA 0.02 inside), the static bed (03) and the
## 0.002 m camera jitter (11 §3) with the strongest field over every Static.
func _set_strength(s: float) -> void:
	var key := get_instance_id()
	if s > 0.0:
		_strength_by_error[key] = s
	else:
		_strength_by_error.erase(key)
	var top := 0.0
	for v: float in _strength_by_error.values():
		top = maxf(top, v)
	CoherenceRenderer.set_static(top)
	AudioManager.set_static_inside(top > 0.0)
	if player != null and is_instance_valid(player) and player.rig != null:
		player.rig.set_jitter(Tuning.FEEDBACK_STATIC_JITTER if top > 0.0 else 0.0)


static func strongest_field() -> float:
	var top := 0.0
	for v: float in _strength_by_error.values():
		top = maxf(top, v)
	return top


# --- audio (03: hum through walls, the band rises inside) -----------------------------------------

func _start_audio() -> void:
	if _hum == null:
		_hum = AudioManager.loop(HUM, self)
		_band = AudioManager.loop(BAND, self)
	_hum.start()
	_band.start()
	_band.set_volume(Tuning.STATIC_BAND_OUTSIDE_DB)


func _stop_audio() -> void:
	if _hum != null:
		_hum.stop()
		_band.stop()


func _release_audio() -> void:
	if _hum != null:
		_hum.release()
		_band.release()
		_hum = null
		_band = null
