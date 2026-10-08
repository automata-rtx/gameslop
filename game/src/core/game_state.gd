extends Node
## Run and meta state (05 Interfaces, 13 Interfaces, 14 §3). Pure data and rules: never
## touches scene nodes or UI; announces changes on the EventBus and asks SaveManager to write
## meta.json on the persistence events of 13 §3 (note, notice, level transition, unlock, run end).
## Owns the strata order (05 §2), loadout starts (05 §7), modes (05 §8), the Descent Score
## (05 §5) and the 14 milestone unlocks (05 §6), each earned once and announced once.

const WIN_CAUSE := &"threshold"
const NOTE_U6 := &"U6"
## 05 §6 unlocks #10 to #13: error id -> unlock id.
const CODEX_UNLOCKS: Dictionary = {
	&"still": &"codex_still", &"echo": &"codex_echo", &"flicker": &"codex_flicker", &"null": &"codex_null",
}
const ERROR_FLICKER := &"flicker"

## The current or most recent Descent; null before the first run.
var run: RunState = null
var meta: MetaState = MetaState.new()

var _run_active: bool = false
var _last_cause: StringName = &""
## Run counters already added to meta.stats (flushed at each level transition, 13 §3).
var _flushed: Dictionary = {}


func _ready() -> void:
	meta = SaveManager.load_meta()
	# The pickup announces a note on the bus; the run keeps it (05 §5 notes_found_this_run)
	# and the Archive keeps it across runs (13).
	EventBus.note_found.connect(record_note)
	EventBus.item_used.connect(_on_item_used)
	EventBus.breaker_thrown.connect(_on_breaker_thrown)


## Starts a Descent. Daily Descent always uses Faller (05 §7) and spends today's attempt at
## once (05 §8: one attempt per day per save), so quitting cannot buy a second try. Whether a
## mode or loadout may be chosen is the title's question (is_mode_available,
## is_loadout_available); debug launches start anything.
func start_run(mode: StringName, loadout: StringName, run_seed: int) -> void:
	if mode == Tuning.MODE_DAILY:
		loadout = Tuning.MODE_DAILY_LOADOUT
	run = RunState.new()
	run.mode = mode
	run.loadout = loadout
	run.run_seed = run_seed
	var kit: LoadoutData = DataRegistry.loadout(loadout)
	run.depth = kit.start_depth if kit != null else 1  # Diver starts at depth 3 (05 §7)
	run.coherence = kit.start_coherence if kit != null else Tuning.COHERENCE_MAX
	if kit != null:
		run.crank_rate_mult = kit.crank_rate_mult
		run.flicker_attract_mult = kit.flicker_attract_mult
		run.start_items = kit.start_items.duplicate()
	run.max_depth = run.depth
	run.strata_order = strata_order_for(run_seed)
	run.started_at_ms = Time.get_ticks_msec()
	run.first_descent = not meta.first_descent_done
	_flushed = {}
	meta.depth_reached(run.depth)
	_run_active = true
	_last_cause = &""
	if mode == Tuning.MODE_DAILY:
		run.daily_key = today_key()
		meta.daily[run.daily_key] = {"score": 0, "depth": run.depth, "cause": "abandoned"}
	_check_depth_unlocks()
	EventBus.run_started.emit(mode, run_seed)
	_persist()


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
	# 13 §3 level transition: the stratum just stood in counts as reached (01 §6 tier 2 notes
	# appear on a later visit, so the current level's own stratum is not counted yet).
	meta.stratum_reached(stratum_for(run.depth))
	run.depth += 1
	if run.depth > run.max_depth:
		run.max_depth = run.depth
		# 13 §2 depth_reached_counts: one count per run per depth, written here as the run
		# reaches it (record_run does not count it again).
		meta.depth_reached(run.depth)
	_flush_stats()
	_check_depth_unlocks()
	EventBus.level_left.emit(proper)
	_persist()


