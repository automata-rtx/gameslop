class_name StratumShotsM22
extends RefCounted
## Build-verification poses for Offices and Server (M2.2), appended to LevelShots' five by
## StratumShots: Offices "cubicles" (across an open office from its corner, the partitions
## below the eye), "dark_group" (from a lit cell towards a dark fixture group), "meeting"
## (the glass wall from the corridor); Server "racks" (down the longest aisle), "cage"
## (a cage's fence from the aisle), "rack_face" (a rack front at 1.5 m). Each pose is
## {name, from, to}, eye height above the floor.

const EYE := 1.6


static func poses(data: LevelData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g := data.grid
	if data.stratum == &"offices":
		for room in g.room_list:
			if room.kind == OfficeRooms.OPEN:
				var r := room.rect
				var from := g.world_of(r.position) + Vector3(-0.5, EYE, -0.5)
				out.append({&"name": "cubicles", &"from": from, &"to": g.world_of(r.end - Vector2i.ONE) + Vector3(0, 0.4, 0)})
				break
		var dark := _dark_pose(data)
		if not dark.is_empty():
			out.append(dark)
		for room in g.room_list:
			if room.kind == OfficeRooms.MEETING:
				for e in room.perimeter_edges():
					if g.wall(Vector2i(e.x, e.y), e.z) != LevelGrid.GLASS:
						continue
					var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
					var dv := LevelGrid.DIRS[e.z]
					var from := g.world_of(o) + Vector3(0, EYE, 0) + Vector3(dv.x, 0, dv.y) * 0.6
					out.append({&"name": "meeting", &"from": from, &"to": g.world_of(room.center()) + Vector3(0, 1.0, 0)})
					break
				break
	elif data.stratum == &"server":
		var racks := _aisle_pose(data)
		if not racks.is_empty():
			out.append(racks)
		for room in g.room_list:
			if room.kind != ServerGenerator.CAGE:
				continue
			for e in room.perimeter_edges():
				if g.wall(Vector2i(e.x, e.y), e.z) != LevelGrid.GLASS:
					continue
				var o := Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]
				var dv := LevelGrid.DIRS[e.z]
				var from := g.world_of(o) + Vector3(0, EYE, 0) + Vector3(dv.x, 0, dv.y) * 0.7
				out.append({&"name": "cage", &"from": from, &"to": g.world_of(room.center()) + Vector3(0, 0.6, 0)})
				break
			break
	return out


## From the walkable cell nearest a dark fixture (3 to 6 cells off, a clear grid line)
## towards it.
static func _dark_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	for p in data.placements_of(LevelData.P_FIXTURE):
		if not bool(p[&"params"].get(&"dark", false)):
			continue
		var c: Vector2i = p[&"cell"]
		for d in 4:
			var o := c
			var k := 0
			while k < 5 and g.can_step(o, d):
				o += LevelGrid.DIRS[d]
				k += 1
			if k >= 3:
				var from := g.world_of(o) + Vector3(0, EYE, 0)
				return {&"name": "dark_group", &"from": from, &"to": g.world_of(c) + Vector3(0, 1.0, 0)}
	return {}


## Server: from the head of the longest aisle between racks, down it; and a rack front.
static func _aisle_pose(data: LevelData) -> Dictionary:
	var g := data.grid
	var best := Vector3i(-1, -1, -1)
	var best_n := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR:
			continue
		for d: int in [LevelGrid.E, LevelGrid.S]:
			var side := (d + 1) % 4
			if g.kind(c + LevelGrid.DIRS[side]) != LevelGrid.RACK or g.kind(c - LevelGrid.DIRS[side]) != LevelGrid.RACK:
				continue
			if g.can_step(c, LevelGrid.opposite(d)) and g.kind(c - LevelGrid.DIRS[d]) == LevelGrid.FLOOR \
					and g.kind(c - LevelGrid.DIRS[d] + LevelGrid.DIRS[side]) == LevelGrid.RACK:
				continue
			var n := 0
			var p := c
			while g.can_step(p, d):
				p += LevelGrid.DIRS[d]
				n += 1
			if n > best_n:
				best_n = n
				best = Vector3i(c.x, c.y, d)
	if best.x < 0:
		return {}
	var dv := LevelGrid.DIRS[best.z]
	var from := g.world_of(Vector2i(best.x, best.y)) + Vector3(0, EYE, 0) - Vector3(dv.x, 0, dv.y) * 0.6
	return {&"name": "racks", &"from": from, &"to": from + Vector3(dv.x, -0.35, dv.y) * 10.0}
