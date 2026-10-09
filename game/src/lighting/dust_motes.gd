class_name DustMotes
extends GPUParticles3D
## 02 §10: dust motes in Halls, Garage and Offices. One box emitter (12 m) that follows
## the player; 200 particles, 1 mm quads, slow drift, alpha 0.12, lit (so the flashlight
## picks them out). Particles live in world space, so moving the box never drags them.
## The Substrate's 1 px white pixels drifting upward (02 §10, M3.2) are the same follow-box
## emitter with a screen-pixel draw pass: `create_pixels`.

## The node the box follows (the player or camera). Null: the emitter stays put.
var follow: Node3D

const LIFETIME_S := 14.0
const DRIFT_SPEED_MIN := 0.01      # m/s
const DRIFT_SPEED_MAX := 0.04
const SINK := 0.004                # m/s^2, barely settling
const PIXEL_SHADER := "res://shaders/pixel_particles.gdshader"


## `particle_scale` is the preset's particle count factor (02 §12: Low 50%).
static func create(particle_scale: float = 1.0) -> DustMotes:
	var d := DustMotes.new()
	d.name = "DustMotes"
	d.amount = maxi(1, roundi(Tuning.DUST_PARTICLES * particle_scale))
	d.lifetime = LIFETIME_S
	d.preprocess = LIFETIME_S
	d.local_coords = false
	d.randomness = 1.0
	var half := Tuning.DUST_BOX_SIZE * 0.5
	d.visibility_aabb = AABB(Vector3.ONE * -(half + 1.0), Vector3.ONE * (Tuning.DUST_BOX_SIZE + 2.0))
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.process_material = _process_material(half)
	d.draw_pass_1 = _quad()
	return d


## 02 §10 Substrate: 1 px white "pixels" drifting upward in the same 12 m follow box,
## unshaded (pixel_particles.gdshader), fading in and out over their lifetime.
static func create_pixels(particle_scale: float = 1.0) -> DustMotes:
	var d := DustMotes.new()
	d.name = "SubstratePixels"
	d.amount = maxi(1, roundi(Tuning.SUBSTRATE_PIXEL_PARTICLES * particle_scale))
	var half := Tuning.DUST_BOX_SIZE * 0.5
	d.lifetime = Tuning.DUST_BOX_SIZE / (Tuning.SUBSTRATE_PIXEL_RISE_MIN + Tuning.SUBSTRATE_PIXEL_RISE_MAX)
	d.preprocess = d.lifetime
	d.local_coords = false
	d.randomness = 1.0
	d.visibility_aabb = AABB(Vector3.ONE * -(half + 2.0), Vector3.ONE * (Tuning.DUST_BOX_SIZE + 4.0))
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _process_material(half)
	m.spread = 8.0
	m.initial_velocity_min = Tuning.SUBSTRATE_PIXEL_RISE_MIN
	m.initial_velocity_max = Tuning.SUBSTRATE_PIXEL_RISE_MAX
	m.gravity = Vector3.ZERO
	d.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load(PIXEL_SHADER) as Shader
	mat.set_shader_parameter(&"pixel_px", Tuning.SUBSTRATE_PIXEL_PX)
	mat.set_shader_parameter(&"pixel_color", Color(0.902, 0.902, 0.902, Tuning.SUBSTRATE_PIXEL_ALPHA))
	q.material = mat
	d.draw_pass_1 = q
	return d


func _process(_delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		global_position = follow.global_position


static func _process_material(half: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3.ONE * half
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = DRIFT_SPEED_MIN
	m.initial_velocity_max = DRIFT_SPEED_MAX
	m.gravity = Vector3(0.0, -SINK, 0.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	return m


static func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * Tuning.DUST_QUAD_SIZE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, Tuning.DUST_ALPHA)
	mat.roughness = 1.0
	q.material = mat
	return q
