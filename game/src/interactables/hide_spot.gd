class_name HideSpot
extends Node3D
## A hide spot host (06 §10, 09 §6). M1.3 stub: the closet/locker kind only; the other
## kinds (under car, under desk, pump corner, rack gap) reuse this host with their own
## view point, yaw limit and mask in M2.
## Scene contract: %ViewPoint (Marker3D: the eye inside, facing out), %ExitPoint (Marker3D:
## where the player stands after leaving, facing away from the spot), and an Interactable
## (%Interactable) on a collider on layer 4. The view mask (6 slits for a locker) is a
## CanvasLayer this host shows while occupied.

signal occupied_changed(on: bool)

const KIND_LOCKER := &"locker"

@export var kind: StringName = KIND_LOCKER
@export var yaw_limit_deg: float = Tuning.HIDE_LOCKER_YAW_LIMIT
## Geometry between the view point and the room (a locker door): hidden while occupied,
## because the view mask stands in for it.
@export var occluders: Array[Node3D] = []

@onready var view_point: Marker3D = %ViewPoint
@onready var exit_point: Marker3D = %ExitPoint
@onready var interactable: Interactable = %Interactable

var occupant: Node = null
var _mask: CanvasLayer


func _ready() -> void:
	add_to_group(&"hide_spots")
	interactable.condition = _can_use
	interactable.interacted.connect(_on_interacted)
	_refresh_prompt()


## 09 §6: entering requires no error within 3 m.
func _can_use(player: Node) -> bool:
	if occupant != null:
		return occupant == player
	for e in get_tree().get_nodes_in_group(&"errors"):
		if e is Node3D and (e as Node3D).global_position.distance_to(global_position) < Tuning.HIDE_ENTER_MIN_ERROR_DIST:
			return false
	return true


func _on_interacted(player: Node) -> void:
	if occupant == null:
		if player.has_method(&"enter_hide"):
			player.call(&"enter_hide", self)
	elif occupant == player and player.has_method(&"leave_hide"):
		player.call(&"leave_hide")


## Called by the Player when it has entered (true) or fully left (false).
func set_occupant(player: Node) -> void:
	occupant = player
	_refresh_prompt()
	_show_mask(player != null)
	for o in occluders:
		if o != null:
			o.visible = player == null
	occupied_changed.emit(player != null)


func view_transform() -> Transform3D:
	return view_point.global_transform


func exit_transform() -> Transform3D:
	return exit_point.global_transform


func _refresh_prompt() -> void:
	if occupant == null:
		interactable.prompt = Strings.PROMPT_HIDE
		interactable.hold_time = 0.0
	else:
		interactable.prompt = Strings.PROMPT_LEAVE
		interactable.hold_time = Tuning.HIDE_LEAVE_HOLD_TIME


func _show_mask(on: bool) -> void:
	if kind != KIND_LOCKER:
		return
	if on and _mask == null:
		_mask = _build_locker_mask()
		add_child(_mask)
	if _mask:
		_mask.visible = on


## 09 §6: a slatted view of 6 horizontal slits. Plain black bars until the
## locker_slats shader lands (M2); the slits sit in the middle third of the screen.
func _build_locker_mask() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -1  # under the HUD, over the world
	var slits := Tuning.HIDE_LOCKER_SLITS
	var band_top := 0.3
	var band_bottom := 0.7
	var slit_h := (band_bottom - band_top) / float(slits * 2 - 1)
	var edges: Array[Vector2] = [Vector2(0.0, band_top)]
	for i in slits - 1:
		var y := band_top + slit_h * float(i * 2 + 1)
		edges.append(Vector2(y, y + slit_h))
	edges.append(Vector2(band_bottom, 1.0))
	for e in edges:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.anchor_left = 0.0
		r.anchor_right = 1.0
		r.anchor_top = e.x
		r.anchor_bottom = e.y
		layer.add_child(r)
	return layer
