class_name StratumShotsM23
extends RefCounted
## Build-verification poses for the Substrate (M2.3), appended to LevelShots' five by
## StratumShots: "pocket" (the Threshold from the critical path, a few cells before it),
## "studio" (a studio light rig from a few cells off), "checker" (into an unfinished room or
## segment). Each pose is {name, from, to}, eye height above the floor.

const EYE := 1.6
## Cells back along the critical path from the Threshold for the pocket pose (the doorway
## outside the 3x3 pocket), and how far behind that cell's centre the eye stands.
const POCKET_BACK := 2
const POCKET_STEP_BACK := 0.6


static func poses(data: LevelData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data.stratum != Tuning.STRATUM_SUBSTRATE:
		return out
	var g := data.grid
	var path := data.critical_path
	if path.size() > POCKET_BACK:
		var at := path[path.size() - 1 - POCKET_BACK]
		var door := g.world_of(data.exit_cell)
		var back := (g.world_of(at) - door).normalized() * POCKET_STEP_BACK
		var from := g.world_of(at) + back + Vector3(0, EYE, 0)
		out.append({&"name": "pocket", &"from": from, &"to": door + Vector3(0, 1.0, 0)})
	var studio := _studio_pose(data)
	if not studio.is_empty():
		out.append(studio)
	var checker := checker_pose(data)
	if not checker.is_empty():
		out.append(checker)
	return out


## A studio light rig (outside the spawn room and the pocket) from the walkable cell farthest
## from it along a straight open line (2 to 4 cells), looking at its head.
static func _studio_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	for p in data.placements_of(LevelData.P_FIXTURE):
		var c: Vector2i = p[&"cell"]
		if g.has_flag(c, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM):
			continue
		for d in 4:
			var n := 0
			var q := c
			while n < 4 and g.can_step(q, d):
				q += LevelGrid.DIRS[d]
				n += 1
			if n < 2:
				continue
			var head := g.world_of(c) + (p[&"offset"] as Vector3)
			var from := g.world_of(q) + Vector3(0, EYE, 0)
			return {&"name": "studio", &"from": from, &"to": head - Vector3(0, 0.6, 0)}
	return {}


## Into the largest unfinished room, from its doorway (or down an unfinished corridor). Also
## the Cycle 2 tour's "patch" (02 §7: surfaces at u = 0.2), in any stratum.
static func checker_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	var pick: RoomData = null
	for r in g.room_list:
		if g.has_flag(r.rect.position, LevelGrid.F_UNFINISHED) and (pick == null or r.rect.get_area() > pick.rect.get_area()):
			pick = r
	if pick != null:
		for e in pick.perimeter_edges():
			var c := Vector2i(e.x, e.y)
			if not g.can_step(c, e.z):
				continue
			var o := c + LevelGrid.DIRS[e.z]
			var dv := -LevelGrid.DIRS[e.z]
			var from := g.world_of(o) + Vector3(0, EYE, 0) - Vector3(dv.x, 0, dv.y) * 0.5
			var to := g.world_of(pick.rect.position) + Vector3(pick.rect.size.x - 1, 0, pick.rect.size.y - 1) + Vector3(0, 0.6, 0)
			return {&"name": "checker", &"from": from, &"to": to}
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR or not g.has_flag(c, LevelGrid.F_UNFINISHED):
			continue
		for d in 4:
			if g.can_step(c, d) and g.can_step(c + LevelGrid.DIRS[d], d):
				var dv := LevelGrid.DIRS[d]
				var from := g.world_of(c) + Vector3(0, EYE, 0)
				return {&"name": "checker", &"from": from, &"to": from + Vector3(dv.x, -0.3, dv.y) * 6.0}
	return {}
