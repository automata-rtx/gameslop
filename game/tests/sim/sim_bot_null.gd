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
## R14b: a route around Null is kept between repaths unless a new one is clearly better
## (SimBot._kept_route), so the bot no longer flips between ways every 0.5 s.
## R14: in the Pursuit the explorer and the cautious bot also route through soft walls when
## that shortens the way to the Threshold (a player reading the unrender view sees them),
## by the real noclip input: stand at the cell centre before the soft edge, face it, hold
## `noclip` through the 0.35 s charge and the pass, release. Only while Coherence is above
## twice the 5 Coherence cost (noclip can never take the last of it: TOO THIN); a soft wall
## the aim refuses or that does not carry the body across is not tried again.

## Cells within this of Null's floor point are avoided (its 2 m core plus a body and the
## 2.4 m/s it walks between repaths).
const AVOID := 4.0
## Inside Null's radius the bot keeps moving and sprints.
const PRESS := 12.0
const REPATH := 0.5
## Soft-wall noclip (R14): Coherence must exceed this many times the cost; give up on a
## crossing after this long; read an invalid aim only after the hold has had this long.
const SOFT_AFFORD := 2.0
const SOFT_GIVE_UP := 2.0
const SOFT_AIM_GRACE := 0.2
## Within this of the near cell's centre the bot stops walking and charges (the ray reaches
## 2.5 m; the wall is 1 m from the centre).
const SOFT_AT := 0.6
## R14b route hysteresis: a new route replaces the kept one only when it is under this
## fraction of the kept route's remaining length (20% shorter), or when the kept route
## enters Null's 2 m core (or a Static field, or cannot be walked any more).
const ROUTE_SWITCH := 0.8
## M3.4: in the Pursuit every profile walks straight across open floor to the farthest of
## the next STRAIGHT_LOOKAHEAD waypoints it can reach on a clear line (a player reading the
## unrender view does not walk a room's cells in an L or a staircase). A line is clear when
## it and its two parallels STRAIGHT_HALF_WIDTH to either side step only through open edges.
const STRAIGHT_LOOKAHEAD := 8
const STRAIGHT_HALF_WIDTH := 0.45
const STRAIGHT_SAMPLE := 0.2

var bot: SimBot
## Bot seconds when Null entered Chase (-1 never), seconds in its core, Coherence drained.
var woke_at: float = -1.0
var core_s: float = 0.0
var drained: float = 0.0
var min_dist: float = INF
## Distance (floor, XZ+Y) from Null to the player when it woke.
var wake_dist: float = -1.0
## Soft-wall passes made, crossings given up, and the edges (LevelGrid.edge_key) not to try.
var soft_passes: int = 0
## The level's shape at the wake (`_wake_shape`, R14 report keys).
var shape: Dictionary = {}
var soft_fails: int = 0
var bad_soft: Dictionary = {}
## The crossing under way: the near cell and the direction (-1 none), seconds held.
var _nc_cell: Vector2i = LevelData.NO_CELL
var _nc_dir: int = -1
var _nc_held: float = 0.0


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
		_wake_shape(e)
	if e.in_core():
		core_s += dt
	drained = e.drained
	min_dist = minf(min_dist, e.distance_to_player())


