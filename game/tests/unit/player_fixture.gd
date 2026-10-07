class_name PlayerFixture
extends RefCounted
## Test helpers for the player suites: a floor, walls, and a spawned player.scn.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LOCKER_SCENE := "res://scenes/interactables/hide_spot_locker.tscn"
const ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"crouch",
	&"interact", &"flashlight", &"crank", &"noclip", &"use_item",
]


## A 40 x 40 m floor on the world layer under `parent`; returns its root.
static func make_world(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "TestWorld"
	parent.add_child(root)
	box(root, Vector3(40, 0.2, 40), Vector3(0, -0.1, 0))
	return root


static func box(parent: Node, size: Vector3, pos: Vector3, layer: int = PlayerLayers.WORLD_MASK) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos
	return body


## A wall body: a box on the world layer carrying the level builder's `wall_kind` meta
## (06 Interfaces), so noise attenuation counts it.
static func wall(parent: Node, size: Vector3, pos: Vector3, kind: StringName = &"interior") -> StaticBody3D:
	var b := box(parent, size, pos)
	b.set_meta(NoiseModel.WALL_META, kind)
	return b


static func spawn_player(world: Node3D, pos: Vector3 = Vector3.ZERO) -> Player:
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	world.add_child(p)
	p.global_position = pos
	return p


static func release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


## Horizontal speed of the player.
static func flat_speed(p: Player) -> float:
	return Vector3(p.velocity.x, 0.0, p.velocity.z).length()
