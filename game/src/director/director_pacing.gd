class_name DirectorPacing
extends RefCounted
## 10 §2 intensity model and the sawtooth (Calm → Build → Peak → Relief → Build), pure:
## no nodes and no clock of its own. The Director feeds it fixed steps (`step(dt, ...)`,
## 10 Hz) and the one-off events; it answers with a phase and a queue of `actions` the
## Director carries out (wake, hint, retreat). Depth 6 runs Calm then Pursuit (10 §2).
##
## Readings (M1.8): the time input (+0.010/s) and the decay (−0.01/s, −0.03/s in Relief)
## are separate rows and both apply; intensity ≥ 0.8 in Build leaves Build for Peak and
## asks for the nearest hunter to be woken and hinted to 12 m (only when the level has a
## hunter); a contact in Build or Peak ends it (Relief 40 s); an evasion ends Peak.

## Actions the Director drains after each step.
const ACT_WAKE_ONE := &"wake_one"              # Build entry: wake one dormant hunter
const ACT_WAKE_NEAREST := &"wake_nearest"      # intensity ≥ 0.8: wake + hint to 12 m
const ACT_HINT_TOWARD := &"hint_toward"        # Build: 15 to 30 m from the player, every 20 s
const ACT_HINT_AWAY := &"hint_away"            # Relief: hunters ≥ 25 m, Static off the path
const ACT_RETREAT_CHASERS := &"retreat_chasers"  # Peak cap: retreat(20)
const ACT_WAKE_NULL := &"wake_null"            # Pursuit entry (Null is M2.6)
const ACT_HINT_STATIC_ACROSS := &"hint_static_across"  # Pursuit, every 60 s

const CALM := Tuning.DIRECTOR_PHASE_CALM
const BUILD := Tuning.DIRECTOR_PHASE_BUILD
const PEAK := Tuning.DIRECTOR_PHASE_PEAK
const RELIEF := Tuning.DIRECTOR_PHASE_RELIEF
const PURSUIT := Tuning.DIRECTOR_PHASE_PURSUIT
## Fixed steps accumulate float error; durations compare with this slack.
const EPS := 0.0001

var intensity: float = 0.0
var phase: StringName = CALM
## Seconds in the current phase, and on the level.
var phase_time: float = 0.0
var level_time: float = 0.0
var calm_length: float = Tuning.DIRECTOR_CALM_TIME
var relief_length: float = 0.0
## Depth 6 (Substrate): Calm then Pursuit, no sawtooth.
var pursuit: bool = false
var actions: Array[StringName] = []
## Every phase entered, in order (telemetry, the sim harness).
var history: Array[StringName] = [CALM]

var _rng: RandomNumberGenerator
var _hint_left: float = 0.0
var _low_coherence_done: bool = false
var _exit_seen_done: bool = false
var _last_coherence: float = Tuning.COHERENCE_MAX
## 06 §8: after a wall pass that broke line of sight the intensity stays lowered for 15 s.
var _hold_until: float = -1.0
var _hold_value: float = 1.0


## `arrival`: &"start", &"proper" or &"drop" (14 §4). `depth6`: the Pursuit schedule.
func _init(seed_value: int = 0, arrival: StringName = Tuning.RUN_ARRIVE_START, depth6: bool = false) -> void:
	_rng = Seeds.rng(seed_value)
	pursuit = depth6
	calm_length = calm_length_for(arrival, depth6)


## 10 §2 / §7 rule 2: 30 s after a proper exit (or a start), 15 s after a drop; the
## Substrate's Calm is 30 s.
static func calm_length_for(arrival: StringName, depth6: bool = false) -> float:
	if depth6:
		return Tuning.DIRECTOR_PURSUIT_CALM_TIME
	return Tuning.DIRECTOR_CALM_TIME_AFTER_DROP if arrival == Tuning.RUN_ARRIVE_DROP else Tuning.DIRECTOR_CALM_TIME


func calm_left() -> float:
	return maxf(calm_length - level_time, 0.0) if phase == CALM else 0.0


func is_holding() -> bool:
	return level_time < _hold_until


## Adds to intensity, clamped to [0, 1]; a rise is capped while a noclip hold is on.
func add(amount: float) -> void:
	var v := clampf(intensity + amount, Tuning.INTENSITY_MIN, Tuning.INTENSITY_MAX)
	if amount > 0.0 and is_holding():
		v = minf(v, maxf(_hold_value, intensity))
	intensity = v


# --- events (10 §2 table) ------------------------------------------------------------------

func on_sprint_step() -> void:
	add(Tuning.INTENSITY_NOISE_SPRINT_STEP)


func on_crank() -> void:
	add(Tuning.INTENSITY_NOISE_CRANK)


func on_noclip_commit() -> void:
	add(Tuning.INTENSITY_NOISE_NOCLIP)


func on_breaker() -> void:
	add(Tuning.INTENSITY_NOISE_BREAKER)


## +0.10 once per level, when Coherence crosses below 30.
func on_coherence(value: float) -> void:
	var crossed := value < Tuning.COHERENCE_LOW_INTENSITY_BELOW and _last_coherence >= Tuning.COHERENCE_LOW_INTENSITY_BELOW
	_last_coherence = value
	if crossed and not _low_coherence_done:
		_low_coherence_done = true
		add(Tuning.INTENSITY_LOW_COHERENCE)


