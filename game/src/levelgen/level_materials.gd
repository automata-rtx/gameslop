class_name LevelMaterials
extends RefCounted
## World-shader materials for the level surface classes (02 §5, §7).

## Surface material per class for each stratum (02 §7); a stratum without a table gets
## plain world-shader materials from its StratumData colours.
const MATERIALS: Dictionary = {
	&"halls": {
		BuildPlan.C_FLOOR: "res://data/materials/halls/carpet.tres",
		BuildPlan.C_CEILING: "res://data/materials/halls/ceiling_tile.tres",
		BuildPlan.C_WALL: "res://data/materials/halls/wallpaper.tres",
		BuildPlan.C_SOFT: "res://data/materials/halls/soft_wall.tres",
	},
}
const WORLD_SHADER := "res://shaders/world_surface.gdshader"

static func paths(stratum: StringName) -> Array:
	return (MATERIALS.get(stratum, {}) as Dictionary).values()


static func for_class(stratum: StratumData, cls: int) -> Material:
	var table: Dictionary = MATERIALS.get(stratum.id, {})
	var path: String = table.get(cls, table.get(BuildPlan.C_WALL, ""))
	var mat: Material = load(path) as Material if path != "" else null
	if mat == null:
		mat = _fallback(stratum, cls)
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
		_:
			m.set_shader_parameter(&"albedo", stratum.wall_color)
	if cls == BuildPlan.C_SOFT:
		m.set_shader_parameter(&"soft", 1.0)
	return m
