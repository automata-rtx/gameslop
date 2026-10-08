class_name MetaSchema
extends RefCounted
## meta.json schema v1 (13 §2): MetaState <-> Dictionary, explicit migrations, and the
## validation rules: unknown keys are preserved, missing keys get defaults, values are
## validated (depth 1 to 999, scores and counters >= 0). Pure functions; no file I/O.

const STAT_INTS: Array[String] = [
	"runs", "wins", "best_depth", "best_score", "walls_passed", "floors_dropped", "notes_total",
	"evasions", "breakers_thrown",
]
const STAT_FLOATS: Array[String] = ["distance_walked_m", "coherence_spent", "time_played_s"]
## deaths_by keys: the five errors and the Substrate (13 §2).
const DEATH_CAUSES: Array[String] = ["still", "echo", "flicker", "static", "null", "substrate"]
const KNOWN_KEYS: Array[String] = [
	"version", "created_at", "first_descent_done", "unlocks", "notes_found", "codex",
	"polaroids_seen", "stats", "daily", "last_run", "endless_best_depth", "cycle_unlocked",
]
const DAILY_KEY_LENGTH := 8
## Upper bound for counters read from disk (a hand-edited 1e300 must not overflow an int).
const COUNTER_MAX := 1000000000


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


static func default_stats() -> Dictionary:
	var s := {}
	for k in STAT_INTS:
		s[k] = 0
	for k in STAT_FLOATS:
		s[k] = 0.0
	var deaths := {}
	for c in DEATH_CAUSES:
		deaths[c] = 0
	s["deaths_by"] = deaths
	s["depth_reached_counts"] = {}
	s["items_used"] = {}
	s["strata_reached"] = []
	return s


# --- migration ---------------------------------------------------------------------------

## Brings a parsed file up to the current version. Returns an empty Dictionary when the data
## cannot be read as any version (the caller treats it as corrupt). Each step is explicit.
static func migrate(d: Dictionary) -> Dictionary:
	var v: Variant = d.get("version", 0)
	if not (v is int or v is float) or int(v) < 0:
		return {}
	var out := d.duplicate(true)
	if int(v) == 0:
		out = _migrate_0_to_1(out)
	# A file from a newer build keeps its known fields and its unknown keys (13 §2).
	return out


## Version 0 (the synthetic pre-release layout of 13 §7): no version key, unlocks as a list of
## earned ids, codex absent. Version 1 keys unlocks by id.
static func _migrate_0_to_1(d: Dictionary) -> Dictionary:
	var u: Variant = d.get("unlocks", {})
	if u is Array:
		var by_id := {}
		for id: Variant in u:
			if id is String or id is StringName:
				by_id[String(id)] = true
		d["unlocks"] = by_id
	d["version"] = 1
	return d


# --- MetaState -> Dictionary ---------------------------------------------------------------

static func to_dict(m: MetaState) -> Dictionary:
	var d := m.unknown.duplicate(true)
	d["version"] = MetaState.VERSION
	d["created_at"] = m.created_at
	d["first_descent_done"] = m.first_descent_done
	d["unlocks"] = m.unlocks.duplicate(true)
	var notes: Array = []
	for n in m.notes_found:
		notes.append(String(n))
	d["notes_found"] = notes
	d["codex"] = m.codex.duplicate(true)
	d["polaroids_seen"] = Array(m.polaroids_seen)
	d["stats"] = m.stats.duplicate(true)
	d["daily"] = m.daily.duplicate(true)
	d["last_run"] = m.last_run.duplicate(true)
	d["endless_best_depth"] = m.endless_best_depth
	d["cycle_unlocked"] = m.cycle_unlocked
	return d


# --- Dictionary -> MetaState (validated) -------------------------------------------------------

## Every field validated with its default; `d` is already migrated.
static func from_dict(d: Dictionary) -> MetaState:
	var m := MetaState.new()
	for k: Variant in d:
		if not KNOWN_KEYS.has(str(k)):
			m.unknown[str(k)] = d[k]
	var created: Variant = d.get("created_at", "")
	if created is String and not (created as String).is_empty():
		m.created_at = created
	m.first_descent_done = to_bool(d.get("first_descent_done"), false)
	var u: Variant = d.get("unlocks", {})
	if u is Dictionary:
		for k: Variant in u:
			m.unlocks[str(k)] = to_bool(u[k], false)
	var notes: Variant = d.get("notes_found", [])
	if notes is Array:
		for n: Variant in notes:
			if (n is String or n is StringName) and not String(n).is_empty() and not m.notes_found.has(StringName(n)):
				m.notes_found.append(StringName(n))
	var codex: Variant = d.get("codex", {})
	if codex is Dictionary:
		for k: Variant in codex:
			m.codex[str(k)] = to_int(codex[k], 0, 0, COUNTER_MAX)
	var seen: Variant = d.get("polaroids_seen", [])
	if seen is Array:
		for p: Variant in seen:
			if (p is int or p is float) and int(p) >= 0 and not m.polaroids_seen.has(int(p)):
				m.polaroids_seen.append(int(p))
	m.stats = validate_stats(d.get("stats", {}))
	m.daily = _validate_daily(d.get("daily", {}))
	m.last_run = _validate_last_run(d.get("last_run", {}))
	m.endless_best_depth = to_int(d.get("endless_best_depth"), 0, 0, Tuning.META_DEPTH_MAX)
	m.cycle_unlocked = to_bool(d.get("cycle_unlocked"), false)
	return m


