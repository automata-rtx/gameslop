class_name Scares
extends RefCounted
## 10 §5 scares, M1 stub: the gating is real (Build only, one per 30 s, none below 0.2
## intensity, all above 0.5, per-kind minimum intervals) and `request` is a no-op that
## returns false. The events themselves (door slam, payphone, Static swell, fixture
## dropout, Echo pre-echo) land with their props and errors in M2.
## Scares never cost Coherence and never spawn anything.

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


## Kinds allowed now (10 §5): Build only, at most one per 30 s, scaled by intensity.
func available(phase: StringName, intensity: float, now: float) -> Array[StringName]:
	var out: Array[StringName] = []
	if phase != Tuning.DIRECTOR_PHASE_BUILD or intensity < Tuning.SCARE_INTENSITY_NONE_BELOW:
		return out
	if now - last_any < Tuning.SCARE_MIN_INTERVAL:
		return out
	var span := Tuning.SCARE_INTENSITY_ALL_ABOVE - Tuning.SCARE_INTENSITY_NONE_BELOW
	var frac := clampf((intensity - Tuning.SCARE_INTENSITY_NONE_BELOW) / span, 0.0, 1.0)
	var count := clampi(ceili(frac * ORDER.size()), 1, ORDER.size())
	for i in count:
		var k := ORDER[i]
		if now - float(last_by_kind.get(k, -INF)) >= min_interval(k):
			out.append(k)
	return out


## Asks for a scare of `kind`. M1: records the request and does nothing (returns false);
## a scare that ran would set last_any and last_by_kind.
func request(kind: StringName, now: float) -> bool:
	requested.append({&"kind": kind, &"time": now})
	# TODO(M2): door slam, payphone, Static swell, fixture dropout, Echo pre-echo.
	return false
