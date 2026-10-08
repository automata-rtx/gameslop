class_name RoomData
extends RefCounted
## One room of a level (07 §2): a rectangle of ROOM cells with a kind and a fixture group.

const GENERIC := &"generic"
const SPAWN := &"spawn"
const EXIT := &"exit"
const BREAKER := &"breaker"
const CLOSET := &"closet"
## The Substrate's Threshold pocket (07 §5.6): the exit room, 3x3, lit, the door standing alone.
const POCKET := &"pocket"

var id: int = -1
var rect: Rect2i = Rect2i()
## generic, spawn, exit, breaker, closet, pool_hall, pump, office_open, office_small,
## meeting, cage, pocket (07 §2).
var kind: StringName = GENERIC
var fixture_group: int = -1
## Openings in the room's perimeter: Vector3i(x, z, dir) of the room-side cell and edge.
var doors: Array[Vector3i] = []


func _init(room_rect: Rect2i = Rect2i(), room_kind: StringName = GENERIC) -> void:
	rect = room_rect
	kind = room_kind


func has_cell(c: Vector2i) -> bool:
	return rect.has_point(c)


func center() -> Vector2i:
	return rect.position + rect.size / 2


## Every cell of the rectangle, row by row.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, z))
	return out


## Perimeter edges of the room: Vector3i(x, z, dir) for each inside cell edge facing out.
func perimeter_edges() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c in cells():
		for d in 4:
			if not rect.has_point(c + LevelGrid.DIRS[d]):
				out.append(Vector3i(c.x, c.y, d))
	return out
