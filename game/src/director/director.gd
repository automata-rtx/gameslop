class_name Director
extends Node
## The per-level pacing authority (10). Macro only: it spawns the roster, wakes, hints,
## sets aggression and retreats; it never tells an error where the player is (a hint is
## always a cell at a range from the player, 10 §1). Errors stay honest: a chase starts
## only from their senses (08 §2).
##
## Time: a `time_source` Callable returning seconds (tests pass FakeClock.now); without
## one, the Director counts its own physics time (pausable, so hitstop and the pause menu
## stop it). `update()` advances in fixed 0.1 s steps (10 Hz, 10 §2).
## The run calls begin(level, player, arrival) (14 Interfaces, M1.9 hook); depth, Cycle
## and stratum come from the level data and the run. Pure parts: DirectorPacing
## (intensity, phases), DirectorRules (aggression, roster, caps, threat, exclusivity),
## DirectorSpawn (fair cells, hints, the Static cut test), DirectorHunters (the calls down).

const GROUP := &"director"

var time_source: Callable
var level: Level
var data: LevelData
var player: Player
var depth: int = 1
var cycle: int = 1
var stratum: StringName = Tuning.STRATUM_DEPTH1
var arrival: StringName = Tuning.RUN_ARRIVE_START
var drops_in_a_row: int = 0
var first_descent: bool = false
## 10 Interfaces: read-only views of the pacing model.
var intensity: float:
	get:
		return pacing.intensity
var phase: StringName:
	get:
		return pacing.phase
var aggression: float = 0.0
var threat: float = 0.0
var pacing: DirectorPacing = DirectorPacing.new()
var errors: Array[ErrorBase] = []
## The roster as designed (05 §3) and the ids skipped because they have no scene yet.
var roster: Array[StringName] = []
var skipped: Array[StringName] = []
## The roster as spawned (since M2.5 the design roster; ids without a scene are `skipped`).
var spawned_roster: Array[StringName] = []
var native: StringName = &""
## 10 §4 contact exclusivity: the one clock (CHANGELOG: owned by the Director). −1: none.
var last_contact_ms: int = -1
var contacts: int = 0
var refused: int = 0
## Hunter chases the Director let run (entered Chase/Follow/Stalk outside Calm and Relief),
## and chases it sent away because they started in Calm or Relief (not encounters, cp-04).
var encounters: int = 0
var retreated_chases: int = 0
var telemetry := DirectorTelemetry.new()
## 10 §5: the gating (Scares) and the world events (ScareEvents), rebuilt by begin().
var scares := Scares.new()
var scare_events := ScareEvents.new()
var inputs := DirectorInputs.new()
var rng: RandomNumberGenerator = Seeds.rng(0)
var hunters := DirectorHunters.new()
var statics := DirectorStatics.new()
## R19: true (the run sets it) spreads begin's roster work over the frames after arrival
## within the build slice budget (DirectorArrival); false runs it inside begin.
var staged: bool = false
var arrival_work := DirectorArrival.new()

var _active: bool = false
var _game_time: float = 0.0
var _last_tick: float = 0.0
var _begin_time: float = 0.0
var _aggr_left: float = 0.0
var _check_left: float = 0.0
var _static_left: float = 0.0
var _telemetry_left: float = 0.0
var _scare_left: float = 0.0
var _scare_d: float = INF
## The scare kind that ran since the last telemetry row (its `scare` column).
var _scare_mark: StringName = &""


func _init() -> void:
	name = "Director"
	add_to_group(GROUP)
	add_to_group(DebugOverlay.GROUP)


func _exit_tree() -> void:
	end()


func now() -> float:
	return float(time_source.call()) if time_source.is_valid() else _game_time




