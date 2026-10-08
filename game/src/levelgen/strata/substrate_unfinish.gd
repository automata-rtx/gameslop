class_name SubstrateUnfinish
extends RefCounted
## The Substrate's "unfinish" step (07 §5.6) over a finished Halls or Offices layout, and the
## surface units shared with Cycle 2 corruption (07 §9, 02 §7). Pure data on the grid; every
## draw comes from the rng passed in.
##   unfinish         20% of corridor cells in 2 to 5-cell clusters become VOID
##   repair           the minimum removed cells come back to reconnect the level (BFS),
##                    restoring the corridor they belonged to
##   limit_dead_ends  dead-end chains end at 4 cells (Null never corners the player, 08 §7)
##   offset_rooms     25% of rooms float +-0.25 m, with 1-cell doorway ramps where a straight
##                    corridor meets the door (a step within the walker's climb elsewhere)
##   mark_units       a fraction of built surfaces flagged UNFINISHED, whole rooms or whole
##                    corridor segments, never partially


## Removal rounds (each a batch of clusters, then one repair).
const ROUNDS := 6


## Corridor cells at the openings of `rooms` (kept: the spawn room and the pocket stay whole,
## with their doorways).
static func doorway_cells(grid: LevelGrid, rooms: Array[RoomData]) -> Dictionary:
	var out: Dictionary = {}
	for room in rooms:
		if room == null:
			continue
		for e in room.perimeter_edges():
			var c := Vector2i(e.x, e.y)
			var o := c + LevelGrid.DIRS[e.z]
			if grid.can_step(c, e.z) and grid.room_id[grid.idx(o)] < 0:
				out[grid.idx(o)] = true
	return out


## Removes `fraction` of the corridor (FLOOR) cells in clusters of MIN..MAX connected
## cells, never a `protected` cell, in rounds: each round removes the shortfall, brings back
## the fewest removed cells that keep the level whole (`repair`) and cuts dead ends to
## `dead_end_max` cells (`limit_dead_ends`, trimming tips first, which removes a few more).
## A round that would leave more than the validator's maximum VOID fraction is undone and
## tried again at half the size. Returns the corridor cell count before removal (the base of
## the VOID fraction); `removed` receives the cells left VOID.
static func unfinish(grid: LevelGrid, rng: RandomNumberGenerator, from: Vector2i, protected: Dictionary,
		dead_end_max: int, removed: Array[Vector2i], fraction: float = Tuning.SUBSTRATE_VOID_CLUSTER_FRACTION) -> int:
	var before_cells := grid.cells.duplicate()
	var before_walls := grid.walls.duplicate()
	var corridor: Array[Vector2i] = []
	for i in grid.cell_count():
		if grid.cells[i] == LevelGrid.FLOOR:
			corridor.append(grid.cell_at(i))
	var base := corridor.size()
	var target := roundi(base * fraction)
	var most := floori(base * Tuning.SUBSTRATE_VOID_FRACTION_MAX)
	RoomOps.shuffle(corridor, rng)
	var gone := 0
	var cursor := 0
	var want := target
	for round in ROUNDS:
		if want <= 0 or cursor >= corridor.size():
			break
		var undo_cells := grid.cells.duplicate()
		var undo_walls := grid.walls.duplicate()
		var undo_cursor := cursor
		var taken := 0
		while taken < want and cursor < corridor.size():
			var start := corridor[cursor]
			cursor += 1
			if grid.kind(start) != LevelGrid.FLOOR or protected.has(grid.idx(start)):
				continue
			var size := rng.randi_range(Tuning.SUBSTRATE_VOID_CLUSTER_MIN, Tuning.SUBSTRATE_VOID_CLUSTER_MAX)
			size = mini(size, maxi(Tuning.SUBSTRATE_VOID_CLUSTER_MIN, want - taken))
			var cluster := _cluster(grid, start, size, protected, rng)
			if cluster.size() < Tuning.SUBSTRATE_VOID_CLUSTER_MIN:
				continue
			for c in cluster:
				for d in 4:
					grid.set_wall(c, d, LevelGrid.WALL)
				grid.set_kind(c, LevelGrid.VOID)
			taken += cluster.size()
		grid.finalize_walls()
		repair(grid, from, before_cells, before_walls)
		limit_dead_ends(grid, dead_end_max, protected)
		var now := 0
		for i in grid.cell_count():
			if before_cells[i] == LevelGrid.FLOOR and grid.cells[i] == LevelGrid.VOID:
				now += 1
		if now > most:
			grid.cells = undo_cells
			grid.walls = undo_walls
			cursor = undo_cursor
			want = want / 2
			continue
		gone = now
		want = target - gone
	removed.clear()
	for i in grid.cell_count():
		if before_cells[i] == LevelGrid.FLOOR and grid.cells[i] == LevelGrid.VOID:
			removed.append(grid.cell_at(i))
	return base


