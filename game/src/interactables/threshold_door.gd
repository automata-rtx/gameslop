class_name ThresholdDoor
extends Exit
## The Threshold (01 §8, 02 §7, 07 §5.6): a plain white front door in a frame, standing alone
## at the centre of the Substrate's lit pocket, a 2 cm strip of daylight under it (the only
## warm light in the stratum). Its lock is always Open (07 §6 depth 6), but the leaf stays
## shut until the player walks into the doorway; then it swings outward, away from them, and
## the run takes them through. In a Descent that ends the run with cause `threshold`
## (RunLevelSetup.ends_descent; the ending scene is M2.15's); in Endless it is a proper exit
## into Cycle 2 (05 §8).


## The leaf opens only for the player walking in (an Open lock would otherwise stand open).
func _move_leaves(open_: bool, time: float) -> void:
	super(open_ and is_entering, time)


func try_enter(player: Node3D) -> bool:
	if not super(player):
		return false
	_move_leaves(true, DOOR_OPEN_TIME)
	return true
