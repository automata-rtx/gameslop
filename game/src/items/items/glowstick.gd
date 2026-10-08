class_name Glowstick
extends RigidBody3D
## A cracked glowstick in the world (09 §2): a chemical light. An OmniLight3D `#7CFF4A`, energy
## 0.9, range 4 m, no shadows, in group `chemical_light`, on an emissive tube. It burns 90 s and
## dims over the last 20 s, then goes. Landing from a throw is an `impact` noise (6 m, the Echo
## lure); a dropped stick is set down silently. Lit area counts for observing Still (08 §4);
## Flicker cannot use it (it is not a fixture). Layer 8 (`thrown`), collides with the world only.
## The lit predicate and Flicker read the group: `Glowstick.is_lit(tree, pos)`. In a level, the
## light counts only where it has a clear grid sight line (SightOps), and the light node is
## hidden while the stick is out of grid view of the player's camera: an unshadowed 4 m light
## would otherwise shine through 0.2 m walls (CHANGELOG 2026-10-08). The tube still glows.

const GROUP_LIGHT := &"chemical_light"
const LAYER_THROWN := 8
const SOUND_LAND := &"glowstick_land"
const SOUND_FIZZ := &"glowstick_fizz"
## Light below this energy no longer counts as lit.
const LIT_MIN_ENERGY := 0.05
## Seconds between grid-view checks of the light against the camera.
const VIEW_CHECK_S := Tuning.LIGHT_POOL_REEVAL_INTERVAL

## Seconds burned.
var age: float = 0.0
## True for a stick set down by hand: no impact noise.
var quiet: bool = false
var light: OmniLight3D
var landed: bool = false

var _tube_mat: ShaderMaterial
var _bounce_mat: PhysicsMaterial
var _view_left: float = 0.0


func _init() -> void:
	name = "Glowstick"
	collision_layer = 1 << (LAYER_THROWN - 1)
	collision_mask = PlayerLayers.WORLD_MASK
	mass = 0.05
	linear_damp = 0.25
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	_bounce_mat = PhysicsMaterial.new()
	_bounce_mat.bounce = Tuning.GLOWSTICK_BOUNCE
	_bounce_mat.friction = 0.8
	physics_material_override = _bounce_mat
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.014
	cap.height = ItemModels.GLOWSTICK_LEN
	shape.shape = cap
	add_child(shape)
	var model := ItemModels.held(&"glowstick")
	model.rotation = Vector3.ZERO
	model.name = "Model"
	add_child(model)
	_tube_mat = ((model.get_node("Tube") as MeshInstance3D).material_override as ShaderMaterial).duplicate()
	(model.get_node("Tube") as MeshInstance3D).material_override = _tube_mat
	ItemModels.set_held(model, false)
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = ItemModels.GLOW
	light.light_energy = Tuning.GLOWSTICK_LIGHT_ENERGY
	light.omni_range = Tuning.GLOWSTICK_LIGHT_RANGE
	light.shadow_enabled = false
	light.add_to_group(GROUP_LIGHT)
	add_child(light)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.level_left.connect(func(_proper: bool) -> void: queue_free())
	AudioManager.start_loop(SOUND_FIZZ, self)


func _physics_process(dt: float) -> void:
	tick(dt)
	_view_left -= dt
	if _view_left <= 0.0 and is_inside_tree():
		_view_left = VIEW_CHECK_S
		var cam := get_viewport().get_camera_3d()
		update_view(Level.grid_in(get_tree()), cam.global_position if cam != null else global_position)


## Shows the light only while the stick is in grid view of `eye` (or of a cell one step
## from it). No grid: always shown. Public so tests drive it.
func update_view(grid: LevelGrid, eye: Vector3) -> void:
	light.visible = grid == null or SightOps.clear_near(grid, eye, global_position)


## Burn `dt` seconds. Public so tests step time.
func tick(dt: float) -> void:
	age += dt
	if age >= Tuning.GLOWSTICK_LIFETIME:
		light.visible = false
		light.light_energy = 0.0
		queue_free()
		return
	_apply_life()


## 1 for the first 70 s, falling linearly to 0 over the last 20 s.
static func life_factor(seconds: float) -> float:
	var dim_start := Tuning.GLOWSTICK_LIFETIME - Tuning.GLOWSTICK_DIM_TIME
	if seconds <= dim_start:
		return 1.0
	return clampf(1.0 - (seconds - dim_start) / Tuning.GLOWSTICK_DIM_TIME, 0.0, 1.0)


func life() -> float:
	return life_factor(age)


func _apply_life() -> void:
	var f := life()
	light.light_energy = Tuning.GLOWSTICK_LIGHT_ENERGY * f
	_tube_mat.set_shader_parameter(&"emission_strength", ItemModels.GLOW_EMISSION * f)


## Throws: at `origin`, with velocity `v`, tumbling end over end along its flight.
func launch(origin: Vector3, v: Vector3) -> void:
	global_position = origin
	global_rotation = Vector3(0.0, atan2(-v.x, -v.z), PI * 0.5)
	linear_velocity = v
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() > 0.01:
		angular_velocity = flat.normalized().cross(Vector3.UP) * 7.0


## Sets the stick down at `pos` without a sound (hold use_item, 09 §2).
func set_down(pos: Vector3, yaw: float) -> void:
	quiet = true
	global_position = pos
	global_rotation = Vector3(0.0, yaw, PI * 0.5)


func _on_body_entered(_body: Node) -> void:
	if landed:
		return
	landed = true
	# Bounces once (09 §2), then settles.
	_bounce_mat.bounce = 0.0
	if quiet:
		return
	NoiseModel.emit(global_position, Tuning.NOISE_ITEM_DROP_RADIUS, Tuning.NOISE_KIND_IMPACT)
	AudioManager.play_3d(SOUND_LAND, global_position)


## 06 Interfaces / 08 §4: is `pos` inside the light of a burning glowstick (or any chemical
## light) with a clear grid sight line from the light to it? The Player's observation asks
## this through Player.add_light_query. Visibility of the light node is ignored: it is hidden
## for rendering when the player cannot see the stick, which says nothing about what it lights.
## `grid` defaults to the live level's (none: no sight test).
static func is_lit(tree: SceneTree, pos: Vector3, grid: LevelGrid = null) -> bool:
	if grid == null:
		grid = Level.grid_in(tree)
	for n in tree.get_nodes_in_group(GROUP_LIGHT):
		var l := n as OmniLight3D
		if l == null or not l.is_inside_tree() or l.is_queued_for_deletion() or l.light_energy <= LIT_MIN_ENERGY:
			continue
		var at := l.global_position
		if pos.distance_to(at) <= l.omni_range and (grid == null or SightOps.clear(grid, at, pos)):
			return true
	return false


## Initial speed for a 45 degree throw that lands `range_m` away on the floor, when released
## `height` above it: with A = g * range, v = A / sqrt(g * height + A) (v = sqrt(A) at height 0).
static func throw_speed(range_m: float, height: float) -> float:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var a := g * range_m
	return a / sqrt(g * maxf(height, 0.0) + a)
