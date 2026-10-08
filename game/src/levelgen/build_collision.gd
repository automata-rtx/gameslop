class_name BuildCollision
extends RefCounted
## Collision for a level (07 §8) as pure data, each shape with the 07 §7 metadata:
## - one 2 x 0.2 x 2 box per open cell's floor, at its floor height (M2.1: a cell beside a
##   lower floor, a basin rim, reaches down to that floor and over its edge strip, so the
##   basin's sides are solid), and a sloped convex shape per ramp or step cell;
## - one box per wall edge, from the lowest floor to the highest ceiling either side
##   (partitions 1.5 m; doors only above the opening);
## - a solid block in every void cell next to open space, over the heights around it;
## - Pools: an invisible rail on every edge from walkable floor into deep water (07 §5.2:
##   "deeper is modelled as SOLID for movement"), POOLS_DEEP_RAIL_HEIGHT above the floor.
## Worker-thread safe; LevelBuilder makes the bodies.


static func boxes(p: BuildPlan) -> Array[Dictionary]:
	var grid := p.grid
	var boxes: Array[Dictionary] = []
	for z in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, z)
			var ch := Vector2i(x / p.chunk_cells, z / p.chunk_cells)
			if grid.is_sight_open(c):
				_floor(boxes, p, c, ch)
			elif _touches_open(grid, c):
				_void_box(boxes, p, c, ch)
			var dirs: Array[int] = [LevelGrid.E, LevelGrid.S]
			if x == 0:
				dirs.append(LevelGrid.W)
			if z == 0:
				dirs.append(LevelGrid.N)
			for d in dirs:
				_edge_box(boxes, p, c, d, ch)
			if grid.is_walkable(c):
				for d in 4:
					if grid.kind(c + LevelGrid.DIRS[d]) == LevelGrid.DEEP:
						_rail(boxes, grid, c, d, ch)
	return boxes


static func _touches_open(grid: LevelGrid, c: Vector2i) -> bool:
	for d in LevelGrid.DIRS:
		if grid.is_sight_open(c + d):
			return true
	return false


## Lowest and highest open height over cell c (a ramp's whole run).
static func _range(p: BuildPlan, c: Vector2i) -> Vector2:
	if p.grid.ramp_dir_of(c) >= 0:
		var lo := p._slopes.run_bottom(c)
		var hi := p._slopes.run_top(c)
		return Vector2(lo, p.ceiling_at(c, hi))
	var y := p.grid.floor_y(c)
	return Vector2(y, p.ceiling_at(c, y))


static func _floor(boxes: Array[Dictionary], p: BuildPlan, c: Vector2i, ch: Vector2i) -> void:
	var grid := p.grid
	var cs := Tuning.GRID_CELL_SIZE
	var t := Tuning.GRID_WALL_THICKNESS
	var meta := {&"cell": c, &"kind": grid.kind(c)}
	var body := "%d,%d,floor" % [ch.x, ch.y]
	if grid.ramp_dir_of(c) >= 0:
		boxes.append({&"body": body, &"chunk": ch, &"kind": BuildPlan.BODY_FLOOR, &"size": Vector3.ONE,
			&"pos": Vector3(c.x * cs, 0.0, c.y * cs), &"soft": -1, &"meta": meta, &"points": _ramp_points(p, c)})
		return
	var y := grid.floor_y(c)
	var bottom := y - t
	# Reach over the edge strip towards lower open neighbours: the strip is this floor's
	# (its face is the basin side), so the solid goes to the lower cell's interior edge.
	var lo := Vector2(-cs * 0.5, -cs * 0.5)
	var hi := Vector2(cs * 0.5, cs * 0.5)
	for d in 4:
		var o := c + LevelGrid.DIRS[d]
		if not grid.is_sight_open(o) or grid.wall(c, d) != LevelGrid.NONE:
			continue
		var oy := _range(p, o).x
		if oy < y - 0.01:
			bottom = minf(bottom, oy - t)
			var dv := LevelGrid.DIRS[d]
			if dv.x + dv.y > 0:
				hi += Vector2(dv) * t * 0.5
			else:
				lo += Vector2(dv) * t * 0.5
	var size := Vector3(hi.x - lo.x, y - bottom, hi.y - lo.y)
	var mid := Vector3(c.x * cs + (lo.x + hi.x) * 0.5, (y + bottom) * 0.5, c.y * cs + (lo.y + hi.y) * 0.5)
	boxes.append({&"body": body, &"chunk": ch, &"kind": BuildPlan.BODY_FLOOR,
		&"size": size, &"pos": mid, &"soft": -1, &"meta": meta})


