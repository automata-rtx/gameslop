class_name MazeOps
extends RefCounted
## Corridor operations of the shared ops library (07 §4): maze_fill, sparsify, braid,
## straighten, and dead-end chain repair. All loops are bounded; all randomness comes from
## the RandomNumberGenerator passed in.
##
## Corridors are 1 cell wide and separated by edge walls (07 §2 "edge walls"): every free
## cell of the region is a maze node, so two corridors that run side by side share one
## 0.2 m wall and a noclip through it lands in the neighbouring corridor. `sparsify` then
## removes corridor leaves until the level reaches its walkable cell target (05 §2).


## Recursive backtracker over every VOID cell in `region` (iterative, explicit stack),
## skipping cell indices in `blocked` (they stay VOID: the masses between corridors).
## Disconnected pockets start their own walk and are joined to an earlier corridor cell.
## Returns the number of cells carved.
static func maze_fill(grid: LevelGrid, region: Rect2i, rng: RandomNumberGenerator, blocked: Dictionary = {}) -> int:
	var carved := 0
	var stack: Array[Vector2i] = []
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var start := Vector2i(x, z)
			if grid.kind(start) != LevelGrid.VOID or blocked.has(grid.idx(start)):
				continue
			grid.set_kind(start, LevelGrid.FLOOR)
			carved += 1
			_join_to_corridor(grid, start, region)
			stack.append(start)
			carved += _walk(grid, region, rng, stack, blocked)
	return carved


static func _walk(grid: LevelGrid, region: Rect2i, rng: RandomNumberGenerator, stack: Array[Vector2i], blocked: Dictionary) -> int:
	var carved := 0
	var guard := region.size.x * region.size.y * 4
	var options := PackedInt32Array()
	options.resize(4)
	var w := grid.size.x
	var steps := PackedInt32Array([-w, 1, w, -1])
	while not stack.is_empty() and guard > 0:
		guard -= 1
		var c: Vector2i = stack[stack.size() - 1]
		var i := c.y * w + c.x
		var n_opt := 0
		# Index arithmetic: the hot loop of generation.
		if c.y > region.position.y and _free(grid, i - w, blocked):
			options[n_opt] = 0
			n_opt += 1
		if c.x < region.end.x - 1 and _free(grid, i + 1, blocked):
			options[n_opt] = 1
			n_opt += 1
		if c.y < region.end.y - 1 and _free(grid, i + w, blocked):
			options[n_opt] = 2
			n_opt += 1
		if c.x > region.position.x and _free(grid, i - 1, blocked):
			options[n_opt] = 3
			n_opt += 1
		if n_opt == 0:
			stack.pop_back()
			continue
		var dir := options[rng.randi_range(0, n_opt - 1)]
		var j := i + steps[dir]
		grid.cells[j] = LevelGrid.FLOOR
		grid.walls[i * 4 + dir] = LevelGrid.NONE
		grid.walls[j * 4 + (dir + 2) % 4] = LevelGrid.NONE
		carved += 1
		stack.append(grid.cell_at(j))
	return carved


static func _free(grid: LevelGrid, j: int, blocked: Dictionary) -> bool:
	return grid.cells[j] == LevelGrid.VOID and not blocked.has(j)


static func _join_to_corridor(grid: LevelGrid, c: Vector2i, region: Rect2i) -> void:
	for d in 4:
		var o := c + LevelGrid.DIRS[d]
		if region.has_point(o) and grid.kind(o) == LevelGrid.FLOOR:
			grid.set_wall(c, d, LevelGrid.NONE)
			return


## Removes corridor (FLOOR) leaves until the walkable count is at most `target`, in rounds:
## each round removes the current leaves (in random order), so every dead-end branch
## shrinks by one cell per round and the level keeps its coverage instead of losing whole
## branches. Removing a leaf never disconnects anything. `protected` holds cell indices
## that are never removed (corridor cells at room doors).
static func sparsify(grid: LevelGrid, target: int, rng: RandomNumberGenerator, protected: Dictionary) -> int:
	var walkable := grid.walkable_count()
	var pool: Array[Vector2i] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if _removable_leaf(grid, c, protected):
			pool.append(c)
	var removed := 0
	var guard := grid.cell_count()
	while walkable > target and not pool.is_empty() and guard > 0:
		guard -= 1
		RoomOps.shuffle(pool, rng)
		var next: Array[Vector2i] = []
		for c in pool:
			if walkable <= target:
				break
			if not _removable_leaf(grid, c, protected):
				continue
			var neighbour := Vector2i(-1, -1)
			for d in 4:
				if grid.can_step(c, d):
					neighbour = c + LevelGrid.DIRS[d]
				grid.set_wall(c, d, LevelGrid.WALL)
			grid.set_kind(c, LevelGrid.VOID)
			walkable -= 1
			removed += 1
			if neighbour.x >= 0 and _removable_leaf(grid, neighbour, protected):
				next.append(neighbour)
		pool = next
	return removed


