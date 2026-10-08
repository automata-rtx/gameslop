class_name ItemModels
extends RefCounted
## Held and world models of the items, built from primitives only (09 §3, 02 T8).
## Every model is a Node3D whose origin is the model's centre. Every part uses the world
## shader (02 §5) so jitter, unrender and the grade reach items like the level: held models
## carry `held = 1` (no jitter, never unrendered), world models `held = 0`. Exceptions: the
## Polaroid held up (an unshaded overlay with the painted photo, PolaroidItem) and chalk
## decals (a Decal, which unrender must not touch, 09 §9).

const WHITE := Color("F2F2F2")
const GLOW := Color("7CFF4A")
const DARK := Color(0.08, 0.08, 0.09)

const POLAROID_W := 0.09
const POLAROID_H := 0.11
const POLAROID_PHOTO := 0.07
const GLOWSTICK_LEN := 0.15
const CHALK_LEN := 0.06
const FLARE_LEN := 0.25
const RADIO_W := 0.12
const RADIO_H := 0.08
const RADIO_D := 0.035
const RADIO_ANTENNA := 0.1
const FUSE_LEN := 0.05
const CARD_W := 0.085
const CARD_H := 0.054
const FLARE_RED := Color(0.32, 0.05, 0.04)
const BRASS := Color(0.71, 0.55, 0.22)
const FUSE_GREY := Color(0.5, 0.5, 0.52)
const LED_RED := Color("FF3B3B")
const CARD_AMBER := Color("FFB000")
## Glowstick tube emission at full life.
const GLOW_EMISSION := 2.5
const WORLD_SHADER := preload("res://shaders/world_surface.gdshader")


static func held(kind: StringName) -> Node3D:
	var m := _build(kind)
	set_held(m, true)
	return m


static func _build(kind: StringName) -> Node3D:
	match kind:
		&"polaroid":
			return _polaroid()
		&"glowstick":
			return _glowstick()
		&"chalk":
			return _chalk()
		&"flare":
			return _flare()
		&"radio":
			return _radio()
		&"fuse":
			return _fuse()
		&"keycard":
			return _keycard()
	var n := Node3D.new()
	n.name = "Held_%s" % kind
	return n


## The model on the floor: the held model, tilted for display.
static func world(kind: StringName) -> Node3D:
	var m := _build(kind)
	set_held(m, false)
	match kind:
		&"polaroid":
			m.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(20.0), 0.0)
		&"glowstick":
			m.rotation = Vector3(0.0, deg_to_rad(35.0), deg_to_rad(90.0))
		&"chalk":
			m.rotation = Vector3(0.0, 0.0, deg_to_rad(80.0))
		&"flare":
			m.rotation = Vector3(0.0, deg_to_rad(25.0), deg_to_rad(90.0))
		&"radio":
			m.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(15.0), 0.0)
		&"fuse":
			m.rotation = Vector3(0.0, deg_to_rad(-30.0), deg_to_rad(90.0))
		&"keycard":
			m.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(20.0), 0.0)
	# Wrap so the pickup can spin or bob the wrapper without fighting the tilt.
	var holder := Node3D.new()
	holder.name = "World_%s" % kind
	holder.add_child(m)
	return holder


## A world-shader material (02 §5): flat albedo, no noise, optional emission of its colour.
static func material(color: Color, rough: float = 0.8, emission: float = 0.0, is_held: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	m.set_shader_parameter(&"albedo", color)
	m.set_shader_parameter(&"roughness", rough)
	m.set_shader_parameter(&"noise_albedo_amount", 0.0)
	m.set_shader_parameter(&"held", 1.0 if is_held else 0.0)
	if emission > 0.0:
		m.set_shader_parameter(&"emission", color)
		m.set_shader_parameter(&"emission_strength", emission)
	return m


static func _mat(color: Color, rough: float = 0.8, emission: float = 0.0) -> ShaderMaterial:
	return material(color, rough, emission)


## Sets the world shader's `held` on every part of `model` (each model owns its materials).
static func set_held(model: Node, on: bool) -> void:
	var parts: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		parts.append(model)
	for n in parts:
		var sm := (n as MeshInstance3D).material_override as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter(&"held", 1.0 if on else 0.0)


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
static func glow_material(life: float) -> ShaderMaterial:
	var m := _mat(GLOW.darkened(0.25), 0.4)
	m.set_shader_parameter(&"emission", GLOW)
	m.set_shader_parameter(&"emission_strength", GLOW_EMISSION * life)
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


## A 0.25 m dark red cylinder with a pale striker cap (09 §3). The flame and the light belong
## to the Flare node, not the model.
static func _flare() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_flare"
	var c := CylinderMesh.new()
	c.top_radius = 0.014
	c.bottom_radius = 0.014
	c.height = FLARE_LEN
	c.radial_segments = 12
	c.rings = 1
	_mesh(root, c, _mat(FLARE_RED, 0.9), Vector3.ZERO, Vector3.ZERO, "Body")
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0155
	cap.bottom_radius = 0.0155
	cap.height = 0.03
	cap.radial_segments = 12
	cap.rings = 1
	_mesh(root, cap, _mat(Color(0.75, 0.72, 0.66), 0.7), Vector3(0.0, FLARE_LEN * 0.5 - 0.01, 0.0), Vector3.ZERO, "Cap")
	var band := CylinderMesh.new()
	band.top_radius = 0.0145
	band.bottom_radius = 0.0145
	band.height = 0.02
	band.radial_segments = 12
	band.rings = 1
	_mesh(root, band, _mat(WHITE, 0.8), Vector3(0.0, -0.04, 0.0), Vector3.ZERO, "Band")
	root.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(8.0), deg_to_rad(-10.0))
	return root


