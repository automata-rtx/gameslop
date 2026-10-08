class_name MetaState
extends RefCounted
## Persistent meta progression (13 §2 schema v1), held by GameState, read and written as
## meta.json by SaveManager. Serialisation, validation and migration are pure functions of
## a Dictionary (MetaSchema); this class holds the typed fields and the accessors (13 Interfaces).

const VERSION := Tuning.META_VERSION

var version: int = VERSION
var created_at: String = ""
var first_descent_done: bool = false
## unlock id (String) -> bool; every id of Tuning.UNLOCK_IDS is present.
var unlocks: Dictionary = {}
var notes_found: Array[StringName] = []
## error id (String) -> notice count (13 §3 "Error noticed_player").
var codex: Dictionary = {}
var polaroids_seen: Array[int] = []
## 13 §2 stats block (MetaSchema.default_stats). `depth_reached_counts` (string depth -> times
## a run reached it) backs unlock #7, "reach depth 4 twice" (05 §6); `strata_reached` (stratum
## ids, production addition) backs tier 2 notes (01 §6).
var stats: Dictionary = MetaSchema.default_stats()
## "YYYYMMDD" -> {score, depth, cause} (13 §2, §4).
var daily: Dictionary = {}
## {cause, depth, stratum, score, seed} of the last finished run; empty before the first.
var last_run: Dictionary = {}
var endless_best_depth: int = 0
var cycle_unlocked: bool = false
## M2.12 (additive): found notes opened in the Archive (13 §5: unread notes blink once on
## the first Archive open), first-run hints already shown (04 §9, Strings.HINT_IDS), and
## whether reaching depth 3 has retired the hints (the Hints option turns them back on).
var notes_read: Array[StringName] = []
var hints_shown: Array[StringName] = []
var hints_retired: bool = false
## Keys this build does not know, preserved on save (13 §2).
var unknown: Dictionary = {}


func _init() -> void:
	created_at = MetaSchema.now_iso()
	for id: StringName in Tuning.UNLOCK_IDS:
		unlocks[String(id)] = false
	for id: StringName in Tuning.ERROR_IDS:
		codex[String(id)] = 0


func is_unlocked(id: StringName) -> bool:
	return bool(unlocks.get(String(id), false))


## Returns true when `id` was not already earned.
func earn(id: StringName) -> bool:
	if is_unlocked(id):
		return false
	unlocks[String(id)] = true
	return true


## Returns true when the note is new to the Archive.
func note_found(id: StringName) -> bool:
	if notes_found.has(id):
		return false
	notes_found.append(id)
	return true


## 08 §2 "noticed_player": one Archive encounter for error `id`. Returns the new count.
func codex_notice(id: StringName) -> int:
	var n: int = int(codex.get(String(id), 0)) + 1
	codex[String(id)] = n
	return n


## A run reached `depth`. Returns how many runs have reached it, this one included.
## GameState.descend calls this once per run per depth; record_run never counts it again.
func depth_reached(depth: int) -> int:
	var counts: Dictionary = stats.get("depth_reached_counts", {})
	var n: int = int(counts.get(str(depth), 0)) + 1
	counts[str(depth)] = n
	stats["depth_reached_counts"] = counts
	return n


## How many runs have reached `depth` (0 when none).
func depth_count(depth: int) -> int:
	var counts: Dictionary = stats.get("depth_reached_counts", {})
	return int(counts.get(str(depth), 0))


## Records that a run has stood in `stratum` (tier 2 notes, 01 §6). Returns true when new.
func stratum_reached(stratum: StringName) -> bool:
	var reached: Array = stats.get("strata_reached", [])
	if reached.has(String(stratum)):
		return false
	reached.append(String(stratum))
	stats["strata_reached"] = reached
	return true


func has_reached_stratum(stratum: StringName) -> bool:
	return (stats.get("strata_reached", []) as Array).has(String(stratum))


## Adds `amount` to a numeric stats key (13 §2). Integer keys stay integers.
func add_stat(key: String, amount: float) -> void:
	if MetaSchema.STAT_INTS.has(key):
		stats[key] = int(stats.get(key, 0)) + int(amount)
	else:
		stats[key] = float(stats.get(key, 0.0)) + amount


## stats.items_used[kind] += 1.
func item_used(kind: StringName) -> void:
	var used: Dictionary = stats.get("items_used", {})
	used[String(kind)] = int(used.get(String(kind), 0)) + 1
	stats["items_used"] = used


func has_daily(key: String) -> bool:
	return daily.has(key)


## 13 §2 daily entry, or an empty Dictionary.
func daily_result(key: String) -> Dictionary:
	return daily.get(key, {})


## Run end (13 §3): runs, wins, deaths_by, time played, last_run, best_score, best_depth,
## daily[...] when daily, endless_best_depth when endless. Keys of `result`: cause, depth
## (deepest reached), stratum, score, seed, mode, won, seconds, daily_key. Depth counts are
## written by GameState.descend as the run goes and are not counted here (no double count).
func record_run(result: Dictionary) -> void:
	var cause := String(result.get("cause", ""))
	var depth := clampi(int(result.get("depth", 1)), Tuning.META_DEPTH_MIN, Tuning.META_DEPTH_MAX)
	var score := maxi(0, int(result.get("score", 0)))
	add_stat("runs", 1)
	if bool(result.get("won", false)):
		add_stat("wins", 1)
	var deaths: Dictionary = stats.get("deaths_by", {})
	if deaths.has(cause):
		deaths[cause] = int(deaths[cause]) + 1
	add_stat("time_played_s", maxf(0.0, float(result.get("seconds", 0.0))))
	stats["best_score"] = maxi(int(stats.get("best_score", 0)), score)
	stats["best_depth"] = maxi(int(stats.get("best_depth", 0)), depth)
	last_run = {
		"cause": cause, "depth": depth, "stratum": String(result.get("stratum", "")),
		"score": score, "seed": int(result.get("seed", 0)),
	}
	var key := String(result.get("daily_key", ""))
	if not key.is_empty():
		daily[key] = {"score": score, "depth": depth, "cause": cause}
	if StringName(result.get("mode", &"")) == Tuning.MODE_ENDLESS:
		endless_best_depth = maxi(endless_best_depth, depth)


## Found notes the Archive has not shown yet (13 §5), in the order found.
func unread_notes() -> Array[StringName]:
	var out: Array[StringName] = []
	for n in notes_found:
		if not notes_read.has(n):
			out.append(n)
	return out


## Marks found notes as read. Returns true when anything changed.
func mark_notes_read(ids: Array[StringName]) -> bool:
	var changed := false
	for n in ids:
		if notes_found.has(n) and not notes_read.has(n):
			notes_read.append(n)
			changed = true
	return changed


## Distinct Archive notes other than `except` (unlock #14 counts the 35 notes besides U6).
func notes_count_except(except: StringName) -> int:
	var n := notes_found.size()
	return n - 1 if notes_found.has(except) else n


func to_dict() -> Dictionary:
	return MetaSchema.to_dict(self)


static func from_dict(d: Dictionary) -> MetaState:
	return MetaSchema.from_dict(d)
