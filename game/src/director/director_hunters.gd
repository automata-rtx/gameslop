class_name DirectorHunters
extends RefCounted
## The Director's calls down to its errors (10 §2 to §4, §7): spawning the roster at fair
## cells, awake arrivals, the survey each step (nearest hunter, chasers, threat), the phase
## actions (wake, hint toward, hint away, retreat), the chaser caps, the Calm keep-away and
## Static's critical-path nudge. Every hint is a cell at a range from the player, never the
## player's position (10 §1).

## One step's view of the errors.
class Survey:
	var nearest: float = INF
	var chasing: int = 0
	var hunters: int = 0
	var threat: float = 0.0

const STATIC := &"static"

var director: Director
## Static instance id -> seconds its field has cut the only route (08 §3).
var _cut_time: Dictionary = {}
var _counts: Dictionary = {}
## Hunters with no fair cell at level entry, retried once per second (`spawn_pending`).
var pending: Array[StringName] = []
## Hunters that arrived in Search after a drop (05 §3), and chasers sent away by the cap.
var awake: Array[ErrorBase] = []
var cap_retreats: int = 0


func live() -> Array[ErrorBase]:
	var out: Array[ErrorBase] = []
	for e in director.errors:
		if is_instance_valid(e) and e.is_inside_tree():
			out.append(e)
	return out


func _hunters() -> Array[ErrorBase]:
	var out: Array[ErrorBase] = []
	for e in live():
		if DirectorRules.is_hunter(e.error_id):
			out.append(e)
	return out


func _statics() -> Array[ErrorStatic]:
	var out: Array[ErrorStatic] = []
	for e in live():
		if e is ErrorStatic:
			out.append(e as ErrorStatic)
	return out


func chasers() -> Array[ErrorBase]:
	var out: Array[ErrorBase] = []
	for e in _hunters():
		if DirectorRules.is_chasing_state(e.state):
			out.append(e)
	return out


func _player_ok() -> bool:
	var p := director.player
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _grid() -> LevelGrid:
	return director.data.grid if director.data != null else null


# --- spawning (10 §4) -------------------------------------------------------------------------

## Spawns every spawnable roster id Dormant at a distinct fair cell. Ids without a scene yet
## are recorded in `director.skipped` (TODO(M2.5, M2.6): Flicker, Null).
func spawn_roster(roster: Array[StringName]) -> void:
	var d := director
	var ids: Array[StringName] = []
	for id in roster:
		if DirectorRules.spawnable(id):
			ids.append(id)
		else:
			d.skipped.append(id)
	if ids.is_empty() or not _player_ok() or _grid() == null:
		return
	var band := DirectorSpawn.breaker_exit_band(d.data) if _first_descent_depth1() else {}
	var cells := _pick(ids, band)
	for i in ids.size():
		if cells[i] == LevelData.NO_CELL:
			# No fair cell from the arrival pose (an open hall in view): wait until the
			# player moves or turns (M1.13: every level with a native slot has a hunter).
			pending.append(ids[i])
			continue
		spawn(ids[i], _grid().world_of(cells[i]))


## DirectorSpawn.pick_cells from the player's current pose.
func _pick(ids: Array[StringName], band: Dictionary = {}) -> Array[Vector2i]:
	var d := director
	var cam := d.player.rig.camera
	var vp_size := cam.get_viewport().get_visible_rect().size if cam.is_inside_tree() else Vector2(16, 9)
	var aspect := maxf(vp_size.x / maxf(vp_size.y, 1.0), 16.0 / 9.0)
	var fwd := -cam.global_transform.basis.z
	return DirectorSpawn.pick_cells(d.data, ids, d.native, d.player.global_position, d.player.eye_position(),
		fwd, DirectorSpawn.half_fov_h(cam.fov, aspect), d.rng, band)


## Once per second: spawns each pending hunter as soon as a fair cell exists (same rules as
## at entry). One spawned after Calm wakes at once (Build entry would have woken it), where
## 05 §10 allows; otherwise it is Dormant like the rest.
func spawn_pending() -> void:
	if pending.is_empty() or not _player_ok() or _grid() == null:
		return
	var cells := _pick(pending)
	var left: Array[StringName] = []
	for i in pending.size():
		if cells[i] == LevelData.NO_CELL:
			left.append(pending[i])
			continue
		var e := spawn(pending[i], _grid().world_of(cells[i]))
		if e != null and director.pacing.phase != DirectorPacing.CALM and director.wake_allowed():
			_wake(e)
	pending = left