## End the Descent. cause: the death cause of 06 §9, `threshold` for the win, or `abandoned`.
func end_run(cause: StringName) -> void:
	if not _run_active:
		push_warning("GameState.end_run called with no active run")
		return
	_run_active = false
	_last_cause = cause
	var won := cause == WIN_CAUSE
	meta.stratum_reached(stratum_for(run.depth))
	_flush_stats()
	run.score = compute_score()
	meta.record_run({
		"cause": String(cause), "depth": run.max_depth, "stratum": String(stratum_for(run.depth)),
		"score": run.score, "seed": run.run_seed, "mode": run.mode, "won": won,
		"seconds": Clock.run_seconds(), "daily_key": run.daily_key,
	})
	if won:
		# 05 §6 #9, 13 §3 Ending: Endless and Cycle 2.
		meta.cycle_unlocked = true
		_earn(&"endless")
	# 05 §10: the scripted first-Descent guarantees apply to one Descent only.
	meta.first_descent_done = true
	_persist()
	EventBus.run_ended.emit(cause, run.score)


# --- counters the run scene calls down (05 Interfaces, production additions) -----------------

## 08 §2 noticed_player: the run's encounter and the Archive codex (13 §3), unlocks #10 to #13.
func record_notice(id: StringName) -> void:
	if run == null:
		return
	run.encounters[id] = int(run.encounters.get(id, 0)) + 1
	var n := meta.codex_notice(id)
	if CODEX_UNLOCKS.has(id) and n >= Tuning.UNLOCK_CODEX_ENCOUNTERS:
		_earn(CODEX_UNLOCKS[id])
	_persist()


## 08 §2 lost_player: an evasion (05 §5), unlock #6 (Flicker three times in one run).
func record_evasion(id: StringName) -> void:
	if run == null:
		return
	# 05 §5 ruling (CHANGELOG 2026-10-08): Static evasions feed the Archive and codex only;
	# stepping in and out of a field must not farm score.
	if id != &"static":
		run.evasions += 1
	run.evasions_by[id] = int(run.evasions_by.get(id, 0)) + 1
	if id == ERROR_FLICKER and int(run.evasions_by[id]) >= Tuning.UNLOCK_LIGHTBEARER_FLICKER_EVASIONS:
		if _earn(&"lightbearer"):
			_persist()


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


## A note was read (EventBus.note_found). Once per run per id; the Archive keeps it too
## (13 §3: notes_found, stats.notes_total, unlocks #5 and #14).
func record_note(id: StringName) -> void:
	var new_to_archive := meta.note_found(id)
	var new_to_run := run != null and _run_active and not run.notes_found.has(id)
	if new_to_run:
		run.notes_found.append(id)
		meta.add_stat("notes_total", 1)
	if not new_to_archive and not new_to_run:
		return
	if meta.notes_found.size() >= Tuning.UNLOCK_CARTOGRAPHER_NOTES:
		_earn(&"cartographer")
	if meta.notes_count_except(NOTE_U6) >= Tuning.UNLOCK_NOTE_U6_NOTES:
		_earn(&"note_u6")
	_persist()


# --- score (05 §5) -------------------------------------------------------------------------

## The Descent Score of the current or last run. Time from Clock.run_seconds() (hitstop and
## menu pause excluded), never wall time; the time bonus only for a win.
func compute_score() -> int:
	if run == null:
		return 0
	var won := not _run_active and _last_cause == WIN_CAUSE
	return score_for(run.max_depth, run.proper_exits, run.coherence, run.notes_found.size(),
			run.evasions, Clock.run_seconds(), won)


## 05 §5. Coherence counts as the whole number the HUD shows; the time bonus rounds down.
static func score_for(max_depth: int, proper_exits: int, coherence_at_end: float, notes: int,
		evasions: int, seconds: float, won: bool) -> int:
	var s := Tuning.SCORE_PER_DEPTH * max_depth \
			+ Tuning.SCORE_PER_PROPER_EXIT * proper_exits \
			+ Tuning.SCORE_PER_COHERENCE * maxi(0, roundi(coherence_at_end)) \
			+ Tuning.SCORE_PER_NOTE * notes \
			+ Tuning.SCORE_PER_EVASION * evasions
	if won:
		s += floori(maxf(0.0, Tuning.SCORE_TIME_BONUS_BASE - seconds) * Tuning.SCORE_TIME_BONUS_RATE)
	return s


# --- modes and loadouts (05 §7, §8) -------------------------------------------------------------

