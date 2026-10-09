class_name LandingStairwell
extends RefCounted
## The stairwell Landing (05 §4: "stairwell landing for Pools, Server"). The same shell as the
## elevator cabin, so the door, the item panel, the player's spot and the camera framing do not
## move, drawn as a concrete stair landing: the floor is a landing block with a half-flight
## going down along the right wall (four steps into the dark), a sloped handrail on its edge
## and one wall-mounted fixture on the left wall. Surfaces are the stratum's own materials and
## the fixture is the stratum's own (Pools' white panel lamp, Server's red emergency box).
## Primitives only (02 T8). `Landing.apply_theme` calls `build`; nothing here ticks.

const MAT_ROOT := "res://data/materials/%s/%s.tres"
## stratum -> material file per role (names under data/materials/<stratum>/).
const SETS := {
	&"pools": {&"wall": &"tile_wall", &"floor": &"tile_floor", &"ceiling": &"tile_ceiling",
			&"rail": &"prop_chrome", &"door": &"door_metal",
			&"housing": &"fixture_housing", &"emissive": &"fixture_emissive"},
	&"server": {&"wall": &"wall", &"floor": &"floor_tile", &"ceiling": &"ceiling",
			&"rail": &"prop_metal", &"door": &"door_leaf",
			&"housing": &"emergency_housing", &"emissive": &"emergency_emissive"},
}
## Landing-local metres (the shell is 2 x 2.4 x 2, floor y = 0, the door in the -z wall).
const BLOCK_DEPTH := 1.5
const STAIR_X := 0.4                 # the half-flight fills x 0.4 .. 1.0 along the right wall
const STAIR_Z0 := -0.1               # its first step starts here and runs to the back wall
const STAIR_Z1 := 1.0
const STAIR_STEPS := 4
const STAIR_RISE := 0.2
const RAIL_HEIGHT := 0.95
const RAIL_RADIUS := 0.02
const POST_RADIUS := 0.016
const FIXTURE_POS := Vector3(-0.94, 2.0, -0.65)   # on the left wall, in the player's view
const FIXTURE_LIGHT_OUT := 0.3       # m the light stands off the wall
## Render constants (not design numbers): the stratum's fixture light is tuned for long rooms
## under a 6 m ceiling, the closet takes a different amount of it.
const LIGHT_SCALE := {&"pools": 0.9, &"server": 10.0}


static func is_stairwell(stratum: StringName) -> bool:
	return SETS.has(stratum)


static func material(stratum: StringName, role: StringName) -> Material:
	return load(MAT_ROOT % [stratum, SETS[stratum][role]]) as Material


## Builds the landing block, the half-flight, the handrail and the wall fixture under `geometry`
## and returns the fixture's light. The shell's own surfaces are restyled by the caller.
static func build(geometry: Node3D, stratum: StringName) -> OmniLight3D:
	var floor_mat := material(stratum, &"floor")
	# The landing block (the old floor slab is gone) and the front strip beside the door wall.
	_box(geometry, &"StairLanding", Vector3(1.4, BLOCK_DEPTH, 2.0), Vector3(-0.3, -BLOCK_DEPTH * 0.5, 0.0), floor_mat, true)
	_box(geometry, &"StairFront", Vector3(1.0 - STAIR_X, BLOCK_DEPTH, STAIR_Z0 + 1.0),
			Vector3((1.0 + STAIR_X) * 0.5, -BLOCK_DEPTH * 0.5, (STAIR_Z0 - 1.0) * 0.5), floor_mat, true)
	var run := (STAIR_Z1 - STAIR_Z0) / STAIR_STEPS
	for i in STAIR_STEPS:
		var top := -STAIR_RISE * (i + 1)
		_box(geometry, StringName("Step%d" % i), Vector3(1.0 - STAIR_X, BLOCK_DEPTH + top, run),
				Vector3((1.0 + STAIR_X) * 0.5, (top - BLOCK_DEPTH) * 0.5, STAIR_Z0 + run * (i + 0.5)), floor_mat, true)
	_build_rail(geometry, material(stratum, &"rail"))
	return _build_fixture(geometry, stratum)


