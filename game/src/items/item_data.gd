class_name ItemData
extends Resource
## Defines one item kind (09 §2). Immutable at runtime: per-instance state (radio charge,
## flare burning) lives in ItemSlot.state, never here.
## Interface (09): kind, display_name, glyph, cap, use_time, held_scene, world_scene, weight, unlock_id.

@export var kind: StringName = &""
## Uppercase, as printed in prompts and the belt (`[E] PICK UP GLOWSTICK`).
@export var display_name: String = ""
@export var glyph: Texture2D
## Belt stack cap. Chalk counts uses (one stack, cap 20).
@export var cap: int = 1
## Seconds the use action takes (09 §1: never more than 1.2).
@export var use_time: float = 0.0
@export var held_scene: PackedScene
@export var world_scene: PackedScene
## Pool weight before unlock gating (09 §2). 0 = never placed by the pool.
@export var weight: int = 0
## Unlock id that gates the item in the pool (05 §6). Empty = always available.
@export var unlock_id: StringName = &""

# Fields implied by 09 but not named in its Interfaces section.
## False for the keycard (a key, not a belt item).
@export var belt_item: bool = true
## How much one world pickup adds (chalk: 8 uses; everything else 1).
@export var pickup_count: int = 1
## Colour of the faint pickup light (09 §2, "lit by a faint OmniLight3D of their colour").
@export var world_light_color: Color = Color.WHITE
