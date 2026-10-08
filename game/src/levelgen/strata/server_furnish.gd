class_name ServerFurnish
extends RefCounted
## Server furniture and light (07 §5.5, 02 §7, 09 §6), for ServerGenerator.decorate:
## rack-gap hide spots (markers until M2.8), the cage items' cells, fan grilles on the
## ceiling every 5 cells, cable trays along the aisles, and the light: no overhead
## fixtures, red emergency boxes on the perimeter corridor's outer wall every 6 cells (aisle
## ends), the rack LEDs' aggregate blue light every 2 aisle cells on a rack face, and one
## white light over the exit clearing. Groups: one per aisle (its LED lights), one per ring
## side (its emergency boxes), one for the exit clearing.

## Fixture kinds (params.fixture). The emergency box is the stratum's prefab; the others
## have their own prefabs and light profiles (LevelPlacer, Fixture.light_profile).
const EMERGENCY := &"emergency_box"
const RACK_LED := &"rack_led"
const EXIT_LIGHT := &"exit_light"
const NOOK_INSET := 0.4

var gen: ServerGenerator
var grid: LevelGrid
var data: LevelData
var rng: RandomNumberGenerator


func _init(g: ServerGenerator) -> void:
	gen = g
	grid = g.grid
	data = g.data
	rng = g.rng_props


## 07 §5.5 / 09 §6: a hide spot in each rack-gap nook, looking out along the aisle.
func nooks() -> void:
	data.expected_hide_spots = Tuning.SERVER_RACK_GAP_HIDE_SPOTS
	for e in gen.nooks:
		var c := Vector2i(e.x, e.y)
		grid.add_flag(c, LevelGrid.F_HIDE_SPOT_HOST)
		gen.occupied[grid.idx(c)] = true
		data.add_placement(LevelData.P_HIDE_SPOT, c, StratumGenerator.wall_offset(LevelGrid.opposite(e.z), NOOK_INSET),
			LevelData.yaw_facing(e.z), {&"kind": &"rack_gap", &"dir": e.z, &"view_yaw_limit": Tuning.HIDE_YAW_LIMIT_DEFAULT})


## The cage's item cell: the cell farthest from its gate.
func cage_item_cell(cage: RoomData) -> Vector2i:
	var gate := Vector2i(cage.doors[0].x, cage.doors[0].y) if not cage.doors.is_empty() else cage.center()
	var best := cage.center()
	var best_d := -1
	for c in cage.cells():
		var d := absi(c.x - gate.x) + absi(c.y - gate.y)
		if d > best_d:
			best_d = d
			best = c
	return best


## Fan grilles (ceiling, every 5 cells on both axes over the hall) and cable trays (one
## per aisle run, along its ceiling).
func props() -> void:
	var height := float(Tuning.STRATUM_CEILING_HEIGHT[&"server"])
	var inner := gen.ring.grow(-1)
	var step := Tuning.SERVER_FAN_SPACING_CELLS
	for z in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			if posmod(x, step) == 0 and posmod(z, step) == 0:
				data.add_placement(LevelData.P_PROP, Vector2i(x, z), Vector3(0.0, height, 0.0), 0.0,
					{&"prop": &"fan_grille", &"dir": -1})
	for run in aisles():
		var a: Vector2i = run[0]
		var b: Vector2i = run[run.size() - 1]
		var mid := (Vector2(a) + Vector2(b)) * 0.5
		var c := Vector2i(floori(mid.x), floori(mid.y))
		var off := (mid - Vector2(c)) * Tuning.GRID_CELL_SIZE
		data.add_placement(LevelData.P_PROP, c, Vector3(off.x, Tuning.SERVER_CABLE_TRAY_HEIGHT, off.y),
			0.0 if not gen.rows_along_x() else PI * 0.5,
			{&"prop": &"cable_tray", &"dir": -1, &"length": run.size() * Tuning.GRID_CELL_SIZE})


