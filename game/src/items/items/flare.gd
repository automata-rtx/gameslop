class_name Flare
extends RigidBody3D
## A burning flare (09 §2): carried in the hand (FlareItem) or thrown and lying in the world.
## An OmniLight3D `#FF4A2E`, energy 2.2, range 8 m, shadows at the High setting, with a 1 Hz
## flutter; a 60-particle additive flame; a continuous `light` noise of 14 m once per second.
## It burns 40 s. It is fire, not a fixture: the light joins `chemical_light` (counts for
## observing Still out to its 8 m range, Flicker cannot use it, 08 §4) and the node joins
## `flares_burning` (Static is pushed 6 m away, 08 §3, Tuning.STATIC_FLARE_GROUP).
## Thrown: layer 8 (`thrown`), collides with the world only, bounces once, settles; the
## landing is a 6 m `impact` noise (the Echo lure). Carried: frozen, no collision, the owner
## places it each frame (`tip` Callable) and the thrown-only landing noise never fires.
## Public so tests step time: tick(dt). Signals: burnt_out.

signal burnt_out

const GROUP_LIGHT := Glowstick.GROUP_LIGHT
const GROUP_BURNING := Tuning.STATIC_FLARE_GROUP
const LAYER_THROWN := Glowstick.LAYER_THROWN
const SOUND_LAND := &"flare_land"
const SOUND_BURN := &"flare_burn"
const SOUND_IGNITE := &"flare_ignite"
const COLOR := Color("FF4A2E")
const VIEW_CHECK_S := Tuning.LIGHT_POOL_REEVAL_INTERVAL
const LIT_MIN_ENERGY := Glowstick.LIT_MIN_ENERGY
## The flame's size share while the flare is in the hand (0.4 m from the eye).
const HELD_FLAME_SIZE := 0.3

## Seconds of burn left.
var remaining: float = Tuning.FLARE_BURN_TIME
var age: float = 0.0
var landed: bool = false
var carried: bool = false
var light: OmniLight3D
var flame: GPUParticles3D
## Carried: returns where the flare's tip is (global). Set by the owner.
var tip: Callable

var _bounce_mat: PhysicsMaterial
var _burn_loop: AudioLoop
var _noise_left: float = 0.0
var _view_left: float = 0.0
var _model: Node3D
var _shape: CollisionShape3D


func _init() -> void:
	name = "Flare"
	collision_layer = 1 << (LAYER_THROWN - 1)
	collision_mask = PlayerLayers.WORLD_MASK
	mass = 0.12
	linear_damp = 0.25
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_bounce_mat = PhysicsMaterial.new()
	_bounce_mat.bounce = Tuning.GLOWSTICK_BOUNCE
	_bounce_mat.friction = 0.8
	physics_material_override = _bounce_mat
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.016
	cap.height = ItemModels.FLARE_LEN
	_shape.shape = cap
	add_child(_shape)
	_model = ItemModels.held(&"flare")
	_model.rotation = Vector3.ZERO
	_model.name = "Model"
	ItemModels.set_held(_model, false)
	add_child(_model)
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = COLOR
	light.light_energy = Tuning.FLARE_LIGHT_ENERGY
	light.omni_range = Tuning.FLARE_LIGHT_RANGE
	light.shadow_enabled = shadows_enabled()
	light.position = ItemModels.flare_tip()
	light.add_to_group(GROUP_LIGHT)
	add_child(light)
	flame = make_flame()
	flame.position = ItemModels.flare_tip()
	add_child(flame)
	add_to_group(GROUP_BURNING)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.level_left.connect(_on_level_left)
	_burn_loop = AudioManager.loop(SOUND_BURN, self).start()


## The shadow setting (09 §2: shadows at High).
static func shadows_enabled() -> bool:
	var q: Variant = SettingsManager.get_value(&"shadow_quality")
	return q is StringName and q == &"high" or q is String and q == "high"


