class_name StaticFeed
extends RefCounted
## Static's presentation feed (split out of ErrorStatic, 14 §6): every Static's field
## strength on the player and its distance to the player. The renderer (02 §8: grain 0.6,
## CA 0.02 inside; 08 §3: the drain floor 0.6), the static bed (03) and the 0.002 m camera
## jitter (11 §3) get the strongest field over every Static. Only the Static nearest the
## player pushes, and only when the value moves.

static var _strength: Dictionary = {}
static var _dist: Dictionary = {}
static var _pushed: float = -1.0


## Records one Static's strength (0 outside) and distance; pushes when it is the nearest.
static func report(key: int, s: float, dist: float, player: Player) -> void:
	if s > 0.0:
		_strength[key] = s
	else:
		_strength.erase(key)
	_dist[key] = dist
	if _is_nearest(key):
		push(player)


## A Static that sleeps or leaves: it no longer leads or feeds.
static func forget(key: int, player: Player) -> void:
	_strength.erase(key)
	var had := _dist.erase(key)
	if had:
		push(player)


static func strongest() -> float:
	var top := 0.0
	for v: float in _strength.values():
		top = maxf(top, v)
	return top


static func _is_nearest(key: int) -> bool:
	var mine: float = _dist.get(key, INF)
	for k: int in _dist:
		var d: float = _dist[k]
		if d < mine or (d == mine and k < key):
			return false
	return true


static func push(player: Player) -> void:
	var top := strongest()
	if top == _pushed:
		return
	_pushed = top
	CoherenceRenderer.set_static(top)
	CoherenceRenderer.set_drain_floor(Tuning.STATIC_FORCED_DRAIN * top)
	AudioManager.set_static_inside(top > 0.0)
	if player != null and is_instance_valid(player) and player.rig != null:
		player.rig.set_jitter(Tuning.FEEDBACK_STATIC_JITTER if top > 0.0 else 0.0)
