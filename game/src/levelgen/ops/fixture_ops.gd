class_name FixtureOps
extends RefCounted
## Fixtures and fixture groups (07 §5, 02 §6): one group per room, one per corridor segment
## between junctions (split at the stratum's max fixtures per group). Groups are Flicker's
## habitat unit and the LightPool's registration key.


static func _new_group(gen: StratumGenerator, cells: Array[Vector2i]) -> int:
	var id := gen.grid.groups.size()
	gen.grid.groups[id] = cells
	return id


## Ceiling fixtures for a room: one per 2x2 block, evenly spread (at least one).
static func room_fixtures(gen: StratumGenerator, room: RoomData, height: float, fixture: StringName) -> void:
	var r := room.rect
	var nx := maxi(1, r.size.x / 2)
	var nz := maxi(1, r.size.y / 2)
	var cells: Array[Vector2i] = []
	var spots: Array[Vector2] = []
	for iz in nz:
		for ix in nx:
			# Position in cell units, where cell (x, z) is centred on (x, z).
			var p := Vector2(r.position.x - 0.5 + (ix + 0.5) * r.size.x / float(nx),
				r.position.y - 0.5 + (iz + 0.5) * r.size.y / float(nz))
			var c := Vector2i(roundi(p.x), roundi(p.y))
			cells.append(c)
			spots.append(p - Vector2(c))
	var group := _new_group(gen, cells)
	room.fixture_group = group
	for i in cells.size():
		var off := spots[i] * Tuning.GRID_CELL_SIZE
		gen.data.add_placement(LevelData.P_FIXTURE, cells[i], Vector3(off.x, height, off.y), 0.0,
			{&"group": group, &"fixture": fixture})


## Ceiling fixtures on the `spacing`-cell lattice along corridors (FLOOR cells), grouped per segment
## between junctions, at most `group_max` fixtures per group.
static func corridor_fixtures(gen: StratumGenerator, spacing: int, group_max: int, height: float, fixture: StringName) -> void:
	var grid := gen.grid
	var n := grid.cell_count()
	var masks := PackedInt32Array()
	masks.resize(n)
	var junction := PackedByteArray()
	junction.resize(n)
	for i in n:
		masks[i] = grid.open_mask(i)
		junction[i] = 1 if grid.openings_i(i) >= 3 else 0
	var seg_of := PackedInt32Array()
	seg_of.resize(n)
	seg_of.fill(-1)
	var segment := 0
	# Plain corridor cells seed segments first; junctions left over become their own.
	for pass_junctions in 2:
		for i in n:
			if grid.cells[i] != LevelGrid.FLOOR or seg_of[i] >= 0 or junction[i] != pass_junctions:
				continue
			var ordered := _flood_segment(grid, i, segment, seg_of, masks, junction)
			_place_segment(gen, ordered, spacing, group_max, height, fixture)
			segment += 1


## BFS through plain corridor cells (fewer than 3 openings); junctions join the segment
## but are not expanded. Returns Vector3i(x, z, depth) in BFS order.
static func _flood_segment(grid: LevelGrid, start: int, segment: int, seg_of: PackedInt32Array,
		masks: PackedInt32Array, junction: PackedByteArray) -> Array[Vector3i]:
	var w := grid.size.x
	var steps: Array[int] = [-w, 1, w, -1]
	var c0 := grid.cell_at(start)
	var out: Array[Vector3i] = [Vector3i(c0.x, c0.y, 0)]
	seg_of[start] = segment
	var head := 0
	while head < out.size():
		var e := out[head]
		head += 1
		var i := e.y * w + e.x
		if junction[i] != 0 and head > 1:
			continue
		for d in 4:
			if (masks[i] & (1 << d)) == 0:
				continue
			var j := i + steps[d]
			if grid.cells[j] != LevelGrid.FLOOR or seg_of[j] >= 0:
				continue
			seg_of[j] = segment
			out.append(Vector3i(j % w, j / w, e.z + 1))
	return out


## T2 (02 §2): fixtures sit on one exact lattice for the whole level, `spacing` cells
## apart. A straight run along X is lit where x is a multiple of `spacing`, along Z where z
## is; bends and junctions only where both are (so no two tubes crowd a corner).
static func on_lattice(grid: LevelGrid, c: Vector2i, spacing: int) -> bool:
	var along_x := grid.can_step(c, LevelGrid.E) or grid.can_step(c, LevelGrid.W)
	var along_z := grid.can_step(c, LevelGrid.N) or grid.can_step(c, LevelGrid.S)
	var x_ok := posmod(c.x, spacing) == 0
	var z_ok := posmod(c.y, spacing) == 0
	if along_x and not along_z:
		return x_ok
	if along_z and not along_x:
		return z_ok
	return x_ok and z_ok


static func _place_segment(gen: StratumGenerator, ordered: Array[Vector3i], spacing: int, group_max: int,
		height: float, fixture: StringName) -> void:
	var lit: Array[Vector2i] = []
	for e in ordered:
		var c := Vector2i(e.x, e.y)
		if on_lattice(gen.grid, c, spacing):
			lit.append(c)
	var k := 0
	while k < lit.size():
		var chunk: Array[Vector2i] = lit.slice(k, mini(k + group_max, lit.size()))
		var group := _new_group(gen, chunk)
		for c in chunk:
			gen.data.add_placement(LevelData.P_FIXTURE, c, Vector3(0.0, height, 0.0), 0.0,
				{&"group": group, &"fixture": fixture})
		k += group_max
