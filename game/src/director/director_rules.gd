class_name DirectorRules
extends RefCounted
## The Director's pure rules (10 §3, §4, §6, §7), each a function with explicit inputs so
## the fairness checks are unit-testable with a deterministic clock.

const HUNTERS: Array[StringName] = [&"still", &"echo", &"flicker", &"null"]
## 05 §10: the depth-1 hunter from the second Descent on, and 05 §3's "met hunter".
const MET_HUNTER_CHOICES: Array[StringName] = [&"still", &"echo"]


## Depth inside its Cycle (1..6): Cycle 2 repeats the table (05 §3).
static func cycle_depth(depth: int) -> int:
	return (maxi(depth, 1) - 1) % Tuning.RUN_CYCLE_LENGTH + 1


static func cycle_of(depth: int) -> int:
	return (maxi(depth, 1) - 1) / Tuning.RUN_CYCLE_LENGTH + 1


static func is_hunter(id: StringName) -> bool:
	return HUNTERS.has(id)


static func is_chasing_state(state: StringName) -> bool:
	return Tuning.DIRECTOR_CHASE_STATES.has(state)


# --- 10 §3 aggression -------------------------------------------------------------------------

static func base_aggression(depth: int) -> float:
	return float(Tuning.AGGRESSION_BASE_BY_DEPTH.get(cycle_depth(depth), Tuning.AGGRESSION_BASE_BY_DEPTH[1]))


## 05 §3: +0.15 after one drop, +0.25 after two or more (and never more: §7 rule 7).
static func awake_bonus(drops_in_a_row: int) -> float:
	if drops_in_a_row <= 0:
		return 0.0
	return Tuning.AWAKE_ONE_DROP if drops_in_a_row == 1 else Tuning.AWAKE_TWO_DROPS


## +0.10 per full minute beyond 2× the level's target time, capped at +0.30 (§7 rule 8).
static func time_pressure(depth: int, level_seconds: float) -> float:
	var target: float = Tuning.LEVEL_TARGET_TIME.get(cycle_depth(depth), Tuning.LEVEL_TARGET_TIME[1])
	var over := level_seconds - target * Tuning.RUN_TIME_PRESSURE_TARGET_MULT
	if over < 0.0:
		return 0.0
	var minutes := floorf(over / 60.0)
	return minf(minutes * Tuning.DIRECTOR_TIME_PRESSURE_PER_MINUTE, Tuning.DIRECTOR_TIME_PRESSURE_CAP)


static func cycle_bonus(cycle: int) -> float:
	return Tuning.AGGRESSION_CYCLE2_BONUS if cycle >= 2 else 0.0


## aggression = clamp(base(depth) + awake + time_pressure + cycle, 0, 1).
static func aggression(depth: int, drops_in_a_row: int, level_seconds: float, cycle: int) -> float:
	return clampf(base_aggression(depth) + awake_bonus(drops_in_a_row) + time_pressure(depth, level_seconds)
		+ cycle_bonus(cycle), 0.0, 1.0)


## 05 §10: the depth-1 hunter of a later Descent runs at 0.2 in place of the 0.25 base.
static func error_aggression(level_aggression: float, depth: int, id: StringName) -> float:
	if cycle_depth(depth) == 1 and is_hunter(id):
		return clampf(level_aggression - base_aggression(depth) + Tuning.FIRST_DESCENT_DEPTH1_AGGRESSION, 0.0, 1.0)
	return level_aggression


# --- 10 §4 roster ---------------------------------------------------------------------------

## The roster of error ids for a level (05 §3, §10), in spawn order (Static first). It is
## the design roster; ids without a scene yet are skipped by the Director (`spawnable`).
static func roster(depth: int, stratum: StringName, first_descent: bool, met: Array, rng: RandomNumberGenerator) -> Array[StringName]:
	var d := cycle_depth(depth)
	var cycle := cycle_of(depth)
	var spec: Dictionary = Tuning.ROSTER_BY_DEPTH.get(d, {})
	var out: Array[StringName] = []
	var statics := int(spec.get(&"static", 0)) + (Tuning.ROSTER_CYCLE2_EXTRA_STATIC if cycle >= 2 else 0)
	for i in statics:
		out.append(&"static")
	if d == 1 and not first_descent:
		# 05 §10: from the second Descent on, a dormant Still or Echo at 0.2.
		out.append(MET_HUNTER_CHOICES[rng.randi_range(0, MET_HUNTER_CHOICES.size() - 1)])
	var native := native_for(stratum, met, rng)
	if spec.has(&"native") and native != &"":
		out.append(native)
	if spec.has(&"met_hunter"):
		out.append(met_hunter(native, met, rng))
	for id: StringName in [&"still", &"echo", &"flicker"]:
		if spec.has(id) and not out.has(id):
			out.append(id)
	if spec.has(&"null") and stratum == Tuning.STRATUM_SUBSTRATE:
		out.append(&"null")
	return out


## The stratum's teaching error; Server's slot is a hunter already met this run (05 §3).
static func native_for(stratum: StringName, met: Array, rng: RandomNumberGenerator) -> StringName:
	if stratum == Tuning.STRATUM_SERVER:
		var pool: Array[StringName] = []
		for id in met:
			if is_hunter(StringName(id)) and StringName(id) != &"null":
				pool.append(StringName(id))
		if pool.is_empty():
			pool = MET_HUNTER_CHOICES.duplicate()
		pool.sort()
		return pool[rng.randi_range(0, pool.size() - 1)]
	return StringName(Tuning.STRATUM_NATIVE_ERROR.get(stratum, &""))


