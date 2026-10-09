class_name Level
extends Node3D
## One level (14 §5 level.tscn): LevelBuilder output, the LightPool, the stratum's
## environment and dust. run.tscn (M1.9) instances it per depth, calls begin(), waits for
## `geometry_ready` (walkable) and `built` (navigation baked), then attach_player().
## Errors stay dormant until `navigation_ready` (07 §3).

signal geometry_ready
signal navigation_ready(ok: bool)
signal built

## 02 §10: dust motes in these strata (`dust` holds the Substrate's pixels there).
const DUST_STRATA: Array[StringName] = [&"halls", &"garage", &"offices"]
## The live level is in this group; `Level.grid_in(tree)` reads its grid.
const GROUP := &"levels"

@onready var light_pool: LightPool = %LightPool
@onready var navigation: NavigationRegion3D = %Navigation
@onready var world_environment: WorldEnvironment = %WorldEnvironment
@onready var content: Node3D = %Content

var data: LevelData
var stratum: StratumData
var builder: LevelBuilder
var dust: DustMotes
var preset: StringName = Tuning.QUALITY_PRESET_DEFAULT


func _ready() -> void:
	add_to_group(GROUP)
	# 14 §9 F3 overlay: the level adds its light counts.
	add_to_group(&"debug_info")


## The grid of the level in the tree (null outside a level: benches, unit tests).
static func grid_in(tree: SceneTree) -> LevelGrid:
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(GROUP):
		var l := n as Level
		if l != null and l.data != null and not l.is_queued_for_deletion():
			return l.data.grid
	return null


## F3 overlay lines (DebugOverlay reads the `debug_info` group): every OmniLight3D and
## SpotLight3D in the scene that is drawn (on, and not faded out by distance from the
## camera: pool, glowsticks, items, the flashlight), and the pool's share of them.
func debug_info() -> Dictionary:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var counts := light_counts(get_tree().root, cam.global_position if cam != null else Vector3.INF)
	return {
		&"lights": "OMNI %d   SPOT %d   POOL %d/%d" % [counts.x, counts.y,
			light_pool.active_light_count() if light_pool != null else 0,
			light_pool.pool_size if light_pool != null else 0],
	}


## Vector2i(omni, spot): visible lights under `root`; with `from` (the camera), only the ones
## the renderer draws from there (a distance-faded light past its fade is culled).
static func light_counts(root: Node, from: Vector3 = Vector3.INF) -> Vector2i:
	var out := Vector2i.ZERO
	for n in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not is_drawn(l, from):
			continue
		if l is OmniLight3D:
			out.x += 1
		elif l is SpotLight3D:
			out.y += 1
	return out


func begin(level_data: LevelData, quality_preset: StringName = Tuning.QUALITY_PRESET_DEFAULT) -> void:
	data = level_data
	preset = quality_preset
	stratum = load("res://data/strata/%s.tres" % data.stratum) as StratumData
	world_environment.environment = StratumEnvironment.build(stratum, preset)
	if data.cycle > 1:
		apply_cycle2_fog(world_environment.environment)
	StratumEnvironment.apply_viewport_preset(get_viewport(), preset)
	light_pool.configure(stratum, preset)
	var particles := float(StratumEnvironment.preset_of(preset)[&"particles"])
	if DUST_STRATA.has(data.stratum):
		dust = DustMotes.create(particles)
	elif data.stratum == Tuning.STRATUM_SUBSTRATE:
		# 02 §10: the Substrate's 1 px white pixels drifting upward (Pools' bubbles are the
		# WaterVolumes'; Server has none).
		dust = DustMotes.create_pixels(particles)
	if dust != null:
		add_child(dust)
	builder = LevelBuilder.new()
	builder.name = "Builder"
	builder.light_pool = light_pool
	builder.nav_region = navigation
	add_child(builder)
	builder.geometry_built.connect(func() -> void:
		fade_small_lights(content)
		geometry_ready.emit())
	builder.navigation_baked.connect(func(ok: bool) -> void: navigation_ready.emit(ok))
	builder.built.connect(func() -> void: built.emit())
	builder.build(data, content)


## True when `l` is on and, seen from `from` (INF: anywhere), not past its distance fade.
static func is_drawn(l: Light3D, from: Vector3 = Vector3.INF) -> bool:
	if not l.is_visible_in_tree():
		return false
	if from == Vector3.INF or not l.distance_fade_enabled:
		return true
	return l.global_position.distance_to(from) < l.distance_fade_begin + l.distance_fade_length


## 14 §10 active lights (M3.5): the unpooled short lights under `root` (a pickup's 1 m glint,
## a Garage exit sign's 3 m spill; range <= LIGHT_SMALL_FADE_MAX_RANGE) get the pooled
## lights' distance fade, so only the ones near the camera are drawn. A light that reaches
## no farther than that cannot light anything near a viewer 18 m away.
static func fade_small_lights(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		var reach := (l as OmniLight3D).omni_range if l is OmniLight3D else ((l as SpotLight3D).spot_range if l is SpotLight3D else INF)
		if reach <= Tuning.LIGHT_SMALL_FADE_MAX_RANGE and not l.distance_fade_enabled:
			l.distance_fade_enabled = true
			l.distance_fade_begin = Tuning.LIGHT_POOL_DISTANCE_FADE_BEGIN
			l.distance_fade_length = Tuning.LIGHT_POOL_DISTANCE_FADE_LENGTH


## 02 §7 Cycle 2: fog density x CYCLE2_FOG_MULT (volumetric and distance fog alike; the
## Substrate's distance fog to black has no density to raise).
static func apply_cycle2_fog(env: Environment) -> void:
	env.volumetric_fog_density *= Tuning.CYCLE2_FOG_MULT
	if env.fog_mode == Environment.FOG_MODE_EXPONENTIAL:
		env.fog_density *= Tuning.CYCLE2_FOG_MULT


func is_walkable_now() -> bool:
	return builder != null and builder.is_geometry_built


func is_ready() -> bool:
	return builder != null and builder.is_built


## The spawn point with its facing (07: the spawn room, facing away from the cabin).
func spawn_transform() -> Transform3D:
	return builder.spawn_transform if builder != null else Transform3D.IDENTITY


## Puts the player at the spawn and points the level's per-player systems at it: the light
## pool measures from it, dust follows it, and powered fixtures count as light for its
## observation (06, 08 §4).
func attach_player(player: Node3D, eye: Node3D = null) -> void:
	player.global_transform = spawn_transform()
	light_pool.target = eye if eye != null else player
	light_pool.reevaluate()
	if dust != null:
		dust.follow = eye if eye != null else player
	if player.has_method(&"add_light_query"):
		player.call(&"add_light_query", light_pool.is_lit)


func detach_player(player: Node3D) -> void:
	if player.has_method(&"remove_light_query"):
		player.call(&"remove_light_query", light_pool.is_lit)
	light_pool.target = null
	if dust != null:
		dust.follow = null
