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
		AudioCull.mark(_loop)
	_cull_spin()


## M3.5: the rotor animates only while the grille is on screen (a Server level hangs ~36;
## off screen nobody sees the spin). The enabler disables the AnimationPlayer's processing
## until the renderer reports the grille visible.
func _cull_spin() -> void:
	var en := VisibleOnScreenEnabler3D.new()
	en.name = "SpinOnScreen"
	en.aabb = AABB(Vector3(-0.45, -0.1, -0.45), Vector3(0.9, 0.2, 0.9))
	en.enable_node_path = NodePath("../" + String(get_path_to(anim)))
	add_child(en)


func _exit_tree() -> void:
	if _loop != null:
		_loop.release()
		_loop = null
