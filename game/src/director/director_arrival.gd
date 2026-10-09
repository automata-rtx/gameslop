class_name DirectorArrival
extends RefCounted
## R19 (14 §10 level build slice, 4 ms per frame): the roster work of `Director.begin` as
## ordered steps: the fair cells from the arrival pose, one spawn per id, then the awake
## arrivals, the first Descent's Static bounds and the aggression. `Director.begin` runs them
## at once, or, when the run asks (`Director.staged`), over the frames after arrival within
## the slice budget. The Director's clock, its Calm and its first tick are unchanged: the
## pose and the arrival position are read at begin, and any step still waiting runs before
## the first 0.1 s tick, so every draw from the Director's rng keeps its order.

## Cells per step of the fair-cell scan (each runs a grid sight test; about 2 ms at most).
const FALLBACK_CHUNK_CELLS := 128

var director: Director
var queue := StepQueue.new()


## The steps for `roster` from the player's pose now (DirectorHunters.spawn_roster's order:
## the cells for every spawnable id, then each spawn or, with no fair cell, `pending`).
static func roster_steps(d: Director, roster: Array[StringName]) -> Array[Callable]:
	var h := d.hunters
	var steps: Array[Callable] = []
	var ids: Array[StringName] = []
	for id in roster:
		if DirectorRules.spawnable(id):
			ids.append(id)
		else:
			d.skipped.append(id)
	if ids.is_empty() or not h._player_ok() or h._grid() == null:
		return steps
	var pose := h._pose()
	var cells: Array[Vector2i] = []
	# The rng-free parts of the pick (the walking field, the spawn room, every fair cell),
	# in chunks of cells, then the pick itself (DirectorSpawn.pick_cells with them).
	var ctx := {}
	steps.append(func() -> void: ctx.merge(DirectorSpawn.pick_context(d.data, pose[&"pos"])))
	for k in ceili(float(d.data.grid.cell_count()) / FALLBACK_CHUNK_CELLS):
		steps.append(func() -> void:
			DirectorSpawn.fallback_chunk(d.data, ctx, pose[&"pos"], pose[&"eye"], pose[&"fwd"], pose[&"half_fov"],
				FALLBACK_CHUNK_CELLS))
	steps.append(func() -> void:
		var band := DirectorSpawn.breaker_exit_band(d.data) if h._first_descent_depth1() else {}
		cells.assign(h._pick(ids, band, pose, ctx)))
	for i in ids.size():
		steps.append(func() -> void:
			if cells[i] == LevelData.NO_CELL:
				# No fair cell from the arrival pose (an open hall in view): wait until the
				# player moves or turns (M1.13: every level with a native slot has a hunter).
				h.pending.append(ids[i])
			else:
				h.spawn(ids[i], h._grid().world_of(cells[i])))
	return steps


## Queues begin's roster work for `roster` (with the player at the arrival pose now).
func plan(roster: Array[StringName]) -> void:
	var d := director
	queue.clear()
	queue.append_all(roster_steps(d, roster))
	var awake := DirectorRules.awake_hunters(d.drops_in_a_row)
	var at := d.player.global_position if d.player != null else Vector3.INF
	queue.append(func() -> void:
		d.hunters.awake_arrivals(awake, at)
		d.statics.bound_statics_off_path())