## A ramp cell's wedge, relative to the cell centre at y = 0: the top follows the slope
## (clamped to the run's ends) over the whole cell, the bottom is flat under the run.
static func _ramp_points(p: BuildPlan, c: Vector2i) -> PackedVector3Array:
	var grid := p.grid
	var up := grid.ramp_dir_of(c)
	var dv := LevelGrid.DIRS[up]
	var lo := p._slopes.run_bottom(c)
	var hi := p._slopes.run_top(c)
	var g := grid.ramp_grade[grid.idx(c)]
	var y := grid.floor_y(c)
	var half := Tuning.GRID_CELL_SIZE * 0.5
	var out := PackedVector3Array()
	for s: float in [-half, half]:
		var top := clampf(y + g * s, lo, hi)
		for l: float in [-half, half]:
			var along := Vector3(dv.x, 0.0, dv.y) * s
			var side := Vector3(dv.y, 0.0, dv.x) * l
			out.append(along + side + Vector3(0.0, top, 0.0))
			out.append(along + side + Vector3(0.0, lo - Tuning.GRID_WALL_THICKNESS, 0.0))
	return out


## 07 §7 (2026-10-08): a void block is SOLID. Its body is not a noise wall (no `wall_kind`):
## the walls around it already count, and the block is what lies between them.
static func _void_box(boxes: Array[Dictionary], p: BuildPlan, c: Vector2i, ch: Vector2i) -> void:
	var cs := Tuning.GRID_CELL_SIZE
	var inner := cs - Tuning.GRID_WALL_THICKNESS
	var span := Vector2(INF, -INF)
	for d in LevelGrid.DIRS:
		if p.grid.is_sight_open(c + d):
			var r := _range(p, c + d)
			span = Vector2(minf(span.x, r.x), maxf(span.y, r.y))
	boxes.append({&"body": "%d,%d,void" % [ch.x, ch.y], &"chunk": ch, &"kind": BuildPlan.BODY_VOID,
		&"size": Vector3(inner, span.y - span.x, inner), &"pos": Vector3(c.x * cs, (span.x + span.y) * 0.5, c.y * cs),
		&"soft": -1, &"meta": {&"cell": c, &"wall_type": LevelGrid.SOLID,
			&"wall_kind": Tuning.GRID_WALL_TYPES[LevelGrid.SOLID], &"thickness": inner,
			&"walkable": false, &"void": true}})


