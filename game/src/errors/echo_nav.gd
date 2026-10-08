class_name EchoNav
extends RefCounted
## Navigation points for Echo (08 §2, §6), split out of ErrorEcho (14 §6 400-line limit).
## Pure helpers over one ErrorEcho using its own seeded rng (deterministic per seed):
## navmesh snapping, Wander points, the direct-reach test that trims trail points, the
## Search stand-off and inspection points (never the heard point itself, never its cell),
## wading, and doors.


static func snap(e: ErrorEcho, p: Vector3) -> Vector3:
	var map := e.agent.get_navigation_map()
	if not map.is_valid():
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


static func random_point_near(e: ErrorEcho, centre: Vector3, radius: float) -> Vector3:
	var a := e.rng.randf() * TAU
	var r := sqrt(e.rng.randf()) * radius
	return snap(e, centre + Vector3(cos(a) * r, 0.0, sin(a) * r))


## 08 §6 trimming: true when the navmesh path from `from` to `to` is (nearly) the straight
## line, so the trail points between them can be skipped.
static func is_direct(e: ErrorEcho, from: Vector3, to: Vector3) -> bool:
	var map := e.agent.get_navigation_map()
	if not map.is_valid():
		return true
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return flat(from, to) < Tuning.ECHO_ENTRY_ARRIVE_DIST
	if flat(path[path.size() - 1], to) > Tuning.ERROR_ARRIVE_DIST:
		return false
	var length := 0.0
	for i in range(1, path.size()):
		length += flat(path[i - 1], path[i])
	return length <= flat(from, to) * Tuning.ECHO_DIRECT_SLACK + 0.1


## The farthest trail entry in [trail.next_index, target] Echo can walk to in a straight
## line (it trims the points before it); else the next entry.
static func trail_goal(e: ErrorEcho, trail: EchoTrail, target: int) -> int:
	var from := e.body_position()
	var lo := trail.next_index
	var tried := 0
	for j in range(target, lo, -1):
		if tried >= Tuning.ECHO_DIRECT_CANDIDATES:
			break
		tried += 1
		if is_direct(e, from, trail.entries[j][&"position"]):
			return j
	return lo


## 08 §6 Search: where Echo stands to search the heard `point`: on its own side, at least
## ECHO_SEARCH_MIN_POINT_DIST from it and outside its grid cell (never the point itself,
## so a player standing still is not walked into; CHANGELOG 2026-10-07).
static func stand_off(e: ErrorEcho, point: Vector3) -> Vector3:
	var from := e.body_position()
	var dir := Vector3(from.x - point.x, 0.0, from.z - point.z)
	if dir.length() < 0.01:
		dir = Vector3.BACK
	dir = dir.normalized()
	var best := from
	for k in 4:
		var d := Tuning.ECHO_SEARCH_MIN_POINT_DIST + 0.5 * k
		var p := snap(e, point + dir * d)
		if ok_search_point(e, point, p):
			return p
		best = p
	return best


## 08 §6: up to ERROR_SEARCH_INSPECT_CELLS points within ERROR_SEARCH_INSPECT_RADIUS of the
## heard point, each at least 2 m from it, outside its cell, and reached without passing
## within 2 m of it (a hint replaces the first).
static func plan_inspection(e: ErrorEcho, point: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var from := e.body_position()
	for i in Tuning.ERROR_SEARCH_INSPECT_CELLS:
		if e.has_hint() and i == 0:
			e.clear_hint()
			out.append(snap(e, e._hint))
			continue
		for k in Tuning.ECHO_SEARCH_CANDIDATES:
			var p := random_point_near(e, point, Tuning.ERROR_SEARCH_INSPECT_RADIUS)
			if ok_search_point(e, point, p) and seg_clear(from, p, point):
				out.append(p)
				from = p
				break
	return out


static func ok_search_point(e: ErrorEcho, point: Vector3, p: Vector3) -> bool:
	return flat(p, point) >= Tuning.ECHO_SEARCH_MIN_POINT_DIST and not same_cell(e, p, point)


static func same_cell(e: ErrorEcho, a: Vector3, b: Vector3) -> bool:
	if e.grid == null:
		return false
	return e.grid.cell_of(a) == e.grid.cell_of(b)


## The straight walk a -> b keeps ECHO_SEARCH_MIN_POINT_DIST from `point` (XZ).
static func seg_clear(a: Vector3, b: Vector3, point: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var p2 := Vector2(point.x, point.z)
	var closest := Geometry2D.get_closest_point_to_segment(p2, a2, b2)
	return closest.distance_to(p2) >= Tuning.ECHO_SEARCH_MIN_POINT_DIST - 0.05


## 06 §3 wading for Echo's own body: inside a water volume deeper than 0.3 m.
static func wading_at(e: ErrorEcho, pos: Vector3) -> bool:
	for n in e.get_tree().get_nodes_in_group(WaterVolume.GROUP):
		var w := n as WaterVolume
		if w == null:
			continue
		var cs := Tuning.GRID_CELL_SIZE
		var lo := Vector2(w.rect.position) * cs - Vector2.ONE * cs * 0.5
		var hi := Vector2(w.rect.end) * cs - Vector2.ONE * cs * 0.5
		if pos.x >= lo.x and pos.x <= hi.x and pos.z >= lo.y and pos.z <= hi.y:
			if w.depth_at(pos.y) > Tuning.PLAYER_WADE_DEPTH:
				return true
	return false


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- doors (08 §2, §6: Echo opens doors, with the slam in Follow) ------------------------------

static func bind_doors(e: ErrorEcho) -> Array[Door]:
	var out: Array[Door] = []
	for n in e.get_tree().get_nodes_in_group(&"doors"):
		var door := n as Door
		if door == null:
			continue
		out.append(door)
		door.opened_changed.connect(e._on_door_opened.bind(door))
		on_door_opened(door.is_open, e, door)
	return out


static func on_door_opened(open: bool, e: ErrorEcho, door: Door) -> void:
	if not is_instance_valid(e) or not is_instance_valid(door) or door.leaf == null:
		return
	if open:
		e.body.add_collision_exception_with(door.leaf)
	else:
		e.body.remove_collision_exception_with(door.leaf)


static func open_doors_near(e: ErrorEcho, doors: Array[Door]) -> void:
	var p := e.body_position()
	for door in doors:
		if not is_instance_valid(door) or door.is_open:
			continue
		var d := door.global_position
		if Vector2(d.x - p.x, d.z - p.z).length() <= Tuning.ERROR_DOOR_OPEN_DIST:
			door.open(e.state == Tuning.ERROR_STATE_FOLLOW)