## 10 Interfaces: starts the Director for `p_level` (data, grid, placements) with the
## player who just arrived. Spawns the roster, applies aggression, starts Calm.
func begin(p_level: Level, p_player: Player, p_arrival: StringName = Tuning.RUN_ARRIVE_START) -> void:
	end()
	level = p_level
	data = level.data if level != null else null
	player = p_player
	arrival = p_arrival
	_read_context()
	rng = Seeds.rng(Seeds.derive(data.level_seed if data != null else 0, Tuning.SEED_LABEL_DIRECTOR))
	pacing = DirectorPacing.new(rng.randi(), arrival, DirectorRules.cycle_depth(depth) == 6)
	hunters.director = self
	inputs.director = self
	statics.director = self
	arrival_work.director = self
	var level_seed := data.level_seed if data != null else 0
	scares = Scares.new(Seeds.derive(level_seed, Tuning.SEED_LABEL_SCARES))
	scare_events = ScareEvents.new()
	scare_events.bind(self, scares)
	_scare_left = Tuning.DIRECTOR_SCARE_CHECK_INTERVAL
	_active = true
	_begin_time = now()
	_last_tick = _begin_time
	inputs.connect_all()
	if player != null:
		player.contact_gate = try_contact
	if data != null:
		roster = DirectorRules.roster(depth, stratum, first_descent, _met_hunters(), rng)
		native = StringName(Tuning.STRATUM_NATIVE_ERROR.get(stratum, &""))
		if stratum == Tuning.STRATUM_SERVER:
			for id in roster:
				if DirectorRules.is_hunter(id):
					native = id
					break
		spawned_roster.assign(roster)
		# The roster, the awake arrivals and the Static bounds (DirectorArrival), then the
		# aggression: at once, or staged over the next frames (R19), before the first tick.
		arrival_work.plan(spawned_roster)
	if staged:
		arrival_work.queue.append(_apply_aggression.bind(true))
	else:
		arrival_work.queue.run()
		_apply_aggression(true)
	EventBus.director_phase.emit(pacing.phase)


## Stops listening and gives the player's contact gate back. Errors stay with the level.
func end() -> void:
	if not _active:
		return
	_active = false
	arrival_work.queue.clear()
	inputs.disconnect_all()
	scare_events.stop_ongoing()
	DirectorTelemetry.dump_debug(self)
	if player != null and is_instance_valid(player) and player.contact_gate == Callable(self, &"try_contact"):
		player.contact_gate = Callable()


func is_active() -> bool:
	return _active


func _read_context() -> void:
	depth = data.depth if data != null else 1
	cycle = data.cycle if data != null else 1
	stratum = data.stratum if data != null else Tuning.STRATUM_DEPTH1
	first_descent = data.first_run if data != null else false
	drops_in_a_row = 0
	if GameState.run != null and GameState.is_run_active():
		drops_in_a_row = GameState.run.drops_in_a_row
		# The run's order names the stratum; M1 builds other strata as Halls (M1.9).
		stratum = GameState.stratum_for(depth)


func _met_hunters() -> Array:
	if GameState.run != null and GameState.is_run_active():
		return GameState.run.encounters.keys()
	return []


# --- 10 §4 contact exclusivity --------------------------------------------------------------

## Player.contact_gate: refuses a contact within 3 s of the last one; the refused error
## retreats for 5 s (10 §4). Approving starts the 3 s window.
func try_contact(error: Node) -> bool:
	var t := int(round(now() * 1000.0))
	if not DirectorRules.contact_allowed(t, last_contact_ms):
		refused += 1
		if error != null and error.has_method(&"retreat"):
			error.call(&"retreat", Tuning.DIRECTOR_CONTACT_REFUSED_RETREAT)
		return false
	last_contact_ms = t
	return true


## 10 Interfaces: spawns error `id` Dormant at `spawn_point` (Static wakes: it is weather).
func spawn_error(id: StringName, spawn_point: Vector3) -> ErrorBase:
	return hunters.spawn(id, spawn_point)


## 10 Interfaces: asks for a scare now (10 §5 gating: Build, intensity, intervals, no hunter
## near). Returns true when one ran. The Director also asks every 5 s of Build by itself.
func request_scare() -> bool:
	var k := scares.try_any(pacing.phase, pacing.intensity, pacing.level_time, _scare_d)
	if k != &"":
		_scare_mark = k
	return k != &""


# --- time --------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _active and not arrival_work.queue.is_done():
		arrival_work.queue.run(StepQueue.slice_budget_ms())


func _physics_process(delta: float) -> void:
	_game_time += delta
	update()


## True while begin's staged roster work is still waiting (R19).
func is_arriving() -> bool:
	return _active and not arrival_work.queue.is_done()


## Advances the model to `now()` in fixed 0.1 s steps.
func update() -> void:
	if not _active:
		return
	var t := now()
	if t - _last_tick >= Tuning.DIRECTOR_TICK - 0.000001 and not arrival_work.queue.is_done():
		arrival_work.queue.run()  # R19: the first tick sees the whole roster, as without staging
	while t - _last_tick >= Tuning.DIRECTOR_TICK - 0.000001:
		_last_tick += Tuning.DIRECTOR_TICK
		_tick(Tuning.DIRECTOR_TICK)
		if not _active:
			return