## Descent always; Daily once unlocked (#8) and not yet played today; Endless after a win (#9).
func is_mode_available(mode: StringName) -> bool:
	match mode:
		Tuning.MODE_DESCENT:
			return true
		Tuning.MODE_DAILY:
			return meta.is_unlocked(&"daily") and not meta.has_daily(today_key())
		Tuning.MODE_ENDLESS:
			return meta.is_unlocked(&"endless") or meta.cycle_unlocked
	return false


func is_loadout_available(id: StringName) -> bool:
	var kit: LoadoutData = DataRegistry.loadout(id)
	return kit != null and (kit.unlock_id == &"" or meta.is_unlocked(kit.unlock_id))


## 13 §4: the UTC date key "YYYYMMDD" (today when `date` is empty).
static func today_key(date: Dictionary = {}) -> String:
	var d := date if not date.is_empty() else Time.get_date_dict_from_system(true)
	return "%04d%02d%02d" % [int(d.get("year", 1970)), int(d.get("month", 1)), int(d.get("day", 1))]


## 05 §8, 13 §4: run_seed = hash("NOCLIP:" + "YYYYMMDD"), today when `date` is empty.
static func daily_seed(date: Dictionary = {}) -> int:
	return Seeds.daily(date if not date.is_empty() else Time.get_date_dict_from_system(true))


## 05 §1 Cycle: depths 1 to 6 are Cycle 1, 7 to 12 Cycle 2 (Endless).
static func cycle_for(depth: int) -> int:
	return 1 + (maxi(depth, 1) - 1) / Tuning.RUN_CYCLE_LENGTH


## 05 §10: the scripted first-Descent guarantees apply.
func is_first_descent() -> bool:
	return run.first_descent if run != null and _run_active else not meta.first_descent_done


# --- strata (05 §2) ----------------------------------------------------------------------------

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


func is_run_active() -> bool:
	return _run_active


func last_cause() -> StringName:
	return _last_cause


# --- internals -----------------------------------------------------------------------------------

## 05 §6 #1 to #4, #7, #8: depth milestones, checked whenever the run reaches a depth.
func _check_depth_unlocks() -> void:
	var d := run.max_depth
	if d >= Tuning.UNLOCK_GLOWSTICK_DEPTH:
		_earn(&"glowstick")
	if d >= Tuning.UNLOCK_RADIO_DEPTH:
		_earn(&"radio")
	if d >= Tuning.UNLOCK_FLARE_DEPTH:
		_earn(&"flare")
	if d >= Tuning.UNLOCK_FUSE_DEPTH:
		_earn(&"fuse")
	if d >= Tuning.UNLOCK_DAILY_DEPTH:
		_earn(&"daily")
	if meta.depth_count(Tuning.UNLOCK_DIVER_DEPTH) >= Tuning.UNLOCK_DIVER_TIMES:
		_earn(&"diver")


## Earns `id` once: meta flag, the run's summary list, EventBus.unlock_earned (the HUD
## prints the notification, 04 §6). Returns true when newly earned. The caller persists.
func _earn(id: StringName) -> bool:
	if not meta.earn(id):
		return false
	if run != null:
		run.unlocks_earned.append(id)
	EventBus.unlock_earned.emit(id)
	return true


## 13 §3 level transition and run end: run counters into meta.stats, by difference.
func _flush_stats() -> void:
	if run == null:
		return
	var now := {
		"walls_passed": float(run.walls_passed), "floors_dropped": float(run.drops_total),
		"coherence_spent": run.coherence_spent, "distance_walked_m": run.distance_m,
		"evasions": float(run.evasions),
	}
	for k: String in now:
		var delta: float = now[k] - float(_flushed.get(k, 0.0))
		if delta > 0.0:
			meta.add_stat(k, delta)
		_flushed[k] = now[k]
	meta.stats["best_depth"] = maxi(int(meta.stats.get("best_depth", 0)), run.max_depth)


func _persist() -> void:
	SaveManager.save_meta(meta)


func _on_item_used(kind: StringName) -> void:
	meta.item_used(kind)


func _on_breaker_thrown(_pos: Vector3) -> void:
	meta.add_stat("breakers_thrown", 1)
