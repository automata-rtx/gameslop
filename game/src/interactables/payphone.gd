class_name Payphone
extends Node3D
## The payphone (09 §5, Halls prop `payphone`). `[E] ANSWER` only while it rings. The Director
## rings it (10 §5, Scares.PAYPHONE): `ring()` starts the ring (2 s on, 4 s off, 03) and an 18 m
## door-class noise at the start of each ring, i.e. every 6 s, until it is answered or
## SCARE_PAYPHONE_RING_TIME (30 s) passes. Answering silences it and plays 2 s of line hum.
## Nothing speaks. Scene contract: %Collider (StaticBody3D, world + interactable) with
## %Interactable.

signal ringing_changed(on: bool)
signal answered

const GROUP := &"payphones"
const SOUND_RING := &"payphone_ring"
const SOUND_LINE := &"payphone_line"

@onready var collider: StaticBody3D = %Collider
@onready var interactable: Interactable = %Interactable

var ringing: bool = false
## Seconds since the ring began, and seconds until the next ring starts.
var ring_time: float = 0.0
var next_ring_in: float = 0.0
var ring_limit: float = Tuning.SCARE_PAYPHONE_RING_TIME
var _voice: AudioStreamPlayer3D = null


func _ready() -> void:
	add_to_group(GROUP)
	collider.collision_layer = PlayerLayers.WORLD_MASK | PlayerLayers.INTERACTABLE_MASK
	interactable.condition = _can_answer
	interactable.interacted.connect(_on_interacted)
	_refresh()


## Starts ringing for up to `seconds` (default 30 s). False when it already rings.
func ring(seconds: float = Tuning.SCARE_PAYPHONE_RING_TIME) -> bool:
	if ringing:
		return false
	ringing = true
	ring_time = 0.0
	next_ring_in = 0.0
	ring_limit = seconds
	_refresh()
	ringing_changed.emit(true)
	return true


## Answers: the ringing stops, two seconds of line hum. False when it is not ringing.
func answer(_player: Node = null) -> bool:
	if not ringing:
		return false
	_stop_ringing()
	if _voice != null and is_instance_valid(_voice):
		_voice.stop()
	_voice = AudioManager.play_3d(SOUND_LINE, global_position + Vector3(0.0, 1.3, 0.0))
	answered.emit()
	return true


func _can_answer(_player: Node) -> bool:
	return ringing


func _on_interacted(player: Node) -> void:
	answer(player)


func _physics_process(dt: float) -> void:
	if not ringing:
		return
	tick(dt)


## Advances the ring by `dt` seconds (public so tests step time).
func tick(dt: float) -> void:
	if not ringing:
		return
	ring_time += dt
	if ring_time >= ring_limit:
		_stop_ringing()
		return
	next_ring_in -= dt
	if next_ring_in <= 0.0:
		next_ring_in += Tuning.PAYPHONE_RING_ON_TIME + Tuning.PAYPHONE_RING_OFF_TIME
		var at := global_position + Vector3(0.0, 1.3, 0.0)
		NoiseModel.emit(global_position, Tuning.NOISE_PAYPHONE_RADIUS, Tuning.NOISE_KIND_DOOR)
		_voice = AudioManager.play_3d(SOUND_RING, at)


func _stop_ringing() -> void:
	if not ringing:
		return
	ringing = false
	if _voice != null and is_instance_valid(_voice):
		_voice.stop()
	_voice = null
	_refresh()
	ringing_changed.emit(false)


func _refresh() -> void:
	interactable.prompt = Strings.PROMPT_ANSWER if ringing else ""


## The payphones within the Director's ring distance (SCARE_PAYPHONE_DIST_MIN..MAX, 10 §5) of
## `from` that are not ringing, nearest first.
static func candidates(tree: SceneTree, from: Vector3) -> Array[Payphone]:
	var out: Array[Payphone] = []
	for n in tree.get_nodes_in_group(GROUP):
		var p := n as Payphone
		if p == null or p.ringing or not p.is_inside_tree():
			continue
		var d := p.global_position.distance_to(from)
		if d >= Tuning.SCARE_PAYPHONE_DIST_MIN and d <= Tuning.SCARE_PAYPHONE_DIST_MAX:
			out.append(p)
	out.sort_custom(func(a: Payphone, b: Payphone) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return out
