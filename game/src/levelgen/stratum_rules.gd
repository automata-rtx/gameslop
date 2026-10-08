class_name StratumRules
extends RefCounted
## 07 §8 rule 10 for Offices and Server (M2.2), called by LevelValidator. Each appends its
## failure lines to `f`; `ds` is the spawn distance field.


## Offices: the breaker exists (one, reachable on foot both ways, also when the lock is not
## Powered); one meeting room with GLASS on its corridor side and a DOOR in it; GLASS only
## on the meeting room; partitions only inside open offices; dark fixture groups are whole
## groups and the spawn lobby's group is lit.
static func offices(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var breakers := level.placements_of(LevelData.P_BREAKER)
	if breakers.size() != 1:
		f.append("r10: Offices needs exactly one breaker, found %d" % breakers.size())
	elif not _both_ways(level, ds, breakers[0][&"cell"]):
		f.append("r10: Offices breaker unreachable on foot")
	var meetings := 0
	for room in grid.room_list:
		if room.kind != OfficeRooms.MEETING:
			continue
		meetings += 1
		var glass := 0
		var door := 0
		for e in room.perimeter_edges():
			match grid.wall(Vector2i(e.x, e.y), e.z):
				LevelGrid.GLASS:
					glass += 1
				LevelGrid.DOOR:
					door += 1
		if glass == 0 or door == 0:
			f.append("r10: meeting room %d needs glass and a door (%d, %d)" % [room.id, glass, door])
	if meetings != 1:
		f.append("r10: Offices needs one meeting room, found %d" % meetings)
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			var o := c + LevelGrid.DIRS[d]
			if not grid.in_bounds(o):
				continue
			var t := grid.wall(c, d)
			var ra := grid.room_of(c)
			var rb := grid.room_of(o)
			if t == LevelGrid.GLASS and not _kind(ra, OfficeRooms.MEETING) and not _kind(rb, OfficeRooms.MEETING):
				f.append("r10: glass at %s %s off the meeting room" % [c, LevelGrid.DIR_NAMES[d]])
			if t == LevelGrid.PARTITION and not (ra != null and ra == rb and ra.kind == OfficeRooms.OPEN):
				f.append("r10: partition at %s %s outside an open office" % [c, LevelGrid.DIR_NAMES[d]])
	var dark: Dictionary = {}
	var lit: Dictionary = {}
	for p in level.placements_of(LevelData.P_FIXTURE):
		var g := int(p[&"params"][&"group"])
		if bool(p[&"params"].get(&"dark", false)):
			dark[g] = true
		else:
			lit[g] = true
	for g: int in dark:
		if lit.has(g):
			f.append("r10: fixture group %d is partly dark" % g)
	if dark.is_empty():
		f.append("r10: Offices has no dark fixture group")
	var spawn := grid.room_of(level.spawn_cell)
	if spawn != null and dark.has(spawn.fixture_group):
		f.append("r10: the spawn lobby starts dark")


## Server: every cage has a gate (a DOOR onto a walkable cell) and holds one item; no
## walkable cell is a rack and every rack face toward walkable space is a WALL edge (07 §7:
## racks are tagged WALL on all four faces); no aisle in the hall runs straight for more
## than SERVER_AISLE_STRAIGHT_MAX cells; the exit clearing has its one white light.
static func server(level: LevelData, _ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var items: Dictionary = {}
	for p in level.placements_of(LevelData.P_ITEM):
		items[p[&"cell"]] = true
	for room in grid.room_list:
		if room.kind != ServerGenerator.CAGE:
			continue
		var gate := false
		for e in room.perimeter_edges():
			var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
			gate = gate or (grid.wall(Vector2i(e.x, e.y), e.z) == LevelGrid.DOOR and grid.is_walkable(o))
		if not gate:
			f.append("r10: cage %d has no gate" % room.id)
		var held := 0
		for c in room.cells():
			if items.has(c):
				held += 1
		if held != 1:
			f.append("r10: cage %d holds %d items" % [room.id, held])
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.RACK:
			continue
		var c := grid.cell_at(i)
		for d in 4:
			if grid.is_walkable(c + LevelGrid.DIRS[d]) and grid.wall(c, d) != LevelGrid.WALL:
				f.append("r10: rack %s face %s is not WALL" % [c, LevelGrid.DIR_NAMES[d]])
	var longest := longest_hall_run(level)
	if longest > Tuning.SERVER_AISLE_STRAIGHT_MAX:
		f.append("r10: an aisle runs straight for %d cells" % longest)
	var exit_lights := 0
	for p in level.placements_of(LevelData.P_FIXTURE):
		if p[&"params"].get(&"fixture", &"") == ServerFurnish.EXIT_LIGHT and grid.has_flag(p[&"cell"], LevelGrid.F_EXIT_ROOM):
			exit_lights += 1
	if exit_lights != 1:
		f.append("r10: the exit clearing needs one white light, found %d" % exit_lights)


## The longest straight walk inside the ring (ring cells excluded) along either axis.
static func longest_hall_run(level: LevelData) -> int:
	var grid := level.grid
	var inset := Tuning.SERVER_RING_INSET
	var lo := inset + 1
	var hi := grid.size.x - inset - 2
	var best := 0
	for axis in 2:
		for a in range(lo, hi + 1):
			var run := 0
			for b in range(lo, hi + 1):
				var c := Vector2i(b, a) if axis == 0 else Vector2i(a, b)
				var d := LevelGrid.W if axis == 0 else LevelGrid.N
				if grid.is_walkable(c) and run > 0 and grid.can_step(c, d):
					run += 1
				elif grid.is_walkable(c):
					run = 1
				else:
					run = 0
				best = maxi(best, run)
	return best


static func _kind(room: RoomData, kind: StringName) -> bool:
	return room != null and room.kind == kind


static func _both_ways(level: LevelData, ds: PackedInt32Array, c: Vector2i) -> bool:
	var grid := level.grid
	if not grid.in_bounds(c) or ds[grid.idx(c)] < 0:
		return false
	return grid.distance_field(c)[grid.idx(level.exit_cell)] >= 0
