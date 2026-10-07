class_name Interactable
extends Node
## The interaction component (06 §7, 09 Interfaces, 14 §6). Add it as a child of a
## CollisionObject3D on the `interactable` layer (4); the player's camera ray (2.2 m)
## finds it on whatever collider it hits. The host listens to `interacted` (signals up)
## and keeps `prompt` / `hold_time` current; it never needs to know who the player is.
## Contract: prompt_text() -> String, can_interact(player) -> bool, hold_time: float,
## interact(player).

signal interacted(player: Node)

## Prompt text without the key (the HUD adds "[E] " or "[HOLD E] "; 04 §6). Strings.PROMPT_*.
@export var prompt: String = ""
## Seconds the interact key must be held; 0 means a press (06 §7).
@export var hold_time: float = 0.0
@export var enabled: bool = true
## Optional extra gate: (player: Node) -> bool, e.g. a hide spot's "no error within 3 m".
var condition: Callable


func _enter_tree() -> void:
	add_to_group(&"interactables")


func prompt_text() -> String:
	return prompt


func can_interact(player: Node) -> bool:
	if not enabled or prompt.is_empty():
		return false
	if condition.is_valid():
		return bool(condition.call(player))
	return true


func interact(player: Node) -> void:
	if can_interact(player):
		interacted.emit(player)


## The Interactable on a ray hit: a direct child of the collider, or a node the collider
## names with the `interactable` meta (a NodePath relative to the collider).
static func find_on(collider: Object) -> Interactable:
	if not (collider is Node):
		return null
	var node := collider as Node
	for child in node.get_children():
		if child is Interactable:
			return child as Interactable
	if node.has_meta(&"interactable"):
		var target := node.get_node_or_null(node.get_meta(&"interactable") as NodePath)
		if target is Interactable:
			return target as Interactable
	return null
