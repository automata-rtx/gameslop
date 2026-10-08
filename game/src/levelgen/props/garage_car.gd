class_name GarageCar
extends Node3D
## A parked car (02 §7 Garage, 09 §7): a primitive body in one of the four palette colours
## (#2E2E33, #5A1E1E, #1E2E5A, #CFCFCF), chosen by the placement (`params.color`, from the
## props rng) when the builder places it. Its underside sits 0.4 m up: the under-car hide
## slot (06 §10; the HideSpot scene sits at the car's centre).

const BODY_MATERIAL := "res://data/materials/garage/car_body_%d.tres"


func _ready() -> void:
	var p: Dictionary = get_meta(LevelPlacer.META_PLACEMENT, {})
	var color := int((p.get(&"params", {}) as Dictionary).get(&"color", 0))
	var mat := load(BODY_MATERIAL % clampi(color, 0, 3)) as Material
	for path: NodePath in [^"%Body", ^"%Cabin"]:
		var mi := get_node_or_null(path) as MeshInstance3D
		if mi != null:
			mi.material_override = mat
