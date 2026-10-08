class_name StratumShots
extends RefCounted
## Extra build-verification poses for strata with levels of more than one height (M2.1),
## appended to LevelShots' five: Pools "basin" (from the rim above a basin's steps, looking
## down the steps across the pool, a wet one when there is one) and Garage "ramp" (from the
## foot of a ramp on deck 0, looking up it to deck 1), "ramp_down" (from deck 1, down) and
## "deck" (across deck 0 from a cell no car stands in or beside).
## Each pose is {name, from, to}, eye height above the floor it stands on.

const EYE := 1.6


static func poses(data: LevelData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match data.stratum:
		&"pools":
			var b := _basin_pose(data)
			if not b.is_empty():
				out.append(b)
		&"garage":
			out.append_array(_ramp_poses(data))
			var d := _deck_pose(data)
			if not d.is_empty():
				out.append(d)
		&"offices", &"server":
			out.append_array(StratumShotsM22.poses(data))
	return out


## Garage "deck": across deck 0 from a free cell (no car), down its longest open run.
static func _deck_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	var best := Vector3i(-1, -1, -1)
	var best_n := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR or g.deck[i] != 0 or g.has_flag(c, LevelGrid.F_NO_SPAWN):
			continue
		# M2.13a: not beside a parked car either (a car body a metre off fills a third of the
		# frame with its unlit flank; the pose is about the deck).
		var beside := false
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				beside = beside or LevelShots.prop_cell(g, c + Vector2i(dx, dz))
		if beside:
			continue
		for d in 4:
			var n := 0
			var p := c
			while g.can_step(p, d) and not g.has_flag(p + LevelGrid.DIRS[d], LevelGrid.F_NO_SPAWN):
				p += LevelGrid.DIRS[d]
				n += 1
			if n > best_n:
				best_n = n
				best = Vector3i(c.x, c.y, d)
	if best.x < 0:
		return {}
	var dv := LevelGrid.DIRS[best.z]
	var from := g.world_of(Vector2i(best.x, best.y)) + Vector3(0, EYE, 0)
	return {&"name": "deck", &"from": from, &"to": from + Vector3(dv.x, -0.25, dv.y) * 12.0}


## The first cell of each ramp or step run (its downhill neighbour is not a ramp), wet
## basins' steps first.
static func run_starts(g: LevelGrid) -> Array[Vector2i]:
	var wet: Array[Vector2i] = []
	var dry: Array[Vector2i] = []
	for i in g.cell_count():
		var c := g.cell_at(i)
		var up := g.ramp_dir_of(c)
		if up < 0 or g.kind(c - LevelGrid.DIRS[up]) == LevelGrid.RAMP:
			continue
		if g.has_flag(c, LevelGrid.F_WATER):
			wet.append(c)
		else:
			dry.append(c)
	wet.append_array(dry)
	return wet


static func _top_of(g: LevelGrid, start: Vector2i) -> Vector2i:
	var up := g.ramp_dir_of(start)
	var c := start
	while g.kind(c) == LevelGrid.RAMP:
		c += LevelGrid.DIRS[up]
	return c


static func _basin_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	var starts := run_starts(g)
	if starts.is_empty():
		return {}
	var start := starts[0]
	var dv := LevelGrid.DIRS[g.ramp_dir_of(start)]
	var rim := _top_of(g, start)
	var from := g.world_of(rim) + Vector3(0, EYE, 0) + Vector3(dv.x, 0, dv.y) * 0.6
	var to := g.world_of(start - dv * 2) + Vector3(0, 0.4, 0)
	return {&"name": "basin", &"from": from, &"to": to}


static func _ramp_poses(data: LevelData) -> Array[Dictionary]:
	var g := data.grid
	var out: Array[Dictionary] = []
	var starts := run_starts(g)
	if starts.is_empty():
		return out
	var start := starts[0]
	var dv := LevelGrid.DIRS[g.ramp_dir_of(start)]
	var foot := start - dv
	var top := _top_of(g, start)
	var from := g.world_of(foot) + Vector3(0, EYE, 0) - Vector3(dv.x, 0, dv.y) * 0.8
	out.append({&"name": "ramp", &"from": from, &"to": g.world_of(top) + Vector3(0, EYE, 0)})
	var down_from := g.world_of(top) + Vector3(0, EYE, 0) + Vector3(dv.x, 0, dv.y) * 0.8
	out.append({&"name": "ramp_down", &"from": down_from, &"to": g.world_of(foot) + Vector3(0, 1.0, 0)})
	return out
