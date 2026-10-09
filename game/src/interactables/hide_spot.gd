class_name HideSpot
extends Node3D
## A hide spot host (06 §10, 09 §6): one script, one scene per kind (scenes/interactables/
## hide_spot_<kind>.tscn): locker, under car, under desk, pump corner, rack gap. Each scene
## sets its own view point, yaw limit and view mask kind.
## Scene contract: `view_offset` (the eye inside, looking out) and `exit_offset` (where the
## player stands after leaving, facing away from the spot), both local to the host, and an
## Interactable (%Interactable) on a collider on layer 4 (the host itself may be that collider:
## `under_desk` is one StaticBody3D with its shape and Interactable, 3 nodes, R19 14 §10). The view mask is a CanvasLayer this host shows
## while occupied: six slits for a locker, a floor-level letterbox for a desk, a small window
## for a pump corner, none for a car (the car's belly is the frame) or a rack gap. The LevelPlacer
## orients the scene so its local -Z is the way the occupant looks, except the locker (+Z).

signal occupied_changed(on: bool)

const KIND_LOCKER := &"locker"
const KIND_UNDER_CAR := &"under_car"
const KIND_UNDER_DESK := &"under_desk"
const KIND_PUMP_CORNER := &"pump_corner"
const KIND_RACK_GAP := &"rack_gap"
## The clear part of the view mask for kinds that have one: a Rect2 in 0..1 screen space.
const MASK_CLEAR: Dictionary = {
	KIND_UNDER_DESK: Rect2(0.0, 0.54, 1.0, 0.22),
	KIND_PUMP_CORNER: Rect2(0.34, 0.26, 0.32, 0.36),
}
## 14 canvas layers: -20 hide masks, -10 Coherence screen pass, 0+ HUD, menus above.
const MASK_CANVAS_LAYER := -20

@export var kind: StringName = KIND_LOCKER
@export var yaw_limit_deg: float = Tuning.HIDE_LOCKER_YAW_LIMIT
## Geometry between the view point and the room (a locker door): hidden while occupied,
## because the view mask stands in for it.
@export var occluders: Array[Node3D] = []
## Manifest id of the spot's own sound (car scrape, locker click), played on entering
## and leaving (11 §2). Empty: `hide_<kind>`.
@export var sound: StringName = &""

## The eye inside, looking out, local to the host (R19: was a ViewPoint marker node).
@export var view_offset: Transform3D = Transform3D.IDENTITY
## Where the player stands after leaving, local to the host (R19: was an ExitPoint marker).
@export var exit_offset: Transform3D = Transform3D.IDENTITY

@onready var interactable: Interactable = %Interactable

var occupant: Node = null
var _mask: CanvasLayer


func _ready() -> void:
	add_to_group(&"hide_spots")
	interactable.condition = _can_use
	interactable.interacted.connect(_on_interacted)
	_refresh_prompt()


## 09 §6: entering requires no error within 3 m. The HIDE prompt shows only when the
## player's state machine can enter Hidden now (not mid-noclip, stunned, landing...).
func _can_use(player: Node) -> bool:
	if occupant != null:
		return occupant == player
	if player != null and player.has_method(&"can_hide") and not bool(player.call(&"can_hide")):
		return false
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


## 11 §2 leave hide spot: the view mask lifts as the player starts to leave (the slide out
## takes 0.6 s, the occupant is cleared when it ends). M3.1: it used to lift with the slide's end.
func lift_view_mask() -> void:
	_show_mask(false)


func sound_id() -> StringName:
	return sound if sound != &"" else StringName("hide_%s" % kind)


func view_transform() -> Transform3D:
	return global_transform * view_offset


func exit_transform() -> Transform3D:
	return global_transform * exit_offset


func _refresh_prompt() -> void:
	if occupant == null:
		interactable.prompt = Strings.PROMPT_HIDE
		interactable.hold_time = 0.0
	else:
		interactable.prompt = Strings.PROMPT_LEAVE
		interactable.hold_time = Tuning.HIDE_LEAVE_HOLD_TIME


## True when this kind draws a view mask while occupied.
func has_mask() -> bool:
	return kind == KIND_LOCKER or MASK_CLEAR.has(kind)


## Reads the placement's params (the LevelPlacer calls this): `view_yaw_limit` in degrees.
func configure(params: Dictionary) -> void:
	if params.has(&"view_yaw_limit"):
		yaw_limit_deg = float(params[&"view_yaw_limit"])


func _show_mask(on: bool) -> void:
	if not has_mask():
		return
	if on and _mask == null:
		_mask = _build_locker_mask() if kind == KIND_LOCKER else _build_window_mask(MASK_CLEAR[kind])
		add_child(_mask)
	if _mask:
		_mask.visible = on


## Four black bars around the clear rect `clear` (0..1 screen space).
func _build_window_mask(clear: Rect2) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = MASK_CANVAS_LAYER
	var r := clear
	for e: Rect4 in [Rect4.new(0.0, 0.0, 1.0, r.position.y), Rect4.new(0.0, r.end.y, 1.0, 1.0),
			Rect4.new(0.0, r.position.y, r.position.x, r.end.y), Rect4.new(r.end.x, r.position.y, 1.0, r.end.y)]:
		if e.right <= e.left or e.bottom <= e.top:
			continue
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = e.left
		bar.anchor_right = e.right
		bar.anchor_top = e.top
		bar.anchor_bottom = e.bottom
		layer.add_child(bar)
	return layer


## An anchor rectangle (left, top, right, bottom) in 0..1.
class Rect4:
	var left: float
	var top: float
	var right: float
	var bottom: float

	func _init(l: float, t: float, r: float, b: float) -> void:
		left = l
		top = t
		right = r
		bottom = b


## 09 §6: a slatted view of 6 horizontal slits. Plain black bars until the
## locker_slats shader lands (M2); the slits sit in the middle third of the screen.
func _build_locker_mask() -> CanvasLayer:
	var layer := CanvasLayer.new()
	# Below the Coherence screen pass (-10), so grain and CA land on the mask too (14).
	layer.layer = MASK_CANVAS_LAYER
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
