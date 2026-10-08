class_name SimBotNull
extends RefCounted
## The sim bot's reading of Null (08 §7, M2.6). The explorer and the cautious bot play its
## counter once it is awake (the Pursuit): no exploring, no stopping (crank, look-back,
## pickups, waiting out a Static while Null is within its radius), sprint inside its 12 m
## radius, and route around a 4 m ring of cells about it when the maze has a way around
## (the view through unrendered walls tells a player where it is). Hiding is no counter
## (06 §10: hiding does not stop the core): the Pursuit branch runs before the hide logic.
## The direct bot only sprints with Null within 15 m, as with any chaser, and keeps its
## path. Records the Pursuit timing, the wake distance and the cost.

## Cells within this of Null's floor point are avoided (its 2 m core plus a body and the
## 2.4 m/s it walks between repaths).
const AVOID := 4.0
## Inside Null's radius the bot keeps moving and sprints.
const PRESS := 12.0
const REPATH := 0.5

var bot: SimBot
## Bot seconds when Null entered Chase (-1 never), seconds in its core, Coherence drained.
var woke_at: float = -1.0
var core_s: float = 0.0
var drained: float = 0.0
var min_dist: float = INF
## Distance (floor, XZ+Y) from Null to the player when it woke.
var wake_dist: float = -1.0


func find() -> ErrorNull:
	for n in bot.tree.get_nodes_in_group(ErrorBase.GROUP):
		var e := n as ErrorNull
		if e != null and is_instance_valid(e):
			return e
	return null


func pursuing() -> bool:
	var e := find()
	return e != null and e.state == Tuning.ERROR_STATE_CHASE


func near(dist: float) -> bool:
	var e := find()
	return e != null and e.state == Tuning.ERROR_STATE_CHASE and e.distance_to_player() < dist


## Called once per physics frame by the bot.
func tick(t: float, dt: float) -> void:
	var e := find()
	if e == null or e.state != Tuning.ERROR_STATE_CHASE:
		return
	if woke_at < 0.0:
		woke_at = t
		wake_dist = e.distance_to_player()
	if e.in_core():
		core_s += dt
	drained = e.drained
	min_dist = minf(min_dist, e.distance_to_player())


## Walkable cells inside the avoid ring around the awake Null (empty when it sleeps).
func cells(grid: LevelGrid) -> Dictionary:
	var out := {}
	var e := find()
	if e == null or e.state != Tuning.ERROR_STATE_CHASE:
		return out
	var at := e.global_position
	var cc := grid.cell_of(at)
	var span := ceili(AVOID / Tuning.GRID_CELL_SIZE) + 1
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c := cc + Vector2i(dx, dz)
			if grid.in_bounds(c) and DirectorSpawn.flat_dist(grid.world_of(c), at) < AVOID:
				out[c] = true
	return out


func results(result: Dictionary) -> void:
	result[&"null_woke_s"] = snappedf(woke_at, 0.1)
	result[&"null_core_s"] = snappedf(core_s, 0.1)
	result[&"null_drained"] = snappedf(drained, 0.1)
	result[&"null_wake_dist"] = snappedf(wake_dist, 0.1)
	result[&"null_min_dist"] = snappedf(min_dist, 0.1) if not is_inf(min_dist) else -1.0
