class_name LevelPlacer
extends RefCounted
## Turns LevelData placements (07 §2) into nodes for LevelBuilder: prefabs for fixtures,
## props, hide spots and doors, and Marker3D placeholders for everything whose interactive
## version arrives later (exit, breaker, keycard, items, notes: M1.9/M1.10; error spawns:
## the Director). A marker is in the group `placement_<kind>` (and `error_spawns` for
## error spawns) and carries the placement dictionary as meta `placement`.
## Yaw convention: a placement's yaw turns a node's -Z towards the facing direction, so
## prefabs face -Z (props, fixtures); the locker faces +Z and gets yaw + PI.

const GROUP_PREFIX := "placement_"
const GROUP_ERROR_SPAWNS := &"error_spawns"
const META_PLACEMENT := &"placement"
const PROPS_DIR := "res://scenes/props/%s/%s.tscn"
const DOOR_SCENE := "res://scenes/props/shared/door.tscn"
const HIDE_SPOT_SCENES: Dictionary = {&"locker": "res://scenes/interactables/hide_spot_locker.tscn"}

## Kinds that become markers (interactive versions come later).
const MARKER_KINDS: Array[StringName] = [LevelData.P_SPAWN, LevelData.P_EXIT, LevelData.P_BREAKER,
	LevelData.P_KEYCARD, LevelData.P_ITEM, LevelData.P_NOTE, LevelData.P_ERROR_SPAWN]

var level: LevelData
var stratum: StratumData
var pool: LightPool
var _scenes: Dictionary = {}


func _init(level_data: LevelData, data: StratumData, light_pool: LightPool) -> void:
	level = level_data
	stratum = data
	pool = light_pool


static func group_of(kind: StringName) -> StringName:
	return StringName(GROUP_PREFIX + String(kind))


## Every scene this level will instance, so the builder can load them on a worker thread
## before the first slice (a first-time load() is tens of milliseconds).
func scene_paths() -> PackedStringArray:
	var out := PackedStringArray([DOOR_SCENE])
	if stratum.fixture_prefab_path != "":
		out.append(stratum.fixture_prefab_path)
	for p in level.placements:
		var params: Dictionary = p[&"params"]
		var path := ""
		if p[&"kind"] == LevelData.P_PROP:
			path = PROPS_DIR % [stratum.id, params.get(&"prop", &"")]
		elif p[&"kind"] == LevelData.P_HIDE_SPOT:
			path = HIDE_SPOT_SCENES.get(params.get(&"kind", &"locker"), "")
		if path != "" and not out.has(path) and ResourceLoader.exists(path):
			out.append(path)
	return out


## Hands a scene loaded elsewhere (threaded) to the placer's cache.
func provide(path: String, scene: PackedScene) -> void:
	_scenes[path] = scene


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


func _xform(p: Dictionary, extra_yaw: float = 0.0) -> Transform3D:
	var c: Vector2i = p[&"cell"]
	var pos := level.grid.world_of(c) + (p[&"offset"] as Vector3)
	return Transform3D(Basis(Vector3.UP, float(p[&"yaw"]) + extra_yaw), pos)


## Places one placement under the matching container. Returns the node (or null).
func place(p: Dictionary, containers: Dictionary) -> Node3D:
	var kind: StringName = p[&"kind"]
	if MARKER_KINDS.has(kind):
		return _marker(p, containers[&"markers"])
	match kind:
		LevelData.P_FIXTURE:
			return _fixture(p, containers[&"fixtures"])
		LevelData.P_PROP:
			return _prop(p, containers[&"furniture"])
		LevelData.P_HIDE_SPOT:
			return _hide_spot(p, containers[&"furniture"])
		LevelData.P_WATER:
			return _water(p, containers.get(&"water", containers[&"furniture"]))
	push_warning("LevelPlacer: no builder for placement kind %s" % kind)
	return null


func _marker(p: Dictionary, parent: Node3D) -> Node3D:
	var m := Marker3D.new()
	var c: Vector2i = p[&"cell"]
	m.name = "%s_%d_%d" % [String(p[&"kind"]).capitalize().replace(" ", ""), c.x, c.y]
	m.transform = _xform(p)
	m.set_meta(META_PLACEMENT, p)
	m.add_to_group(group_of(p[&"kind"]))
	if p[&"kind"] == LevelData.P_ERROR_SPAWN:
		m.add_to_group(GROUP_ERROR_SPAWNS)
	parent.add_child(m)
	return m


func _fixture(p: Dictionary, parent: Node3D) -> Node3D:
	var scene := _scene(stratum.fixture_prefab_path)
	if scene == null:
		return null
	var f := scene.instantiate() as Fixture
	var c: Vector2i = p[&"cell"]
	f.name = "Fixture_%d_%d_%d" % [c.x, c.y, parent.get_child_count()]
	var t := _xform(p)
	# T2: tubes run along the corridor; rooms keep one orientation.
	if level.grid.kind(c) == LevelGrid.FLOOR:
		var along_x := level.grid.can_step(c, LevelGrid.E) or level.grid.can_step(c, LevelGrid.W)
		var along_z := level.grid.can_step(c, LevelGrid.N) or level.grid.can_step(c, LevelGrid.S)
		if along_x and not along_z:
			t.basis = Basis(Vector3.UP, PI * 0.5)
	f.transform = t
	f.group_id = int((p[&"params"] as Dictionary).get(&"group", -1))
	parent.add_child(f)
	pool.register_fixture(f)
	return f