func spawn(id: StringName, pos: Vector3) -> ErrorBase:
	var d := director
	var e := ErrorBase.create(id)
	if e == null:
		return null
	var index := int(_counts.get(id, 0))
	_counts[id] = index + 1
	var level_seed := d.data.level_seed if d.data != null else 0
	e.setup(d.player, d.level, Seeds.derive(level_seed, ErrorBase.seed_label(id, index)))
	var parent: Node = d.level if d.level != null else d.get_parent()
	parent.add_child(e)
	if e is ErrorStill:
		(e as ErrorStill).place_at(pos)
	else:
		e.global_position = pos
	e.contacted_player.connect(d.on_error_contact.bind(e))
	e.lost_player.connect(d.on_error_lost.bind(e))
	e.state_changed.connect(d.on_error_state.bind(e))
	e.set_aggression(DirectorRules.error_aggression(d.aggression, d.depth, id))
	d.errors.append(e)
	if id == STATIC:
		# 10 §4: Static starts awake (it is weather).
		e.wake()
	return e


## 05 §3, 10 §4: after drops, one or two hunters (never Null, §7 rule 9) start in Search at
## a cell 30 m from the player (never the player's position); pending ones arrive Dormant.
func awake_arrivals(count: int) -> void:
	if count <= 0 or not _player_ok() or _grid() == null or not director.wake_allowed():
		return
	var hs := _hunters()
	var ids: Array[StringName] = []
	for h in hs:
		ids.append(h.error_id)
	var picks := DirectorRules.awake_arrival_indices(ids, 2 if count >= 2 else 1)
	for i in picks.slice(0, count):
		var e := hs[i]
		var c := DirectorSpawn.cell_at_distance(_grid(), director.player.global_position, Tuning.AWAKE_SEARCH_DIST, director.rng)
		if c == LevelData.NO_CELL:
			continue
		var p := _grid().world_of(c)
		e.start_search(p)
		if not e.navigation_ready and director.level != null:
			# The error wakes to Wander when the navigation is ready; Search after it.
			var err := e
			director.level.navigation_ready.connect(func(ok: bool) -> void:
				if ok and is_instance_valid(err):
					err.start_search(p), CONNECT_ONE_SHOT)
		awake.append(e)


# --- the survey (10 §2 inputs, §6 threat) -------------------------------------------------------

func survey() -> Survey:
	var s := Survey.new()
	var hunter_max := 0.0
	var inside_static := false
	var null_d := INF
	for e in live():
		if e is ErrorStatic:
			inside_static = inside_static or (e as ErrorStatic).inside
			continue
		if not DirectorRules.is_hunter(e.error_id):
			continue
		s.hunters += 1
		if e.is_dormant():
			continue
		var dist := e.distance_to_player()
		var ch := DirectorRules.is_chasing_state(e.state)
		if ch:
			s.chasing += 1
		if e.error_id == &"null":
			null_d = minf(null_d, dist)
		s.nearest = minf(s.nearest, dist)
		hunter_max = maxf(hunter_max, DirectorRules.hunter_threat(dist, ch))
	s.threat = DirectorRules.threat_target(hunter_max, inside_static, null_d)
	return s


# --- phase actions (DirectorPacing.ACT_*) -----------------------------------------------------

