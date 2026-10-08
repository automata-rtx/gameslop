class_name MergedProp
extends Node3D
## A prop authored as several primitive MeshInstance3D children (02 T8) and drawn as one
## mesh with one surface per material (M2.2: an Offices level holds about a hundred desks
## and monitors, so nine draws a desk would not fit 14 §10). On ready the direct mesh
## children of this node, and of each node in `merge`, are merged once per scene into a
## shared ArrayMesh (cached by scene path and node), then replaced by one MeshInstance3D.
## Collision bodies and other children are left alone. Props beyond PROP_VISIBILITY_END
## are not drawn (the level's chunks hide at 45 m, 07 §8).

## Extra nodes whose direct mesh children merge into one mesh under that node (a rotor).
@export var merge: Array[NodePath] = []
## Shadow casting of the merged mesh.
@export var cast_shadows: bool = true

const PROP_VISIBILITY_END := 40.0

static var _cache: Dictionary = {}


func _ready() -> void:
	_merge_children(self, ".")
	for path in merge:
		var n := get_node_or_null(path)
		if n != null:
			_merge_children(n, String(path))


func _merge_children(holder: Node, key_path: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	for c in holder.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			meshes.append(c as MeshInstance3D)
	if meshes.size() < 2:
		return
	var key := "%s|%s" % [scene_file_path, key_path]
	var mesh: ArrayMesh = _cache.get(key)
	if mesh == null:
		mesh = build(meshes)
		if scene_file_path != "":
			_cache[key] = mesh
	for m in meshes:
		holder.remove_child(m)
		m.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = mesh
	mi.visibility_range_end = PROP_VISIBILITY_END
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


## One ArrayMesh with a surface per material of `meshes` (each placed by its transform).
static func build(meshes: Array[MeshInstance3D]) -> ArrayMesh:
	var by_mat: Dictionary = {}
	var order: Array[Material] = []
	for m in meshes:
		var mat := m.material_override
		if not by_mat.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[mat] = st
			order.append(mat)
		for s in m.mesh.get_surface_count():
			(by_mat[mat] as SurfaceTool).append_from(m.mesh, s, m.transform)
	var out := ArrayMesh.new()
	for mat in order:
		(by_mat[mat] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