## The 60-particle additive flame (09 §3): billboard quads rising from the tip, orange fading
## to dark red and out. `size` scales the quads and the rise: 1 for a flare lying in the world,
## HELD_FLAME_SIZE in the hand (a full-size flame 0.4 m from the eye fills the screen).
static func make_flame(size: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Flame"
	p.amount = Tuning.FLARE_FLAME_PARTICLES
	p.lifetime = 0.55
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = flame_material(size)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.disable_receive_shadows = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	return p


## A soft round dot (white to clear), procedural: the flame's particle texture.
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## The flame's process material at `size` (1 = world, HELD_FLAME_SIZE = in the hand).
static func flame_material(size: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 0.35 * size
	pm.initial_velocity_max = 0.9 * size
	pm.gravity = Vector3(0.0, 0.5 * size, 0.0)
	pm.scale_min = 0.6 * size
	pm.scale_max = 1.3 * size
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.008 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.24, 0.55))
	grad.add_point(0.35, Color(1.0, 0.3, 0.1, 0.4))
	grad.set_color(grad.get_point_count() - 1, Color(0.35, 0.04, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	return pm


func _physics_process(dt: float) -> void:
	if carried and tip.is_valid():
		global_position = tip.call()
	tick(dt)
	if is_queued_for_deletion():
		return
	_view_left -= dt
	if _view_left <= 0.0 and is_inside_tree():
		_view_left = VIEW_CHECK_S
		var cam := get_viewport().get_camera_3d()
		update_view(Level.grid_in(get_tree()), cam.global_position if cam != null else global_position)


## Burn `dt` seconds: the flutter, the fade over the last 1.5 s, the 14 m `light` noise once
## per second, and the end. Public so tests step time.
func tick(dt: float) -> void:
	age += dt
	remaining -= dt
	_noise_left -= dt
	if _noise_left <= 0.0:
		_noise_left += 1.0
		NoiseModel.emit(global_position, Tuning.FLARE_NOISE_RADIUS, Tuning.NOISE_KIND_LIGHT)
	if remaining <= 0.0:
		remaining = 0.0
		light.light_energy = 0.0
		light.visible = false
		flame.emitting = false
		remove_from_group(GROUP_BURNING)
		light.remove_from_group(GROUP_LIGHT)
		burnt_out.emit()
		queue_free()
		return
	_apply_light()


## Light energy at `seconds` of age with `left` seconds of burn remaining: 2.2 with a 1 Hz
## flutter of +-15%, dying down over the last FLARE_FADE_TIME.
static func energy_at(seconds: float, left: float) -> float:
	var flutter := 1.0 + Tuning.FLARE_FLUTTER_DEPTH * sin(TAU * Tuning.FLARE_FLUTTER_HZ * seconds)
	var fade := clampf(left / Tuning.FLARE_FADE_TIME, 0.0, 1.0)
	return Tuning.FLARE_LIGHT_ENERGY * flutter * fade


func _apply_light() -> void:
	light.light_energy = energy_at(age, remaining)


## Shows the light only while the flare is in grid view of `eye` (the same hidden-shine fix
## as the Glowstick: an unshadowed 8 m light would shine through 0.2 m walls). No grid:
## always shown.
func update_view(grid: LevelGrid, eye: Vector3) -> void:
	light.visible = grid == null or SightOps.clear_near(grid, eye, global_position)


## Carry mode: frozen in the hand, no collision, the owner moves it with `tip`.
func set_carried(on: bool, tip_provider: Callable = Callable()) -> void:
	carried = on
	tip = tip_provider
	freeze = on
	collision_layer = 0 if on else 1 << (LAYER_THROWN - 1)
	collision_mask = 0 if on else PlayerLayers.WORLD_MASK
	_model.visible = not on
	# The flame stands at the tip: in the hand the flare's own origin is the tip.
	flame.position = Vector3.ZERO if on else ItemModels.flare_tip()
	flame.process_material = flame_material(HELD_FLAME_SIZE if on else 1.0)
	light.position = Vector3.ZERO if on else ItemModels.flare_tip()


## Throws: at `origin`, with velocity `v`, tumbling along its flight (as the Glowstick).
func launch(origin: Vector3, v: Vector3) -> void:
	set_carried(false)
	global_position = origin
	global_rotation = Vector3(0.0, atan2(-v.x, -v.z), PI * 0.5)
	linear_velocity = v
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() > 0.01:
		angular_velocity = flat.normalized().cross(Vector3.UP) * 7.0


func _on_body_entered(_body: Node) -> void:
	if landed or carried:
		return
	landed = true
	_bounce_mat.bounce = 0.0
	NoiseModel.emit(global_position, Tuning.NOISE_ITEM_DROP_RADIUS, Tuning.NOISE_KIND_IMPACT)
	AudioManager.play_3d(SOUND_LAND, global_position)


func _on_level_left(_proper: bool) -> void:
	queue_free()


func _exit_tree() -> void:
	if _burn_loop != null:
		_burn_loop.release()
		_burn_loop = null