func act(a: StringName) -> void:
	match a:
		DirectorPacing.ACT_WAKE_ONE:
			# 05 §10 keeps the first Descent's depth 1 free of active hunters.
			var h := _nearest(true) if director.wake_allowed() else null
			if h != null:
				_wake(h)
		DirectorPacing.ACT_WAKE_NEAREST:
			if not director.wake_allowed():
				return
			var h := _nearest(true)
			if h == null:
				h = _nearest(false)
			if h != null:
				_wake(h)
				_hint_wake_ring(h)
		DirectorPacing.ACT_HINT_TOWARD:
			for h in _free_hunters():
				_hint_ring(h, Tuning.DIRECTOR_HINT_RANGE_MIN, Tuning.DIRECTOR_HINT_RANGE_MAX)
		DirectorPacing.ACT_HINT_AWAY:
			for h in _free_hunters():
				_hint_ring(h, Tuning.DIRECTOR_RELIEF_HINT_AWAY_DIST, Tuning.DIRECTOR_HINT_AWAY_MAX)
			for st in _statics():
				_hint_off_path(st, false)
		DirectorPacing.ACT_HINT_AWAY_NOW:
			# Relief entry (M1.13 ruling): every hunter away at once through the errors'
			# immediate hint (R9): Wander and Search re-target now; in Chase, Satiated or
			# Dormant the hint is stored. Static re-targets off the critical path now.
			for h in _hunters():
				_hint_ring(h, Tuning.DIRECTOR_RELIEF_HINT_AWAY_DIST, Tuning.DIRECTOR_HINT_AWAY_MAX, true)
			for st in _statics():
				_hint_off_path(st, false, true)
		DirectorPacing.ACT_RETREAT_CHASERS:
			for h in chasers():
				h.retreat(Tuning.DIRECTOR_PEAK_RETREAT_TIME)
		DirectorPacing.ACT_WAKE_NULL:
			wake_null()
		DirectorPacing.ACT_HINT_STATIC_ACROSS:
			if _grid() != null:
				# §7 rule 9: never into the Threshold pocket (the exit room and 6 m around it).
				for st in _statics():
					var c := DirectorRules.pursuit_static_cell(_grid(), director.data.critical_path, director.rng)
					if c != LevelData.NO_CELL:
						st.hint(_grid().world_of(c))


## 10 §2 Pursuit entry (after the Substrate's Calm): Null wakes (guarded calls until M2.6).
func wake_null() -> int:
	var n := 0
	for h in _hunters():
		if h.error_id != &"null":
			continue
		if h.has_method(&"pursue"):
			h.call(&"pursue")
		elif h.has_method(&"wake"):
			h.wake()
		n += 1
	return n


## The phases wake every hunter but Null (DirectorRules.phase_wakes).
func _wake(h: ErrorBase) -> void:
	if DirectorRules.phase_wakes(h.error_id):
		h.wake()


## Awake hunters that take hints: not chasing, not satiated (Wander and Search, 08 §2).
func _free_hunters() -> Array[ErrorBase]:
	var out: Array[ErrorBase] = []
	for h in _hunters():
		if not h.is_dormant() and not DirectorRules.is_chasing_state(h.state) and h.state != Tuning.ERROR_STATE_SATIATED:
			out.append(h)
	return out


## The nearest dormant hunter (`dormant`), or the nearest awake one that is not chasing.
func _nearest(dormant: bool) -> ErrorBase:
	var best: ErrorBase = null
	var best_d := INF
	for h in _hunters():
		if h.is_dormant() != dormant or DirectorRules.is_chasing_state(h.state) or not DirectorRules.phase_wakes(h.error_id):
			continue
		var dist := h.distance_to_player()
		if best == null or dist < best_d:
			best = h
			best_d = dist
	return best


## 10 §2: "hints it to 12 m" (within the hint tolerance).
func _hint_wake_ring(h: ErrorBase) -> void:
	_hint_ring(h, Tuning.DIRECTOR_WAKE_HINT_DIST - Tuning.DIRECTOR_HINT_DIST_TOLERANCE,
		Tuning.DIRECTOR_WAKE_HINT_DIST + Tuning.DIRECTOR_HINT_DIST_TOLERANCE)


## A hint to a random walkable cell `rmin` to `rmax` m from the player; `now` asks the
## error to re-target at once (Relief entry).
func _hint_ring(h: ErrorBase, rmin: float, rmax: float, now: bool = false) -> void:
	if not _player_ok() or _grid() == null:
		return
	var c := DirectorSpawn.cell_in_ring(_grid(), director.player.global_position, rmin, rmax, director.rng)
	if c == LevelData.NO_CELL:
		return
	h.hint(_grid().world_of(c), now)