## R14 report: the level's shape at the wake (where the player and Null stand on the
## critical path, how winding the walk to the Threshold is from each, the dead ends).
func _wake_shape(e: ErrorNull) -> void:
	var data := bot.run.data
	var g := data.grid
	var path := data.critical_path
	var pc := g.cell_of(bot.run.player.global_position)
	var nc := g.cell_of(e.global_position)
	shape[&"null_replaced"] = bot.director.hunters.null_replaced
	shape[&"null_wake_flat"] = snappedf(DirectorSpawn.flat_dist(e.global_position, bot.run.player.global_position), 0.1)
	shape[&"path_m"] = snappedf((path.size() - 1) * Tuning.GRID_CELL_SIZE, 1.0)
	shape[&"player_path_f"] = snappedf(DirectorSpawn.path_fraction(path, pc), 0.01)
	shape[&"null_path_f"] = snappedf(DirectorSpawn.path_fraction(path, nc), 0.01)
	var exit := path[path.size() - 1] if not path.is_empty() else data.exit_cell
	var to_exit := g.distance_field(exit)
	for pair: Array in [[&"winding_player", pc], [&"winding_null", nc]]:
		var c: Vector2i = pair[1]
		var straight := DirectorSpawn.flat_dist(g.world_of(c), g.world_of(exit))
		var w := to_exit[g.idx(c)] if g.in_bounds(c) else -1
		shape[pair[0]] = snappedf(w * Tuning.GRID_CELL_SIZE / straight, 0.01) if w >= 0 and straight > 0.0 else -1.0
	var chains := MazeOps.dead_end_chains(g)
	var longest := 0
	for chain in chains:
		longest = maxi(longest, chain.size())
	shape[&"dead_ends"] = chains.size()
	shape[&"dead_end_longest"] = longest
	if OS.has_environment("SIMBOT_NULL"):
		print("null-wake t=%.1f player=%s null=%s %s" % [woke_at, pc, nc, shape])


## True when `floor_pos` is inside the awake Null's 2 m core (XZ).
func in_core(floor_pos: Vector3) -> bool:
	var e := find()
	return e != null and e.state == Tuning.ERROR_STATE_CHASE \
		and DirectorSpawn.flat_dist(floor_pos, e.global_position) < Tuning.NULL_CORE_RADIUS


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


## True when the bot may plan soft-wall crossings now: Null pursues and the cost is cheap
## next to the Coherence left.
func soft_allowed() -> bool:
	return pursuing() and bot.run.player.coherence > Tuning.NOCLIP_SOFT_COST * SOFT_AFFORD


## A soft edge from `c` along `dir` the bot may plan through (both cells walkable).
static func soft_edge(grid: LevelGrid, c: Vector2i, dir: int, bad: Dictionary) -> bool:
	var n := c + LevelGrid.DIRS[dir]
	return grid.wall(c, dir) == LevelGrid.SOFT and grid.is_walkable(c) and grid.is_walkable(n) \
		and not bad.has(LevelGrid.edge_key(c, dir))


## Cells holding a studio light (its pole stands in a corner the grid does not know about):
## a straight line never crosses them. Cached per level.
var _prop_cells: Dictionary = {}
var _prop_data: LevelData = null


func _props(data: LevelData) -> Dictionary:
	if _prop_data != data:
		_prop_data = data
		_prop_cells = {}
		for pl: Dictionary in data.placements:
			if pl.get(&"kind") == LevelData.P_FIXTURE and (pl.get(&"params", {}) as Dictionary).get(&"fixture") == SubstrateGenerator.STUDIO_LIGHT:
				_prop_cells[pl[&"cell"]] = true
	return _prop_cells


## M3.4: drops the bot's next waypoints up to the farthest one reachable on a clear line
## (never past a doorway pair, a soft crossing's near cell, into the Threshold pocket (the
## door is walked into from its face), across a studio light's cell, or, for the profiles
## that route around Null, a cell of its avoid ring).
func straighten() -> void:
	var w := bot._waypoints
	if w.size() < 2 or bot._tight[0] or not pursuing():
		return
	var grid := bot.run.data.grid
	var from := bot.run.player.global_position
	var avoid := cells(grid) if bot.profile != SimBot.PROFILE_DIRECT else {}
	avoid.merge(_props(bot.run.data))
	var best := 0
	for j in range(1, mini(w.size(), STRAIGHT_LOOKAHEAD + 1)):
		var cj := grid.cell_of(w[j])
		if bot._tight[j] or grid.has_flag(cj, LevelGrid.F_EXIT_ROOM) or not walk_clear(grid, from, w[j], avoid):
			break
		best = j
		if bot._soft_cross.has(grid.cell_of(w[j])):
			break
	for k in best:
		bot._prev_wp = w[0]
		w.remove_at(0)
		bot._tight.remove_at(0)


