class_name SimBot
extends RefCounted
## The simulated playtest (M1.8, R8): a scripted bot plays one level of a real run
## (run.tscn, the Director and its errors active) through the player's own input actions.
## Headless; no rendering. Used by `sim_run.gd` (CLI) and `test_sim_run.gd` (the gate).
##
## Time: the bot runs at Engine.time_scale 1 (every physics step is 1/60 s, as in play).
## Launch the CLI with `--fixed-fps 60` so the engine steps as fast as the CPU allows
## without real-time sync; the deltas are identical to play, so nothing is scale-dependent.
## Until the level's navigation is ready (a worker bake) the bot throttles to wall time, so
## errors wake as early in game time as they would for a player.
##
## Profiles (`profile`):
## - direct: walks the grid path to the breaker (Powered exits) and into the exit; light
##   off; sprints only while a hunter chases within 15 m.
## - explorer: flashlight on; visits rooms and dead ends off the path before the breaker
##   and the exit; sprints in short bursts every ~25 s and when chased; stops to crank when
##   the charge is low.
## - cautious: flashlight on; walks the path but stops every ~12 s to look behind for
##   2.5 s; cranks when low and nothing is near; when a hunter chases it hides in a nearby
##   hide spot (leaving with the 0.6 s hold once nothing chases), else faces the chaser and
##   backs away along the path; when Echo follows it stands still (08 §6: the trail ends in
##   6 s). M2.7: it picks up items a few cells off its way and uses the counters it has items
##   for (SimBotItems: Polaroid when low, a flare against Static on the only way, a
##   glowstick at a chasing Still, as a lure for Echo, or as light when Flicker is near).
## Explorer and cautious play Flicker's counter (08 §5, M2.7): the flashlight goes off while
## an awake Flicker's group is within 12 m (or it stalks or attaches; the off switch sheds
## it) and back on 18 m clear; while it stalks they leave its lit area by the nearest cell.
## Explorer and cautious know Static's counter: they path around its field when a detour
## exists, otherwise wait outside it (explorer drops a room after 15 s), and walk out of a
## field by the nearest clear cell. `linger` (the explorer's default in sim_run since M2.7)
## makes a profile visit more rooms and dead ends before its objective (7 and 3, up to 360 s;
## without it the explorer visits 4 and 2), so every phase of the sawtooth is met.
## Doors (M2.7): only a closed door the next waypoints pass through is opened; a stuck bot
## also closes an open door off its path whose leaf stands in its corridor.
## The bot never moves the player by hand: when it makes no progress for 2 s it records a
## stuck event, opens doors in reach, repaths and strafes; 30 s without progress ends the
## run as `stuck`. Doors, the breaker and hide spots are used through their Interactable
## within the player's 2.2 m reach (what pressing E there does).
##
## SIMBOT_DEBUG in the environment prints a line per second (position, goal, Static);
## SIMBOT_TRACE one per 0.5 s (position, cell, next waypoints, goal, stuck time).
##
## Result keys: seed, profile, depth, stratum, outcome (exit, dissolved, stuck, timeout,
## relief, error), time_s, contacts (Director), contact_log ([t, error id, instance, phase,
## chased: the error entered Chase/Follow/Stalk since its last contact]),
## contact_violations, contacts_unchased, contacts_in_relief, spawned (error ids on the
## level), has_hunter, has_static, refused, encounters, retreated_chases, notices, phases (deduplicated
## runs), phase_counts, max_intensity, coherence, roster, skipped, stuck_events, hides,
## hide_tries,
## cranks, sprints, explored, peaks_with_chase, nav_wait_s, physics_dt, telemetry_rows,
## stuck_at (when stuck); M2.7: scares (count), scare_kinds, scare_contacts (contacts within
## 5 s after a scare: pillar 3), decisions (noclip, item use, hide, crank start, light switch),
## dpm (decisions per minute), max_decision_gap_s (00 §5: one every 60 s), decision_kinds,
## items_used, pickups.

const RUN_SCENE := "res://scenes/run.tscn"
const PROFILE_DIRECT := &"direct"
const PROFILE_EXPLORER := &"explorer"
const PROFILE_CAUTIOUS := &"cautious"
const PROFILES: Array[StringName] = [PROFILE_DIRECT, PROFILE_EXPLORER, PROFILE_CAUTIOUS]

const ARRIVE_DIST := 0.5
const TIGHT_DIST := 0.15
const BACKOFF_TIME := 0.8
const LINE_GAIN := 4.0
const DOOR_APPROACH := 0.7          # m either side of a doorway's midpoint
const EXPLORE_REACHED := 1.5
const FIELD_GIVE_UP := 15.0
const REACH := 2.0                  # within the 2.2 m interaction ray
const STUCK_WINDOW := 2.0
const STUCK_MIN_MOVE := 0.3
const STUCK_ABORT := 30.0
const WIGGLE_TIME := 0.6
const SPRINT_CHASE_DIST := 15.0
const REPATH_INTERVAL := 2.0
const EXPLORE_ROOMS := 4
const EXPLORE_DEAD_ENDS := 2
const EXPLORE_MAX_S := 300.0
const LINGER_ROOMS := 7
const LINGER_DEAD_ENDS := 3
const LINGER_MAX_S := 360.0
const ECHO_STILL_MAX := 15.0
const SCARE_CONTACT_WINDOW := 5.0
const SIDESTEP := 1.0
const SIDESTEP_HOLD := 3.0
const FLICKER_DARK_DIST := 12.0
const FLICKER_CLEAR_DIST := 18.0
const SPRINT_BURST_EVERY := 25.0
const SPRINT_BURST_TIME := 3.0
const CRANK_BELOW := 35.0
const CRANK_UNTIL := 90.0
const LOOK_BACK_EVERY := 12.0
const LOOK_BACK_TIME := 2.5
const HIDE_SEARCH_CELLS := 12
const HIDE_CHASE_DIST := 20.0
const HIDE_MIN_TIME := 5.0
const HIDE_QUIET_TIME := 6.0
const HIDE_MAX_TIME := 40.0
const LEAVE_HOLD := 0.8
const MOVE_KEY_DOT := 0.38
## Time comparisons on physics-frame timestamps.
const EPS := 0.02

var tree: SceneTree
var host: Node
var run: Run
var director: Director
var profile: StringName = PROFILE_DIRECT
var depth: int = 1
var max_seconds: float = 600.0
var csv_path: String = ""
## End the run once the Director has entered Relief (the gate test).
var stop_after_relief: bool = false
## Any profile visits the explorer's rooms before its objective (longer levels).
var linger: bool = false