static func validate_stats(v: Variant) -> Dictionary:
	var s := default_stats()
	if not (v is Dictionary):
		return s
	var src: Dictionary = v
	for k: Variant in src:
		if not s.has(str(k)):
			s[str(k)] = src[k]  # unknown stats keys are preserved too
	for k in STAT_INTS:
		s[k] = to_int(src.get(k), 0, 0, COUNTER_MAX)
	s["best_depth"] = to_int(src.get("best_depth"), 0, 0, Tuning.META_DEPTH_MAX)
	for k in STAT_FLOATS:
		s[k] = to_float(src.get(k), 0.0, 0.0, float(COUNTER_MAX))
	var deaths: Variant = src.get("deaths_by", {})
	if deaths is Dictionary:
		for k: Variant in deaths:
			(s["deaths_by"] as Dictionary)[str(k)] = to_int(deaths[k], 0, 0, COUNTER_MAX)
	var counts: Variant = src.get("depth_reached_counts", {})
	if counts is Dictionary:
		for k: Variant in counts:
			var depth := str(k)
			if depth.is_valid_int() and int(depth) >= Tuning.META_DEPTH_MIN and int(depth) <= Tuning.META_DEPTH_MAX:
				(s["depth_reached_counts"] as Dictionary)[str(int(depth))] = to_int(counts[k], 0, 0, COUNTER_MAX)
	var used: Variant = src.get("items_used", {})
	if used is Dictionary:
		for k: Variant in used:
			(s["items_used"] as Dictionary)[str(k)] = to_int(used[k], 0, 0, COUNTER_MAX)
	var strata: Variant = src.get("strata_reached", [])
	if strata is Array:
		for st: Variant in strata:
			if (st is String or st is StringName) and Tuning.STRATA_ALL.has(StringName(st)) \
					and not (s["strata_reached"] as Array).has(String(st)):
				(s["strata_reached"] as Array).append(String(st))
	return s


static func _validate_daily(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k: Variant in v:
		var key := str(k)
		var entry: Variant = v[k]
		if key.length() != DAILY_KEY_LENGTH or not key.is_valid_int() or not (entry is Dictionary):
			continue
		out[key] = {
			"score": to_int(entry.get("score"), 0, 0, COUNTER_MAX),
			"depth": to_int(entry.get("depth"), Tuning.META_DEPTH_MIN, Tuning.META_DEPTH_MIN, Tuning.META_DEPTH_MAX),
			"cause": str(entry.get("cause", "")),
		}
	return out


static func _validate_last_run(v: Variant) -> Dictionary:
	if not (v is Dictionary) or (v as Dictionary).is_empty():
		return {}
	var d: Dictionary = v
	var seed_v: Variant = d.get("seed", 0)
	return {
		"cause": str(d.get("cause", "")),
		"depth": to_int(d.get("depth"), Tuning.META_DEPTH_MIN, Tuning.META_DEPTH_MIN, Tuning.META_DEPTH_MAX),
		"stratum": str(d.get("stratum", "")),
		"score": to_int(d.get("score"), 0, 0, COUNTER_MAX),
		"seed": int(seed_v) if (seed_v is int or seed_v is float) else 0,
	}


# --- value validation ---------------------------------------------------------------------

## JSON numbers arrive as floats; anything else (or NaN) takes the default.
static func to_int(v: Variant, default: int, lo: int, hi: int) -> int:
	if v is int:
		return clampi(v, lo, hi)
	if v is float and not is_nan(v):
		return clampi(int(clampf(v, float(lo), float(hi))), lo, hi)
	return default


static func to_float(v: Variant, default: float, lo: float, hi: float) -> float:
	if (v is float and not is_nan(v)) or v is int:
		return clampf(float(v), lo, hi)
	return default


static func to_bool(v: Variant, default: bool) -> bool:
	return v if v is bool else default
