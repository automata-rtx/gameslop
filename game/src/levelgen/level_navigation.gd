class_name LevelNavigation
extends RefCounted
## The level's navigation source and settings (07 §8): floors, ramps, pool steps and walls
## from the plan (deep water's floor left out), props' static colliders and door jambs.
## Agent radius 0.4, height 1.8, max climb 0.3, cell size 0.2 (the radius is exactly two
## cells). Door leaves are left out: errors open doors. LevelBuilder bakes it threaded.


static func mesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = Tuning.NAV_CELL_SIZE
	nm.cell_height = Tuning.NAV_CELL_HEIGHT
	nm.agent_radius = Tuning.NAV_AGENT_RADIUS
	nm.agent_height = Tuning.NAV_AGENT_HEIGHT
	nm.agent_max_climb = Tuning.NAV_MAX_CLIMB
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return nm


static func source(nm: NavigationMesh, plan: BuildPlan, furniture: Node3D, doors: Node3D) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, furniture)
	src.add_faces(plan.nav_faces, Transform3D.IDENTITY)
	for d in doors.get_children():
		if d is Door:
			_add_jamb_faces(src, d as Door)
	return src


## The jambs' box shapes as navigation obstacles (their faces, in world space), each moved
## back NAV_DOOR_JAMB_INSET from the opening. Rasterised at 0.2 m and eroded by the 0.4 m
## agent radius (two cells a side), the exact 1.0 m opening closed: no path crossed a
## doorway and errors stopped dead at every door. Inset, the bake keeps one lane through
## the middle; the bodies still collide with the real jambs.
static func _add_jamb_faces(src: NavigationMeshSourceGeometryData3D, door: Door) -> void:
	for child in door.jambs.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var box := BoxMesh.new()
		var size := (cs.shape as BoxShape3D).size
		box.size = Vector3(maxf(size.x - Tuning.NAV_DOOR_JAMB_INSET, 0.01), size.y, size.z)
		# The jambs sit at ±x in the door's frame; the opening is toward x = 0.
		var away := signf(cs.position.x) * Tuning.NAV_DOOR_JAMB_INSET * 0.5
		var xf := cs.global_transform * Transform3D(Basis.IDENTITY, Vector3(away, 0.0, 0.0))
		src.add_faces(box.get_faces(), xf)