## A sloped rail down the flight on three posts, and an invisible guard that keeps the player
## on the landing.
static func _build_rail(geometry: Node3D, mat: Material) -> void:
	var drop := STAIR_RISE * STAIR_STEPS
	var span := STAIR_Z1 - STAIR_Z0
	var rail := Node3D.new()
	rail.name = "StairRail"
	geometry.add_child(rail)
	var cyl := CylinderMesh.new()
	cyl.top_radius = RAIL_RADIUS
	cyl.bottom_radius = RAIL_RADIUS
	cyl.height = Vector2(span, drop).length()
	cyl.radial_segments = 8
	cyl.rings = 1
	var bar := _part(rail, cyl, Vector3(STAIR_X, RAIL_HEIGHT - drop * 0.5, STAIR_Z0 + span * 0.5), mat)
	# A cylinder runs along local Y; lay it along z and tip it down the slope.
	bar.rotation = Vector3(PI * 0.5 + atan2(drop, span), 0.0, 0.0)
	var run := span / STAIR_STEPS
	# (z, the surface the post stands on): the landing's edge, then the middle of steps 1 and 3.
	for post_at: Array in [[STAIR_Z0, 0.0], [STAIR_Z0 + run * 1.5, -STAIR_RISE * 2.0], [STAIR_Z0 + run * 3.5, -STAIR_RISE * 4.0]]:
		var z: float = post_at[0]
		var base: float = post_at[1]
		var y_top := RAIL_HEIGHT - drop * (z - STAIR_Z0) / span
		var post := CylinderMesh.new()
		post.top_radius = POST_RADIUS
		post.bottom_radius = POST_RADIUS
		post.height = y_top - base
		post.radial_segments = 6
		post.rings = 1
		_part(rail, post, Vector3(STAIR_X, base + post.height * 0.5, z), mat)
	var guard := StaticBody3D.new()
	guard.name = "StairGuard"
	guard.collision_layer = PlayerLayers.WORLD_MASK
	guard.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.05, 1.2, span)
	cs.shape = shape
	guard.add_child(cs)
	guard.position = Vector3(STAIR_X, 0.6, STAIR_Z0 + span * 0.5)
	rail.add_child(guard)


## The wall-mounted fixture and its light: a housing on the left wall, an emissive face toward
## the room, and the stratum's fixture light (colour, energy, range from its StratumData).
static func _build_fixture(geometry: Node3D, stratum: StringName) -> OmniLight3D:
	var data := load("res://data/strata/%s.tres" % stratum) as StratumData
	var rig := Node3D.new()
	rig.name = "StairFixture"
	rig.position = FIXTURE_POS
	geometry.add_child(rig)
	_part(rig, _box_mesh(Vector3(0.12, 0.18, 0.4)), Vector3.ZERO, material(stratum, &"housing"))
	_part(rig, _box_mesh(Vector3(0.012, 0.12, 0.32)), Vector3(0.062, 0.0, 0.0), material(stratum, &"emissive"))
	var light := OmniLight3D.new()
	light.name = "StairLight"
	light.light_color = data.fixture_light_color
	light.light_energy = data.fixture_light_energy * float(LIGHT_SCALE[stratum])
	light.omni_range = minf(data.fixture_light_range, 6.0)
	light.shadow_enabled = false
	light.position = Vector3(FIXTURE_LIGHT_OUT, -0.05, 0.0)
	rig.add_child(light)
	return light


static func _box_mesh(sz: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = sz
	return bm


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(geometry: Node3D, node_name: StringName, sz: Vector3, pos: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _box_mesh(sz)
	mi.material_override = mat
	mi.position = pos
	geometry.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.name = "%sBody" % node_name
		body.collision_layer = PlayerLayers.WORLD_MASK
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		geometry.add_child(body)
	return mi
