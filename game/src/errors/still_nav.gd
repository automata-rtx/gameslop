class_name StillNav
extends RefCounted
## Navigation points for Still (08 §2, §4), split out of ErrorStill (14 §6 400-line
## limit). Pure helpers over one ErrorStill: navmesh snapping, seeded random points, the
## Satiated retreat point, the Search inspection plan and the Skip destination. They use
## the error's own seeded rng, so behaviour stays deterministic per seed.


static func snap(s: ErrorStill, p: Vector3) -> Vector3:
	var map := s.agent.get_navigation_map()
	if not map.is_valid():
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


static func random_point_near(s: ErrorStill, centre: Vector3, radius: float) -> Vector3:
	var a := s.rng.randf() * TAU
	var r := sqrt(s.rng.randf()) * radius
	return snap(s, centre + Vector3(cos(a) * r, 0.0, sin(a) * r))


## 08 §2: retreat to a hinted point >= 20 m away; without one, the farthest of a few
## seeded candidates 20 to 30 m from the player.
static func retreat_point(s: ErrorStill) -> Vector3:
	var from := s.player.global_position if s.has_player() else s.body_position()
	if s.has_hint() and s._hint.distance_to(from) >= Tuning.ERROR_SATIATED_RETREAT_DIST:
		s.clear_hint()
		return snap(s, s._hint)
	var best := s.body_position()
	var best_d := -1.0
	for i in Tuning.ERROR_RETREAT_SAMPLES:
		var a := s.rng.randf() * TAU
		var r := Tuning.ERROR_SATIATED_RETREAT_DIST * (1.0 + s.rng.randf() * 0.5)
		var p := snap(s, from + Vector3(cos(a) * r, 0.0, sin(a) * r))
		var d := p.distance_to(from)
		if d > best_d:
			best_d = d
			best = p
	return best


## 08 §2, §4 Search: hide spots within 6 m of last_known_pos (each with the aggression-
## scaled chance), then up to 3 nearby points (a hint replaces the first).
static func plan_inspection(s: ErrorStill) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := s.senses.last_known_pos
	for n in s.get_tree().get_nodes_in_group(&"hide_spots"):
		var spot := n as HideSpot
		if spot == null or spot.global_position.distance_to(at) > Tuning.STILL_HIDE_SEARCH_RADIUS:
			continue
		if s.rng.randf() < s.hide_check_chance():
			out.append({"pos": snap(s, spot.exit_point.global_position), "spot": spot})
	for i in Tuning.ERROR_SEARCH_INSPECT_CELLS:
		var p := random_point_near(s, at, Tuning.ERROR_SEARCH_INSPECT_RADIUS)
		if s.has_hint() and i == 0:
			s.clear_hint()
			p = snap(s, s._hint)
		out.append({"pos": p, "spot": null})
	return out


## 08 §4 Skip: the navmesh point 6 m further along the current path, or Vector3.INF when
## there is no path or it lies in the player's frustum.
static func skip_destination(s: ErrorStill) -> Vector3:
	var path := s.agent.get_current_navigation_path()
	if path.size() < 2:
		return Vector3.INF
	var left := Tuning.STILL_SKIP_STEP
	var at := s.body_position()
	var dest := at
	for i in range(s.agent.get_current_navigation_path_index(), path.size()):
		var seg := path[i] - at
		if seg.length() >= left:
			dest = at + seg.normalized() * left
			left = 0.0
			break
		left -= seg.length()
		at = path[i]
		dest = at
	dest = snap(s, dest)
	return Vector3.INF if in_player_frustum(s, dest) else dest


static func in_player_frustum(s: ErrorStill, p: Vector3) -> bool:
	if not s.has_player() or s.player.rig == null:
		return false
	var cam := s.player.rig.camera
	return cam.is_position_in_frustum(p + Vector3.UP * ErrorStill.COLUMN_CENTRE) \
			or cam.is_position_in_frustum(p + Vector3.UP * Tuning.STILL_CAPSULE_HEIGHT)


## 08 §2 doors: gathers the level's doors once (Still opens the closed ones near its path)
## and keeps an open leaf out of the body's collisions. A leaf swings into the cell beside
## the doorway; it is a door, not a wall. A closed leaf still blocks until Still opens it.
static func bind_doors(s: ErrorStill) -> Array[Door]:
	var out: Array[Door] = []
	for n in s.get_tree().get_nodes_in_group(&"doors"):
		var door := n as Door
		if door == null:
			continue
		out.append(door)
		# An instance method: bound static callables from two Stills compare equal.
		door.opened_changed.connect(s._on_door_opened.bind(door))
		on_door_opened(door.is_open, s, door)
	return out


static func on_door_opened(open: bool, s: ErrorStill, door: Door) -> void:
	if not is_instance_valid(s) or not is_instance_valid(door) or door.leaf == null:
		return
	if open:
		s.body.add_collision_exception_with(door.leaf)
	else:
		s.body.remove_collision_exception_with(door.leaf)


## 08 §2: closed doors within ERROR_DOOR_OPEN_DIST are opened; Chase opens with a slam.
static func open_doors_near(s: ErrorStill, doors: Array[Door]) -> void:
	var p := s.body_position()
	for door in doors:
		if not is_instance_valid(door) or door.is_open:
			continue
		var d := door.global_position
		if Vector2(d.x - p.x, d.z - p.z).length() <= Tuning.ERROR_DOOR_OPEN_DIST:
			door.open(s.state == Tuning.ERROR_STATE_CHASE)


## 02 §8: a capsule-topped column standing on its origin: open flat base (it stands on the
## floor; a base disc would z-fight it), 0.5 m radius (Tuning reading), 2.6 m tall with a
## hemispherical top. One shared mesh.
static var _column_mesh: ArrayMesh


static func column_mesh() -> ArrayMesh:
	if _column_mesh != null:
		return _column_mesh
	const SEGMENTS := 24
	const CAP_RINGS := 8
	var r := Tuning.STILL_CAPSULE_RADIUS
	var shaft := Tuning.STILL_CAPSULE_HEIGHT - r
	# Rings from the base up: (height, radius).
	var rings: Array[Vector2] = [Vector2(0.0, r), Vector2(shaft, r)]
	for i in range(1, CAP_RINGS + 1):
		var a := PI * 0.5 * float(i) / CAP_RINGS
		rings.append(Vector2(shaft + sin(a) * r, cos(a) * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		for j in SEGMENTS:
			var a0 := TAU * float(j) / SEGMENTS
			var a1 := TAU * float(j + 1) / SEGMENTS
			var lo := rings[k]
			var hi := rings[k + 1]
			var p00 := Vector3(cos(a0) * lo.y, lo.x, sin(a0) * lo.y)
			var p01 := Vector3(cos(a1) * lo.y, lo.x, sin(a1) * lo.y)
			var p10 := Vector3(cos(a0) * hi.y, hi.x, sin(a0) * hi.y)
			var p11 := Vector3(cos(a1) * hi.y, hi.x, sin(a1) * hi.y)
			for v: Vector3 in [p00, p01, p11, p00, p11, p10]:
				st.add_vertex(v)
	st.generate_normals()
	_column_mesh = st.commit()
	return _column_mesh
