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

@onready var light_pool: LightPool = %LightPool
@onready var navigation: NavigationRegion3D = %Navigation
@onready var world_environment: WorldEnvironment = %WorldEnvironment
@onready var content: Node3D = %Content

var data: LevelData
var stratum: StratumData
var builder: LevelBuilder
var dust: DustMotes
var preset: StringName = Tuning.QUALITY_PRESET_DEFAULT


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