var _rng: RandomNumberGenerator
var _t: float = 0.0
var _waypoints: Array[Vector3] = []
## Per waypoint: arrive within TIGHT_DIST (lined up on a doorway) instead of ARRIVE_DIST.
var _tight: Array[bool] = []
var _prev_wp: Vector3 = Vector3.ZERO
var _backoff_left: float = 0.0
var _goal: Vector3 = Vector3.INF
var _repath_left: float = 0.0
var _stuck_left: float = STUCK_WINDOW
var _stuck_from: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _stuck_events: int = 0
var _wiggle_left: float = 0.0
var _wiggle_side: float = 1.0
var _targets: Array[Vector2i] = []
var _explored: int = 0
var _stuck_at_target: int = 0
var _sprint_next: float = 0.0
var _sprint_left: float = 0.0
var _sprints: int = 0
var _cranking: bool = false
var _cranks: int = 0
var _look_next: float = 0.0
var _look_left: float = 0.0
var _hide_spot: HideSpot = null
var _hidden_for: float = 0.0
var _quiet_for: float = 0.0
var _leave_left: float = 0.0
var _hides: int = 0
var _hide_tries: int = 0
var _escape_goal: Vector3 = Vector3.INF
var _escape_left: float = 0.0
## Static cells on a path without a detour, and how long the bot has waited for them.
var _field_cells: Dictionary = {}
var _field_wait: float = 0.0
var _last_dir: Vector3 = Vector3.FORWARD
var _contact_log: Array = []
var _peak_index: int = -1
var _peaks_chased: int = 0
var _peak_marked: bool = false
var _watched: Dictionary = {}
## Error instance id -> it entered a chasing state since its last contact.
var _chased_since: Dictionary = {}
## Decision events [t, kind] (M2.7: the 00 §5 proxy), the cautious bot's belt, and the item
## it is fetching.
var _decisions: Array = []
var items := SimBotItems.new()
## The Null counter and its numbers (M2.6).
var nul := SimBotNull.new()
var _pickup: ItemPickup = null
var _echo_still: float = 0.0
## The light went off for Flicker (back on when clear); where the bot leaves a lit area to.
var _dark_for_flicker: bool = false
var _flicker_goal: Vector3 = Vector3.INF
## Seconds the inserted step-around waypoints are kept (no periodic repath meanwhile).
var _sidestep_left: float = 0.0
## R14: soft-wall crossings in the current plan (near cell -> direction), Pursuit only.
var _soft_cross: Dictionary = {}
## R14b route hysteresis in the Pursuit: the route being followed (from the cell it was
## planned at), its soft crossings and its goal cell.
var _route: Array[Vector2i] = []
var _route_soft: Dictionary = {}
var _route_goal: Vector2i = LevelData.NO_CELL


## Plays `run_seed` at `depth` (first Descent off, so depth 1 carries a hunter).
func play(run_seed: int) -> Dictionary:
	_rng = Seeds.rng(Seeds.derive(run_seed, "simbot:%s" % profile))
	Engine.time_scale = 1.0
	var meta := GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	if depth > 1:
		GameState.run.depth = depth
		GameState.run.max_depth = depth
	run = (load(RUN_SCENE) as PackedScene).instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 0.5
	host.add_child(run)
	var result := {&"seed": run_seed, &"profile": profile, &"depth": depth, &"outcome": &"error", &"time_s": 0.0}
	var t0 := Time.get_ticks_msec()
	while run.phase != Run.PHASE_PLAYING and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	var level := run.level
	director = level.find_child("Director", true, false) as Director if level != null else null
	if director == null:
		result[&"error"] = "no Director on the level"
		await _teardown(meta)
		return result
	result[&"stratum"] = GameState.stratum_for(depth)
	result[&"nav_wait_s"] = snappedf(await _wait_navigation(), 0.1)
	_plan_profile()
	items.bot = self
	nul.bot = self
	var on_item := func(kind: StringName) -> void: _decide("item:%s" % kind)
	var on_noclip := func(_k: StringName, _a: Vector3, _b: Vector3) -> void: _decide("noclip")
	EventBus.item_used.connect(on_item)
	run.player.noclip_committed.connect(on_noclip)
	var cause: Array[String] = [""]
	run.player.dissolved.connect(func(c: StringName) -> void: cause[0] = String(c))
	var max_i := 0.0
	var outcome := &"timeout"
	while _t < max_seconds:
		await tree.physics_frame
		var dt := tree.root.get_physics_process_delta_time() * Engine.time_scale
		_t += dt
		_watch_errors()
		nul.tick(_t, dt)
		max_i = maxf(max_i, director.intensity)
		_watch_peaks()
		if run.phase == Run.PHASE_DISSOLVING or run.phase == Run.PHASE_ENDED:
			outcome = &"dissolved"
			break
		if run.phase != Run.PHASE_PLAYING:
			outcome = &"exit"
			break
		if stop_after_relief and director.pacing.history.has(DirectorPacing.RELIEF):
			outcome = &"relief"
			break
		_think(dt)
		if OS.has_environment("SIMBOT_TRACE") and fmod(_t, 0.5) < dt:
			print("trace t=%.1f p=%s cell=%s wp=%s tight=%s goal=%s stuck=%.0f ev=%d" % [_t, run.player.global_position.snappedf(0.01),
				run.data.grid.cell_of(run.player.global_position), _waypoints.slice(0, 3), _tight.slice(0, 3),
				run.data.grid.cell_of(_goal), _stuck_time, _stuck_events])
		if OS.has_environment("SIMBOT_DEBUG") and fmod(_t, 1.0) < dt:
			for n in tree.get_nodes_in_group(ErrorBase.GROUP):
				var st := n as ErrorStatic
				if st != null:
					print("dbg t=%.0f p=%s goal=%s st=%s %s r=%.1f inside=%s coh=%.1f wps=%d crank=%s" % [_t, run.player.global_position.snappedf(0.1),
						run.data.grid.cell_of(_goal), st.centre().snappedf(0.1), st.state, st.radius, st.inside, run.player.coherence, _waypoints.size(), _cranking])
		if _stuck_time >= STUCK_ABORT:
			outcome = &"stuck"
			break
	PlayerFixture.release_all()
	items.release()
	EventBus.item_used.disconnect(on_item)
	if is_instance_valid(run.player) and run.player.noclip_committed.is_connected(on_noclip):
		run.player.noclip_committed.disconnect(on_noclip)
	_scare_results(result)
	nul.results(result)
	result[&"cause"] = cause[0]
	result[&"outcome"] = outcome
	result[&"time_s"] = snappedf(_t, 0.1)
	result[&"contacts"] = director.contacts
	result[&"contact_log"] = _contact_log.duplicate(true)
	result[&"contact_violations"] = contact_violations(_contact_log)
	result[&"contacts_unchased"] = _contact_log.filter(func(e: Array) -> bool: return not bool(e[4])).size()
	result[&"contacts_in_relief"] = _contact_log.filter(func(e: Array) -> bool:
		return StringName(e[3]) == DirectorPacing.RELIEF).size()
	var spawned: Array[String] = []
	for e in director.errors:
		if is_instance_valid(e):
			spawned.append(String(e.error_id))
	result[&"spawned"] = spawned
	result[&"has_hunter"] = spawned.any(func(id: String) -> bool: return DirectorRules.is_hunter(StringName(id)))
	result[&"has_static"] = spawned.has("static")
	result[&"refused"] = director.refused
	result[&"encounters"] = director.encounters
	result[&"retreated_chases"] = director.retreated_chases
	result[&"phases"] = _runs(director.pacing.history)
	result[&"phase_counts"] = phase_counts(director.pacing.history)
	result[&"max_intensity"] = snappedf(max_i, 0.01)
	result[&"notices"] = GameState.run.encounters.duplicate()
	result[&"coherence"] = snappedf(run.player.coherence, 0.1)
	result[&"roster"] = director.roster.duplicate()
	result[&"skipped"] = director.skipped.duplicate()
	result[&"peaks_with_chase"] = _peaks_chased
	result[&"stuck_events"] = _stuck_events
	result[&"hides"] = _hides
	result[&"hide_tries"] = _hide_tries
	result[&"cranks"] = _cranks
	result[&"sprints"] = _sprints
	result[&"explored"] = _explored
	result[&"telemetry_rows"] = director.telemetry.size()
	# Time scale 1: every step is the project's physics step, as in play.
	result[&"physics_dt"] = snappedf(tree.root.get_physics_process_delta_time() * Engine.time_scale, 0.0001)
	if outcome == &"stuck":
		result[&"stuck_at"] = _stuck_report()
	if not csv_path.is_empty():
		director.telemetry.dump_csv(csv_path)
	await _teardown(meta)
	return result


