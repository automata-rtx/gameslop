class_name PoolBasins
extends RefCounted
## The Pools grammar's basins and their props (07 §5.2). Each pool hall gets a basin: the
## hall inset by 2 cells, its floor at -0.6, -1.2 or -1.8 m, filled dry, shallow (0.5 m)
## or full (30/40/30). One end has 2 cells of steps (a RAMP run, built as a stepped mesh)
## climbing to the rim. A full basin deeper than POOLS_IMPASSABLE_DEPTH is DEEP water: not
## walkable, entered only by the steps (07 §5.2: "deeper is modelled as SOLID for
## movement"). The exit hall's basin is dry and 1.8 m deep; the drain hatch sits at the
## bottom, at the far end from the steps. Props: two ladders per basin, lane ropes on full
## basins, a lifeguard chair per 3 halls, drips from the ceiling.

const FILL_DRY := 0
const FILL_SHALLOW := 1
const FILL_FULL := 2
const LADDER_INSET := 0.06

var gen: StratumGenerator
## {room, rect (the basin), uphill (step direction), steps: Array[Vector2i], depth, fill,
## surface_y} per hall, in hall order.
var list: Array[Dictionary] = []


func _init(generator: StratumGenerator) -> void:
	gen = generator


## Pre-rolls a hall's basin so the grammar can count its walkable cells while it draws
## halls: {rect, depth, fill, walkable}.
func roll(rect: Rect2i, exit: bool) -> Dictionary:
	var rng := gen.rng_layout
	var depths := Tuning.POOLS_BASIN_DEPTHS
	var depth := depths[rng.randi_range(0, depths.size() - 1)]
	var fill := FILL_DRY
	if exit:
		depth = Tuning.POOLS_EXIT_BASIN_DEPTH
	elif not gen.simplest:
		var w := Tuning.POOLS_FILL_WEIGHTS
		var r := rng.randi_range(0, w[0] + w[1] + w[2] - 1)
		fill = FILL_DRY if r < w[0] else (FILL_SHALLOW if r < w[0] + w[1] else FILL_FULL)
	var basin := rect.grow(-Tuning.POOLS_BASIN_INSET)
	var walkable := rect.get_area()
	if is_deep(depth, fill):
		walkable -= basin.get_area() - Tuning.POOLS_RAMP_CELLS
	return {&"rect": rect, &"depth": depth, &"fill": fill, &"walkable": walkable}


static func is_deep(depth: float, fill: int) -> bool:
	return fill == FILL_FULL and depth > Tuning.POOLS_IMPASSABLE_DEPTH


## Sinks the basin of `room` into the grid: BASIN (or DEEP) cells, the step run, the water
## placement; for the exit hall, the exit cell at the bottom.
func dig(room: RoomData, plan: Dictionary, exit: bool) -> void:
	var grid := gen.grid
	var rng := gen.rng_layout
	var b := room.rect.grow(-Tuning.POOLS_BASIN_INSET)
	var long_x := b.size.x > b.size.y or (b.size.x == b.size.y and rng.randi_range(0, 1) == 0)
	var uphill: int
	if long_x:
		uphill = LevelGrid.E if rng.randi_range(0, 1) == 0 else LevelGrid.W
	else:
		uphill = LevelGrid.S if rng.randi_range(0, 1) == 0 else LevelGrid.N
	var dv := LevelGrid.DIRS[uphill]
	var top := _side_middle(b, uphill)
	var steps: Array[Vector2i] = []
	for k in Tuning.POOLS_RAMP_CELLS:
		steps.push_front(top - dv * k)
	var depth: float = plan[&"depth"]
	var fill: int = plan[&"fill"]
	var deep := is_deep(depth, fill)
	for c in RoomData.new(b).cells():
		grid.set_kind(c, LevelGrid.DEEP if deep and not steps.has(c) else LevelGrid.BASIN)
		grid.set_floor_y(c, -depth)
	GridHeights.set_ramp(grid, steps, uphill, -depth, 0.0)
	var surface := -INF
	if fill == FILL_SHALLOW:
		surface = -depth + Tuning.POOLS_FILL_SHALLOW
	elif fill == FILL_FULL:
		surface = -Tuning.POOLS_FULL_SURFACE_DROP
	if fill != FILL_DRY:
		for c in RoomData.new(b).cells():
			grid.add_flag(c, LevelGrid.F_WATER)
		gen.data.add_placement(LevelData.P_WATER, b.position, Vector3.ZERO, 0.0,
			{&"rect": b, &"surface_y": surface, &"floor_y": -depth})
	list.append({&"room": room, &"rect": b, &"uphill": uphill, &"steps": steps, &"depth": depth,
		&"fill": fill, &"surface_y": surface})
	if exit:
		var length := b.size.x if long_x else b.size.y
		gen.data.exit_cell = top - dv * (length - 1)
		gen.data.exit_dir = LevelGrid.opposite(uphill)