## 07 §8: one box per wall edge, carrying 07 §7's {cell, dir, wall_type} plus thickness and
## what lies on each side. The box spans the cell plus the wall thickness so corners close.
static func _edge_box(boxes: Array[Dictionary], p: BuildPlan, c: Vector2i, d: int, ch: Vector2i) -> void:
	var grid := p.grid
	var o := c + LevelGrid.DIRS[d]
	var oa := grid.is_sight_open(c)
	var ob := grid.is_sight_open(o)
	var type := grid.wall(c, d)
	if (not oa and not ob) or type == LevelGrid.NONE:
		return
	var span := Vector2(INF, -INF)
	for x: Vector2i in [c, o]:
		if grid.is_sight_open(x):
			var r := _range(p, x)
			span = Vector2(minf(span.x, r.x), maxf(span.y, r.y))
	var lo := span.x
	var hi := span.y
	if type == LevelGrid.PARTITION:
		hi = lo + p._part_h
	elif type == LevelGrid.DOOR:
		lo += p._door_h  # the door prefab carries its own body below the header
	var cs := Tuning.GRID_CELL_SIZE
	var t := Tuning.GRID_WALL_THICKNESS
	var dv := LevelGrid.DIRS[d]
	var mid := Vector3((c.x + dv.x * 0.5) * cs, (lo + hi) * 0.5, (c.y + dv.y * 0.5) * cs)
	var size := Vector3(t, hi - lo, cs + t) if dv.x != 0 else Vector3(cs + t, hi - lo, t)
	var type_name: StringName = Tuning.GRID_WALL_TYPES[type]
	var soft: int = p._soft_index.get(edge_key(c, d), -1) if type == LevelGrid.SOFT else -1
	var body := "soft%d" % soft if soft >= 0 else "%d,%d,%s" % [ch.x, ch.y, type_name]
	boxes.append({&"body": body, &"chunk": ch, &"kind": type_name, &"soft": soft,
		&"size": size, &"pos": mid, &"meta": wall_meta(grid, c, d)})


## Pools: the edge from walkable floor `c` into deep water, an invisible solid rail from the
## pool floor to POOLS_DEEP_RAIL_HEIGHT above the edge's floor. Not a noise wall.
static func _rail(boxes: Array[Dictionary], grid: LevelGrid, c: Vector2i, d: int, ch: Vector2i) -> void:
	var o := c + LevelGrid.DIRS[d]
	var cs := Tuning.GRID_CELL_SIZE
	var t := Tuning.GRID_WALL_THICKNESS
	var lo := grid.floor_y(o)
	var hi := grid.edge_floor_y(c, d) + Tuning.POOLS_DEEP_RAIL_HEIGHT
	var dv := LevelGrid.DIRS[d]
	var size := Vector3(t, hi - lo, cs + t) if dv.x != 0 else Vector3(cs + t, hi - lo, t)
	var meta := wall_meta(grid, c, d)
	meta[&"wall_type"] = LevelGrid.SOLID
	meta[&"wall_kind"] = Tuning.GRID_WALL_TYPES[LevelGrid.SOLID]
	meta[&"rail"] = true
	boxes.append({&"body": "%d,%d,rail" % [ch.x, ch.y], &"chunk": ch, &"kind": BuildPlan.BODY_RAIL, &"soft": -1,
		&"size": size, &"pos": Vector3((c.x + dv.x * 0.5) * cs, (lo + hi) * 0.5, (c.y + dv.y * 0.5) * cs), &"meta": meta})


## 07 §7 metadata for the edge (c, dir): the side named by `cell` and `dir`, the type, the
## thickness, and both cells with whether each is walkable ("what is behind") and its floor
## height (noclip lands in the far cell on its floor within a step: ramps, basins). A DOOR
## edge's box is the header above the opening; it carries no `closed` state, so noclip
## treats it as SOLID (the Door prefab's leaf and jambs carry the state).
static func wall_meta(g: LevelGrid, c: Vector2i, d: int) -> Dictionary:
	var o := c + LevelGrid.DIRS[d]
	var type := g.wall(c, d)
	return {
		&"cell": c, &"dir": d, &"wall_type": type, &"wall_kind": Tuning.GRID_WALL_TYPES[type],
		&"thickness": Tuning.GRID_WALL_THICKNESS, &"other_cell": o,
		&"walkable": g.is_walkable(c), &"other_walkable": g.is_walkable(o),
		&"floor_y": g.floor_y(c), &"other_floor_y": g.floor_y(o),
	}


## Edge key independent of which side names it (E or S form).
static func edge_key(c: Vector2i, dir: int) -> Vector3i:
	return LevelGrid.edge_key(c, dir)