## M2.7 result keys: the scares that ran, contacts soon after one, and the decision proxy.
func _scare_results(result: Dictionary) -> void:
	var fired: Array = director.scares.fired
	result[&"scares"] = fired.size()
	var kinds := {}
	for f: Dictionary in fired:
		kinds[String(f[&"kind"])] = int(kinds.get(String(f[&"kind"]), 0)) + 1
	result[&"scare_kinds"] = kinds
	# Scare times are Director level time; the bot's clock also counts the navigation wait.
	var offset := float(result.get(&"nav_wait_s", 0.0))
	var times: Array = fired.map(func(f: Dictionary) -> float: return float(f[&"time"]))
	result[&"scare_contacts"] = scare_contacts(times, _contact_log.map(func(e: Array) -> float: return float(e[0]) - offset))
	var dt: Array = _decisions.map(func(e: Array) -> float: return float(e[0]))
	result[&"decisions"] = _decisions.size()
	result[&"dpm"] = snappedf(_decisions.size() / maxf(_t / 60.0, 0.001), 0.01)
	result[&"max_decision_gap_s"] = snappedf(max_gap(dt, _t), 0.1)
	result[&"decision_kinds"] = _kinds(_decisions)
	result[&"items_used"] = items.uses.duplicate()
	result[&"pickups"] = items.pickups


## Contacts (seconds) that land within 5 s after a scare (seconds): pillar 3 says none should.
static func scare_contacts(scare_times: Array, contact_times: Array) -> int:
	var n := 0
	for c in contact_times:
		for s in scare_times:
			if float(c) >= float(s) and float(c) - float(s) <= SCARE_CONTACT_WINDOW:
				n += 1
				break
	return n


## The longest stretch (s) with no decision between 0 and `end`, decisions at `times`.
static func max_gap(times: Array, end: float) -> float:
	var sorted := times.duplicate()
	sorted.sort()
	var prev := 0.0
	var best := 0.0
	for t in sorted:
		best = maxf(best, float(t) - prev)
		prev = float(t)
	return maxf(best, end - prev)


static func _kinds(log: Array) -> Dictionary:
	var out := {}
	for e: Array in log:
		var k := String(e[1]).get_slice(":", 0)
		out[k] = int(out.get(k, 0)) + 1
	return out


func _decide(kind: String) -> void:
	_decisions.append([snappedf(_t, 0.01), kind])


## Public for SimBotItems.
func tap(action: StringName) -> void:
	_tap(action)


func time() -> float:
	return _t


func hunter_within(dist: float) -> bool:
	return _hunter_within(dist)


func _teardown(meta: MetaState) -> void:
	PlayerFixture.release_all()
	if run != null and is_instance_valid(run):
		run.queue_free()
	for i in 3:
		await tree.process_frame
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = meta


## Holds the bot still, at wall-clock pace, until every error's navigation is ready (or
## 30 s of wall time). Returns the game seconds waited.
func _wait_navigation() -> float:
	var t0 := Time.get_ticks_msec()
	var waited := 0.0
	while Time.get_ticks_msec() - t0 < 30000:
		var ready := true
		for e in director.errors:
			if is_instance_valid(e) and not e.navigation_ready:
				ready = false
		if ready:
			break
		var before := Time.get_ticks_msec()
		await tree.physics_frame
		var dt := tree.root.get_physics_process_delta_time()
		waited += dt
		_t += dt
		var spent := Time.get_ticks_msec() - before
		if spent < int(dt * 1000.0):
			OS.delay_msec(int(dt * 1000.0) - spent)
	return waited


# --- checks (pure, so a test can make them fail) ----------------------------------------------

