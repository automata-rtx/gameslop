class_name WaterVolume
extends Area3D
## A wet basin's water (07 §8 "Water: one Area3D + planar mesh per basin with WATER"):
## the water surface (water.gdshader) and an Area3D on the water layer (7) over the basin,
## from its floor to the surface. While a body that has `water_depth` (the Player, 06 §3)
## is inside, the volume keeps it at the depth of the surface over the body's feet; 0 when
## it leaves. The player does the rest (wading speed, noise, the water step sound). The
## surface carries the water lap loop (03, `water_lap`).

const MATERIAL := "res://data/materials/pools/water.tres"
const GROUP := &"water_volumes"
const LAP_SOUND := &"water_lap"
const LAP_FADE := 1.0

var surface_y: float = 0.0
var floor_y: float = 0.0
## The basin in cells (LevelData P_WATER `rect`).
var rect: Rect2i = Rect2i()
var _inside: Array[Node3D] = []
var _surface: MeshInstance3D
var _lap: AudioLoop


## Builds the surface mesh and the volume for basin `basin_rect` (cells), water at `surface`
## over a floor at `bottom`. Positions itself; call before adding to the tree.
func setup(basin_rect: Rect2i, surface: float, bottom: float, material: Material = null) -> void:
	rect = basin_rect
	surface_y = surface
	floor_y = bottom
	var cs := Tuning.GRID_CELL_SIZE
	var inner := cs - Tuning.GRID_WALL_THICKNESS
	var lo := Vector2(rect.position) * cs - Vector2.ONE * inner * 0.5
	var hi := Vector2(rect.end - Vector2i.ONE) * cs + Vector2.ONE * inner * 0.5
	var size := hi - lo
	name = "Water_%d_%d" % [rect.position.x, rect.position.y]
	add_to_group(GROUP)
	position = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
	collision_layer = 1 << (PlayerLayers.WATER - 1)
	collision_mask = PlayerLayers.PLAYER_MASK
	monitoring = true
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, surface - bottom, size.y)
	var cs_node := CollisionShape3D.new()
	cs_node.name = "Volume"
	cs_node.shape = shape
	cs_node.position = Vector3(0.0, (surface + bottom) * 0.5, 0.0)
	add_child(cs_node)
	var plane := PlaneMesh.new()
	plane.size = size
	# Subdivided like the level meshes so the Coherence jitter trembles it (02 §5).
	plane.subdivide_width = maxi(0, ceili(size.x / Tuning.LEVELBUILD_MESH_MAX_EDGE) - 1)
	plane.subdivide_depth = maxi(0, ceili(size.y / Tuning.LEVELBUILD_MESH_MAX_EDGE) - 1)
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = plane
	mi.position = Vector3(0.0, surface, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material if material != null else load(MATERIAL) as Material
	add_child(mi)
	_surface = mi
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)


func _ready() -> void:
	if _surface != null and AudioManager.has_sound(LAP_SOUND):
		_lap = AudioManager.loop(LAP_SOUND, _surface)
		_lap.start(LAP_FADE)


func _exit_tree() -> void:
	if _lap != null:
		_lap.release()
		_lap = null


## Water depth over a point at height y (0 above the surface).
func depth_at(y: float) -> float:
	return maxf(0.0, surface_y - y)


func _on_entered(body: Node3D) -> void:
	if "water_depth" in body and not _inside.has(body):
		_inside.append(body)


func _on_exited(body: Node3D) -> void:
	_inside.erase(body)
	if is_instance_valid(body) and "water_depth" in body:
		body.set(&"water_depth", 0.0)


func _physics_process(_delta: float) -> void:
	for body in _inside:
		if is_instance_valid(body):
			body.set(&"water_depth", depth_at(body.global_position.y))