## The middle cell of the basin's side `dir`.
static func _side_middle(b: Rect2i, dir: int) -> Vector2i:
	return StratumGenerator.side_middle(RoomData.new(b), dir)


func place_props() -> void:
	var rng := gen.rng_props
	var chairs := list.size() / Tuning.POOLS_HALLS_PER_LIFEGUARD_CHAIR
	var chair_halls: Array[int] = []
	for k in list.size():
		if list[k][&"room"] != (gen as PoolsGenerator).exit_room:
			chair_halls.append(k)
	RoomOps.shuffle(chair_halls, rng)
	for k in list.size():
		var basin: Dictionary = list[k]
		_ladders(basin)
		if basin[&"fill"] == FILL_FULL:
			_lane_rope(basin)
		if chair_halls.find(k) >= 0 and chair_halls.find(k) < chairs:
			_lifeguard_chair(basin, rng)
		for d in Tuning.POOLS_DRIPS_PER_HALL:
			_drip(basin, rng)


## Perpendicular directions to the basin's step axis.
static func _sides(basin: Dictionary) -> Array[int]:
	var up: int = basin[&"uphill"]
	return [(up + 1) % 4, (up + 3) % 4]


## 07 §5.2: ladders on two edges, hung on the basin wall with their top at the rim.
func _ladders(basin: Dictionary) -> void:
	var b: Rect2i = basin[&"rect"]
	var depth: float = basin[&"depth"]
	for side in _sides(basin):
		var c := _side_middle(b, side)
		_prop(&"ladder", c, StratumGenerator.wall_offset(side, LADDER_INSET) + Vector3(0.0, depth, 0.0),
			LevelData.yaw_facing(LevelGrid.opposite(side)), side)


## A lane rope floating along a full basin, one 2 m segment per cell, one lane off the steps.
func _lane_rope(basin: Dictionary) -> void:
	var b: Rect2i = basin[&"rect"]
	var up: int = basin[&"uphill"]
	var side: int = _sides(basin)[0]
	var lift: float = float(basin[&"surface_y"]) + float(basin[&"depth"])
	var c := _side_middle(b, up) + LevelGrid.DIRS[side]
	if not b.has_point(c):
		return
	while b.has_point(c):
		_prop(&"lane_rope", c, Vector3(0.0, lift, 0.0), LevelData.yaw_facing(up), up)
		c -= LevelGrid.DIRS[up]


## A lifeguard chair on the hall floor beside the rim, facing the water. Its 0.8 m frame
## fills the cell (R13): the cell is blocked, so only where the hall stays whole without it.
func _lifeguard_chair(basin: Dictionary, rng: RandomNumberGenerator) -> void:
	var sides := _sides(basin)
	var side := sides[rng.randi_range(0, 1)]
	var c := _side_middle(basin[&"rect"], side) + LevelGrid.DIRS[side]
	var grid := gen.grid
	if not grid.is_walkable(c) or gen.occupied.has(grid.idx(c)):
		return
	if not BlockOps.try_block(grid, [c] as Array[Vector2i], gen.data.spawn_cell):
		return
	gen.occupied[grid.idx(c)] = true
	_prop(&"lifeguard_chair", c, Vector3.ZERO, LevelData.yaw_facing(LevelGrid.opposite(side)), -1)


## 02 §10: a drip from the ceiling at a hashed point of the hall.
func _drip(basin: Dictionary, rng: RandomNumberGenerator) -> void:
	var room: RoomData = basin[&"room"]
	var cells := room.cells()
	var c := cells[rng.randi_range(0, cells.size() - 1)]
	var off := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
	off.y = float(Tuning.STRATUM_CEILING_HEIGHT[&"pools"]) - gen.grid.floor_y(c)
	_prop(&"drip", c, off, 0.0, -1)


func _prop(prop: StringName, c: Vector2i, offset: Vector3, yaw: float, dir: int) -> void:
	gen.data.add_placement(LevelData.P_PROP, c, offset, yaw, {&"prop": prop, &"dir": dir})
