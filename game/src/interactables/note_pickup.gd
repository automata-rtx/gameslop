class_name NotePickup
extends Node3D
## A note lying on the floor (09 §5 "Note", 01 §6): `[E] READ` emits EventBus.note_found(id)
## (the HUD listens and types the sheet, 04 §8; the audio manager ducks the music for it), plays
## the paper slide, and removes the paper from the world. Which note it is comes from the
## spawner (`note_id`). Same scene contract as ItemPickup: Body on layers 4 + 5, Interactable,
## and a faint white light so the paper can be found in the dark.

const BODY_LAYERS := PlayerLayers.INTERACTABLE_MASK | (1 << 4)
const SOUND := &"note_pickup"
const FADE_TIME := 0.15

@export var note_id: StringName = &""

@onready var body: StaticBody3D = %Body
@onready var interactable: Interactable = %Interactable
@onready var paper: Node3D = %Paper
@onready var light: OmniLight3D = %Light

var read_done: bool = false


func _ready() -> void:
	add_to_group(&"note_pickups")
	body.collision_layer = BODY_LAYERS
	light.light_energy = Tuning.ITEM_WORLD_LIGHT_ENERGY
	light.omni_range = Tuning.ITEM_WORLD_LIGHT_RANGE
	light.shadow_enabled = false
	interactable.prompt = Strings.PROMPT_READ
	interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node) -> void:
	read()


## Reads the note: announce it, slide the paper away, free the pickup. False when already read
## or the pickup carries no note.
func read() -> bool:
	if read_done or note_id == &"":
		return false
	read_done = true
	interactable.enabled = false
	body.set_deferred(&"collision_layer", 0)
	AudioManager.play_2d(SOUND)
	EventBus.note_found.emit(note_id)
	if not is_inside_tree():
		queue_free()
		return true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(paper, "scale", Vector3.ONE * 0.05, FADE_TIME)
	tw.tween_property(light, "light_energy", 0.0, FADE_TIME)
	tw.chain().tween_callback(queue_free)
	return true
