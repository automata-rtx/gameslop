class_name ThresholdDoor
extends Exit
## The Threshold (01 §8, 02 §7, 07 §5.6): a plain white front door in a frame, standing alone
## at the centre of the Substrate's lit pocket, a 2 cm strip of daylight under it (the only
## warm light in the stratum). Its lock is always Open (07 §6 depth 6), but the leaf stays
## shut until the player walks into the doorway; then it swings outward, away from them, and
## the run takes them through. In a Descent that ends the run with cause `threshold`
## (RunLevelSetup.ends_descent) and plays the ending (M2.15, `scenes/ending.tscn`); in Endless
## it is a proper exit into Cycle 2 (05 §8).
## M2.15: while it stands in the level it tells MusicDirector.set_threshold_in_view (03 §5:
## A1's fifth while the Threshold is in view) whether the current camera sees it: in the
## frustum and not hidden by the world, at any distance (02 §7: it is seen from far away),
## checked at the exits' seen interval; leaving the tree turns the fifth off.

## Whether the Threshold was in view at the last check.
var in_view: bool = false
var _view_t: float = 0.0


## The leaf opens only for the player walking in (an Open lock would otherwise stand open).
func _move_leaves(open_: bool, time: float) -> void:
	super(open_ and is_entering, time)


func try_enter(player: Node3D) -> bool:
	if not super(player):
		return false
	_move_leaves(true, DOOR_OPEN_TIME)
	return true


## In `cam`'s frustum and not occluded by world geometry, at any distance (the exit's own
## frame and leaf never occlude it). Cells the Substrate left unbuilt hold no walls, so the
## door is seen across them.
func is_in_view(cam: Camera3D) -> bool:
	if cam == null or not is_inside_tree():
		return false
	var p := sight_point.global_position
	if not cam.is_position_in_frustum(p):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, PlayerLayers.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var collider := hit["collider"] as Node
	return collider != null and is_ancestor_of(collider)


func _process(delta: float) -> void:
	super(delta)
	_view_t -= delta
	if _view_t > 0.0:
		return
	_view_t = SEEN_INTERVAL
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_set_in_view(not is_entering and is_in_view(cam))


func _exit_tree() -> void:
	_set_in_view(false)


func _set_in_view(on: bool) -> void:
	if on == in_view:
		return
	in_view = on
	if AudioManager.music != null:
		AudioManager.music.set_threshold_in_view(on)