## Aisle runs: maximal straight runs (along the rows) of walkable hall cells with racks on
## both sides, in grid order. Each is an Array[Vector2i].
func aisles() -> Array[Array]:
	var out: Array[Array] = []
	var along := LevelGrid.E if gen.rows_along_x() else LevelGrid.S
	var back := LevelGrid.opposite(along)
	var seen: Dictionary = {}
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if seen.has(i) or not _aisle_cell(c):
			continue
		if _aisle_cell(c + LevelGrid.DIRS[back]):
			continue
		var run: Array[Vector2i] = []
		var p := c
		while _aisle_cell(p):
			run.append(p)
			seen[grid.idx(p)] = true
			p += LevelGrid.DIRS[along]
		out.append(run)
	return out


func _aisle_cell(c: Vector2i) -> bool:
	if not grid.in_bounds(c) or grid.kind(c) != LevelGrid.FLOOR or gen.corridor.has(grid.idx(c)):
		return false
	var across := gen.across_dirs()
	return grid.kind(c + LevelGrid.DIRS[across[0]]) == LevelGrid.RACK and grid.kind(c + LevelGrid.DIRS[across[1]]) == LevelGrid.RACK


# ---------------------------------------------------------------- light

func fixtures() -> void:
	_emergency_boxes()
	_rack_leds()
	_exit_light()


## 02 §7: red emergency boxes every 12 m at aisle ends: on the perimeter corridor's outer
## wall on the 6-cell lattice, one group per ring side.
func _emergency_boxes() -> void:
	var step := Tuning.SERVER_EMERGENCY_SPACING_CELLS
	var r := gen.ring
	for side in 4:
		var cells: Array[Vector2i] = []
		for c in RingOps.ring_cells(r):
			var on_side := (side == LevelGrid.N and c.y == r.position.y) or (side == LevelGrid.S and c.y == r.end.y - 1) \
				or (side == LevelGrid.W and c.x == r.position.x) or (side == LevelGrid.E and c.x == r.end.x - 1)
			if not on_side:
				continue
			var along := c.x if side == LevelGrid.N or side == LevelGrid.S else c.y
			var t := grid.wall(c, side)
			if posmod(along, step) == 0 and (t == LevelGrid.WALL or t == LevelGrid.SOLID) and not cells.has(c):
				cells.append(c)
		if cells.is_empty():
			continue
		var group := _group(cells)
		for c in cells:
			data.add_placement(LevelData.P_FIXTURE, c,
				StratumGenerator.wall_offset(side, 0.0) + Vector3(0.0, Tuning.SERVER_EMERGENCY_HEIGHT, 0.0),
				LevelData.yaw_facing(LevelGrid.opposite(side)), {&"group": group, &"fixture": EMERGENCY, &"dir": side})


## 02 §7: the rack LEDs light the aisles only in aggregate: one blue light on a rack face
## every SERVER_LED_SPACING_CELLS aisle cells (the level's lattice), alternating sides,
## one group per aisle (Flicker's habitat there, 07 §5.5).
func _rack_leds() -> void:
	var spacing := Tuning.SERVER_LED_SPACING_CELLS
	var across := gen.across_dirs()
	for run in aisles():
		var cells: Array[Vector2i] = []
		for c: Vector2i in run:
			var along := c.x if gen.rows_along_x() else c.y
			if posmod(along, spacing) == 0:
				cells.append(c)
		if cells.is_empty():
			cells.append(run[run.size() / 2])
		var group := _group(cells)
		for c in cells:
			var along := c.x if gen.rows_along_x() else c.y
			var face: int = across[posmod(along / spacing, 2)]
			data.add_placement(LevelData.P_FIXTURE, c,
				StratumGenerator.wall_offset(face, 0.0) + Vector3(0.0, Tuning.SERVER_LED_HEIGHT, 0.0),
				LevelData.yaw_facing(LevelGrid.opposite(face)), {&"group": group, &"fixture": RACK_LED, &"dir": face})


## 07 §5.5: the exit clearing is lit by one white light.
func _exit_light() -> void:
	var c := gen.exit_room.center()
	var group := _group([c] as Array[Vector2i])
	gen.exit_room.fixture_group = group
	data.add_placement(LevelData.P_FIXTURE, c, Vector3(0.0, float(Tuning.STRATUM_CEILING_HEIGHT[&"server"]), 0.0), 0.0,
		{&"group": group, &"fixture": EXIT_LIGHT})


func _group(cells: Array[Vector2i]) -> int:
	var id := grid.groups.size()
	grid.groups[id] = cells
	return id
