class_name BlockOps
extends RefCounted
## R13: cells a prop fills (LevelGrid.F_BLOCKED). A grammar blocks a cell only when the
## level stays whole: the cells are walkable, off the critical path (so it stands as the
## shortest walk), outside the spawn and exit rooms, and every other walkable cell is still
## reachable from `from` (the spawn) with them gone.


static func can_block(grid: LevelGrid, cells: Array[Vector2i], from: Vector2i) -> bool:
	var gone: Dictionary = {}
	for c in cells:
		if not grid.is_walkable(c) or c == from:
			return false
		if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH | LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM):
			return false
		gone[grid.idx(c)] = true
	return _connected_without(grid, gone, from)


## Blocks `cells` when can_block allows it. Returns whether it did.
static func try_block(grid: LevelGrid, cells: Array[Vector2i], from: Vector2i) -> bool:
	if not can_block(grid, cells, from):
		return false
	for c in cells:
		grid.block(c)
	return true


static func _connected_without(grid: LevelGrid, gone: Dictionary, from: Vector2i) -> bool:
	if not grid.is_walkable(from):
		return false
	var seen := PackedByteArray()
	seen.resize(grid.cell_count())
	var start := grid.idx(from)
	seen[start] = 1
	var queue := PackedInt32Array([start])
	var head := 0
	var steps: Array[int] = [-grid.size.x, 1, grid.size.x, -1]
	while head < queue.size():
		var i := queue[head]
		head += 1
		var m := grid.open_mask(i)
		for d in 4:
			if (m & (1 << d)) == 0:
				continue
			var j := i + steps[d]
			if seen[j] == 0 and not gone.has(j):
				seen[j] = 1
				queue.append(j)
	var want := 0
	for i in grid.cell_count():
		if grid.is_walkable_i(i) and not gone.has(i):
			want += 1
	return queue.size() == want