static func _removable_leaf(grid: LevelGrid, c: Vector2i, protected: Dictionary) -> bool:
	return grid.kind(c) == LevelGrid.FLOOR and not protected.has(grid.idx(c)) and grid.openings(c) <= 1


## Corridor dead ends: FLOOR cells with exactly one opening, in index order.
static func dead_ends(grid: LevelGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in grid.cell_count():
		if grid.cells[i] == LevelGrid.FLOOR and grid.openings_i(i) == 1:
			out.append(grid.cell_at(i))
	return out


## 07 §4: opens a wall from a dead end to an adjacent corridor cell for `fraction` of dead
## ends; marks the rest DEAD_END. Returns the number of walls opened.
static func braid(grid: LevelGrid, fraction: float, rng: RandomNumberGenerator) -> int:
	var opened := 0
	for c in dead_ends(grid):
		if grid.openings(c) != 1:
			continue
		var options: Array[int] = []
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if grid.kind(o) == LevelGrid.FLOOR and grid.wall(c, d) == LevelGrid.WALL:
				options.append(d)
		if not options.is_empty() and rng.randf() < fraction:
			grid.set_wall(c, options[rng.randi_range(0, options.size() - 1)], LevelGrid.NONE)
			opened += 1
	mark_dead_ends(grid)
	return opened


## Re-derives the DEAD_END flag from the current walls.
static func mark_dead_ends(grid: LevelGrid) -> void:
	for i in grid.cell_count():
		grid.flags[i] &= ~LevelGrid.F_DEAD_END
	for c in dead_ends(grid):
		grid.add_flag(c, LevelGrid.F_DEAD_END)


## 07 §5.1: straightens `fraction` of corridor turns by opening the wall ahead when it
## joins a corridor (the signature long hallway). Returns the number opened.
static func straighten(grid: LevelGrid, fraction: float, rng: RandomNumberGenerator) -> int:
	var opened := 0
	for i in grid.cell_count():
		if grid.cells[i] != LevelGrid.FLOOR:
			continue
		var m := grid.open_mask(i)
		# Exactly two openings at right angles: N+E, E+S, S+W or W+N.
		if m != 3 and m != 6 and m != 12 and m != 9:
			continue
		if rng.randf() >= fraction:
			continue
		var c := grid.cell_at(i)
		var open_dirs: Array[int] = []
		for d in 4:
			if (m & (1 << d)) != 0:
				open_dirs.append(d)
		# Walking in through one opening, "ahead" is the edge opposite it.
		for d in open_dirs:
			var ahead := LevelGrid.opposite(d)
			var o := c + LevelGrid.DIRS[ahead]
			if grid.kind(o) == LevelGrid.FLOOR and grid.wall(c, ahead) == LevelGrid.WALL:
				grid.set_wall(c, ahead, LevelGrid.NONE)
				opened += 1
				break
	return opened


## Dead-end chains: from each dead end, the corridor cells walked until the first cell
## that is not a plain 2-opening corridor cell. Each entry is the chain, tip first.
static func dead_end_chains(grid: LevelGrid) -> Array[Array]:
	var out: Array[Array] = []
	for tip in dead_ends(grid):
		var chain: Array[Vector2i] = [tip]
		var prev := Vector2i(-1, -1)
		var c := tip
		var guard := grid.cell_count()
		while guard > 0:
			guard -= 1
			var next := Vector2i(-1, -1)
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				if o != prev and grid.can_step(c, d):
					next = o
					break
			if next.x < 0 or grid.kind(next) != LevelGrid.FLOOR or grid.openings(next) != 2:
				break
			chain.append(next)
			prev = c
			c = next
		out.append(chain)
	return out


## Shortens dead-end chains longer than `max_len` cells: opens a wall from one of the first
## `max_len` cells of the chain (tip first) into another corridor cell, which leaves at most
## that many cells hanging; only when no such wall exists are tip cells removed.
## Returns cells removed.
static func limit_dead_ends(grid: LevelGrid, max_len: int, protected: Dictionary) -> int:
	var removed := 0
	for chain in dead_end_chains(grid):
		if chain.size() <= max_len:
			continue
		var opened := false
		for k in mini(max_len, chain.size()):
			var c: Vector2i = chain[k]
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				var pos := chain.find(o)
				# Not the chain neighbours of c (they are already joined).
				if grid.kind(o) == LevelGrid.FLOOR and grid.wall(c, d) == LevelGrid.WALL and (pos < 0 or absi(pos - k) > 1):
					grid.set_wall(c, d, LevelGrid.NONE)
					opened = true
					break
			if opened:
				break
		if opened:
			continue
		for k in chain.size() - max_len:
			var c: Vector2i = chain[k]
			if protected.has(grid.idx(c)):
				break
			for d in 4:
				grid.set_wall(c, d, LevelGrid.WALL)
			grid.set_kind(c, LevelGrid.VOID)
			removed += 1
	mark_dead_ends(grid)
	return removed
