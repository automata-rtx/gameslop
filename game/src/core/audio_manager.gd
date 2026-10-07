extends Node
## Sample playback, buses, reverb per stratum, ducking, and the pool of 32
## AudioStreamPlayer3D (03 Interfaces, 14 §3). No game logic.
## TODO(M1.11): everything below; it also listens to EventBus.noise_emitted so a
## noise and its sound are the same event (03 Interfaces).

var _warned: Dictionary = {}


func _ready() -> void:
	# 11 §4: pulse audio keeps playing through hitstop and the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS


func play_3d(id: StringName, _pos: Vector3, _bus: StringName = &"Errors") -> void:
	_todo("play_3d(%s) (M1.11)" % id)


func play_2d(id: StringName) -> void:
	_todo("play_2d(%s) (M1.11)" % id)


func start_loop(id: StringName, _node: Node3D) -> AudioStreamPlayer3D:
	_todo("start_loop(%s) (M1.11)" % id)
	return null


## Swaps the World reverb and room tone (03 §3).
func set_stratum(stratum: StringName) -> void:
	_todo("set_stratum(%s) (M1.11)" % stratum)


func duck(bus: StringName, db: float, seconds: float) -> void:
	_todo("duck(%s, %s, %s) (M1.11)" % [bus, db, seconds])


func _todo(what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("not implemented: AudioManager.%s" % what)
