extends Node
## Run and meta state (05 Interfaces, 13 Interfaces, 14 §3). Pure data and rules:
## never touches scene nodes or UI; announces changes on the EventBus.
## M0.2 provides the lifecycle skeleton; M1.9 adds the strata order (05 §2), loadout
## starts (05 §7), note recording and the meta depth counts. Owed by M2.10: score,
## unlocks, record_run, Daily, Endless.

## The current or most recent Descent; null before the first run.
var run: RunState = null
var meta: MetaState = MetaState.new()

var _run_active: bool = false
var _last_cause: StringName = &""
var _warned: Dictionary = {}


func _ready() -> void:
	# The pickup announces a note on the bus; the run keeps it (05 §5 notes_found_this_run)
	# and the Archive keeps it across runs (13).
	EventBus.note_found.connect(record_note)


func start_run(mode: StringName, loadout: StringName, run_seed: int) -> void:
	run = RunState.new()
	run.mode = mode
	run.loadout = loadout
	run.run_seed = run_seed
	var kit: LoadoutData = DataRegistry.loadout(loadout)
	run.depth = kit.start_depth if kit != null else 1  # Diver starts at depth 3 (05 §7)
	run.coherence = kit.start_coherence if kit != null else Tuning.COHERENCE_MAX
	run.max_depth = run.depth
	run.strata_order = strata_order_for(run_seed)
	run.started_at_ms = Time.get_ticks_msec()
	meta.depth_reached(run.depth)
	_run_active = true
	_last_cause = &""
	EventBus.run_started.emit(mode, run_seed)


## Leave the current level: proper exit (true) or drop (false). 05 §4.
func descend(proper: bool) -> void:
	if not _run_active:
		push_warning("GameState.descend called with no active run")
		return
	if proper:
		run.proper_exits += 1
		run.drops_in_a_row = 0
	else:
		run.drops_in_a_row += 1
	run.depth += 1
	if run.depth > run.max_depth:
		run.max_depth = run.depth
		# 13 §2 depth_reached_counts: one count per run per depth, written here as the run
		# reaches it (record_run, M2.10, must not count it again).
		meta.depth_reached(run.depth)
	EventBus.level_left.emit(proper)


## End the Descent. cause: the death cause of 06 §9, or how the run otherwise ended.
func end_run(cause: StringName) -> void:
	if not _run_active:
		push_warning("GameState.end_run called with no active run")
		return
	_run_active = false
	_last_cause = cause
	# 05 §10: the scripted first-Descent guarantees apply to one Descent only.
	meta.first_descent_done = true
	EventBus.run_ended.emit(cause, compute_score())


## Counters the run scene calls down (05 Interfaces, production additions). Run-scoped;
## the meta Archive counters are written by record_run (M2.10).
func record_notice(id: StringName) -> void:
	if run == null:
		return
	run.encounters[id] = int(run.encounters.get(id, 0)) + 1


func record_evasion(id: StringName) -> void:
	if run == null:
		return
	run.evasions += 1
	run.evasions_by[id] = int(run.evasions_by.get(id, 0)) + 1


## `kind`: what the Coherence bought (&"noclip_wall", &"noclip_floor", ...).
func record_spend(_kind: StringName, amount: float) -> void:
	if run == null:
		return
	run.coherence_spent += maxf(amount, 0.0)


func record_wall_pass() -> void:
	if run != null:
		run.walls_passed += 1


func record_drop() -> void:
	if run != null:
		run.drops_total += 1


## A note was read (EventBus.note_found). Once per run per id; the Archive keeps it too.
func record_note(id: StringName) -> void:
	meta.note_found(id)
	if run != null and _run_active and not run.notes_found.has(id):
		run.notes_found.append(id)


## 05 §2: the stratum at `depth` of this run (Cycle 2 repeats the order).
func stratum_for(depth: int) -> StringName:
	var order: Array[StringName] = run.strata_order if run != null and not run.strata_order.is_empty() \
			else strata_order_for(0)
	return order[posmod(depth - 1, Tuning.RUN_CYCLE_LENGTH)]


## 05 §2 Descent structure: Halls; Pools or Garage by coin flip; one of Pools, Garage,
## Offices that is not the depth 2 stratum (never Server); one of the remaining four with
## Server; the last remaining; Substrate. Seeded from `run_seed` only.
static func strata_order_for(run_seed: int) -> Array[StringName]:
	var rng := Seeds.rng(Seeds.derive(run_seed, Tuning.SEED_LABEL_STRATA))
	var order: Array[StringName] = [Tuning.STRATUM_DEPTH1]
	var d2: StringName = Tuning.STRATUM_DEPTH2_CHOICES[rng.randi_range(0, Tuning.STRATUM_DEPTH2_CHOICES.size() - 1)]
	order.append(d2)
	var d3_choices: Array[StringName] = []
	for s in Tuning.STRATUM_DEPTH3_CHOICES:
		if s != d2:
			d3_choices.append(s)
	order.append(d3_choices[rng.randi_range(0, d3_choices.size() - 1)])
	var rest: Array[StringName] = []
	for s in Tuning.STRATUM_DEPTH4_CHOICES:
		if not order.has(s):
			rest.append(s)
	var d4: StringName = rest[rng.randi_range(0, rest.size() - 1)]
	order.append(d4)
	rest.erase(d4)
	order.append(rest[0])
	order.append(Tuning.STRATUM_DEPTH6)
	return order


## 05 §5. TODO(M2.10): the Descent Score formula. The time bonus must read
## Clock.run_seconds() (hitstop and menu pause excluded), never wall time.
func compute_score() -> int:
	_todo("compute_score (M2.10)")
	return 0


func is_run_active() -> bool:
	return _run_active


func last_cause() -> StringName:
	return _last_cause


func _todo(what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("not implemented: GameState.%s" % what)
