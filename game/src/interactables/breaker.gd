class_name Breaker
extends Node3D
## A wall box with a lever (09 §5 "Breaker", 07 §6 Powered lock). Hold interact 0.6 s:
## the lever animates 0.3 s, the clunk, a 25 m `mech` noise, EventBus.breaker_thrown(pos).
## The run answers the bus event with the power wave (wave_delays below) and the exit.
## Variant B (07 §6, unlock #4): an empty fuse socket; the player inserts a carried fuse
## (0.8 s) before the lever can be thrown, and can pull it back out (0.8 s) at any time: a
## small socket collider (%Socket, %SocketInteractable) offers `[HOLD E] PULL FUSE` while the
## fuse is in and the belt can take it. 08 §5: pulling it after the throw trips the breaker
## (the lever springs back up, `power_cut`: the run unpowers the floor and seals the exit);
## inserting it again re-runs the throw (lever, 25 m `mech` noise, the power wave).
## Scene contract: %Pivot (lever hinge), %Lamp (indicator), %Body (StaticBody3D on world +
## interactable) with %Interactable, %Socket (StaticBody3D, layer set here) with
## %SocketInteractable.

signal thrown(pos: Vector3)
## Variant B: the fuse was pulled after the throw (08 §5). The run cuts the wave's power.
signal power_cut(pos: Vector3)

const VARIANT_A := &"a"
const VARIANT_B := &"b"
const FUSE := &"fuse"
const LEVER_UP_DEG := -35.0
const LEVER_DOWN_DEG := 35.0
const LAMP_OFF := 0.0
const LAMP_ON := 3.0

@export var variant: StringName = VARIANT_A

@onready var pivot: Node3D = %Pivot
@onready var lamp: MeshInstance3D = %Lamp
@onready var body: StaticBody3D = %Body
@onready var interactable: Interactable = %Interactable
@onready var socket: StaticBody3D = %Socket
@onready var socket_interactable: Interactable = %SocketInteractable

var is_thrown: bool = false
var fuse_in: bool = true
## Variant B: the fuse was pulled after a throw; inserting it re-runs the throw (08 §5).
var tripped: bool = false
var _lamp_mat: ShaderMaterial
var _fuse_model: Node3D


func _ready() -> void:
	add_to_group(&"breakers")
	body.set_meta(&"wall_kind", &"PROP")
	pivot.rotation.x = deg_to_rad(LEVER_UP_DEG)
	if lamp.material_override is ShaderMaterial:
		_lamp_mat = lamp.material_override.duplicate() as ShaderMaterial
		lamp.material_override = _lamp_mat
		_lamp_mat.set_shader_parameter(&"emission_strength", LAMP_OFF)
	fuse_in = variant != VARIANT_B
	interactable.condition = _offers
	interactable.interacted.connect(_on_interacted)
	_refresh_prompt(null)
	socket_interactable.condition = _socket_offers
	socket_interactable.interacted.connect(_on_socket_interacted)
	_fuse_model = ItemModels.held(&"fuse")
	_fuse_model.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ItemModels.set_held(_fuse_model, false)
	socket.add_child(_fuse_model)
	_sync_socket()


## What the box offers this player: the lever, or (Variant B) inserting a carried fuse.
func _offers(player: Node) -> bool:
	if is_thrown:
		return false
	_refresh_prompt(player)
	if fuse_in:
		return true
	# 09 §5: without a fuse the box still offers its dim, keyless FUSE MISSING notice
	# (the HUD routes it by text); interacting then does nothing (_on_interacted).
	return true


func _refresh_prompt(player: Node) -> void:
	if fuse_in:
		interactable.prompt = Strings.PROMPT_FLIP_BREAKER
		interactable.hold_time = Tuning.BREAKER_HOLD_TIME
	else:
		interactable.prompt = Strings.PROMPT_INSERT_FUSE if player == null or _carries_fuse(player) else Strings.PROMPT_FUSE_MISSING
		var has := player == null or _carries_fuse(player)
		interactable.hold_time = Tuning.FUSE_INSERT_TIME if has else 0.0


static func _carries_fuse(player: Node) -> bool:
	var inv := Inventory.of(player) if player != null else null
	return inv != null and inv.has(FUSE)


func _on_interacted(player: Node) -> void:
	if not fuse_in:
		insert_fuse(player)
		return
	throw_breaker()


## 09 §2: puts the carried fuse in the socket (Variant B). Returns false without one.
## After a trip (08 §5) the breaker throws again by itself.
func insert_fuse(player: Node) -> bool:
	if fuse_in or is_thrown:
		return false
	var inv := Inventory.of(player)
	if inv == null or inv.consume(FUSE, 1) <= 0:
		return false
	fuse_in = true
	AudioManager.play_3d(&"fuse_insert", global_position + Vector3(0.0, 1.2, -0.3))
	_refresh_prompt(player)
	_sync_socket()
	if tripped:
		tripped = false
		throw_breaker()
	return true