func _prop(p: Dictionary, parent: Node3D) -> Node3D:
	var prop: StringName = (p[&"params"] as Dictionary).get(&"prop", &"")
	var scene := _scene(PROPS_DIR % [stratum.id, prop])
	if scene == null:
		return _marker(p, parent)
	var n := scene.instantiate() as Node3D
	var c: Vector2i = p[&"cell"]
	n.name = "%s_%d_%d" % [String(prop).capitalize().replace(" ", ""), c.x, c.y]
	n.transform = _xform(p)
	n.set_meta(META_PLACEMENT, p)
	n.add_to_group(&"props")
	_tag_bodies(n, {&"prop": prop, &"wall_kind": &"PROP"})
	if prop == &"wall_clock":
		_freeze_clock(n, c)
	parent.add_child(n)
	return n


## 09 §7: clock hands frozen at a hashed time.
func _freeze_clock(n: Node3D, c: Vector2i) -> void:
	var minutes := posmod(hash(Vector3i(c.x, c.y, level.level_seed)), 720)
	var hour := n.get_node_or_null(^"%HourHand") as Node3D
	var minute := n.get_node_or_null(^"%MinuteHand") as Node3D
	# The face looks along -Z; hands turn about Z, clockwise as seen from the front.
	if hour != null:
		hour.rotation.z = TAU * minutes / 720.0
	if minute != null:
		minute.rotation.z = TAU * (minutes % 60) / 60.0


func _hide_spot(p: Dictionary, parent: Node3D) -> Node3D:
	var kind: StringName = (p[&"params"] as Dictionary).get(&"kind", &"locker")
	var scene := _scene(HIDE_SPOT_SCENES.get(kind, ""))
	if scene == null:
		return _marker(p, parent)
	var n := scene.instantiate() as Node3D
	var c: Vector2i = p[&"cell"]
	n.name = "HideSpot_%d_%d" % [c.x, c.y]
	n.transform = _xform(p, PI)
	n.set_meta(META_PLACEMENT, p)
	_tag_bodies(n, {&"wall_kind": &"PROP"})
	parent.add_child(n)
	return n


## 07 §8 water: one WaterVolume (surface mesh and the water-layer Area3D) per wet basin.
func _water(p: Dictionary, parent: Node3D) -> Node3D:
	var params: Dictionary = p[&"params"]
	var w := WaterVolume.new()
	w.setup(params[&"rect"], float(params[&"surface_y"]), float(params[&"floor_y"]),
		LevelMaterials.for_class(stratum, LevelMaterials.C_WATER))
	w.set_meta(META_PLACEMENT, p)
	parent.add_child(w)
	return w


## 09 §5 doors: one prefab per DOOR edge, centred in the edge strip. Closet doors start
## closed (they are hide spot hosts); other doors start open.
func door(c: Vector2i, dir: int, parent: Node3D) -> Node3D:
	var scene := _scene(DOOR_SCENE)
	if scene == null:
		return null
	var d := scene.instantiate() as Door
	var dv := LevelGrid.DIRS[dir]
	var pos := level.grid.world_of(c) + Vector3(dv.x, 0.0, dv.y) * Tuning.GRID_CELL_SIZE * 0.5
	d.name = "Door_%d_%d_%s" % [c.x, c.y, LevelGrid.DIR_NAMES[dir]]
	d.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 if dv.x != 0 else 0.0), pos)
	var room_a := level.grid.room_of(c)
	var room_b := level.grid.room_of(c + dv)
	var closet := (room_a != null and room_a.kind == RoomData.CLOSET) or (room_b != null and room_b.kind == RoomData.CLOSET)
	d.start_open = not closet
	parent.add_child(d)
	d.set_edge_meta(BuildCollision.wall_meta(level.grid, c, dir))
	d.apply_materials(LevelMaterials.for_class(stratum, BuildPlan.C_WALL),
		LevelMaterials.for_class(stratum, LevelMaterials.C_DOOR_LEAF),
		LevelMaterials.for_class(stratum, LevelMaterials.C_DOOR_HANDLE))
	d.grid = level.grid
	return d


## Props' and lockers' static bodies are world geometry (layer 1) without wall metadata
## of a grid edge; a `wall_kind` of PROP lets noise counting tell them from walls.
static func _tag_bodies(n: Node, meta: Dictionary) -> void:
	if n is StaticBody3D:
		for k in meta:
			if not n.has_meta(k):
				n.set_meta(k, meta[k])
	for child in n.get_children():
		_tag_bodies(child, meta)
