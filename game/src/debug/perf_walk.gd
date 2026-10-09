class_name PerfWalk
extends RefCounted
## The perf bench's player (M3.5, PerfBench): sprints back and forth along the first cells of
## the critical path through the player's own input actions, facing the next cell centre,
## so the hunters can close on one beat (a whole path outruns Echo's hearing). A body that
## has not moved a metre in STUCK_TIME (a door, a prop, a contact stun) is put on the next
## cell: the bench is about cost, not about walking well. Debug-only.

const STUCK_TIME := 1.5
const ARRIVE_DIST := 0.6
const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]

var player: Player
var route: Array[Vector3] = []
var _wp: int = 0
var _dir_step: int = 1
var _stuck_t: float = 0.0
var _stuck_from: Vector3 = Vector3.ZERO


## Cell centres of `cells` cells of `data`'s critical path from the spawn.
func _init(p_player: Player, data: LevelData, cells: int) -> void:
	player = p_player
	var path := data.critical_path
	for i in mini(path.size(), cells):
		route.append(data.grid.world_of(path[i]))


func drive(delta: float) -> void:
	if route.size() < 2 or not is_instance_valid(player):
		return
	var w := route[_wp]
	var to := Vector3(w.x - player.global_position.x, 0.0, w.z - player.global_position.z)
	if to.length() < ARRIVE_DIST:
		_advance()
		return
	var dir := to.normalized()
	player.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	Input.action_press(&"move_forward")
	if player.locomotion.stamina.is_locked_out():
		Input.action_release(&"sprint")
	else:
		Input.action_press(&"sprint")
	_stuck_t += delta
	if _stuck_t >= STUCK_TIME:
		if player.global_position.distance_to(_stuck_from) < 1.0:
			player.global_position = w
			_advance()
		_stuck_t = 0.0
		_stuck_from = player.global_position


func _advance() -> void:
	if _wp + _dir_step < 0 or _wp + _dir_step >= route.size():
		_dir_step = -_dir_step
	_wp += _dir_step


## Lets go of every movement key (the bench's teardown).
static func release() -> void:
	for a in ACTIONS:
		Input.action_release(a)