## True when a body walks from `a` to `b` (XZ) through open edges only: the centre line and
## its two parallels STRAIGHT_HALF_WIDTH to either side; a diagonal cell change needs both
## of its L steps open; no cell in `avoid`.
static func walk_clear(grid: LevelGrid, a: Vector3, b: Vector3, avoid: Dictionary = {}) -> bool:
	var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := seg.length()
	if length < 0.01:
		return true
	var side := seg.normalized().cross(Vector3.UP) * STRAIGHT_HALF_WIDTH
	var n := ceili(length / STRAIGHT_SAMPLE)
	for off: Vector3 in [Vector3.ZERO, side, -side]:
		var prev := grid.cell_of(a + off)
		if not grid.is_walkable(prev) or avoid.has(prev):
			return false
		for i in range(1, n + 1):
			var c := grid.cell_of(a + off + seg * (float(i) / n))
			if c == prev:
				continue
			if not grid.is_walkable(c) or avoid.has(c) or not _step_ok(grid, prev, c):
				return false
			prev = c
	return true


static func _step_ok(grid: LevelGrid, c0: Vector2i, c1: Vector2i) -> bool:
	var d := c1 - c0
	var dir := LevelGrid.DIRS.find(d)
	if dir >= 0:
		return grid.can_step(c0, dir)
	if absi(d.x) != 1 or absi(d.y) != 1:
		return false
	var dx := LevelGrid.DIRS.find(Vector2i(d.x, 0))
	var dz := LevelGrid.DIRS.find(Vector2i(0, d.y))
	var ax := c0 + Vector2i(d.x, 0)
	var az := c0 + Vector2i(0, d.y)
	return grid.can_step(c0, dx) and grid.can_step(ax, dz) and grid.can_step(c0, dz) and grid.can_step(az, dx)


func soft_active() -> bool:
	return _nc_dir >= 0


func begin_soft(cell: Vector2i, dir: int) -> void:
	_nc_cell = cell
	_nc_dir = dir
	_nc_held = 0.0


## One frame of a crossing: face the soft wall and hold `noclip`. Returns false when the
## crossing ended this frame (done or given up; the input is released). An aim refused with
## a reason (SOLID, TOO FAR, TOO THIN, NO SPACE) gives up at once; the cooldown's blocked
## aim (no reason) is waited out.
func soft_tick(dt: float) -> bool:
	var p := bot.run.player
	var grid := bot.run.data.grid
	var nt := p.noclip_targeting as NoclipTargeting
	var far := _nc_cell + LevelGrid.DIRS[_nc_dir]
	_nc_held += dt
	var passing := nt != null and nt.phase == NoclipTargeting.Phase.PASSING
	if not passing and grid.cell_of(p.global_position) == far:
		soft_passes += 1
		_end_soft()
		return false
	var refused := nt == null or (not passing and nt.phase == NoclipTargeting.Phase.IDLE \
		and _nc_held > SOFT_AIM_GRACE and not bool(nt.reported[2]) and StringName(nt.reported[3]) != &"")
	if refused or (not passing and _nc_held > SOFT_GIVE_UP):
		bad_soft[LevelGrid.edge_key(_nc_cell, _nc_dir)] = true
		soft_fails += 1
		_end_soft()
		return false
	var v := LevelGrid.DIRS[_nc_dir]
	p.rotation = Vector3(0.0, atan2(-float(v.x), -float(v.y)), 0.0)
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(a)
	Input.action_press(&"noclip")
	return true


func _end_soft() -> void:
	Input.action_release(&"noclip")
	_nc_dir = -1
	_nc_cell = LevelData.NO_CELL


func results(result: Dictionary) -> void:
	result.merge(shape)
	result[&"soft_passes"] = soft_passes
	result[&"soft_fails"] = soft_fails
	result[&"null_woke_s"] = snappedf(woke_at, 0.1)
	result[&"null_core_s"] = snappedf(core_s, 0.1)
	result[&"null_drained"] = snappedf(drained, 0.1)
	result[&"null_wake_dist"] = snappedf(wake_dist, 0.1)
	result[&"null_min_dist"] = snappedf(min_dist, 0.1) if not is_inf(min_dist) else -1.0
