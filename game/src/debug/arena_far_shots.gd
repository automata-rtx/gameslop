class_name ArenaFarShots
extends RefCounted
## The error arena's T6 frames (02 §2: "each error is identifiable from a silhouette or
## signature at 15 m with the flashlight off"; M3 review S4, R20): each visual error in its
## native stratum, 15 m down a straight run, the stratum's own fixtures on, the flashlight
## off. static_15m (Halls), still_15m (Garage), flicker_15m_a / _b (Offices, two moments of
## the stutter). Echo and Null are sound-first: their T6 signatures are the late step and the
## grid tone (`docs/qa/listen_check.md`). The errors' ticking is paused for the captures.

const DIST := 15.0
const RUN_CELLS := 8          # 16 m of open steps: the error stands inside the run


## A straight run of RUN_CELLS open steps, the player at its start looking down it.
static func _pose_run(arena: ErrorArena) -> Vector3:
	var cor: Array = arena._corridor(RUN_CELLS, arena.get(&"_stratum") != &"halls")
	var fwd := arena._pose_player(cor[0], cor[1])
	arena.player.rig.reset_pitch()
	arena.player.flashlight.set_on(false, true)
	return fwd


static func static_15m(arena: ErrorArena, dir: String) -> void:
	var fwd := _pose_run(arena)
	var st := arena.spawn(&"static", arena.player.global_position + fwd * DIST) as ErrorStatic
	st.set_physics_process(false)
	await arena.shot(dir, "static_15m")
	arena.free_error(st)


static func still_15m(arena: ErrorArena, dir: String) -> void:
	var fwd := _pose_run(arena)
	var still := arena.spawn(&"still", arena.player.global_position + fwd * DIST) as ErrorStill
	still.set_physics_process(false)
	await arena.shot(dir, "still_15m")
	arena.free_error(still)


## Offices: a lit group of at least 3 fixtures whose centroid is 13 to 17 m from a walkable
## cell with a clear grid line to the centroid that sees 3 or more of them along clear lines.
static func flicker_15m(arena: ErrorArena, dir: String) -> void:
	var pool := arena.level.light_pool
	var grid := arena.data.grid
	var ids: Array = pool.group_ids()
	ids.sort()
	var best := {}
	var best_score := 0.0
	for g: int in ids:
		if not pool.is_group_lit(g) or pool.group(g).size() < 3:
			continue
		var c := pool.group_centroid(g)
		for i in grid.cell_count():
			var cell := grid.cell_at(i)
			if not grid.is_walkable(cell) or grid.has_flag(cell, LevelGrid.F_SPAWN_ROOM):
				continue
			var w := grid.world_of(cell)
			var d := FlickerHabitat.flat(w, c)
			if absf(d - DIST) > 2.0 or not SightOps.clear(grid, w, Vector3(c.x, w.y, c.z)):
				continue
			var seen := 0
			for f in pool.group(g):
				if SightOps.clear(grid, w, Vector3(f.global_position.x, w.y, f.global_position.z)):
					seen += 1
			var score := seen - absf(d - DIST) * 0.01
			if seen >= 3 and score > best_score:
				best_score = score
				best = {&"group": g, &"stand": w}
	if best.is_empty():
		push_warning("arena: no lit fixture group 15 m from a vantage")
		return
	var g: int = best[&"group"]
	var c := pool.group_centroid(g)
	ArenaFlickerShots._pose(arena, best[&"stand"], c)
	arena.player.flashlight.set_on(false, true)
	var e := arena.spawn(&"flicker", Vector3(c.x, arena.player.global_position.y, c.z)) as ErrorFlicker
	e.respawn_at(g)
	e.set_physics_process(false)
	await arena.shot(dir, "flicker_15m_a")
	await arena.get_tree().create_timer(0.07).timeout
	await arena.shot(dir, "flicker_15m_b")
	arena.free_error(e)
