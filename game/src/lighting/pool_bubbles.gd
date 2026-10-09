class_name PoolBubbles
extends GPUParticles3D
## 02 §10 Pools: rising bubbles near water. Each wet basin (a WaterVolume) has a few thin
## streams: one emitter per stream, a small source on the basin floor at a point hashed from
## the basin, bubbles rising straight to just under the surface, where they end (their
## lifetime is the water's depth over the rise speed). A stream reads where scattered single
## bubbles vanish (one regular source is the 10% wrong, pillar 5). Unshaded rims
## (bubble_particles.gdshader) drawn after the water surface and tinted by their depth under
## it. Counts scale by the preset's particle factor (02 §12: Low 50%).

const SHADER := "res://shaders/bubble_particles.gdshader"
## Off the floor and under the surface (m), so no bubble starts in the tile or pokes out.
const FLOOR_LIFT := 0.04
const SURFACE_MARGIN := 0.03
const WOBBLE_SPREAD_DEG := 3.0
## Sources stay this far inside the basin's walls (m).
const WALL_MARGIN := 0.4

static var _draw_pass: QuadMesh


## The streams for a basin of `size` (m, x by z, centred on the parent) holding water `depth`
## m deep over a floor at `floor_y` (world height; the parent stands at y 0). `key` seeds the
## source points (the basin's rect), so a level always bubbles in the same places. Empty
## when the basin is dry.
static func streams(size: Vector2, floor_y: float, depth: float, key: int, particle_scale: float = 1.0) -> Array[PoolBubbles]:
	var out: Array[PoolBubbles] = []
	var rise := depth - FLOOR_LIFT - SURFACE_MARGIN
	if rise <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return out
	var count := stream_count(size)
	var rng := Seeds.rng(Seeds.derive(key, Tuning.SEED_LABEL_BUBBLES))
	var half := (size * 0.5 - Vector2.ONE * WALL_MARGIN).max(Vector2.ZERO)
	for i in count:
		var at := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var b := create(Vector3(at.x, floor_y + FLOOR_LIFT, at.y), rise, particle_scale)
		if b != null:
			b.name = "Bubbles%d" % i
			b.set_instance_shader_parameter(&"surface_y", floor_y + depth)
			out.append(b)
	return out


## Streams in a basin of `size`: one per POOLS_BUBBLE_STREAM_AREA m², 1 to the max.
static func stream_count(size: Vector2) -> int:
	return clampi(roundi(size.x * size.y / Tuning.POOLS_BUBBLE_STREAM_AREA), 1, Tuning.POOLS_BUBBLE_STREAMS_MAX)


## One stream rising `rise` m from `at` (the parent's space). Null when it would hold none.
static func create(at: Vector3, rise: float, particle_scale: float = 1.0) -> PoolBubbles:
	var n := roundi(Tuning.POOLS_BUBBLES_PER_STREAM * particle_scale)
	if n < 1 or rise <= 0.0:
		return null
	var b := PoolBubbles.new()
	b.amount = n
	b.lifetime = rise / Tuning.POOLS_BUBBLE_RISE
	b.preprocess = b.lifetime
	b.randomness = 0.5
	b.local_coords = false
	b.position = at
	var r := Tuning.POOLS_BUBBLE_SOURCE_RADIUS + rise * tan(deg_to_rad(WOBBLE_SPREAD_DEG)) + 0.1
	b.visibility_aabb = AABB(Vector3(-r, -0.1, -r), Vector3(r * 2.0, rise + 0.2, r * 2.0))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = Tuning.POOLS_BUBBLE_SOURCE_RADIUS
	m.direction = Vector3.UP
	m.spread = WOBBLE_SPREAD_DEG
	m.initial_velocity_min = Tuning.POOLS_BUBBLE_RISE
	m.initial_velocity_max = Tuning.POOLS_BUBBLE_RISE
	m.gravity = Vector3.ZERO
	m.scale_min = Tuning.POOLS_BUBBLE_SIZE_MIN
	m.scale_max = Tuning.POOLS_BUBBLE_SIZE_MAX
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 1))
	fade.add_point(0.1, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	b.process_material = m
	b.draw_pass_1 = draw_pass()
	return b


## The unit quad every stream shares (scaled per particle by scale_min..scale_max).
static func draw_pass() -> QuadMesh:
	if _draw_pass == null:
		_draw_pass = QuadMesh.new()
		_draw_pass.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER) as Shader
		# After the water surface's transparent pass (default priority 0): the surface
		# refracts only the opaque image, so bubbles drawn before it would vanish.
		mat.render_priority = 1
		_draw_pass.material = mat
	return _draw_pass