func _tick(dt: float) -> void:
	var s := hunters.survey()
	var before := pacing.phase
	# The hunter count only gates the 0.8 wake: none may be woken where 05 §10 forbids it.
	pacing.step(dt, s.nearest, s.chasing, s.hunters if wake_allowed() else 0)
	for a in pacing.take_actions():
		hunters.act(a)
	_scare_d = s.scare_d
	if pacing.phase != before:
		EventBus.director_phase.emit(pacing.phase)
		if pacing.phase != DirectorPacing.BUILD:
			scare_events.stop_ongoing()  # no scare plays on into Peak or Relief (10 §5)
	scare_events.tick(now())
	if pacing.phase == DirectorPacing.BUILD:
		_scare_left -= dt
		if _scare_left <= 0.0:
			_scare_left = Tuning.DIRECTOR_SCARE_CHECK_INTERVAL
			request_scare()
	_check_left -= dt
	if _check_left <= 0.0:
		_check_left = Tuning.DIRECTOR_CALM_CHECK_INTERVAL
		hunters.enforce_caps(s)
		hunters.spawn_pending()
		hunters.respawn_flickers(now())
	_static_left -= dt
	if _static_left <= 0.0:
		_static_left = Tuning.STATIC_FAIR_CHECK_INTERVAL
		statics.static_fairness(Tuning.STATIC_FAIR_CHECK_INTERVAL)
	_aggr_left -= dt
	if _aggr_left <= 0.0:
		_aggr_left = Tuning.DIRECTOR_AGGRESSION_UPDATE_INTERVAL
		_apply_aggression(false)
	inputs.noclip_los_check()
	var prev := threat
	threat = DirectorRules.smooth_threat(threat, s.threat, dt)
	if absf(threat - prev) > 0.0005 or (threat == 0.0 and prev != 0.0):
		EventBus.threat_changed.emit(threat)
	if AudioManager.has_node(^"MusicDirector"): AudioManager.get_node(^"MusicDirector").call(&"set_intensity", pacing.intensity)  # 10 §6
	_telemetry_left -= dt
	if _telemetry_left <= 0.0:
		_telemetry_left = Tuning.DIRECTOR_TELEMETRY_INTERVAL
		telemetry.record(pacing.level_time, pacing.intensity, pacing.phase, aggression, threat, s.nearest,
			player.coherence if player != null and is_instance_valid(player) else 0.0, s.chasing, _scare_mark)
		_scare_mark = &""


## 05 §10: the first Descent's depth 1 has no active hunter; one placed there anyway (a
## bench, a test) stays dormant through Build and the 0.8 wake (cp-04 review).
func wake_allowed() -> bool:
	return not (first_descent and DirectorRules.cycle_depth(depth) == 1)


## 10 §3: applied to every error whenever it changes, at most once per second.
func _apply_aggression(force: bool) -> void:
	var a := DirectorRules.aggression(depth, drops_in_a_row, pacing.level_time, cycle)
	if not force and is_equal_approx(a, aggression):
		return
	aggression = a
	for e in hunters.live():
		e.set_aggression(DirectorRules.error_aggression(aggression, depth, e.error_id))


## Error signals, connected by DirectorHunters.spawn.
func on_error_contact(_cost: float, _e: ErrorBase) -> void:
	contacts += 1
	pacing.on_contact()


func on_error_lost(e: ErrorBase) -> void:
	pacing.on_evasion(DirectorRules.is_hunter(e.error_id))


## 10 §7 rule 2: no hunter chases during Calm; one that starts is sent away for the rest.
## A chase that starts in Relief is sent away the same way (relief is space; cp-04). Those
## are not encounters; every other hunter chase is.
func on_error_state(_from: StringName, to: StringName, e: ErrorBase) -> void:
	if not DirectorRules.is_chasing_state(to) or not DirectorRules.is_hunter(e.error_id):
		return
	var left := -1.0
	if pacing.phase == DirectorPacing.CALM:
		left = pacing.calm_left()
	elif pacing.phase == DirectorPacing.RELIEF:
		left = pacing.relief_left()
	if left < 0.0:
		encounters += 1
		return
	retreated_chases += 1
	e.retreat(maxf(left, Tuning.DIRECTOR_CONTACT_REFUSED_RETREAT))


## 14 §9 F3 overlay lines (each error adds its own state and distance).
func debug_info() -> Dictionary:
	return {
		"director": "%s %.0f s" % [String(pacing.phase).to_upper(), pacing.phase_time],
		"intensity": "%.2f" % pacing.intensity,
		"aggression": "%.2f" % aggression,
		"threat": "%.2f   contacts %d (refused %d)  chases %d (sent away %d)" % [threat, contacts, refused,
			encounters, retreated_chases],
		"scares": "%d (last %s)" % [scares.count(), String(scares.fired.back()[&"kind"]) if not scares.fired.is_empty() else "-"],
	}