## The tip of a flare model in its own space (where the flame stands).
static func flare_tip() -> Vector3:
	return Vector3(0.0, FLARE_LEN * 0.5 + 0.005, 0.0)


## A 0.12 m box with a 0.1 m antenna and a red LED (09 §3). `Led` glows when the radio is on.
## The radio's parts sit this far from the model origin, so the 0.12 m box rests inside the
## frame at the held position (lower right, 0.38 m from the eye) instead of off its edge.
const HOLD := Vector3(-0.055, 0.04, 0.0)


static func _radio() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_radio"
	var box := BoxMesh.new()
	box.size = Vector3(RADIO_W, RADIO_H, RADIO_D)
	_mesh(root, box, _mat(Color(0.3, 0.32, 0.28), 0.7), HOLD, Vector3.ZERO, "Box")
	var grille := BoxMesh.new()
	grille.size = Vector3(0.05, 0.05, 0.004)
	_mesh(root, grille, _mat(DARK, 0.95), HOLD + Vector3(-0.026, -0.004, RADIO_D * 0.5 + 0.001), Vector3.ZERO, "Grille")
	var dial := BoxMesh.new()
	dial.size = Vector3(0.026, 0.012, 0.004)
	_mesh(root, dial, _mat(Color(0.62, 0.6, 0.5), 0.6), HOLD + Vector3(0.03, 0.012, RADIO_D * 0.5 + 0.001), Vector3.ZERO, "Dial")
	var led := BoxMesh.new()
	led.size = Vector3(0.008, 0.008, 0.004)
	_mesh(root, led, _mat(LED_RED.darkened(0.7), 0.5), HOLD + Vector3(0.045, -0.025, RADIO_D * 0.5 + 0.001), Vector3.ZERO, "Led")
	var ant := CylinderMesh.new()
	ant.top_radius = 0.0016
	ant.bottom_radius = 0.0022
	ant.height = RADIO_ANTENNA
	ant.radial_segments = 6
	ant.rings = 1
	_mesh(root, ant, _mat(Color(0.7, 0.7, 0.72), 0.4), HOLD + Vector3(-0.045, RADIO_H * 0.5 + RADIO_ANTENNA * 0.5 - 0.004, 0.0), Vector3(0.0, 0.0, deg_to_rad(-12.0)), "Antenna")
	root.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(-24.0), deg_to_rad(4.0))
	return root


## Lights or darkens the radio model's LED.
static func set_radio_led(model: Node, on: bool) -> void:
	var led := model.get_node_or_null("Led") as MeshInstance3D
	if led == null:
		return
	var m := (led.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"albedo", LED_RED if on else LED_RED.darkened(0.7))
	m.set_shader_parameter(&"emission", LED_RED)
	m.set_shader_parameter(&"emission_strength", 3.0 if on else 0.0)
	led.material_override = m


## A 0.05 m grey cylinder with brass caps (09 §3).
static func _fuse() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_fuse"
	var c := CylinderMesh.new()
	c.top_radius = 0.009
	c.bottom_radius = 0.009
	c.height = FUSE_LEN
	c.radial_segments = 12
	c.rings = 1
	_mesh(root, c, _mat(FUSE_GREY, 0.5), Vector3.ZERO, Vector3.ZERO, "Body")
	for sign_y: float in [-1.0, 1.0]:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0098
		cap.bottom_radius = 0.0098
		cap.height = 0.012
		cap.radial_segments = 12
		cap.rings = 1
		_mesh(root, cap, _mat(BRASS, 0.35), Vector3(0.0, sign_y * (FUSE_LEN * 0.5 - 0.002), 0.0), Vector3.ZERO, "Cap_up" if sign_y > 0.0 else "Cap_down")
	root.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(10.0), deg_to_rad(-20.0))
	return root


## The keycard: a flat amber card with a dark stripe (not a belt item; carried, shown as a
## glyph beside the depth label). The model is the pickup and the card in the reader's hand.
static func _keycard() -> Node3D:
	var root := Node3D.new()
	root.name = "Held_keycard"
	var card := BoxMesh.new()
	card.size = Vector3(CARD_W, CARD_H, 0.002)
	_mesh(root, card, _mat(CARD_AMBER, 0.6, 0.35), Vector3.ZERO, Vector3.ZERO, "Card")
	var stripe := BoxMesh.new()
	stripe.size = Vector3(CARD_W, 0.011, 0.0005)
	_mesh(root, stripe, _mat(DARK, 0.8), Vector3(0.0, 0.012, 0.0012), Vector3.ZERO, "Stripe")
	root.rotation = Vector3(deg_to_rad(10.0), deg_to_rad(-20.0), deg_to_rad(6.0))
	return root
