class_name Scares
extends RefCounted
## 10 §5 scares: cheap, honest-sounding events that build anticipation. This class is the
## gating and the bookkeeping, pure and clock-driven: Build only (never Calm, Peak, Relief or
## Pursuit), at most one per 30 s, none below 0.2 intensity and all above 0.5, each kind's own
## minimum interval, and never while a hunter is within SCARE_HUNTER_CLEAR_DIST of the player
## (pillar 3: a scare is never the way an error kills, so it never lands on a contact).
## The events themselves (door slam, payphone ring, Static swell, fixture dropout, Echo
## pre-echo) are `executors`: kind -> Callable() -> bool, true when the event ran. The
## Director binds ScareEvents' world executors; tests bind fakes. Scares never cost
## Coherence and never spawn anything.

const DOOR_SLAM := &"door_slam"
const PAYPHONE := &"payphone"
const STATIC_SWELL := &"static_swell"
const FIXTURE_DROPOUT := &"fixture_dropout"
const PRE_ECHO := &"pre_echo"
## Cheapest first: as intensity climbs from 0.2 to 0.5 more of the list opens.
const ORDER: Array[StringName] = [STATIC_SWELL, FIXTURE_DROPOUT, DOOR_SLAM, PRE_ECHO, PAYPHONE]

var last_any: float = -INF
var last_by_kind: Dictionary = {}
## Every request (kind, time), for tests and telemetry.
var requested: Array[Dictionary] = []
## Every scare that ran: {kind, time}.
var fired: Array[Dictionary] = []
## kind -> Callable() -> bool (ScareEvents.bind, or a test's fakes).
var executors: Dictionary = {}

var _rng: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	_rng = Seeds.rng(seed_value)


static func min_interval(kind: StringName) -> float:
	match kind:
		DOOR_SLAM:
			return Tuning.SCARE_DOOR_SLAM_INTERVAL
		PAYPHONE:
			return Tuning.SCARE_PAYPHONE_INTERVAL
		STATIC_SWELL:
			return Tuning.SCARE_STATIC_SWELL_INTERVAL
		FIXTURE_DROPOUT:
			return Tuning.SCARE_FIXTURE_DROPOUT_INTERVAL
		PRE_ECHO:
			return Tuning.SCARE_PRE_ECHO_INTERVAL
	return INF


## Kinds allowed now (10 §5): Build only, at most one per 30 s, scaled by intensity, each
## kind's own interval, and none while a hunter is near (`hunter_d`: the nearest awake hunter,
## INF when none).
func available(phase: StringName, intensity: float, now: float, hunter_d: float = INF) -> Array[StringName]:
	var out: Array[StringName] = []
	if phase != Tuning.DIRECTOR_PHASE_BUILD or intensity < Tuning.SCARE_INTENSITY_NONE_BELOW:
		return out
	if hunter_d < Tuning.SCARE_HUNTER_CLEAR_DIST:
		return out
	if now - last_any < Tuning.SCARE_MIN_INTERVAL:
		return out
	var span := Tuning.SCARE_INTENSITY_ALL_ABOVE - Tuning.SCARE_INTENSITY_NONE_BELOW
	var frac := clampf((intensity - Tuning.SCARE_INTENSITY_NONE_BELOW) / span, 0.0, 1.0)
	var count := clampi(ceili(frac * ORDER.size()), 1, ORDER.size())
	for i in count:
		var k := ORDER[i]
		if interval_ok(k, now):
			out.append(k)
	return out


## The global 30 s and the kind's own interval have both passed.
func interval_ok(kind: StringName, now: float) -> bool:
	return now - last_any >= Tuning.SCARE_MIN_INTERVAL and now - float(last_by_kind.get(kind, -INF)) >= min_interval(kind)


## Runs a scare of `kind` now when its intervals allow and its executor finds a place for it
## (a door, a payphone, a fixture, a Static, an Echo). The phase is the caller's check
## (`available`, Director.request_scare). Returns true when it ran.
func request(kind: StringName, now: float) -> bool:
	requested.append({&"kind": kind, &"time": now})
	if not interval_ok(kind, now):
		return false
	var ex: Callable = executors.get(kind, Callable())
	if not ex.is_valid() or not bool(ex.call()):
		return false
	last_any = now
	last_by_kind[kind] = now
	fired.append({&"kind": kind, &"time": now})
	return true


## Tries the available kinds in a seeded random order until one runs. Returns its kind, or
## &"" when none could run.
func try_any(phase: StringName, intensity: float, now: float, hunter_d: float = INF) -> StringName:
	var kinds := available(phase, intensity, now, hunter_d)
	for i in range(kinds.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	for k in kinds:
		if request(k, now):
			return k
	return &""


## Scares of `kind` that ran (all kinds when empty).
func count(kind: StringName = &"") -> int:
	if kind == &"":
		return fired.size()
	return fired.filter(func(f: Dictionary) -> bool: return f[&"kind"] == kind).size()


## Seconds since the last scare that ran (INF when none).
func since_last(now: float) -> float:
	return now - last_any
