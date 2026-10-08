class_name ItemsErrorStandIn
extends Node3D
## A stand-in for an error in the items bench: a matte column in group `errors` with an
## `error_id`, to observe and light. It carries no behaviour of an error (no error reacts to
## the Polaroid; `flashes` stays 0 and is kept for the bench readout). Bench only.

var error_id: StringName = &"still"
var flashes: int = 0
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"errors")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 2.2, 0.6)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.02, 0.02, 0.02)
	_mat.roughness = 1.0
	bm.material = _mat
	mi.mesh = bm
	mi.position.y = 1.1
	add_child(mi)