## Depth 4: one of the hunters already met this run (Still or Echo), not the native.
static func met_hunter(native: StringName, met: Array, rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = []
	for id in MET_HUNTER_CHOICES:
		if met.has(id) and id != native:
			pool.append(id)
	if pool.is_empty():
		for id in MET_HUNTER_CHOICES:
			if id != native:
				pool.append(id)
	return pool[rng.randi_range(0, pool.size() - 1)]


## An id is spawned when it has a scene (ErrorBase.SCENES); Null arrives with M2.6.
static func spawnable(id: StringName) -> bool:
	return ErrorBase.SCENES.has(id)


## 10 §4: depth ≤ 3: 1; 4 to 5: 2; 6: Null plus 1. Static never counts.
static func max_chasers(depth: int) -> int:
	return int(Tuning.DIRECTOR_MAX_CHASERS.get(cycle_depth(depth), 1))


## 10 §4 depth 6 "Null plus 1": the cap for hunters other than Null. Null never counts
## against it (it is the Pursuit) and is never sent away by it.
static func max_other_chasers(depth: int) -> int:
	var cap := max_chasers(depth)
	return maxi(cap - 1, 1) if cycle_depth(depth) == 6 else cap


## 10 §4, §7 rule 6: given the chasing hunters' ids nearest first, the indices of those over
## the cap (the farthest), which the Director retreats. Null is never among them.
static func chasers_over_cap(ids: Array[StringName], depth: int) -> Array[int]:
	var out: Array[int] = []
	var kept := 0
	for i in ids.size():
		if ids[i] == &"null":
			continue
		kept += 1
		if kept > max_other_chasers(depth):
			out.append(i)
	return out


## True when the chasers (ids) fill the cap, so the free hunters are hinted away.
static func chaser_cap_reached(ids: Array[StringName], depth: int) -> bool:
	return ids.filter(func(id: StringName) -> bool: return id != &"null").size() >= max_other_chasers(depth)


## The Director wakes every hunter but Null by its phases; Null wakes only when the
## Substrate's Calm ends (10 §2, §7 rule 9).
static func phase_wakes(id: StringName) -> bool:
	return is_hunter(id) and id != &"null"


## 05 §3, 10 §4 awake arrivals: the indices (into the spawned hunters' ids, spawn order) of
## the one or two that start in Search after drops. Null never does (§7 rule 9).
static func awake_arrival_indices(ids: Array[StringName], drops_in_a_row: int) -> Array[int]:
	var out: Array[int] = []
	var want := awake_hunters(drops_in_a_row)
	for i in ids.size():
		if out.size() >= want:
			break
		if phase_wakes(ids[i]):
			out.append(i)
	return out


## 05 §3: hunters starting in Search after one drop, or two and more.
static func awake_hunters(drops_in_a_row: int) -> int:
	if drops_in_a_row <= 0:
		return 0
	return Tuning.AWAKE_SEARCHING_HUNTERS_ONE if drops_in_a_row == 1 else Tuning.AWAKE_SEARCHING_HUNTERS_TWO


# --- 10 §4 contact exclusivity --------------------------------------------------------------

## True when a contact at `now_ms` is allowed after the last one (`last_ms` < 0: none yet).
static func contact_allowed(now_ms: int, last_ms: int) -> bool:
	return last_ms < 0 or now_ms - last_ms >= int(Tuning.CONTACT_EXCLUSIVITY_TIME * 1000.0)


# --- 10 §6 threat -------------------------------------------------------------------------------

## One hunter's share: clamp((15 − d) / 15, 0, 1), ×1.0 in Chase, ×0.5 otherwise.
static func hunter_threat(d: float, chasing: bool) -> float:
	var t := clampf((Tuning.THREAT_RANGE - d) / Tuning.THREAT_RANGE, 0.0, 1.0)
	return t * (Tuning.THREAT_CHASE_MULT if chasing else Tuning.THREAT_OTHER_MULT)


## max over hunters, plus 0.3 inside Static's field, plus 1 − d/12 inside Null's radius.
static func threat_target(hunter_max: float, inside_static: bool, null_d: float) -> float:
	var t := hunter_max
	if inside_static:
		t += Tuning.THREAT_STATIC_BONUS
	if null_d < Tuning.THREAT_NULL_RADIUS:
		t += 1.0 - null_d / Tuning.THREAT_NULL_RADIUS
	return clampf(t, 0.0, 1.0)


## First-order smoothing: 0.5 s time constant up, 2 s down.
static func smooth_threat(current: float, target: float, dt: float) -> float:
	var tau := Tuning.THREAT_SMOOTH_UP_TIME if target > current else Tuning.THREAT_SMOOTH_DOWN_TIME
	return current + (target - current) * (1.0 - exp(-dt / tau))


# --- 10 §2 Pursuit, §7 rule 9 -----------------------------------------------------------------

## A critical-path cell to hint Static across during the Substrate's Pursuit: never in the
## Threshold pocket (the exit room) nor within the Static clearance (6 m, more than a field's
## 5 m radius) of it, so a field hinted there cannot cover the pocket. NO_CELL when the path
## has no such cell.
static func pursuit_static_cell(grid: LevelGrid, path: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var pocket: Array[Vector3] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			pocket.append(grid.world_of(c))
	var pool: Array[Vector2i] = []
	for c in path:
		if grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			continue
		var w := grid.world_of(c)
		var near := false
		for q in pocket:
			if DirectorSpawn.flat_dist(w, q) < Tuning.DIRECTOR_STATIC_OFF_PATH_CLEARANCE:
				near = true
				break
		if not near:
			pool.append(c)
	if pool.is_empty():
		return LevelData.NO_CELL
	return pool[rng.randi_range(0, pool.size() - 1)]