func on_exit_seen() -> void:
	if _exit_seen_done:
		return
	_exit_seen_done = true
	add(Tuning.INTENSITY_EXIT_SEEN)


func on_note() -> void:
	add(Tuning.INTENSITY_NOTE)


## A `lost_player`. A hunter's evasion during Peak ends it.
func on_evasion(hunter: bool = true) -> void:
	add(Tuning.INTENSITY_EVASION)
	if hunter and phase == PEAK:
		_enter(RELIEF)


## The bite ends the peak: Relief 40 s (also when the chase had not been seen yet).
func on_contact() -> void:
	add(Tuning.INTENSITY_CONTACT)
	if phase == PEAK or phase == BUILD:
		_enter(RELIEF, Tuning.DIRECTOR_RELIEF_AFTER_CONTACT_TIME)


## 06 §8, 10 §2: −0.20 and no rise above the new value for 15 s.
func on_noclip_broke_los() -> void:
	add(Tuning.INTENSITY_NOCLIP_BROKE_LOS)
	_hold_until = level_time + Tuning.NOCLIP_DIRECTOR_RELIEF_TIME
	_hold_value = intensity


# --- the 10 Hz step -------------------------------------------------------------------------

## One fixed step. `nearest_hunter_d`: distance to the nearest awake hunter (INF if none);
## `chasing`: hunters in Chase/Follow/Stalk; `hunters`: hunters on the level.
func step(dt: float, nearest_hunter_d: float = INF, chasing: int = 0, hunters: int = 0) -> void:
	level_time += dt
	phase_time += dt
	if phase != CALM:
		add(Tuning.INTENSITY_TIME_PER_S * dt)
	if not is_inf(nearest_hunter_d):
		var near := clampf((Tuning.INTENSITY_NEAREST_HUNTER_RANGE - nearest_hunter_d) / Tuning.INTENSITY_NEAREST_HUNTER_RANGE, 0.0, 1.0)
		add(near * Tuning.INTENSITY_NEAREST_HUNTER_PER_S * dt)
	if chasing > 0:
		add(Tuning.INTENSITY_CHASE_PER_S * dt)
	add((Tuning.INTENSITY_DECAY_RELIEF_PER_S if phase == RELIEF else Tuning.INTENSITY_DECAY_PER_S) * dt)
	if phase == PURSUIT:
		intensity = maxf(intensity, Tuning.DIRECTOR_PURSUIT_INTENSITY_FLOOR)
	_advance(dt, chasing, hunters)


func _advance(dt: float, chasing: int, hunters: int) -> void:
	match phase:
		CALM:
			if phase_time >= calm_length - EPS:
				_enter(PURSUIT if pursuit else BUILD)
		BUILD:
			if chasing > 0:
				_enter(PEAK)
			elif intensity >= Tuning.DIRECTOR_WAKE_INTENSITY and hunters > 0:
				actions.append(ACT_WAKE_NEAREST)
				_enter(PEAK)
			else:
				_hint_left -= dt
				if _hint_left <= EPS:
					_hint_left = Tuning.DIRECTOR_HINT_INTERVAL
					actions.append(ACT_HINT_TOWARD)
		PEAK:
			if phase_time >= Tuning.DIRECTOR_PEAK_MAX_TIME - EPS:
				# 10 §2: a chase that does not resolve is exhausting, not scary.
				actions.append(ACT_RETREAT_CHASERS)
				_enter(RELIEF)
		RELIEF:
			if phase_time >= relief_length - EPS:
				_enter(BUILD)
			else:
				_hint_left -= dt
				if _hint_left <= EPS:
					_hint_left = Tuning.DIRECTOR_HINT_INTERVAL
					actions.append(ACT_HINT_AWAY)
		PURSUIT:
			_hint_left -= dt
			if _hint_left <= EPS:
				_hint_left = Tuning.DIRECTOR_PURSUIT_STATIC_HINT_INTERVAL
				actions.append(ACT_HINT_STATIC_ACROSS)


func _enter(to: StringName, relief_time: float = -1.0) -> void:
	phase = to
	phase_time = 0.0
	history.append(to)
	match to:
		BUILD:
			actions.append(ACT_WAKE_ONE)
			actions.append(ACT_HINT_TOWARD)
			_hint_left = Tuning.DIRECTOR_HINT_INTERVAL
		RELIEF:
			relief_length = relief_time if relief_time >= 0.0 else \
				_rng.randf_range(Tuning.DIRECTOR_RELIEF_MIN_TIME, Tuning.DIRECTOR_RELIEF_MAX_TIME)
			actions.append(ACT_HINT_AWAY)
			_hint_left = Tuning.DIRECTOR_HINT_INTERVAL
		PURSUIT:
			actions.append(ACT_WAKE_NULL)
			actions.append(ACT_HINT_STATIC_ACROSS)
			_hint_left = Tuning.DIRECTOR_PURSUIT_STATIC_HINT_INTERVAL


## Returns and clears the queued actions.
func take_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(actions)
	actions.clear()
	return out