## Up to `want` connected corridor cells from `start` (breadth first, random direction order).
static func _cluster(grid: LevelGrid, start: Vector2i, want: int, protected: Dictionary,
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var cluster: Array[Vector2i] = [start]
	var dirs: Array[int] = [0, 1, 2, 3]
	var k := 0
	while cluster.size() < want and k < cluster.size():
		var c: Vector2i = cluster[k]
		k += 1
		RoomOps.shuffle(dirs, rng)
		for d in dirs:
			if cluster.size() >= want:
				break
			var o := c + LevelGrid.DIRS[d]
			if grid.can_step(c, d) and grid.kind(o) == LevelGrid.FLOOR and not protected.has(grid.idx(o)) \
					and not cluster.has(o):
				cluster.append(o)
	return cluster


## Reconnects every walkable cell to `from` by bringing back the fewest removed cells:
## a BFS from the connected part through cells that were walkable in `before_cells` along
## edges that were open in `before_walls`, to the first stranded walkable cell; the cells on
## that route come back with their old openings along it. Repeats until one piece remains.
## Returns the number of cells restored.
static func repair(grid: LevelGrid, from: Vector2i, before_cells: PackedByteArray, before_walls: PackedByteArray) -> int:
	var restored := 0
	var n := grid.cell_count()
	var w := grid.size.x
	var steps := PackedInt32Array([-w, 1, w, -1])
	var guard := n
	while guard > 0:
		guard -= 1
		var ds := grid.distance_field(from)
		var stranded := false
		for i in n:
			if LevelGrid.kind_walkable(grid.cells[i]) and ds[i] < 0:
				stranded = true
				break
		if not stranded:
			break
		var parent := PackedInt32Array()
		parent.resize(n)
		parent.fill(-2)
		var queue := PackedInt32Array()
		for i in n:
			if ds[i] >= 0:
				parent[i] = -1
				queue.append(i)
		var head := 0
		var hit := Vector2i(-1, -1)  # (last cell on the route, stranded cell)
		while head < queue.size() and hit.x < 0:
			var i := queue[head]
			head += 1
			for d in 4:
				var b := before_walls[i * 4 + d]
				if b != LevelGrid.NONE and b != LevelGrid.DOOR:
					continue
				var j := i + steps[d]
				if parent[j] != -2:
					continue
				if LevelGrid.kind_walkable(grid.cells[j]):
					if ds[j] < 0:
						hit = Vector2i(i, j)
						break
					continue
				if grid.cells[j] == LevelGrid.VOID and LevelGrid.kind_walkable(before_cells[j]):
					parent[j] = i
					queue.append(j)
		if hit.x < 0:
			break  # nothing left to restore: the validator reports the stranded cells
		var route: Array[int] = [hit.y]
		var k := hit.x
		while k >= 0:
			route.append(k)
			if LevelGrid.kind_walkable(grid.cells[k]):
				break
			k = parent[k]
		for r in route:
			if grid.cells[r] == LevelGrid.VOID:
				grid.cells[r] = before_cells[r]
				restored += 1
				var c := grid.cell_at(r)
				for d in 4:
					grid.set_wall(c, d, LevelGrid.WALL)
		for m in range(route.size() - 1):
			var a := grid.cell_at(route[m])
			var b2 := grid.cell_at(route[m + 1])
			grid.set_wall(a, LevelGrid.DIRS.find(b2 - a), before_walls[route[m] * 4 + LevelGrid.DIRS.find(b2 - a)])
		grid.finalize_walls()
	return restored


## Dead-end chains end at `max_len` cells (07 §8 rule 10: 4 in the Substrate): a chain
## loses its tip cells to VOID down to `max_len` (an unfinished corridor stops short; nothing
## is reconnected, so no walk gets shorter); a chain held by a protected cell has a wall
## opened into another corridor near its tip instead (MazeOps.limit_dead_ends).
static func limit_dead_ends(grid: LevelGrid, max_len: int, protected: Dictionary) -> void:
	for k in 3:
		var long := false
		for chain in MazeOps.dead_end_chains(grid):
			if chain.size() <= max_len:
				continue
			var cut := 0
			for m in chain.size() - max_len:
				var c: Vector2i = chain[m]
				if protected.has(grid.idx(c)):
					break
				for d in 4:
					grid.set_wall(c, d, LevelGrid.WALL)
				grid.set_kind(c, LevelGrid.VOID)
				cut += 1
			long = long or cut < chain.size() - max_len
		grid.finalize_walls()
		if long:
			MazeOps.limit_dead_ends(grid, max_len, protected)
			grid.finalize_walls()
		var left := false
		for chain in MazeOps.dead_end_chains(grid):
			left = left or chain.size() > max_len
		if not left:
			return


## Raises or lowers FRACTION of `rooms` by OFFSET (07 §5.6). A straight corridor cell at a
## raised or lowered room's opening becomes a 1-cell ramp (within the step height either
## way); elsewhere the doorway is a plain step. Refreshes the ledges.
static func offset_rooms(grid: LevelGrid, rooms: Array[RoomData], rng: RandomNumberGenerator) -> Array[RoomData]:
	# Rooms with a straight doorway corridor (one that can carry the ramp) float first.
	var straight: Array[RoomData] = []
	var other: Array[RoomData] = []
	for room in rooms:
		(straight if _has_straight_doorway(grid, room) else other).append(room)
	RoomOps.shuffle(straight, rng)
	RoomOps.shuffle(other, rng)
	var pool: Array[RoomData] = straight
	pool.append_array(other)
	var n := roundi(pool.size() * Tuning.SUBSTRATE_FLOOR_OFFSET_FRACTION)
	var moved: Array[RoomData] = []
	for k in mini(n, pool.size()):
		var room: RoomData = pool[k]
		var y := Tuning.SUBSTRATE_FLOOR_OFFSET * (1.0 if rng.randi_range(0, 1) == 1 else -1.0)
		for c in room.cells():
			grid.set_floor_y(c, y)
		moved.append(room)
	for room in moved:
		var y := grid.floor_y(room.rect.position)
		for e in room.perimeter_edges():
			var c := Vector2i(e.x, e.y)
			if not grid.can_step(c, e.z):
				continue
			_doorway_ramp(grid, c + LevelGrid.DIRS[e.z], LevelGrid.opposite(e.z), y)
	GridHeights.refresh_ledges(grid)
	return moved


static func _has_straight_doorway(grid: LevelGrid, room: RoomData) -> bool:
	for e in room.perimeter_edges():
		var c := Vector2i(e.x, e.y)
		if not grid.can_step(c, e.z):
			continue
		var o := c + LevelGrid.DIRS[e.z]
		if grid.kind(o) == LevelGrid.FLOOR and grid.open_mask(grid.idx(o)) == (1 << e.z) | (1 << LevelGrid.opposite(e.z)):
			return true
	return false


## Cell `o` outside a door, `toward` the room whose floor is at `y`: a ramp from the floor
## beyond it to the room's when `o` is a straight corridor cell along that axis between a
## level floor and the room.
static func _doorway_ramp(grid: LevelGrid, o: Vector2i, toward: int, y: float) -> void:
	if grid.kind(o) != LevelGrid.FLOOR or absf(grid.floor_y(o)) > 0.001:
		return
	var away := LevelGrid.opposite(toward)
	if grid.open_mask(grid.idx(o)) != (1 << toward) | (1 << away):
		return
	var far := o + LevelGrid.DIRS[away]
	if grid.kind(far) != LevelGrid.FLOOR or absf(grid.floor_y(far)) > 0.001:
		return
	var run: Array[Vector2i] = [o]
	if y > 0.0:
		GridHeights.set_ramp(grid, run, toward, 0.0, y)
	else:
		GridHeights.set_ramp(grid, run, away, y, 0.0)


## Surface units (07 §5.6 "by room or corridor segment, never partially"): each room not in
## `skip_rooms` is one; corridor cells (walkable, no room) form segments between junctions,
## and cells with three or more openings join their block of `block` x `block` cells (open
## decks, rings) so a patch is never a scatter of single cells.
static func units(grid: LevelGrid, skip_rooms: Array[RoomData], block: int = 4) -> Array[Array]:
	var out: Array[Array] = []
	for room in grid.room_list:
		if not skip_rooms.has(room):
			out.append(room.cells())
	var n := grid.cell_count()
	var seen := PackedByteArray()
	seen.resize(n)
	var blocks: Dictionary = {}
	for i in n:
		if seen[i] != 0 or not LevelGrid.kind_walkable(grid.cells[i]) or grid.room_id[i] >= 0:
			continue
		if grid.openings_i(i) >= 3:
			seen[i] = 1
			var c := grid.cell_at(i)
			var key := Vector2i(c.x / block, c.y / block)
			if not blocks.has(key):
				blocks[key] = out.size()
				out.append([] as Array[Vector2i])
			(out[blocks[key]] as Array).append(c)
			continue
		var seg: Array[Vector2i] = []
		var queue := PackedInt32Array([i])
		seen[i] = 1
		var head := 0
		while head < queue.size():
			var j := queue[head]
			head += 1
			seg.append(grid.cell_at(j))
			var c := grid.cell_at(j)
			for d in 4:
				if not grid.can_step(c, d):
					continue
				var k := grid.idx(c + LevelGrid.DIRS[d])
				if seen[k] != 0 or grid.room_id[k] >= 0 or grid.openings_i(k) >= 3:
					continue
				seen[k] = 1
				queue.append(k)
		out.append(seg)
	return out


## Flags whole units UNFINISHED, in random order, until `fraction` of the walkable cells
## carry it. Returns the cells flagged.
static func mark_units(grid: LevelGrid, unit_list: Array[Array], fraction: float, rng: RandomNumberGenerator) -> int:
	var target := roundi(grid.walkable_count() * fraction)
	var order: Array[int] = []
	for k in unit_list.size():
		order.append(k)
	RoomOps.shuffle(order, rng)
	var marked := 0
	for k in order:
		if marked >= target:
			break
		var unit: Array = unit_list[k]
		for c: Vector2i in unit:
			grid.add_flag(c, LevelGrid.F_UNFINISHED)
		marked += unit.size()
	return marked
