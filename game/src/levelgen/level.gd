class_name Level
extends Node3D
## One level (14 §5 level.tscn): LevelBuilder output, the LightPool, the stratum's
## environment and dust. run.tscn (M1.9) instances it per depth, calls begin(), waits for
## `geometry_ready` (walkable) and `built` (navigation baked), then attach_player().
## Errors stay dormant until `navigation_ready` (07 §3).

signal geometry_ready
signal navigation_ready(ok: bool)
signal built

## 02 §10: dust motes in these strata.
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
## SpotLight3D in the scene that is on (pool, glowsticks, items, the flashlight), and the
## pool's share of them.
func debug_info() -> Dictionary:
	var counts := light_counts(get_tree().root)
	return {
		&"lights": "OMNI %d   SPOT %d   POOL %d/%d" % [counts.x, counts.y,
			light_pool.active_light_count() if light_pool != null else 0,
			light_pool.pool_size if light_pool != null else 0],
	}


## Vector2i(omni, spot): visible lights under `root`.
static func light_counts(root: Node) -> Vector2i:
	var out := Vector2i.ZERO
	for n in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not l.is_visible_in_tree():
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
	StratumEnvironment.apply_viewport_preset(get_viewport(), preset)
	light_pool.configure(stratum, preset)
	if DUST_STRATA.has(data.stratum):
		dust = DustMotes.create(float(StratumEnvironment.preset_of(preset)[&"particles"]))
		add_child(dust)
	builder = LevelBuilder.new()
	builder.name = "Builder"
	builder.light_pool = light_pool
	builder.nav_region = navigation
	add_child(builder)
	builder.geometry_built.connect(func() -> void: geometry_ready.emit())
	builder.navigation_baked.connect(func(ok: bool) -> void: navigation_ready.emit(ok))
	builder.built.connect(func() -> void: built.emit())
	builder.build(data, content)


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
