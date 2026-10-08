class_name PoolDrip
extends Node3D
## A drip from a Pools ceiling (02 §10, 03 "Drip"): one droplet falls from this point every
## DRIP_PERIOD seconds and ticks on the floor below (the fall height is the placement's
## offset above its cell's floor). Cosmetic; the phase is hashed from the position so a
## level's drips are out of step but reproducible.

const DRIP_PERIOD := 4.0
const GRAVITY := 9.8

@onready var particles: GPUParticles3D = %Drops

var _fall: float = 6.0
var _t: float = 0.0


func _ready() -> void:
	var p: Dictionary = get_meta(LevelPlacer.META_PLACEMENT, {})
	var off: Vector3 = p.get(&"offset", Vector3(0.0, _fall, 0.0))
	_fall = maxf(0.5, off.y)
	particles.lifetime = DRIP_PERIOD
	_t = float(posmod(hash(Vector3i((global_position * 10.0).round())), 1000)) / 1000.0 * DRIP_PERIOD


func _process(delta: float) -> void:
	_t += delta
	if _t < DRIP_PERIOD:
		return
	_t -= DRIP_PERIOD
	var land := sqrt(2.0 * _fall / GRAVITY)
	get_tree().create_timer(land).timeout.connect(func() -> void:
		if is_inside_tree():
			AudioManager.play_3d(&"drip", global_position - Vector3(0.0, _fall, 0.0)))
