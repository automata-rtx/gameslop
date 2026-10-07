class_name RingBuffer
extends RefCounted
## A fixed-capacity FIFO (08 Interfaces: `Player.step_trail() -> RingBuffer`). Pushing
## onto a full buffer drops the oldest entry. Index 0 is the oldest entry.
## The player's step trail holds Dictionaries {position: Vector3, time: float (s),
## surface: StringName, speed_kind: StringName (walk / sprint / crouch)} (08 §6).

var capacity: int

var _items: Array = []
var _head: int = 0   # index of the oldest entry once the buffer is full


func _init(cap: int) -> void:
	capacity = maxi(cap, 1)


func push(item: Variant) -> void:
	if _items.size() < capacity:
		_items.append(item)
	else:
		_items[_head] = item
		_head = (_head + 1) % capacity


func size() -> int:
	return _items.size()


func is_empty() -> bool:
	return _items.is_empty()


## The i-th entry, 0 = oldest. Negative indices count from the newest (-1 = newest).
func get_at(i: int) -> Variant:
	var n := _items.size()
	if i < 0:
		i += n
	if i < 0 or i >= n:
		return null
	return _items[(_head + i) % n]


func newest() -> Variant:
	return get_at(-1)


func oldest() -> Variant:
	return get_at(0)


## Entries oldest first (a copy).
func to_array() -> Array:
	var out: Array = []
	for i in _items.size():
		out.append(get_at(i))
	return out


func clear() -> void:
	_items.clear()
	_head = 0
