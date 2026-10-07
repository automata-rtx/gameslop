class_name PlayerObservation
extends RefCounted
## The observation predicate (06 Interfaces, 08 §4): Player.is_observing(node) is true when
## the node is in the camera frustum (any of its observe points is: a crouched player
## looking at a 2.6 m column from 2.5 m sees its centre but not its top), within 30 m and
## unoccluded (every observe point has a clear world-layer ray from the eye), and lit:
## the flashlight is on, an observe point lies within 25 deg of the beam axis and within
## the beam's range (22 m), or any registered light query reports an observe point lit
## (glowstick within 4 m, burning flare within 8 m, a powered fixture's light range).
## Light queries are Callables (pos: Vector3) -> bool registered by the level's
## LightPool and by items. The 25 deg observation angle is wider than the 19 deg visible
## half-cone on purpose: it errs toward the player (CHANGELOG, production).


## Points an observer must see: the node's `observe_points()` if it has one (Still: the
## column's centre and top), else its origin.
static func points_of(node: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if node.has_method(&"observe_points"):
		for p: Variant in node.call(&"observe_points"):
			if p is Vector3:
				out.append(p)
	if out.is_empty():
		out.append(node.global_position)
	return out


static func is_observing(camera: Camera3D, node: Node3D, flashlight_on: bool, beam_origin: Vector3,
		beam_axis: Vector3, light_queries: Array[Callable], exclude: Array[RID]) -> bool:
	if camera == null or node == null or not node.is_inside_tree():
		return false
	var eye := camera.global_position
	var points := points_of(node)
	var space := camera.get_world_3d().direct_space_state
	var node_rids := _rids_of(node)
	var ignore: Array[RID] = exclude.duplicate()
	ignore.append_array(node_rids)
	# Cheap tests first: every point within 30 m, any point in the frustum.
	var any_in_frustum := false
	for p in points:
		if eye.distance_to(p) > Tuning.STILL_OBSERVE_MAX_DIST:
			return false
		any_in_frustum = any_in_frustum or camera.is_position_in_frustum(p)
	if not any_in_frustum:
		return false
	for p in points:
		if not clear_line(space, eye, p, ignore):
			return false
	for p in points:
		if is_lit(p, flashlight_on, beam_origin, beam_axis, light_queries):
			return true
	return false


static func is_lit(p: Vector3, flashlight_on: bool, beam_origin: Vector3, beam_axis: Vector3,
		light_queries: Array[Callable]) -> bool:
	if flashlight_on and in_beam(p, beam_origin, beam_axis):
		return true
	for q in light_queries:
		if q.is_valid() and bool(q.call(p)):
			return true
	return false


## 08 §4: within 25 deg of the beam axis (a tired 30 deg beam still counts if aimed) and
## within the beam's range: a point the beam does not reach is not lit by it.
static func in_beam(p: Vector3, beam_origin: Vector3, beam_axis: Vector3) -> bool:
	var to := p - beam_origin
	if to.length_squared() < 0.0001:
		return true
	if to.length() > Tuning.FLASH_RANGE:
		return false
	return rad_to_deg(beam_axis.normalized().angle_to(to.normalized())) <= Tuning.STILL_OBSERVE_BEAM_ANGLE


static func clear_line(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, PlayerLayers.WORLD_MASK, exclude)
	return space.intersect_ray(q).is_empty()


static func _rids_of(node: Node) -> Array[RID]:
	var out: Array[RID] = []
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	return out
