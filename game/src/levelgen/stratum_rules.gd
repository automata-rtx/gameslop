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


## Substrate (07 §8 rule 10, §5.6; M2.3): the Threshold pocket is 3x3, lit (a studio light
## in it) and holds the threshold_door at the exit cell; the VOID the unfinish step left is
## 15% to 25% of the corridor cells it started from; no dead-end chain is longer than 4 cells
## unless a soft wall opens its tip (08 §7: Null never corners the player); every edge
## between walkable space and VOID is SOLID or SOFT; the spawn room is finished; 6 to 10
## studio lights at least 6 cells apart and no other fixture; no doors, hide spots or lock;
## the floor is solid in a Descent; Null's spawn on the critical path at least 20 m from the
## spawn, and the Statics off it.
static func substrate(level: LevelData, ds: PackedInt32Array, f: PackedStringArray) -> void:
	var grid := level.grid
	var pocket := grid.room_of(level.exit_cell)
	if pocket == null or pocket.rect.size != Tuning.SUBSTRATE_THRESHOLD_POCKET_SIZE:
		f.append("r10: the Threshold pocket must be a %s room" % Tuning.SUBSTRATE_THRESHOLD_POCKET_SIZE)
	var exits := level.placements_of(LevelData.P_EXIT)
	if exits.size() != 1 or exits[0][&"cell"] != level.exit_cell or exits[0][&"params"].get(&"exit_kind", &"") != SubstrateGenerator.THRESHOLD_DOOR:
		f.append("r10: the threshold_door must stand at the exit cell")
	var lights: Array[Vector2i] = []
	var pocket_lit := false
	for p in level.placements_of(LevelData.P_FIXTURE):
		if p[&"params"].get(&"fixture", &"") != SubstrateGenerator.STUDIO_LIGHT:
			f.append("r10: a %s fixture in the Substrate" % p[&"params"].get(&"fixture", &""))
			continue
		var c: Vector2i = p[&"cell"]
		# "At least 6 cells apart" on foot: the spawn room's and the pocket's lights may face
		# each other across a SOLID edge, never across a short walk.
		var walk := grid.distance_field(c)
		for o in lights:
			var d := walk[grid.idx(o)]
			if d >= 0 and d < Tuning.SUBSTRATE_STUDIO_LIGHT_SPACING_CELLS:
				f.append("r10: studio lights at %s and %s closer than %d cells" % [o, c, Tuning.SUBSTRATE_STUDIO_LIGHT_SPACING_CELLS])
		lights.append(c)
		pocket_lit = pocket_lit or (pocket != null and grid.room_of(c) == pocket)
	if lights.size() < Tuning.SUBSTRATE_STUDIO_LIGHTS_MIN or lights.size() > Tuning.SUBSTRATE_STUDIO_LIGHTS_MAX:
		f.append("r10: %d studio lights, want %d to %d" % [lights.size(), Tuning.SUBSTRATE_STUDIO_LIGHTS_MIN, Tuning.SUBSTRATE_STUDIO_LIGHTS_MAX])
	if not pocket_lit:
		f.append("r10: the Threshold pocket is not lit")
	var frac := void_fraction(level)
	if frac < Tuning.SUBSTRATE_VOID_FRACTION_MIN or frac > Tuning.SUBSTRATE_VOID_FRACTION_MAX:
		f.append("r10: VOID fraction %.2f outside %.2f..%.2f" % [frac, Tuning.SUBSTRATE_VOID_FRACTION_MIN, Tuning.SUBSTRATE_VOID_FRACTION_MAX])
	for c in level.unfinished_void:
		if grid.kind(c) != LevelGrid.VOID:
			f.append("r10: unfinished cell %s is not VOID" % c)
			break
	for chain in MazeOps.dead_end_chains(grid):
		if chain.size() > Tuning.NULL_DEAD_END_MAX_CELLS and not _soft_tip(grid, chain[0]):
			f.append("r10: Substrate dead end of %d cells at %s" % [chain.size(), chain[0]])
	var spawn := grid.room_of(level.spawn_cell)
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if spawn != null and spawn.has_cell(c) and grid.has_flag(c, LevelGrid.F_UNFINISHED):
			f.append("r10: the spawn room is unfinished at %s" % c)
		if not LevelGrid.kind_walkable(grid.cells[i]):
			continue
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			var t := grid.wall(c, d)
			if t == LevelGrid.DOOR:
				f.append("r10: a door at %s %s" % [c, LevelGrid.DIR_NAMES[d]])
			if grid.in_bounds(o) and grid.kind(o) == LevelGrid.VOID and t != LevelGrid.SOLID and t != LevelGrid.SOFT:
				f.append("r10: edge %s %s to VOID is not SOLID" % [c, LevelGrid.DIR_NAMES[d]])
	if not level.placements_of(LevelData.P_HIDE_SPOT).is_empty() or level.exit_lock != Tuning.LOCK_OPEN:
		f.append("r10: the Substrate has no hide spots and no lock")
	if level.depth == Tuning.RUN_FINAL_DEPTH and not level.floor_solid:
		f.append("r10: the Substrate floor must be solid in a Descent")
	var null_ok := false
	var statics := 0
	for p in level.placements_of(LevelData.P_ERROR_SPAWN):
		var c: Vector2i = p[&"cell"]
		match p[&"params"].get(&"error", &""):
			&"null":
				null_ok = c == level.null_spawn_cell and grid.has_flag(c, LevelGrid.F_CRITICAL_PATH) \
					and ds[grid.idx(c)] * Tuning.GRID_CELL_SIZE >= Tuning.NULL_SPAWN_MIN_DIST
			&"static":
				statics += 1
				if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
					f.append("r10: a Static spawn on the critical path at %s" % c)
	if not null_ok:
		f.append("r10: Null's spawn must be on the critical path, %.0f m or more from the spawn" % Tuning.NULL_SPAWN_MIN_DIST)
	var want := Tuning.SUBSTRATE_STATIC_COUNT + (Tuning.CYCLE2_EXTRA_STATIC if level.cycle > 1 else 0)
	if statics != want:
		f.append("r10: %d Static spawns, want %d" % [statics, want])


