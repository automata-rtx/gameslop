class_name LoadoutData
extends Resource
## A starting kit (05 §7). Daily Descent always uses Faller.

@export var id: StringName = &""
@export var display_name: String = ""
## One line for the loadout card (04 §7).
@export var description: String = ""
## Starting belt: item kind -> count (chalk counts uses).
@export var start_items: Dictionary[StringName, int] = {}
@export var start_coherence: float = 100.0
@export var start_depth: int = 1
## Flashlight crank rate multiplier (Lightbearer 1.5).
@export var crank_rate_mult: float = 1.0
## Multiplier on the distance from which Flicker is attracted to the player's light
## (Lightbearer 1.5, 08 §5 Attached).
@export var flicker_attract_mult: float = 1.0
## Milestone unlock that makes the loadout selectable (05 §6). Empty = always.
@export var unlock_id: StringName = &""