## 05 §9 rules 4 and 5 over a contact log of [t (s), error id, instance id] in time order:
## at least 3 s between any two contacts, at least 20 s (Satiated) between two contacts by
## the same error. Returns one line per violation.
static func contact_violations(log: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var last_by: Dictionary = {}
	for i in log.size():
		var e: Array = log[i]
		var t := float(e[0])
		if i > 0:
			var prev := float((log[i - 1] as Array)[0])
			if t - prev < Tuning.CONTACT_EXCLUSIVITY_TIME - EPS:
				out.append("exclusivity: contacts %.2f s apart at %.1f s" % [t - prev, t])
		var key: Variant = e[2]
		if last_by.has(key) and t - float(last_by[key]) < Tuning.ERROR_SATIATED_TIME - EPS:
			out.append("satiated: %s contacted again %.2f s later at %.1f s" % [e[1], t - float(last_by[key]), t])
		last_by[key] = t
	return out


## The phase a contact landed in: the Director hears the contact first and may already have
## entered Relief for it (phase_time still 0); then it is the phase before.
static func phase_before_contact(p: DirectorPacing) -> StringName:
	if p.phase == DirectorPacing.RELIEF and p.phase_time == 0.0 and p.history.size() >= 2:
		return p.history[p.history.size() - 2]
	return p.phase


## Entries of each phase in a Director history.
static func phase_counts(history: Array[StringName]) -> Dictionary:
	var out := {}
	for p in history:
		out[p] = int(out.get(p, 0)) + 1
	return out


static func _runs(history: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in history:
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


## Counts the Peaks during which a hunter actually chased (Peak pressure, cp-04 #19).
func _watch_peaks() -> void:
	var h := director.pacing.history
	if director.phase != DirectorPacing.PEAK:
		return
	if h.size() != _peak_index:
		_peak_index = h.size()
		_peak_marked = false
	if not _peak_marked and _chaser() != null:
		_peak_marked = true
		_peaks_chased += 1


## Logs each error's approved contacts (the error's own signal, not the Director's count).
func _watch_errors() -> void:
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var e := n as ErrorBase
		if e == null or _watched.has(e.get_instance_id()):
			continue
		_watched[e.get_instance_id()] = true
		var id := e.error_id
		var key := e.get_instance_id()
		e.state_changed.connect(func(_from: StringName, to: StringName) -> void:
			if DirectorRules.is_chasing_state(to):
				_chased_since[key] = true)
		e.contacted_player.connect(func(_cost: float) -> void:
			_contact_log.append([snappedf(_t, 0.001), String(id), key, String(phase_before_contact(director.pacing)),
				bool(_chased_since.get(key, false))])
			_chased_since[key] = false)


# --- the bot ---------------------------------------------------------------------------------

func _plan_profile() -> void:
	var p := run.player
	if profile != PROFILE_DIRECT:
		# Light on: one press of the flashlight key.
		_tap(&"flashlight")
	if profile == PROFILE_EXPLORER or linger:
		_targets = _explore_targets(LINGER_ROOMS if linger else EXPLORE_ROOMS, LINGER_DEAD_ENDS if linger else EXPLORE_DEAD_ENDS)
		_sprint_next = _rng.randf_range(10.0, SPRINT_BURST_EVERY)
	if profile == PROFILE_CAUTIOUS:
		_look_next = _rng.randf_range(6.0, LOOK_BACK_EVERY)
	_stuck_from = p.global_position
	_prev_wp = p.global_position


## Off-path rooms and dead ends, visited nearest first.
func _explore_targets(rooms_n: int, ends_n: int) -> Array[Vector2i]:
	var grid := run.data.grid
	var pool: Array[Vector2i] = []
	var rooms := grid.rooms()
	for r: RoomData in rooms:
		if r.kind == RoomData.SPAWN or r.kind == RoomData.EXIT:
			continue
		var c := r.center()
		if grid.is_walkable(c) and not grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			pool.append(c)
	_shuffle(pool)
	var out: Array[Vector2i] = pool.slice(0, rooms_n)
	var ends: Array[Vector2i] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if grid.has_flag(c, LevelGrid.F_DEAD_END) and not grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			ends.append(c)
	_shuffle(ends)
	out.append_array(ends.slice(0, ends_n))
	return out


func _shuffle(a: Array[Vector2i]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


func _think(dt: float) -> void:
	var p := run.player
	items.tick(dt)
	_use_in_reach()
	if p.is_hidden() or (_hide_spot != null and _leave_left > 0.0):
		_hidden_tick(dt)
		return
	var chaser := _chaser()
	var chase_d := chaser.distance_to_player() if chaser != null else INF
	if profile != PROFILE_DIRECT and chaser == null and _in_static():
		# Static's counter: get out of the field the short way, then go around.
		_escape_left -= dt
		if _escape_goal == Vector3.INF or _escape_left <= 0.0 \
				or DirectorSpawn.flat_dist(p.global_position, _escape_goal) < ARRIVE_DIST:
			# Re-aimed every second: the field drifts (and searches toward steps).
			_escape_goal = _escape_cell()
			_escape_left = 1.0
		if _escape_goal != Vector3.INF:
			if _cranking:
				_cranking = false
				Input.action_release(&"crank")
			_follow(_escape_goal, dt, false)
			return
	_escape_goal = Vector3.INF
	if items.busy():
		_halt()
		return
	if profile != PROFILE_DIRECT and nul.pursuing():
		# Null's counter (08 §7): straight for the Threshold, never stopping, sprinting
		# inside its radius; _plan_path routes around it when the maze allows.
		_targets.clear()
		if _cranking:
			_cranking = false
			Input.action_release(&"crank")
		_follow(_goal_now(), dt, nul.near(SimBotNull.PRESS))
		return
	if profile != PROFILE_DIRECT and _flicker_counter(dt):
		return
	match profile:
		PROFILE_EXPLORER:
			_explorer(dt, chaser, chase_d)
		PROFILE_CAUTIOUS:
			_cautious(dt, chaser, chase_d)
		_:
			_follow(_goal_now(), dt, chase_d < SPRINT_CHASE_DIST)


func _explorer(dt: float, chaser: ErrorBase, chase_d: float) -> void:
	var p := run.player
	var f := p.flashlight
	if _cranking:
		if f.charge >= CRANK_UNTIL or chaser != null or _in_static():
			_cranking = false
			Input.action_release(&"crank")
		else:
			_halt()
			return
	elif f.on and f.charge < CRANK_BELOW and chaser == null and not _in_static():
		_cranking = true
		_cranks += 1
		_decide("crank")
		Input.action_press(&"crank")
		_halt()
		return
	_sprint_next -= dt
	if _sprint_next <= 0.0:
		_sprint_next = _rng.randf_range(SPRINT_BURST_EVERY * 0.6, SPRINT_BURST_EVERY * 1.4)
		_sprint_left = SPRINT_BURST_TIME
		_sprints += 1
	_sprint_left -= dt
	_follow(_goal_now(), dt, _sprint_left > 0.0 or chase_d < SPRINT_CHASE_DIST)


func _cautious(dt: float, chaser: ErrorBase, chase_d: float) -> void:
	var p := run.player
	var f := p.flashlight
	if chaser != null and chase_d < HIDE_CHASE_DIST:
		if _cranking:
			_cranking = false
			Input.action_release(&"crank")
		if chaser.error_id == &"echo" and _echo_still < ECHO_STILL_MAX:
			# 08 §6: stop and the trail ends in 6 s; throw a lure ahead if there is one.
			_echo_still += dt
			var away := p.global_position - chaser.body_position()
			_halt(Vector3(away.x, 0.0, away.z))
			items.maybe_glowstick(chaser, chase_d)
			return
		items.maybe_glowstick(chaser, chase_d)
		if _hide_spot == null:
			_hide_spot = _nearby_spot()
			if _hide_spot != null:
				_hide_tries += 1
		if _hide_spot != null:
			_follow(_hide_spot.exit_transform().origin, dt, false)
			return
		# No spot near: face the chaser (an observed Still cannot move) and back away.
		var to := chaser.body_position() - p.global_position
		_follow(_goal_now(), dt, false, Vector3(to.x, 0.0, to.z))
		return
	_hide_spot = null
	if chaser == null:
		_echo_still = 0.0
	if items.maybe_polaroid(_hunter_within(HIDE_CHASE_DIST)) or items.maybe_flare(_field_wait):
		_halt()
		return
	if _pickup == null or not is_instance_valid(_pickup) or _pickup.picked:
		_pickup = items.nearby_pickup()
	if _pickup != null and not _cranking:
		if items.take_in_reach(_pickup):
			_pickup = null
		else:
			_follow(_pickup.global_position, dt, false)
			return
	if _cranking:
		if f.charge >= CRANK_UNTIL or _in_static():
			_cranking = false
			Input.action_release(&"crank")
		else:
			_halt()
			return
	elif f.on and f.charge < CRANK_BELOW and not _hunter_within(HIDE_CHASE_DIST) and not _in_static():
		_cranking = true
		_cranks += 1
		_decide("crank")
		Input.action_press(&"crank")
		_halt()
		return
	_look_next -= dt
	if _look_left > 0.0:
		_look_left -= dt
		_halt(-_last_dir)
		return
	if _look_next <= 0.0:
		_look_next = _rng.randf_range(LOOK_BACK_EVERY * 0.7, LOOK_BACK_EVERY * 1.3)
		_look_left = LOOK_BACK_TIME
	_follow(_goal_now(), dt, false)


## Hidden: wait until nothing chases for a while, then hold interact to leave.
func _hidden_tick(dt: float) -> void:
	var p := run.player
	_release_moves()
	if _leave_left > 0.0:
		_leave_left -= dt
		Input.action_press(&"interact")
		if _leave_left <= 0.0 or not p.is_hidden():
			Input.action_release(&"interact")
			_leave_left = 0.0
			if not p.is_hidden():
				_hide_spot = null
		return
	_hidden_for += dt
	_quiet_for = _quiet_for + dt if _chaser() == null else 0.0
	if (_hidden_for >= HIDE_MIN_TIME and _quiet_for >= HIDE_QUIET_TIME) or _hidden_for >= HIDE_MAX_TIME:
		Input.action_release(&"interact")
		_leave_left = LEAVE_HOLD
	_stuck_from = p.global_position
	_stuck_left = STUCK_WINDOW


## Doors on the way, the breaker and the chosen hide spot, through their Interactables.
func _use_in_reach() -> void:
	var p := run.player
	if p.is_hidden():
		return
	if run.breaker != null and not run.breaker.is_thrown \
			and DirectorSpawn.flat_dist(p.global_position, run.breaker.global_position) < REACH:
		run.breaker.interactable.interact(p)
		# Variant B: the first interact inserts the carried fuse, the next throws the lever.
		if run.breaker.fuse_in and not run.breaker.is_thrown:
			run.breaker.interactable.interact(p)
	# M2.9 locks: the fuse (Variant B) and the keycard (Keyed) are picked up, then swiped.
	var want := _lock_pickup()
	if want != null and DirectorSpawn.flat_dist(p.global_position, want.global_position) < REACH:
		want.interactable.interact(p)
	if run.exit != null and run.exit.reader != null and not run.exit.reader.accepted and p.inventory.keycard \
			and DirectorSpawn.flat_dist(p.global_position, run.exit.reader.global_position) < REACH + 0.5:
		run.exit.reader.interactable.interact(p)
	if _hide_spot != null and DirectorSpawn.flat_dist(p.global_position, _hide_spot.global_position) < REACH:
		if _hide_spot.interactable.can_interact(p):
			_hide_spot.interactable.interact(p)
			if p.is_hidden():
				_hides += 1
				_decide("hide")
				_hidden_for = 0.0
				_quiet_for = 0.0
				_clear_path()
				return
	if _waypoints.is_empty():
		return
	for n in tree.get_nodes_in_group(&"doors"):
		var d := n as Door
		if d == null or d.is_open or not run.level.is_ancestor_of(d):
			continue
		# Only a door the path goes through (M2.7): opening one beside the path swings its
		# leaf into the corridor (a 1-cell corridor is then blocked).
		if DirectorSpawn.flat_dist(d.global_position, p.global_position) < REACH and _door_on_path(d):
			d.interactable.interact(p)


## The next room to explore (explorer, or any profile with `linger`), else the objective.
func _goal_now() -> Vector3:
	var p := run.player
	while not _targets.is_empty() and _t < (LINGER_MAX_S if linger else EXPLORE_MAX_S):
		var c := _targets[0]
		var here := run.data.grid.cell_of(p.global_position)
		if _field_wait > FIELD_GIVE_UP:
			# Static sits on the only way there: explore elsewhere.
			_targets.remove_at(0)
			_field_wait = 0.0
		elif DirectorSpawn.flat_dist(p.global_position, run.data.grid.world_of(c)) < EXPLORE_REACHED \
				or (here == c and _stuck_events > _stuck_at_target):
			_targets.remove_at(0)
			_explored += 1
			_stuck_at_target = _stuck_events
		else:
			return run.data.grid.world_of(c)
	return _objective()


## The pickup the lock still needs (07 §6): the Variant B fuse while the socket is empty and
## the belt holds none, or the keycard while the reader has not accepted one. Null otherwise.
func _lock_pickup() -> ItemPickup:
	var kind := &""
	if run.breaker != null and not run.breaker.is_thrown and not run.breaker.fuse_in and not run.player.inventory.has(&"fuse"):
		kind = &"fuse"
	elif run.exit != null and run.exit.reader != null and not run.exit.reader.accepted and not run.player.inventory.keycard:
		kind = &"keycard"
	if kind == &"":
		return null
	for n in tree.get_nodes_in_group(ItemPickup.GROUP):
		var it := n as ItemPickup
		if it != null and not it.picked and it.kind == kind and run.level.is_ancestor_of(it):
			return it
	return null


func _objective() -> Vector3:
	var want := _lock_pickup()
	if want != null:
		return want.global_position
	if run.breaker != null and not run.breaker.is_thrown and run.data.breaker_cell != LevelData.NO_CELL:
		return run.data.grid.world_of(run.data.breaker_cell)
	if run.exit != null:
		return run.exit.walk_in_point()
	return run.data.grid.world_of(run.data.exit_cell)


## Walks the grid path to `goal`, looking along the way (or along `look` when given).
func _follow(goal: Vector3, dt: float, sprint: bool, look: Vector3 = Vector3.ZERO) -> void:
	var p := run.player
	var grid := run.data.grid
	if nul.soft_active():
		# R14: a soft-wall crossing under way (SimBotNull holds noclip facing the wall).
		_halt()
		if nul.soft_tick(dt):
			return
		_clear_path()
		_soft_cross = {}
	_repath_left -= dt
	# No periodic repath inside a doorway: the cell under the body flips at the edge.
	var in_doorway := not _tight.is_empty() and _tight[0]
	_sidestep_left -= dt
	if goal != _goal or (_repath_left <= 0.0 and not in_doorway and _sidestep_left <= 0.0) or _waypoints.is_empty():
		_goal = goal
		_repath_left = SimBotNull.REPATH if profile != PROFILE_DIRECT and nul.pursuing() else REPATH_INTERVAL
		_plan_path(goal)
	while not _waypoints.is_empty() and DirectorSpawn.flat_dist(p.global_position, _waypoints[0]) \
			< (TIGHT_DIST if _tight[0] else ARRIVE_DIST):
		_prev_wp = _waypoints[0]
		_waypoints.remove_at(0)
		_tight.remove_at(0)
	if not _waypoints.is_empty() and _field_cells.has(grid.cell_of(_waypoints[0])) and not _in_static() \
			and not nul.near(SimBotNull.PRESS):
		_field_wait += dt
		_halt()
		return
	_field_wait = 0.0
	var here := grid.cell_of(p.global_position)
	if _soft_cross.has(here) and not _waypoints.is_empty() \
			and grid.cell_of(_waypoints[0]) == here + LevelGrid.DIRS[int(_soft_cross[here])] \
			and DirectorSpawn.flat_dist(p.global_position, grid.world_of(here)) < SimBotNull.SOFT_AT:
		# R14: at the near cell's centre: noclip through the soft wall.
		if nul.soft_allowed():
			_decide("noclip_soft")
			nul.begin_soft(here, int(_soft_cross[here]))
			_halt()
			nul.soft_tick(dt)
			return
		_soft_cross = {}
		_clear_path()
	var waiting := run.exit != null and goal.is_equal_approx(_exit_point()) and not run.exit.is_open()
	if _waypoints.is_empty() or (waiting and _waypoints.size() <= 1):
		_halt()
		return
	var w := _waypoints[0]
	var dir := Vector3(w.x - p.global_position.x, 0.0, w.z - p.global_position.z).normalized()
	if _tight[0]:
		# Through a doorway: hold the line from the last waypoint (1 m opening, 0.35 m body).
		var seg := Vector3(w.x - _prev_wp.x, 0.0, w.z - _prev_wp.z)
		if seg.length() > 0.2:
			seg = seg.normalized()
			var off := Vector3(p.global_position.x - _prev_wp.x, 0.0, p.global_position.z - _prev_wp.z)
			var lateral := off - seg * off.dot(seg)
			dir = (seg - lateral * LINE_GAIN).normalized()
	if _backoff_left > 0.0:
		# Recovery: back toward the last waypoint reached, then try again.
		_backoff_left -= dt
		var back := Vector3(_prev_wp.x - p.global_position.x, 0.0, _prev_wp.z - p.global_position.z)
		if back.length() > 0.1:
			dir = back.normalized()
	elif _wiggle_left > 0.0:
		_wiggle_left -= dt
		dir = (dir + dir.cross(Vector3.UP) * _wiggle_side * 1.5).normalized()
	_last_dir = dir
	_drive(dir, look if look != Vector3.ZERO else dir, sprint and look == Vector3.ZERO)
	_check_stuck(dt)


## Cell centres along the grid path; a step through a wall opening (a doorway, an edge
## that is not open floor) is taken from the centre of the cell before it, through the
## edge's midpoint, so the body lines up with the opening.
func _plan_path(goal: Vector3) -> void:
	var p := run.player
	var grid := run.data.grid
	_clear_path()
	var prev := grid.cell_of(p.global_position)
	var cells := ErrorStatic.cell_path(grid, prev, grid.cell_of(goal))
	_field_cells = {}
	_soft_cross = {}
	if profile != PROFILE_DIRECT:
		# Static's counter is to go around (08 §3): take a detour when one exists, else
		# wait outside the field for it to drift (_follow). R14: in the Pursuit, soft walls
		# count as steps when the bot can pay for them (the shorter way wins).
		var soft := nul.soft_allowed()
		var fields := _static_cells()
		var both := fields.duplicate()
		both.merge(nul.cells(grid))
		var around := _path_avoiding(prev, grid.cell_of(goal), both, soft)
		if around.is_empty() and both.size() != fields.size():
			around = _path_avoiding(prev, grid.cell_of(goal), fields, soft)
		if not around.is_empty():
			cells = around
			if nul.pursuing():
				# R14b: keep the route around Null unless the new one is clearly better.
				var kept := _kept_route(prev, grid.cell_of(goal), cells, fields)
				if kept.is_empty():
					_route = [prev] as Array[Vector2i]
					_route.append_array(cells)
					_route_soft = _soft_cross.duplicate()
					_route_goal = grid.cell_of(goal)
				else:
					cells = kept
					_soft_cross = _route_soft.duplicate()
		else:
			_field_cells = fields
			_soft_cross = {}
			_route = [] as Array[Vector2i]
	if not _soft_cross.is_empty() and _soft_cross.has(prev):
		# The first crossing is from the bot's own cell: walk to its centre first.
		_push_wp(grid.world_of(prev), false)
	for c in cells:
		var dir := LevelGrid.DIRS.find(c - prev)
		if dir >= 0 and int(_soft_cross.get(prev, -1)) == dir:
			# A soft wall (R14): from the near cell's centre straight through (no doorway pair).
			_push_wp(grid.world_of(c), false)
			prev = c
			continue
		if dir >= 0 and grid.in_bounds(prev) and grid.wall(prev, dir) != LevelGrid.NONE:
			var a := grid.world_of(prev)
			var b := grid.world_of(c)
			var mid := (a + b) * 0.5
			var l := (b - a).normalized()
			_push_wp(mid - l * DOOR_APPROACH, true)
			_push_wp(mid + l * DOOR_APPROACH, true)
		_push_wp(grid.world_of(c), false)
		prev = c
	_push_wp(goal, false)


## R14b: the rest of the kept Pursuit route from `here` (empty to take `fresh`): the route
## is kept while it still leads to `goal`, the bot is on it, it can still be walked (open
## steps, or its soft crossings while noclip is affordable and not refused), it stays out
## of Static's fields and of Null's 2 m core, and `fresh` is not clearly shorter (under
## SimBotNull.ROUTE_SWITCH of its length).
func _kept_route(here: Vector2i, goal: Vector2i, fresh: Array[Vector2i], fields: Dictionary) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if _route_goal != goal:
		return none
	var k := _route.find(here)
	if k < 0 or k >= _route.size() - 1:
		return none
	var rest: Array[Vector2i] = _route.slice(k + 1)
	if float(fresh.size()) < float(rest.size()) * SimBotNull.ROUTE_SWITCH:
		return none
	var grid := run.data.grid
	var prev := here
	for c in rest:
		if fields.has(c) or nul.in_core(grid.world_of(c)):
			return none
		var d := LevelGrid.DIRS.find(c - prev)
		if d < 0:
			return none
		if not grid.can_step(prev, d) and (int(_route_soft.get(prev, -1)) != d or not nul.soft_allowed() \
				or not SimBotNull.soft_edge(grid, prev, d, nul.bad_soft)):
			return none
		prev = c
	return rest


## Walkable cells inside an awake Static's field (plus a body's margin).
func _static_cells() -> Dictionary:
	var grid := run.data.grid
	var out := {}
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var st := n as ErrorStatic
		if st == null or st.is_dormant():
			continue
		var r := st.radius + Tuning.PLAYER_CAPSULE_RADIUS + 0.25
		var cc := grid.cell_of(st.centre())
		var span := ceili(r / Tuning.GRID_CELL_SIZE) + 1
		for dz in range(-span, span + 1):
			for dx in range(-span, span + 1):
				var c := cc + Vector2i(dx, dz)
				if grid.in_bounds(c) and DirectorSpawn.flat_dist(grid.world_of(c), st.centre()) < r:
					out[c] = true
	return out


## BFS over the grid that never enters `blocked` (except the goal), but may leave it when
## it starts inside (the way out of a field first); empty when there is no such path.
## With `soft` (R14) a soft wall between walkable cells is a step too; the crossings the
## path takes are recorded in `_soft_cross`.
func _path_avoiding(from: Vector2i, to: Vector2i, blocked: Dictionary, soft: bool = false) -> Array[Vector2i]:
	var g := run.data.grid
	var out: Array[Vector2i] = []
	_soft_cross = {}
	if (blocked.is_empty() and not soft) or not g.in_bounds(from) or not g.in_bounds(to):
		return out
	var via_soft := {}
	var prev := {from: from}
	var escaping := {from: blocked.has(from)}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			break
		for d in 4:
			var through := soft and SimBotNull.soft_edge(g, c, d, nul.bad_soft)
			if not through and not g.can_step(c, d):
				continue
			var n := c + LevelGrid.DIRS[d]
			if prev.has(n):
				continue
			if blocked.has(n) and n != to and not bool(escaping[c]):
				continue
			prev[n] = c
			if through:
				via_soft[n] = d
			escaping[n] = bool(escaping[c]) and blocked.has(n)
			queue.append(n)
	if not prev.has(to) or from == to:
		return out
	var k := to
	while k != from:
		out.push_front(k)
		if via_soft.has(k):
			_soft_cross[prev[k]] = via_soft[k]
		k = prev[k]
	return out


func _push_wp(w: Vector3, tight: bool) -> void:
	_waypoints.append(w)
	_tight.append(tight)


func _clear_path() -> void:
	_waypoints.clear()
	_tight.clear()


func _exit_point() -> Vector3:
	if run.exit != null:
		return run.exit.walk_in_point()
	return run.data.grid.world_of(run.data.exit_cell)


## Faces `look` (mouse look) and presses the move keys nearest to `move` in that frame.
func _drive(move: Vector3, look: Vector3, sprint: bool) -> void:
	var p := run.player
	var l := Vector3(look.x, 0.0, look.z)
	if l.length_squared() > 0.0001:
		p.rotation = Vector3(0.0, atan2(-l.x, -l.z), 0.0)
	var fwd := -p.global_transform.basis.z
	var right := p.global_transform.basis.x
	var f := move.dot(fwd)
	var r := move.dot(right)
	_key(&"move_forward", f > MOVE_KEY_DOT)
	_key(&"move_back", f < -MOVE_KEY_DOT)
	_key(&"move_right", r > MOVE_KEY_DOT)
	_key(&"move_left", r < -MOVE_KEY_DOT)
	# A player lets go of sprint during the stamina lockout (12 §7 auto-sprint off by default).
	_key(&"sprint", sprint and f > MOVE_KEY_DOT and not p.locomotion.stamina.is_locked_out())


## Stands still (optionally facing `look`); resets the stuck window.
func _halt(look: Vector3 = Vector3.ZERO) -> void:
	var p := run.player
	if look != Vector3.ZERO:
		p.rotation = Vector3(0.0, atan2(-look.x, -look.z), 0.0)
	_release_moves()
	_stuck_left = STUCK_WINDOW
	_stuck_from = p.global_position


func _release_moves() -> void:
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)


func _key(action: StringName, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


## A key press for one physics frame (the input edge), released on the next.
func _tap(action: StringName) -> void:
	Input.action_press(action)
	tree.physics_frame.connect(func() -> void: Input.action_release(action), CONNECT_ONE_SHOT)


func _check_stuck(dt: float) -> void:
	var p := run.player
	if p.is_stunned():
		_stuck_left = STUCK_WINDOW
		_stuck_from = p.global_position
		return
	_stuck_left -= dt
	if _stuck_left > 0.0:
		return
	if DirectorSpawn.flat_dist(p.global_position, _stuck_from) < STUCK_MIN_MOVE \
			and not _tight.is_empty() and _tight[0] \
			and DirectorSpawn.flat_dist(p.global_position, _waypoints[0]) < ARRIVE_DIST:
		# Lined up as well as the doorway allows (an open leaf can stand on the centre).
		_prev_wp = _waypoints[0]
		_waypoints.remove_at(0)
		_tight.remove_at(0)
	elif DirectorSpawn.flat_dist(p.global_position, _stuck_from) < STUCK_MIN_MOVE:
		# No teleport: count it, open every closed door in reach (E), repath and strafe out.
		_open_doors_in_reach()
		_stuck_events += 1
		_stuck_time += STUCK_WINDOW
		if not _waypoints.is_empty() and not _tight[0]:
			# On open floor something the grid does not hold (a pillar, a car's corner) is in
			# the way: step around it, alternating sides (M2.7).
			var to := _waypoints[0] - p.global_position
			var dir := Vector3(to.x, 0.0, to.z).normalized()
			var side := dir.cross(Vector3.UP) * _wiggle_side * SIDESTEP
			_wiggle_side = -_wiggle_side
			_waypoints.insert(0, p.global_position + side + dir * SIDESTEP * 1.3)
			_tight.insert(0, false)
			_waypoints.insert(0, p.global_position + side - dir * 0.2)
			_tight.insert(0, false)
			_sidestep_left = SIDESTEP_HOLD
		else:
			_clear_path()
		if _sidestep_left > 0.0:
			pass
		elif _stuck_events % 2 == 1:
			_backoff_left = BACKOFF_TIME
		else:
			_wiggle_left = WIGGLE_TIME
			_wiggle_side = -_wiggle_side
	else:
		_stuck_time = 0.0
	_stuck_left = STUCK_WINDOW
	_stuck_from = p.global_position


## True when one of the next doorway waypoints (the lined-up pair either side of an edge
## crossing) belongs to door `d`.
func _door_on_path(d: Door) -> bool:
	for i in mini(_waypoints.size(), 6):
		if _tight[i] and DirectorSpawn.flat_dist(_waypoints[i], d.global_position) < DOOR_APPROACH + 0.4:
			return true
	return false


## A stuck bot presses E on the doors in reach: a closed door on its path opens; an open door
## off its path closes (its leaf stands in the corridor).
func _open_doors_in_reach() -> void:
	var p := run.player
	for n in tree.get_nodes_in_group(&"doors"):
		var d := n as Door
		if d == null or not run.level.is_ancestor_of(d) \
				or DirectorSpawn.flat_dist(d.global_position, p.global_position) >= REACH + 0.5:
			continue
		if d.is_open != _door_on_path(d):
			d.interactable.interact(p)


# --- Flicker's counter (08 §5) ------------------------------------------------------------------

## The nearest awake Flicker (by its group centroid).
func _flicker() -> ErrorFlicker:
	var best: ErrorFlicker = null
	var best_d := INF
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var fl := n as ErrorFlicker
		if fl == null or fl.is_dormant() or fl.despawned:
			continue
		var d := fl.distance_to_player()
		if d < best_d:
			best = fl
			best_d = d
	return best


## Darkness is the counter: light off near Flicker's group or when it stalks or attaches, on
## again when clear; while it stalks, walk out of its lit area by the nearest cell. True when
## the bot moved for it this frame.
func _flicker_counter(dt: float) -> bool:
	var p := run.player
	var fl := _flicker()
	var d := fl.distance_to_player() if fl != null else INF
	var near := fl != null and (d < FLICKER_DARK_DIST or fl.state == Tuning.ERROR_STATE_ATTACHED \
		or fl.state == Tuning.ERROR_STATE_STALK)
	if near and p.flashlight.on:
		if _cranking:
			_cranking = false
			Input.action_release(&"crank")
		_tap(&"flashlight")
		_dark_for_flicker = true
		_decide("light")
		if profile == PROFILE_CAUTIOUS:
			# Chemical light: Flicker cannot use it (09). Dropped at the feet.
			items.use(&"glowstick", Tuning.GLOWSTICK_DROP_HOLD + 0.1)
	elif _dark_for_flicker and not p.flashlight.on and (fl == null or d > FLICKER_CLEAR_DIST):
		_tap(&"flashlight")
		_dark_for_flicker = false
		_decide("light")
	if fl == null or fl.state != Tuning.ERROR_STATE_STALK or fl.pool() == null \
			or not FlickerHabitat.in_lit_area(fl.pool(), fl.current_group, p.global_position):
		_flicker_goal = Vector3.INF
		return false
	if _flicker_goal == Vector3.INF or DirectorSpawn.flat_dist(p.global_position, _flicker_goal) < ARRIVE_DIST:
		_flicker_goal = _unlit_cell(fl)
	if _flicker_goal == Vector3.INF:
		return false
	_follow(_flicker_goal, dt, true)
	return true


## The nearest cell (walking) outside the stalking Flicker's lit area.
func _unlit_cell(fl: ErrorFlicker) -> Vector3:
	var grid := run.data.grid
	var walk := grid.distance_field(grid.cell_of(run.player.global_position))
	var best := Vector3.INF
	var best_w := 1 << 30
	for i in walk.size():
		if walk[i] < 0 or walk[i] >= best_w:
			continue
		var w := grid.world_of(grid.cell_at(i))
		if not FlickerHabitat.in_lit_area(fl.pool(), fl.current_group, w):
			best = w
			best_w = walk[i]
	return best


## Where the bot gave up: its position, cell, the next waypoint's cell and the edge kinds.
func _stuck_report() -> Dictionary:
	var p := run.player
	var grid := run.data.grid
	var c := grid.cell_of(p.global_position)
	var walls := []
	for d in 4:
		walls.append([grid.wall(c, d), grid.can_step(c, d)])
	var doors := []
	for n in tree.get_nodes_in_group(&"doors"):
		var d := n as Door
		if d != null and d.global_position.distance_to(p.global_position) < 3.0:
			doors.append([str(d.global_position.snappedf(0.01)), d.is_open, str(d.leaf.global_position.snappedf(0.01)),
				str((d.leaf.global_transform.basis.x).snappedf(0.01))])
	return {&"pos": str(p.global_position.snappedf(0.01)), &"cell": str(c), &"doors": str(doors),
		&"next": str(grid.cell_of(_waypoints[0])) if not _waypoints.is_empty() else "",
		&"goal": str(grid.cell_of(_goal)), &"walls": str(walls), &"state": String(p.state_machine.state)}


func _chaser() -> ErrorBase:
	var best: ErrorBase = null
	var best_d := INF
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var e := n as ErrorBase
		if e == null or not DirectorRules.is_hunter(e.error_id) or not DirectorRules.is_chasing_state(e.state):
			continue
		var d := e.distance_to_player()
		if d < best_d:
			best = e
			best_d = d
	return best


## The nearest cell (walking) clear of every awake Static's field by a body and a step.
func _escape_cell() -> Vector3:
	var grid := run.data.grid
	var fields: Array[ErrorStatic] = []
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var st := n as ErrorStatic
		if st != null and not st.is_dormant():
			fields.append(st)
	var walk := grid.distance_field(grid.cell_of(run.player.global_position))
	var best := Vector3.INF
	var best_w := 1 << 30
	for i in walk.size():
		if walk[i] < 0 or walk[i] >= best_w:
			continue
		var w := grid.world_of(grid.cell_at(i))
		var clear := true
		for st in fields:
			if DirectorSpawn.flat_dist(w, st.centre()) < st.radius + 1.5:
				clear = false
				break
		if clear:
			best = w
			best_w = walk[i]
	return best


func _in_static() -> bool:
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var st := n as ErrorStatic
		if st != null and st.inside:
			return true
	return false


func _hunter_within(dist: float) -> bool:
	for n in tree.get_nodes_in_group(ErrorBase.GROUP):
		var e := n as ErrorBase
		if e != null and DirectorRules.is_hunter(e.error_id) and not e.is_dormant() and e.distance_to_player() < dist:
			return true
	return false


## The nearest usable hide spot within a few cells' walk.
func _nearby_spot() -> HideSpot:
	var p := run.player
	var grid := run.data.grid
	var walk := grid.distance_field(grid.cell_of(p.global_position))
	var best: HideSpot = null
	var best_w := HIDE_SEARCH_CELLS + 1
	for n in tree.get_nodes_in_group(&"hide_spots"):
		var s := n as HideSpot
		if s == null or s.occupant != null or not run.level.is_ancestor_of(s):
			continue
		var c := grid.cell_of(s.exit_transform().origin)
		if not grid.in_bounds(c):
			continue
		var w := walk[grid.idx(c)]
		if w >= 0 and w < best_w:
			best = s
			best_w = w
	return best