## 09 §2, 08 §5: pulls the fuse back out onto the belt. False when it is not in or the belt
## cannot take it. After the throw it trips the breaker: the lever springs back up, the lamp
## goes out and `power_cut` asks the run to unpower the floor and seal the exit.
func pull_fuse(player: Node) -> bool:
	if variant != VARIANT_B or not fuse_in:
		return false
	var inv := Inventory.of(player)
	if inv == null or inv.add(FUSE, 1) <= 0:
		return false
	fuse_in = false
	AudioManager.play_3d(&"fuse_pull", global_position + Vector3(0.0, 1.2, -0.3))
	if is_thrown:
		_trip()
	_refresh_prompt(player)
	_sync_socket()
	return true


func _trip() -> void:
	is_thrown = false
	tripped = true
	interactable.enabled = true
	var tw := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(pivot, ^"rotation:x", deg_to_rad(LEVER_UP_DEG), Tuning.BREAKER_LEVER_TIME)
	if _lamp_mat != null:
		_lamp_mat.set_shader_parameter(&"emission_strength", LAMP_OFF)
	power_cut.emit(global_position)


func _socket_offers(player: Node) -> bool:
	var inv := Inventory.of(player) if player != null else null
	return variant == VARIANT_B and fuse_in and inv != null and inv.can_accept(FUSE)


func _on_socket_interacted(player: Node) -> void:
	pull_fuse(player)


## The socket collider answers only a Variant B box (thrown or not, 08 §5); the fuse shows
## while it is in.
func _sync_socket() -> void:
	var live := variant == VARIANT_B
	socket.collision_layer = PlayerLayers.INTERACTABLE_MASK if live else 0
	_fuse_model.visible = variant == VARIANT_B and fuse_in


## Throws the lever (09 §5). Returns false when already thrown or the fuse is missing.
func throw_breaker() -> bool:
	if is_thrown or not fuse_in:
		return false
	is_thrown = true
	interactable.enabled = false
	_sync_socket()
	var tw := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(pivot, ^"rotation:x", deg_to_rad(LEVER_DOWN_DEG), Tuning.BREAKER_LEVER_TIME)
	if _lamp_mat != null:
		_lamp_mat.set_shader_parameter(&"emission_strength", LAMP_ON)
	var pos := global_position
	AudioManager.play_3d(&"breaker_lever", pos)
	NoiseModel.emit(pos, Tuning.NOISE_BREAKER_RADIUS, Tuning.NOISE_KIND_MECH)
	EventBus.breaker_thrown.emit(pos)
	thrown.emit(pos)
	return true


## 02 §6 power wave: the seconds after the throw at which each position lights. The wave
## travels at 12 m/s by walking distance from `from_cell` (07 grid; a straight line where
## the grid gives no path), with a 40 ms stagger per fixture in arrival order.
static func wave_delays(grid: LevelGrid, from_cell: Vector2i, positions: Array[Vector3]) -> PackedFloat32Array:
	var dist := grid.distance_field(from_cell) if grid != null else PackedInt32Array()
	var origin := grid.world_of(from_cell) if grid != null else Vector3.ZERO
	var metres := PackedFloat32Array()
	for p in positions:
		metres.append(walking_distance(grid, dist, origin, p))
	var order: Array[int] = []
	for i in positions.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return metres[a] < metres[b])
	var out := PackedFloat32Array()
	out.resize(positions.size())
	for rank in order.size():
		var i := order[rank]
		out[i] = metres[i] / Tuning.LIGHT_BREAKER_WAVE_SPEED + rank * Tuning.LIGHT_BREAKER_STAGGER_MS / 1000.0
	return out


## Metres of walking from the field's origin to `p` (cell steps × 2 m plus the offset inside
## the cell), or the straight line when `p` is off the walkable grid.
static func walking_distance(grid: LevelGrid, dist: PackedInt32Array, origin: Vector3, p: Vector3) -> float:
	if grid == null or dist.is_empty():
		return Vector2(p.x - origin.x, p.z - origin.z).length()
	var c := grid.cell_of(p)
	if not grid.in_bounds(c) or dist[grid.idx(c)] < 0:
		return Vector2(p.x - origin.x, p.z - origin.z).length()
	var centre := grid.world_of(c)
	return dist[grid.idx(c)] * Tuning.GRID_CELL_SIZE + Vector2(p.x - centre.x, p.z - centre.z).length()
