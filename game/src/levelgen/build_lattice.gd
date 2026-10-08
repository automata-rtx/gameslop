class_name BuildLattice
extends RefCounted
## The shared lattice of a BuildPlan (07 §8): every face is subdivided on it, so faces that
## share an edge share its vertices. Along X and Z: each fine column's bounds (cell interior
## 1.8 m, edge strip 0.2 m) plus steps of at most LEVELBUILD_MESH_MAX_EDGE; along Y: every
## 0.5 m and every floor, ceiling, door top, partition top and rack top in the level.
## (Split out of BuildPlan in M2.2; pure data, worker thread.)


static func make(p: BuildPlan) -> void:
	var grid := p.grid
	for i in grid.size.x * 2 + 1:
		p._xb.append(breaks(i))
	for j in grid.size.y * 2 + 1:
		p._zb.append(breaks(j))
	var marks: Dictionary = {}
	for i in grid.cell_count():
		if grid.ramp_dir[i] > 0:
			continue
		var y := grid.floor_heights[i]
		for v: float in [y, y + p._door_h, y + p._part_h, p.ceiling_at(grid.cell_at(i), y)]:
			marks[roundi(v * 1000.0)] = v
		if grid.cells[i] == LevelGrid.RACK:
			marks[roundi((y + p.rack_height) * 1000.0)] = y + p.rack_height
	var lo := 0.0
	var hi := p.height
	for k: int in marks:
		lo = minf(lo, marks[k])
		hi = maxf(hi, marks[k])
	var step := Tuning.LEVELBUILD_MESH_MAX_EDGE
	for k in range(ceili(lo / step - 0.0001), floori(hi / step + 0.0001) + 1):
		marks[roundi(k * step * 1000.0)] = k * step
	var keys := marks.keys()
	keys.sort()
	for k: int in keys:
		p._yb.append(marks[k])


## Breaks of fine column i (or row): its two bounds plus subdivisions of at most 0.5 m.
static func breaks(i: int) -> PackedFloat32Array:
	var half_t := Tuning.GRID_WALL_THICKNESS * 0.5
	var cs := Tuning.GRID_CELL_SIZE
	var lo: float
	var hi: float
	if i % 2 == 0:
		var line := (i / 2) * cs - cs * 0.5
		lo = line - half_t
		hi = line + half_t
	else:
		var c := ((i - 1) / 2) * cs
		lo = c - cs * 0.5 + half_t
		hi = c + cs * 0.5 - half_t
	var n := maxi(1, ceili((hi - lo) / Tuning.LEVELBUILD_MESH_MAX_EDGE - 0.0001))
	var out := PackedFloat32Array()
	for k in n + 1:
		out.append(lo + (hi - lo) * k / n if k < n else hi)
	return out


## Y breaks of `p` within [lo, hi].
static func ys(p: BuildPlan, lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for y in p._yb:
		if y >= lo - 0.0001 and y <= hi + 0.0001:
			out.append(y)
	return out