## Removed cells over the corridor cells the unfinish step started from (07 §8 rule 10).
static func void_fraction(level: LevelData) -> float:
	return float(level.unfinished_void.size()) / maxf(1.0, float(level.unfinish_base))


static func _soft_tip(grid: LevelGrid, tip: Vector2i) -> bool:
	for d in 4:
		if grid.wall(tip, d) == LevelGrid.SOFT:
			return true
	return false


## Cycle 2 corruption (07 §9, 02 §7; M2.3): the spawn and exit rooms keep every fixture and
## stay finished; dead fixtures are about the 02 share; outside the Substrate, UNFINISHED
## surfaces cover about the 02 share.
static func cycle2(level: LevelData, f: PackedStringArray) -> void:
	var grid := level.grid
	if level.stratum == Tuning.STRATUM_SUBSTRATE:
		return
	var keep := LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM
	var fixtures := 0
	var dead := 0
	for p in level.placements_of(LevelData.P_FIXTURE):
		fixtures += 1
		if bool(p[&"params"].get(&"dead", false)):
			dead += 1
			if grid.has_flag(p[&"cell"], keep):
				f.append("c2: a dead fixture in the spawn or exit room at %s" % p[&"cell"])
	if dead > ceili(fixtures * Tuning.CYCLE2_FIXTURES_DARK) + 1:
		f.append("c2: %d of %d fixtures dead" % [dead, fixtures])
	var marked := 0
	for i in grid.cell_count():
		if (grid.flags[i] & LevelGrid.F_UNFINISHED) == 0:
			continue
		marked += 1
		if (grid.flags[i] & keep) != 0:
			f.append("c2: an unfinished surface in the spawn or exit room at %s" % grid.cell_at(i))
			break
	var share := float(marked) / maxf(1.0, float(grid.walkable_count()))
	if share < Tuning.CYCLE2_SURFACE_UNRENDER_FRACTION * 0.5 or share > Tuning.CYCLE2_SURFACE_UNRENDER_FRACTION * 2.0:
		f.append("c2: %.2f of the surfaces unfinished, want about %.2f" % [share, Tuning.CYCLE2_SURFACE_UNRENDER_FRACTION])
