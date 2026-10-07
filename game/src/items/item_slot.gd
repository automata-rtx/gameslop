class_name ItemSlot
extends RefCounted
## One belt slot (09 §1, Interfaces): the kind it holds, how many, and the mutable
## per-instance state (radio charge, flare burning, fuse; Polaroid image queue). Never held
## by an ItemData: that resource is shared and immutable.

var kind: StringName = &""
## Stack size. Chalk counts uses (one stack, cap 20).
var count: int = 0
## Polaroid: `images` is an Array[int] of the photo indices of the held Polaroids, oldest first.
var state: Dictionary = {}


func _init(k: StringName = &"", n: int = 0, s: Dictionary = {}) -> void:
	kind = k
	count = n
	state = s.duplicate(true)


func is_empty() -> bool:
	return kind == &"" or count <= 0


func copy() -> ItemSlot:
	return ItemSlot.new(kind, count, state)


## Folds `extra` state into this slot's: arrays append, anything else keeps the existing value.
func merge_state(extra: Dictionary) -> void:
	for key: Variant in extra:
		var v: Variant = extra[key]
		if v is Array and state.get(key) is Array:
			(state[key] as Array).append_array(v as Array)
		elif not state.has(key):
			state[key] = v.duplicate(true) if v is Array or v is Dictionary else v
