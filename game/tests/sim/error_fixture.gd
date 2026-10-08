class_name ErrorFixture
extends RefCounted
## Test helpers for the error suites: a 60 x 60 m floor with a baked navigation mesh, the
## player, and errors spawned by id (as the Director will).

const FLOOR_SIZE := 60.0


## Floor on the world layer plus a NavigationRegion3D baked from it (synchronously).
static func make_world(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "ErrorWorld"
	parent.add_child(root)
	PlayerFixture.box(root, Vector3(FLOOR_SIZE, 0.2, FLOOR_SIZE), Vector3(0, -0.1, 0))
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	root.add_child(region)
	var nm := NavigationMesh.new()
	nm.cell_size = Tuning.NAV_CELL_SIZE
	nm.cell_height = Tuning.NAV_CELL_HEIGHT
	nm.agent_radius = Tuning.NAV_AGENT_RADIUS
	nm.agent_height = Tuning.NAV_AGENT_HEIGHT
	nm.agent_max_climb = Tuning.NAV_MAX_CLIMB
	var src := NavigationMeshSourceGeometryData3D.new()
	var h := FLOOR_SIZE * 0.5
	src.add_faces(PackedVector3Array([
		Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h),
		Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h),
	]), Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var map := region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, Tuning.NAV_CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, Tuning.NAV_CELL_HEIGHT)
	region.navigation_mesh = nm
	# The server applies a new region on its own sync; until then map queries return the
	# zero vector (a Satiated retreat snapped every candidate to the origin and stood still:
	# the flaky test_satiated_retreats_away). Force the sync so the map is ready now.
	NavigationServer3D.map_force_update(map)
	return root


## An error of `id` at `pos`, set up for `player` with navigation ready, still Dormant.
static func spawn(world: Node3D, id: StringName, pos: Vector3, player: Player, seed_value: int = 7) -> ErrorBase:
	var e := ErrorBase.create(id)
	e.setup(player, null, seed_value)
	world.add_child(e)
	if e is ErrorStill:
		(e as ErrorStill).place_at(pos)
	else:
		e.global_position = pos
	e.set_navigation_ready(true)
	return e


## Horizontal distance.
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
