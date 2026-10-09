class_name EchoTrail
extends RefCounted
## Echo's copy of the player's step trail (08 §6): only the steps Echo actually heard,
## stamped on Echo's own clock (seconds), oldest first. Pure data; ErrorEcho walks it.
##
## In Follow, Echo targets the entry recorded ECHO_TRAIL_DELAY (800 ms) before the newest
## heard entry (not 800 ms before now), so when the player stops no entry arrives and the
## target stops moving: Echo reaches it and freezes (CHANGELOG 2026-10-07).
## `next_index` is the first entry Echo has not reached yet; entries it can reach
## directly are trimmed by the walker (advance_to), which is how it gains on corners.
## Entries: {position: Vector3, time: float (Echo's clock), surface: StringName,
## speed_kind: StringName (walk / sprint / crouch), resolved: bool}.

var entries: Array[Dictionary] = []
var next_index: int = 0
var capacity: int = Tuning.ECHO_TRAIL_CAPACITY
## R21: entries added unresolved since the last resolve() (an upper bound: a dropped entry
## is not subtracted), so resolve() does not walk the whole trail every physics frame.
var _unresolved: int = 0
## R21: target_index() is asked every physics frame but changes only when a step is heard
## or dropped; the answer is kept for the trail version and delay it was computed for.
var _version: int = 0
var _target_version: int = -1
var _target_size: int = -1
var _target_delay: float = NAN
var _target_cached: int = -1


func clear() -> void:
	entries.clear()
	next_index = 0
	_unresolved = 0
	_version += 1


func size() -> int:
	return entries.size()


func is_empty() -> bool:
	return entries.is_empty()


## A heard step at `pos` at Echo time `time`. Surface and speed kind are filled from the
## player's step trail by resolve() (the noise arrives before the player pushes the entry).
func add(pos: Vector3, time: float, surface: StringName = &"", speed_kind: StringName = &"") -> Dictionary:
	var e := {&"position": pos, &"time": time, &"surface": surface, &"speed_kind": speed_kind,
		&"resolved": surface != &"" and speed_kind != &""}
	entries.append(e)
	_version += 1
	if not bool(e[&"resolved"]):
		_unresolved += 1
	while entries.size() > capacity:
		entries.pop_front()
		next_index = maxi(next_index - 1, 0)
	return e


func newest() -> Dictionary:
	return entries[-1] if not entries.is_empty() else {}


func newest_time() -> float:
	return float(entries[-1][&"time"]) if not entries.is_empty() else -INF


## The entry Echo targets in Follow: the last one recorded at least `delay` before the
## newest heard entry, else the earliest heard one. -1 when empty.
func target_index(delay: float = Tuning.ECHO_TRAIL_DELAY) -> int:
	if entries.is_empty():
		return -1
	if _version == _target_version and entries.size() == _target_size and delay == _target_delay:
		return _target_cached
	var limit := newest_time() - delay + 1e-6
	var out := 0
	for i in entries.size():
		if float(entries[i][&"time"]) <= limit:
			out = i
		else:
			break
	_target_version = _version
	_target_size = entries.size()
	_target_delay = delay
	_target_cached = out
	return out


## True when Echo has reached its target entry (nothing to walk: it stands).
func at_target(delay: float = Tuning.ECHO_TRAIL_DELAY) -> bool:
	return entries.is_empty() or next_index > target_index(delay)


## Echo reached entry `i` (or trimmed to it).
func advance_to(i: int) -> void:
	next_index = maxi(next_index, i + 1)


## Heard entries recorded at or after `t`.
func count_since(t: float) -> int:
	var n := 0
	for i in range(entries.size() - 1, -1, -1):
		if float(entries[i][&"time"]) < t:
			break
		n += 1
	return n


## Drops entries older than `t` (the trail starts at the earliest heard step of a window).
func drop_before(t: float) -> void:
	while not entries.is_empty() and float(entries[0][&"time"]) < t:
		entries.pop_front()
		_version += 1
		next_index = maxi(next_index - 1, 0)


## Fills surface and speed kind of unresolved entries from the player's trail
## (Player.step_trail(), 08 Interfaces) by matching the step position. Unmatched entries
## keep `fallback_surface` and walk.
func resolve(player_trail: RingBuffer, fallback_surface: StringName) -> void:
	if _unresolved == 0:
		return
	_unresolved = 0
	for e in entries:
		if bool(e[&"resolved"]):
			continue
		var found: Variant = _match(player_trail, e[&"position"])
		if found is Dictionary:
			e[&"surface"] = StringName((found as Dictionary).get(&"surface", fallback_surface))
			e[&"speed_kind"] = StringName((found as Dictionary).get(&"speed_kind", NoiseModel.GAIT_WALK))
		else:
			e[&"surface"] = fallback_surface if e[&"surface"] == &"" else e[&"surface"]
			e[&"speed_kind"] = NoiseModel.GAIT_WALK if e[&"speed_kind"] == &"" else e[&"speed_kind"]
		e[&"resolved"] = true


static func _match(trail: RingBuffer, pos: Vector3) -> Variant:
	if trail == null:
		return null
	for i in range(trail.size() - 1, maxi(trail.size() - Tuning.ECHO_RESOLVE_LOOKBACK, 0) - 1, -1):
		var t: Variant = trail.get_at(i)
		if t is Dictionary and ((t as Dictionary).get(&"position", Vector3.INF) as Vector3).distance_to(pos) < 0.01:
			return t
	return null


## 08 §6: the recorded speed kind's speed (walk 3.2, sprint 5.6, crouch 1.6 m/s).
static func speed_for(kind: StringName) -> float:
	match kind:
		NoiseModel.GAIT_SPRINT:
			return Tuning.PLAYER_SPRINT_SPEED
		NoiseModel.GAIT_CROUCH:
			return Tuning.PLAYER_CROUCH_SPEED
	return Tuning.PLAYER_WALK_SPEED
