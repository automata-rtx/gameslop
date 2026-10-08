class_name NoclipFixture
extends RefCounted
## Synthetic noclip walls for the M1.4 suites: StaticBody3D boxes on the world layer that
## carry the level builder's metadata (07 Interfaces: body meta `wall_kind`, a `shape_meta`
## table per shape owner read through LevelBuilder.shape_info).

const EYE := Vector3(0.0, Tuning.PLAYER_CAMERA_HEIGHT, 0.0)
const FORWARD := Vector3(0.0, 0.0, -1.0)
## The standard test wall: 4 m wide, 2.7 m high, 0.2 m thick, its near face 0.9 m ahead.
const WALL_Z := -1.0
const WALL_SIZE := Vector3(4.0, 2.7, 0.2)


## A builder-style wall body: one shape owner with 07 §7 metadata. The player stands at
## cell (0, 0) (z > the wall) and the wall is that cell's N edge; `far_walkable` is the
## cell beyond it.
static func wall(parent: Node, kind: StringName, pos: Vector3 = Vector3(0, WALL_SIZE.y * 0.5, WALL_Z),
		size: Vector3 = WALL_SIZE, far_walkable: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PlayerLayers.WORLD_MASK
	body.collision_mask = 0
	body.set_meta(&"wall_kind", kind)
	var s := BoxShape3D.new()
	s.size = size
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, s)
	body.set_meta(&"shape_meta", {owner_id: {
		&"cell": Vector2i(0, 0), &"dir": LevelGrid.N, &"wall_type": Tuning.GRID_WALL_TYPES.find(kind),
		&"wall_kind": kind, &"thickness": size.z, &"other_cell": Vector2i(0, -1),
		&"walkable": true, &"other_walkable": far_walkable}})
	parent.add_child(body)
	body.global_position = pos
	return body


## A floor slab marked like the builder's floors (meta `floor`, per-shape cell kind).
static func floor_slab(parent: Node, size: Vector3, pos: Vector3, cell_kind: int = LevelGrid.FLOOR) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PlayerLayers.WORLD_MASK
	body.collision_mask = 0
	body.set_meta(&"floor", true)
	body.set_meta(&"surface", &"carpet")
	var s := BoxShape3D.new()
	s.size = size
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, s)
	body.set_meta(&"shape_meta", {owner_id: {&"cell": Vector2i(0, 0), &"kind": cell_kind}})
	parent.add_child(body)
	body.global_position = pos
	return body


## A world root with a 40 x 40 m builder-style floor at y = 0.
static func world(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "NoclipWorld"
	parent.add_child(root)
	floor_slab(root, Vector3(40, 0.2, 40), Vector3(0, -0.1, 0))
	return root


static func capsule() -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = Tuning.PLAYER_CAPSULE_RADIUS
	c.height = Tuning.PLAYER_CAPSULE_HEIGHT
	return c


## NoclipQuery.evaluate from the standard eye at the origin.
static func aim(root: Node3D, dir: Vector3 = FORWARD, coherence: float = 100.0, floor_solid: bool = false,
		eye: Vector3 = EYE) -> Dictionary:
	return NoclipQuery.evaluate(root.get_world_3d().direct_space_state, eye, dir,
			Vector3(eye.x, 0.0, eye.z), capsule(), coherence, floor_solid)
