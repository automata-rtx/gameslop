class_name LevelMaterials
extends RefCounted
## World-shader materials for the level surface classes (02 §5, §7), plus the door prefab's
## parts (09 §5), so every stratum's doors wear its own palette.

## Door parts (not BuildPlan mesh classes; LevelPlacer asks for them per door).
const C_DOOR_LEAF := 100
const C_DOOR_HANDLE := 101
## Pools water surface (water.gdshader, M2.1).
const C_WATER := 102

## Surface material per class for each stratum (02 §7); a stratum without a table gets
## plain world-shader materials from its StratumData colours.
const MATERIALS: Dictionary = {
	&"halls": {
		BuildPlan.C_FLOOR: "res://data/materials/halls/carpet.tres",
		BuildPlan.C_CEILING: "res://data/materials/halls/ceiling_tile.tres",
		BuildPlan.C_WALL: "res://data/materials/halls/wallpaper.tres",
		BuildPlan.C_SOFT: "res://data/materials/halls/soft_wall.tres",
		C_DOOR_LEAF: "res://data/materials/halls/door_wood.tres",
		C_DOOR_HANDLE: "res://data/materials/halls/prop_metal.tres",
	},
	&"pools": {
		BuildPlan.C_FLOOR: "res://data/materials/pools/tile_floor.tres",
		BuildPlan.C_CEILING: "res://data/materials/pools/tile_ceiling.tres",
		BuildPlan.C_WALL: "res://data/materials/pools/tile_wall.tres",
		BuildPlan.C_SOFT: "res://data/materials/pools/soft_wall.tres",
		BuildPlan.C_BASIN: "res://data/materials/pools/basin_tile.tres",
		C_DOOR_LEAF: "res://data/materials/pools/door_metal.tres",
		C_DOOR_HANDLE: "res://data/materials/pools/prop_chrome.tres",
		C_WATER: "res://data/materials/pools/water.tres",
	},
	&"garage": {
		BuildPlan.C_FLOOR: "res://data/materials/garage/concrete_floor.tres",
		BuildPlan.C_CEILING: "res://data/materials/garage/concrete_ceiling.tres",
		BuildPlan.C_WALL: "res://data/materials/garage/concrete_wall.tres",
		BuildPlan.C_SOFT: "res://data/materials/garage/soft_wall.tres",
		C_DOOR_LEAF: "res://data/materials/garage/barrier.tres",
		C_DOOR_HANDLE: "res://data/materials/garage/fixture_cage.tres",
	},
	&"offices": {
		BuildPlan.C_FLOOR: "res://data/materials/offices/carpet_tile.tres",
		BuildPlan.C_CEILING: "res://data/materials/offices/ceiling_tile.tres",
		BuildPlan.C_WALL: "res://data/materials/offices/wall_panel.tres",
		BuildPlan.C_SOFT: "res://data/materials/offices/soft_wall.tres",
		BuildPlan.C_PARTITION: "res://data/materials/offices/partition.tres",
		BuildPlan.C_GLASS: "res://data/materials/offices/glass.tres",
		C_DOOR_LEAF: "res://data/materials/offices/door_leaf.tres",
		C_DOOR_HANDLE: "res://data/materials/offices/prop_metal.tres",
	},
	&"server": {
		BuildPlan.C_FLOOR: "res://data/materials/server/floor_tile.tres",
		BuildPlan.C_CEILING: "res://data/materials/server/ceiling.tres",
		BuildPlan.C_WALL: "res://data/materials/server/wall.tres",
		BuildPlan.C_SOFT: "res://data/materials/server/soft_wall.tres",
		BuildPlan.C_GLASS: "res://data/materials/server/fence.tres",
		BuildPlan.C_RACK: "res://data/materials/server/rack.tres",
		C_DOOR_LEAF: "res://data/materials/server/door_leaf.tres",
		C_DOOR_HANDLE: "res://data/materials/server/prop_metal.tres",
	},
}
const WORLD_SHADER := "res://shaders/world_surface.gdshader"

static func paths(stratum: StringName) -> Array:
	return (MATERIALS.get(stratum, {}) as Dictionary).values()


## Fallback materials made so far, by "stratum:class" (one shared material per pair).
static var _made: Dictionary = {}


static func for_class(stratum: StratumData, cls: int) -> Material:
	var table: Dictionary = MATERIALS.get(stratum.id, {})
	var fallback_cls := BuildPlan.C_WALL if cls < C_DOOR_LEAF else -1
	var path: String = table.get(cls, table.get(fallback_cls, ""))
	var mat: Material = load(path) as Material if path != "" else null
	if mat == null:
		var key := "%s:%d" % [stratum.id, cls]
		if not _made.has(key):
			_made[key] = _fallback(stratum, cls)
		mat = _made[key]
	return mat


static func _fallback(stratum: StratumData, cls: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(WORLD_SHADER) as Shader
	match cls:
		BuildPlan.C_FLOOR:
			m.set_shader_parameter(&"albedo", stratum.floor_color)
			m.set_shader_parameter(&"roughness", stratum.floor_roughness)
		BuildPlan.C_CEILING:
			m.set_shader_parameter(&"albedo", stratum.ceiling_color)
		BuildPlan.C_PARTITION:
			m.set_shader_parameter(&"albedo", stratum.partition_color)
		C_DOOR_LEAF:
			m.set_shader_parameter(&"albedo", stratum.wall_color.darkened(0.35))
			m.set_shader_parameter(&"roughness", 0.7)
		C_DOOR_HANDLE:
			m.set_shader_parameter(&"albedo", Color(0.6, 0.6, 0.58))
			m.set_shader_parameter(&"roughness", 0.45)
			m.set_shader_parameter(&"metallic", 0.5)
		_:
			m.set_shader_parameter(&"albedo", stratum.wall_color)
	if cls == BuildPlan.C_SOFT:
		m.set_shader_parameter(&"soft", 1.0)
	return m
