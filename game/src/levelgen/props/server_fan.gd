class_name ServerFan
extends MergedProp
## A Server ceiling fan grille (02 §7 "Fans", 03 "Fan loop"): the rotor turns on a looped
## AnimationPlayer, each fan at its own phase (hashed from its position, so a level's fans
## are out of step but reproducible), and carries the fan loop when the sound exists.

@onready var anim: AnimationPlayer = %Anim

var _loop: AudioLoop


func _ready() -> void:
	super._ready()
	var h := posmod(hash(Vector3i((global_position * 10.0).round())), 1000)
	if anim.has_animation(&"spin"):
		anim.play(&"spin")
		anim.seek(anim.get_animation(&"spin").length * h / 1000.0, true)
	if AudioManager.has_sound(&"fan_loop"):
		_loop = AudioManager.loop(&"fan_loop", self)
		_loop.start(0.5)


func _exit_tree() -> void:
	if _loop != null:
		_loop.release()
		_loop = null
