extends Node
## Run and meta state (05 Interfaces, 13 Interfaces, 14 §3). Pure data and rules:
## never touches scene nodes or UI; announces changes on the EventBus.
## M0.2 provides the lifecycle skeleton. Owed by later tasks:
## strata order and loadout starts (M1.9), score, unlocks, Daily, Endless (M2.10).

## The current or most recent Descent; null before the first run.
var run: RunState = null
var meta: MetaState = MetaState.new()

var _run_active: bool = false
var _last_cause: StringName = &""
var _warned: Dictionary = {}


func start_run(mode: StringName, loadout: StringName, run_seed: int) -> void:
	run = RunState.new()
	run.mode = mode
	run.loadout = loadout
	run.run_seed = run_seed
	var kit: LoadoutData = DataRegistry.loadout(loadout)
	run.depth = kit.start_depth if kit != null else 1  # Diver starts at depth 3 (05 §7)
	run.max_depth = run.depth
	run.started_at_ms = Time.get_ticks_msec()
	_todo("start_run: strata_order (05 §2), loadout coherence and items (05 §7)")
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
	run.max_depth = maxi(run.max_depth, run.depth)
	EventBus.level_left.emit(proper)


## End the Descent. cause: the death cause of 06 §9, or how the run otherwise ended.
func end_run(cause: StringName) -> void:
	if not _run_active:
		push_warning("GameState.end_run called with no active run")
		return
	_run_active = false
	_last_cause = cause
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
