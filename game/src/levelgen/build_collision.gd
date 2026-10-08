class_name BuildCollision
extends RefCounted
## Collision boxes for a level (07 §8) as pure data: one 2 x 0.2 x 2 box per floor cell and
## one per wall edge (2 x height x 0.2; partitions 1.5 m; doors only above the opening),
## each with the 07 §7 metadata. Worker-thread safe; LevelBuilder makes the bodies.


static func boxes(grid: LevelGrid, height: float, chunk_cells: int, part_h: float, door_h: float,
		soft_index: Dictionary) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var cs := Tuning.GRID_CELL_SIZE
	var t := Tuning.GRID_WALL_THICKNESS
	for z in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, z)
			var ch := Vector2i(x / chunk_cells, z / chunk_cells)
			if grid.is_walkable(c):
				var fy := grid.floor_y(c)
				boxes.append({&"body": "%d,%d,floor" % [ch.x, ch.y], &"chunk": ch, &"kind": BuildPlan.BODY_FLOOR,
					&"size": Vector3(cs, t, cs), &"pos": Vector3(x * cs, fy - t * 0.5, z * cs),
					&"soft": -1, &"meta": {&"cell": c, &"kind": grid.kind(c)}})
			elif _touches_walkable(grid, c):
				_void_box(boxes, height, c, ch)
			var dirs: Array[int] = [LevelGrid.E, LevelGrid.S]
			if x == 0:
				dirs.append(LevelGrid.W)
			if z == 0:
				dirs.append(LevelGrid.N)
			for d in dirs:
				_edge_box(boxes, grid, height, part_h, door_h, soft_index, c, d, ch)
	return boxes


static func _touches_walkable(grid: LevelGrid, c: Vector2i) -> bool:
	for d in LevelGrid.DIRS:
		if grid.is_walkable(c + d):
			return true
	return false


## 07 §7 (2026-10-08): a void block is SOLID. Its body is not a noise wall (no `wall_kind`):
## the walls around it already count, and the block is what lies between them.
static func _void_box(boxes: Array[Dictionary], height: float, c: Vector2i, ch: Vector2i) -> void:
	var cs := Tuning.GRID_CELL_SIZE
	var inner := cs - Tuning.GRID_WALL_THICKNESS
	boxes.append({&"body": "%d,%d,void" % [ch.x, ch.y], &"chunk": ch, &"kind": BuildPlan.BODY_VOID,
		&"size": Vector3(inner, height, inner), &"pos": Vector3(c.x * cs, height * 0.5, c.y * cs),
		&"soft": -1, &"meta": {&"cell": c, &"wall_type": LevelGrid.SOLID,
			&"wall_kind": Tuning.GRID_WALL_TYPES[LevelGrid.SOLID], &"thickness": inner,
			&"walkable": false, &"void": true}})


## 07 §8: one box per wall edge (2 x height x 0.2; partitions 1.5 m), carrying 07 §7's
## {cell, dir, wall_type} plus thickness and what lies on each side. The box spans the
## cell plus the wall thickness so corners close.
static func _edge_box(boxes: Array[Dictionary], grid: LevelGrid, height: float, part_h: float, door_h: float,
		soft_index: Dictionary, c: Vector2i, d: int, ch: Vector2i) -> void:
	var o := c + LevelGrid.DIRS[d]
	var wa := grid.is_walkable(c)
	var wb := grid.is_walkable(o)
	var type := grid.wall(c, d)
	if (not wa and not wb) or type == LevelGrid.NONE:
		return
	var cs := Tuning.GRID_CELL_SIZE
	var t := Tuning.GRID_WALL_THICKNESS
	var lo := 0.0
	var hi := height
	if type == LevelGrid.PARTITION:
		hi = part_h
	elif type == LevelGrid.DOOR:
		lo = door_h  # the door prefab carries its own body below the header
	var dv := LevelGrid.DIRS[d]
	var mid := Vector3((c.x + dv.x * 0.5) * cs, (lo + hi) * 0.5, (c.y + dv.y * 0.5) * cs)
	var size := Vector3(t, hi - lo, cs + t) if dv.x != 0 else Vector3(cs + t, hi - lo, t)
	var type_name: StringName = Tuning.GRID_WALL_TYPES[type]
	var soft: int = soft_index.get(edge_key(c, d), -1) if type == LevelGrid.SOFT else -1
	var body := "soft%d" % soft if soft >= 0 else "%d,%d,%s" % [ch.x, ch.y, type_name]
	boxes.append({&"body": body, &"chunk": ch, &"kind": type_name, &"soft": soft,
		&"size": size, &"pos": mid, &"meta": wall_meta(grid, c, d)})


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
