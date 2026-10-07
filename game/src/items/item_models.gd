class_name ItemModels
extends RefCounted
## Held and world models of the items, built from primitives only (09 §3, 02 T8).
## Every model is a Node3D whose origin is the model's centre. Held models are lit by the
## scene (the flashlight lights them), except emissive parts and the Polaroid photo.

const WHITE := Color("F2F2F2")
const GLOW := Color("7CFF4A")
const DARK := Color(0.08, 0.08, 0.09)

const POLAROID_W := 0.09
const POLAROID_H := 0.11
const POLAROID_PHOTO := 0.07
const GLOWSTICK_LEN := 0.15
const CHALK_LEN := 0.06


static func held(kind: StringName) -> Node3D:
	match kind:
		&"polaroid":
			return _polaroid()
		&"glowstick":
			return _glowstick()
		&"chalk":
			return _chalk()
	var n := Node3D.new()
	n.name = "Held_%s" % kind
	return n


## The model on the floor: the held model, tilted for display.
static func world(kind: StringName) -> Node3D:
	var m := held(kind)
	match kind:
		&"polaroid":
			m.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(20.0), 0.0)
		&"glowstick":
			m.rotation = Vector3(0.0, deg_to_rad(35.0), deg_to_rad(90.0))
		&"chalk":
			m.rotation = Vector3(0.0, 0.0, deg_to_rad(80.0))
	# Wrap so the pickup can spin or bob the wrapper without fighting the tilt.
	var holder := Node3D.new()
	holder.name = "World_%s" % kind
	holder.add_child(m)
	return holder


static func _mat(color: Color, rough: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not node_name.is_empty():
		mi.name = node_name
	parent.add_child(mi)
	return mi


## 0.09 x 0.11 m white quad with a black inner quad (09 §3). `Photo` is the inner quad: black
## while held, and PolaroidItem swaps in the painted image (unshaded) when it is held up.
static func _polaroid() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_polaroid"
	var card := BoxMesh.new()
	card.size = Vector3(POLAROID_W, POLAROID_H, 0.003)
	_mesh(root, card, _mat(WHITE, 0.7), Vector3.ZERO, Vector3.ZERO, "Card")
	var photo := QuadMesh.new()
	photo.size = Vector2(POLAROID_PHOTO, POLAROID_PHOTO)
	var pm := _mat(Color.BLACK, 0.9)
	_mesh(root, photo, pm, Vector3(0.0, 0.009, 0.0018), Vector3.ZERO, "Photo")
	root.rotation = Vector3(deg_to_rad(8.0), deg_to_rad(-14.0), deg_to_rad(4.0))
	return root


## A 0.15 m green emissive cylinder with a dark cap (09 §3).
static func _glowstick() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_glowstick"
	var body := CylinderMesh.new()
	body.top_radius = 0.012
	body.bottom_radius = 0.012
	body.height = GLOWSTICK_LEN
	body.radial_segments = 12
	body.rings = 1
	_mesh(root, body, glow_material(1.0), Vector3.ZERO, Vector3.ZERO, "Tube")
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0135
	cap.bottom_radius = 0.0135
	cap.height = 0.018
	cap.radial_segments = 12
	cap.rings = 1
	_mesh(root, cap, _mat(DARK, 0.6), Vector3(0.0, GLOWSTICK_LEN * 0.5 + 0.005, 0.0), Vector3.ZERO, "Cap")
	root.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(10.0), deg_to_rad(-12.0))
	return root


## The emissive tube material (energy 2.5 at full life).
static func glow_material(life: float) -> StandardMaterial3D:
	var m := _mat(GLOW, 0.4, 2.5 * life)
	m.albedo_color = GLOW.darkened(0.25)
	return m


## A 0.06 m white tapered cylinder (09 §3).
static func _chalk() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_chalk"
	var c := CylinderMesh.new()
	c.top_radius = 0.0085
	c.bottom_radius = 0.0115
	c.height = CHALK_LEN
	c.radial_segments = 10
	c.rings = 1
	_mesh(root, c, _mat(WHITE, 1.0), Vector3.ZERO, Vector3.ZERO, "Stick")
	root.rotation = Vector3(deg_to_rad(-70.0), 0.0, deg_to_rad(-10.0))
	return root