func _hint_off_path(st: ErrorStatic, nudge: bool, now: bool = false) -> void:
	if _grid() == null:
		return
	var c := DirectorSpawn.off_path_cell(_grid(), director.data.critical_path, st.global_position)
	if c == LevelData.NO_CELL:
		return
	if nudge:
		st.nudge(_grid().world_of(c))
	else:
		st.hint(_grid().world_of(c), now)


# --- fairness (10 §7) ---------------------------------------------------------------------------

func _first_descent_depth1() -> bool:
	return director.first_descent and DirectorRules.cycle_depth(director.depth) == 1 and _grid() != null


## 05 §10 first Descent, as the M1.13 ruling places it: the first Static spawns between the
## breaker and the exit and its drift stays within 6 m of that stretch of the critical path
## (`DirectorSpawn.breaker_exit_band`); any other Static drifts in a side loop
## (`side_loop_cells`). Each gets its wander filter through `ErrorStatic.set_wander_filter`
## (called only when it exists). Returns the first Static's filter, or an invalid Callable
## when none applies.
func bound_statics_off_path() -> Callable:
	var d := director
	if not _first_descent_depth1():
		return Callable()
	var statics := _statics()
	if statics.is_empty():
		return Callable()
	var first := Callable()
	for i in statics.size():
		var st := statics[i]
		var allowed := DirectorSpawn.breaker_exit_band(d.data) if i == 0 else {}
		if allowed.is_empty():
			allowed = DirectorSpawn.side_loop_cells(_grid(), d.data.critical_path, st.global_position)
		if allowed.is_empty():
			continue
		var filter := DirectorSpawn.cell_filter(_grid(), allowed)
		if i == 0:
			first = filter
		if st.has_method(&"set_wander_filter"):
			st.call(&"set_wander_filter", filter)
	return first


## Once per second: Calm keeps awake hunters ≥ 30 m (rule 2); chaser caps (rule 6, Null
## exempt): over the cap the farthest chasers retreat 5 s, at it the others are hinted away.
func enforce_caps(_s: Survey) -> void:
	var d := director
	if d.pacing.phase == DirectorPacing.CALM:
		for h in _free_hunters():
			if h.distance_to_player() < Tuning.DIRECTOR_CALM_HUNTER_MIN_DIST:
				_hint_ring(h, Tuning.DIRECTOR_CALM_HUNTER_MIN_DIST, Tuning.DIRECTOR_HINT_AWAY_MAX)
	var ch := chasers()
	ch.sort_custom(func(a: ErrorBase, b: ErrorBase) -> bool: return a.distance_to_player() < b.distance_to_player())
	var ids: Array[StringName] = []
	for h in ch:
		ids.append(h.error_id)
	if not DirectorRules.chaser_cap_reached(ids, d.depth):
		return
	for i in DirectorRules.chasers_over_cap(ids, d.depth):
		ch[i].retreat(Tuning.DIRECTOR_CONTACT_REFUSED_RETREAT)
		cap_retreats += 1
	for h in _free_hunters():
		if DirectorRules.phase_wakes(h.error_id):
			_hint_ring(h, Tuning.DIRECTOR_RELIEF_HINT_AWAY_DIST, Tuning.DIRECTOR_HINT_AWAY_MAX)


## 08 §3, 10 §7 rule 4: every 5 s, does a Static field cut the only route from the player
## to the exit? After 40 s cumulative it is nudged off the critical path at 1.2 m/s.
func static_fairness(interval: float) -> void:
	if not _player_ok() or _grid() == null or director.data.exit_cell == LevelData.NO_CELL:
		return
	var from := _grid().cell_of(director.player.global_position)
	for st in _statics():
		if st.is_dormant():
			continue
		var key := st.get_instance_id()
		if DirectorSpawn.static_cuts_path(_grid(), st.centre(), st.radius, from, director.data.exit_cell):
			_cut_time[key] = float(_cut_time.get(key, 0.0)) + interval
		if float(_cut_time.get(key, 0.0)) >= Tuning.STATIC_FAIR_CUMULATIVE_LIMIT:
			_cut_time[key] = 0.0
			_hint_off_path(st, true)


func cut_time(st: ErrorStatic) -> float:
	return float(_cut_time.get(st.get_instance_id(), 0.0))
