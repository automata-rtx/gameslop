class_name ServerCableTray
extends Node3D
## A cable tray along a Server aisle's ceiling (07 §5.5, visual only): a tray 0.4 m wide
## with a dark cable bundle in it and hanger rods up to the ceiling every 2 m. Its length is
## the placement's `params.length` (the aisle run), along the prefab's Z. Built from box
## primitives on ready (02 T8) into one mesh of two surfaces (one draw per material); no
## collision (it hangs above head height).

const WIDTH := 0.4
const DEPTH := 0.06
const ROD_SPACING := 2.0
const TRAY_MATERIAL := "res://data/materials/server/cable_tray.tres"
const CABLE_MATERIAL := "res://data/materials/server/dark_metal.tres"


func _ready() -> void:
	var p: Dictionary = get_meta(LevelPlacer.META_PLACEMENT, {})
	var length := float((p.get(&"params", {}) as Dictionary).get(&"length", ROD_SPACING))
	var tray := SurfaceTool.new()
	tray.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(tray, Vector3(WIDTH, 0.008, length), Vector3.ZERO)
	_box(tray, Vector3(0.01, DEPTH, length), Vector3(-WIDTH * 0.5, DEPTH * 0.5, 0.0))
	_box(tray, Vector3(0.01, DEPTH, length), Vector3(WIDTH * 0.5, DEPTH * 0.5, 0.0))
	var drop := float(Tuning.STRATUM_CEILING_HEIGHT[&"server"]) - Tuning.SERVER_CABLE_TRAY_HEIGHT
	var rods := maxi(1, floori(length / ROD_SPACING))
	for k in rods:
		var z := -length * 0.5 + (k + 0.5) * length / rods
		for side: float in [-1.0, 1.0]:
			_box(tray, Vector3(0.012, drop, 0.012), Vector3(side * WIDTH * 0.5, drop * 0.5, z))
	var cable := SurfaceTool.new()
	cable.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(cable, Vector3(WIDTH * 0.7, 0.035, maxf(0.1, length - 0.05)), Vector3(0.0, 0.022, 0.0))
	var mesh := tray.commit()
	cable.commit(mesh)
	mesh.surface_set_material(0, load(TRAY_MATERIAL) as Material)
	mesh.surface_set_material(1, load(CABLE_MATERIAL) as Material)
	var mi := MeshInstance3D.new()
	mi.name = "Tray"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _box(st: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var m := BoxMesh.new()
	m.size = size
	st.append_from(m, 0, Transform3D(Basis.IDENTITY, at))
