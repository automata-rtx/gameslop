class_name Door
extends Node3D
## A hinged door in a DOOR edge (09 §5): 0.6 s swing with ease-out, blocks movement when
## closed, never locks. A chasing error slams it open (0.15 s). The leaf body carries the
## edge's 07 §7 metadata so noclip treats a closed door as a candidate wall.
## Scene contract: %Hinge (Node3D the leaf turns on), %Leaf (AnimatableBody3D on layers
## world + interactable) with an Interactable child (%Interactable), %Jambs (StaticBody3D),
## meshes %JambL, %JambR, %LeafMesh, %Knob (materials per stratum, apply_materials).

signal opened_changed(open: bool)

const OPEN_ANGLE := deg_to_rad(-95.0)
const WALL_KIND := &"wall_kind"
const KIND_PROP := &"PROP"

@export var start_open: bool = false

@onready var hinge: Node3D = %Hinge
@onready var leaf: AnimatableBody3D = %Leaf
@onready var jambs: StaticBody3D = %Jambs
@onready var interactable: Interactable = %Interactable

var is_open: bool = false
## The level grid (set by LevelPlacer after the edge meta): the door keeps its edge's
## closed state there, so a closed door blocks grid sight (SightOps).
var grid: LevelGrid:
	set(g):
		grid = g
		_sync_grid()
var _swing: Tween


func _ready() -> void:
	add_to_group(&"doors")
	interactable.interacted.connect(func(_p: Node) -> void: toggle())
	_set_open(start_open, 0.0, false)


## Copies the edge metadata (07 §7) onto the bodies: the leaf is the DOOR wall itself; the
## jambs are plain wall (WALL). The leaf counts as a wall for noise (06 §6) only while it is
## closed: an open leaf's `wall_kind` is PROP. Leaf and jambs both carry `closed`, so noclip
## refuses the whole frame of an open door (SOLID); the header above (BuildCollision) has
## no `closed` and is always SOLID.
func set_edge_meta(meta: Dictionary) -> void:
	for k in meta:
		leaf.set_meta(k, meta[k])
		jambs.set_meta(k, meta[k])
	jambs.set_meta(&"wall_type", LevelGrid.WALL)
	jambs.set_meta(WALL_KIND, Tuning.GRID_WALL_TYPES[LevelGrid.WALL])
	_apply_leaf_kind()


## Per-stratum materials (LevelMaterials): jamb panels, leaf, handle.
func apply_materials(jamb: Material, leaf_mat: Material, handle: Material) -> void:
	for n in [%JambL, %JambR]:
		(n as MeshInstance3D).material_override = jamb
	(%LeafMesh as MeshInstance3D).material_override = leaf_mat
	(%Knob as MeshInstance3D).material_override = handle


func _sync_grid() -> void:
	if grid != null and leaf != null and leaf.has_meta(&"cell"):
		grid.set_door_closed(leaf.get_meta(&"cell"), int(leaf.get_meta(&"dir")), not is_open)


func _apply_leaf_kind() -> void:
	leaf.set_meta(WALL_KIND, KIND_PROP if is_open else Tuning.GRID_WALL_TYPES[LevelGrid.DOOR])


func toggle() -> void:
	_set_open(not is_open, Tuning.DOOR_SWING_TIME, true)


func open(slam: bool = false) -> void:
	if not is_open:
		_set_open(true, Tuning.DOOR_SLAM_TIME if slam else Tuning.DOOR_SWING_TIME, true, slam)


func close() -> void:
	if is_open:
		_set_open(false, Tuning.DOOR_SWING_TIME, true)


func _set_open(on: bool, time: float, audible: bool, slam: bool = false) -> void:
	is_open = on
	interactable.prompt = Strings.PROMPT_CLOSE_DOOR if on else Strings.PROMPT_OPEN_DOOR
	leaf.set_meta(&"closed", not on)
	# The jambs follow the leaf for noclip (07 §7): an open doorway's frame is SOLID.
	jambs.set_meta(&"closed", not on)
	_apply_leaf_kind()
	_sync_grid()
	var angle := OPEN_ANGLE if on else 0.0
	if _swing != null:
		_swing.kill()
	if time <= 0.0:
		hinge.rotation.y = angle
	else:
		_swing = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_swing.tween_property(hinge, ^"rotation:y", angle, time)
	if audible:
		var id := &"door_slam" if slam else (&"door_open" if on else &"door_close")
		var radius := Tuning.NOISE_DOOR_SLAM_RADIUS if slam else (Tuning.NOISE_DOOR_OPEN_RADIUS if on else Tuning.NOISE_DOOR_CLOSE_RADIUS)
		AudioManager.play_3d(id, global_position)
		EventBus.noise_emitted.emit(global_position, radius, Tuning.NOISE_KIND_DOOR)
	opened_changed.emit(on)
