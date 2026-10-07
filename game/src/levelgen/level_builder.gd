class_name LevelBuilder
extends Node
## LevelData -> nodes (07 §8, 14 §5). The geometry plan (BuildPlan) is computed on a
## worker thread; nodes are made on the main thread in slices of at most 4 ms per frame
## (14 §10). Then the navigation mesh bakes on a worker thread (threaded bake, 07 §8).
##   var b := LevelBuilder.new(); add_child(b)
##   await b.build(level, parent)       # resolves on `built` (after the navigation bake)
## `geometry_built` fires first: the level is walkable from then on; errors stay dormant
## until `built` (07 §3; on a failed bake `navigation_ok` is false and the level is still
## winnable, 14 §12).
##
## Collision (07 §7, §8): StaticBody3D per chunk and kind on layer 1, one BoxShape3D per
## floor cell / wall edge through shape owners (no CollisionShape3D nodes). Bodies carry
## `surface` (floors) or `wall_kind` (walls: the 07 §2 type name), and `shape_meta`, a
## Dictionary shape owner id -> {cell, dir, wall_type, wall_kind, thickness, other_cell,
## walkable, other_walkable} (floors: {cell, kind}); read it with `shape_info()`.

signal geometry_built
signal navigation_baked(ok: bool)
signal built

## Floor `surface` meta per stratum (06 §6 noise by surface).
const FLOOR_SURFACE: Dictionary = {&"halls": &"carpet"}

var level: LevelData
var stratum: StratumData
var plan: BuildPlan
## Provided by level.tscn; created under the parent when absent.
var light_pool: LightPool
var nav_region: NavigationRegion3D

var is_geometry_built: bool = false
var is_built: bool = false
var navigation_ok: bool = false
## Stats for tests and the debug overlay.
var max_slice_ms: float = 0.0
var slice_ms: PackedFloat32Array = PackedFloat32Array()
var slices: int = 0
var plan_ms: float = 0.0
var bake_ms: float = 0.0
var slowest_job_ms: float = 0.0
var slowest_job: StringName = &""
var spawn_transform: Transform3D = Transform3D.IDENTITY

var _parent: Node3D
var _containers: Dictionary = {}
var _jobs: Array[Callable] = []
## Per job: a cost class key (method plus what it makes), and the last cost per key in µs.
var _job_keys: Array[StringName] = []
var _job_cost: Dictionary = {}
var _task_id: int = -1
var _plan_result: BuildPlan
var _bodies: Dictionary = {}
var _shapes: Dictionary = {}
var _materials: Dictionary = {}
var _soft_nodes: Dictionary = {}
var _placer: LevelPlacer
var _loading: PackedStringArray = PackedStringArray()
var _preloaded: Array[Resource] = []
var _bake_started_us: int = 0
var _plan_started_us: int = 0


## Starts building `level_data` under `parent`. Returns the `built` signal.
func build(level_data: LevelData, parent: Node3D) -> Signal:
	level = level_data
	_parent = parent
	stratum = load("res://data/strata/%s.tres" % level.stratum) as StratumData
	var h := float(Tuning.STRATUM_CEILING_HEIGHT.get(level.stratum, stratum.height))
	for n in [&"geometry", &"bodies", &"soft_walls", &"furniture", &"fixtures", &"doors", &"markers"]:
		var c := Node3D.new()
		c.name = String(n).to_pascal_case()
		parent.add_child(c)
		_containers[n] = c
	if light_pool == null:
		light_pool = LightPool.new()
		light_pool.name = "LightPool"
		parent.add_child(light_pool)
		light_pool.configure(stratum)
	if nav_region == null:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "Navigation"
		parent.add_child(nav_region)
	light_pool.grid = level.grid
	_placer = LevelPlacer.new(level, stratum, light_pool)
	var paths := _placer.scene_paths()
	for path: String in LevelMaterials.paths(level.stratum):
		paths.append(path)
	for path in paths:
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading.append(path)
	_plan_started_us = Time.get_ticks_usec()
	_task_id = WorkerThreadPool.add_task(func() -> void: _plan_result = BuildPlan.make(level_data, h),
		false, "BuildPlan")
	set_process(true)
	return built


func _process(_delta: float) -> void:
	if not _loading.is_empty() and not _poll_loads():
		return
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		plan = _plan_result
		plan_ms = (Time.get_ticks_usec() - _plan_started_us) / 1000.0
		if plan == null:
			_fail("the geometry plan failed")
			return
		_queue_jobs()
	if _jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var budget := Tuning.LEVELBUILD_SLICE_MS * 1000.0 * Tuning.LEVELBUILD_SLICE_HEADROOM
	var first := true
	while not _jobs.is_empty():
		# A job kind not measured yet runs only first in a slice; a known kind runs only
		# when its last measured cost still fits the slice.
		var key: StringName = _job_keys[0]
		var spent := Time.get_ticks_usec() - t0
		if not first and spent + float(_job_cost.get(key, budget)) > budget:
			break
		first = false
		var job: Callable = _jobs.pop_front()
		_job_keys.remove_at(0)
		var j0 := Time.get_ticks_usec()
		job.call()
		var us := Time.get_ticks_usec() - j0
		_job_cost[key] = us
		if us / 1000.0 > slowest_job_ms:
			slowest_job_ms = us / 1000.0
			slowest_job = key
	slices += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	slice_ms.append(ms)
	max_slice_ms = maxf(max_slice_ms, ms)


## A build that cannot finish still resolves (14 §12: never hang the Landing).
func _fail(why: String) -> void:
	push_error("LevelBuilder: %s" % why)
	set_process(false)
	is_geometry_built = true
	is_built = true
	navigation_ok = false
	geometry_built.emit()
	navigation_baked.emit(false)
	built.emit()


## True when every prefab scene and material has loaded (failed loads fall back to load() later).
func _poll_loads() -> bool:
	for path in _loading:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	for path in _loading:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path)
			if res is PackedScene:
				_placer.provide(path, res as PackedScene)
			else:
				_preloaded.append(res)  # held so load() below hits the cache
	_loading.clear()
	return true


## Jobs are small (one mesh, a few dozen shapes, one prefab) so a slice stops near 3 ms.
func _queue_jobs() -> void:
	for m in plan.meshes:
		_job(_make_mesh.bind(m), &"mesh")
	var by_body: Dictionary = {}
	for b in plan.boxes:
		var key: String = b[&"body"]
		if not by_body.has(key):
			by_body[key] = []
		(by_body[key] as Array).append(b)
	var keys := by_body.keys()
	keys.sort()
	for key in keys:
		var list: Array = by_body[key]
		for k in range(0, list.size(), Tuning.LEVELBUILD_SHAPES_PER_JOB):
			_job(_add_shapes.bind(list.slice(k, k + Tuning.LEVELBUILD_SHAPES_PER_JOB)), &"shapes")
		_job(_attach_body.bind(_body(list[0]), int(list[0].get(&"soft", -1))), &"attach")
	for p in level.placements:
		var params: Dictionary = p[&"params"]
		_job(_place.bind(p), StringName("place:%s:%s" % [p[&"kind"], params.get(&"prop", params.get(&"kind", ""))]))
	var g := level.grid
	for i in g.cell_count():
		var c := g.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if g.wall(c, d) == LevelGrid.DOOR and (g.is_walkable(c) or g.is_walkable(c + LevelGrid.DIRS[d])):
				_job(_placer.door.bind(c, d, _containers[&"doors"]), &"door")
	_job(_finish_geometry, &"finish")
	_job(_start_bake, &"bake")


func _job(c: Callable, key: StringName) -> void:
	_jobs.append(c)
	_job_keys.append(key)


# ---------------------------------------------------------------- meshes

func _material(cls: int) -> Material:
	if not _materials.has(cls):
		_materials[cls] = LevelMaterials.for_class(stratum, cls)
	return _materials[cls]


func _make_mesh(m: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m[&"arrays"])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var cls: int = m[&"cls"]
	mi.material_override = _material(cls)
	var ch: Vector2i = m[&"chunk"]
	if m[&"soft"] >= 0:
		mi.name = "Mesh"
		_soft_node(m[&"soft"]).add_child(mi)
	else:
		mi.name = "%s_%d_%d" % [String(BuildPlan.CLASS_NAMES[cls]).capitalize(), ch.x, ch.y]
		# 07 §8: chunks beyond 40 m are hidden; the range is measured to the chunk's AABB
		# centre, so add half its footprint to keep every surface within 45 m drawn.
		var box: AABB = m[&"aabb"]
		mi.visibility_range_end = Tuning.CHUNK_VISIBILITY_END + Vector2(box.size.x, box.size.z).length() * 0.5
		(_containers[&"geometry"] as Node3D).add_child(mi)


## 09 §8: each soft wall is its own node (mesh with soft = 1, its own body).
func _soft_node(index: int) -> Node3D:
	if _soft_nodes.has(index):
		return _soft_nodes[index]
	var n := Node3D.new()
	var e: Vector3i = level.soft_walls[index] if index < level.soft_walls.size() else Vector3i.ZERO
	n.name = "SoftWall_%d_%d_%s" % [e.x, e.y, LevelGrid.DIR_NAMES[e.z]]
	n.add_to_group(&"soft_walls")
	n.set_meta(&"edge", e)
	(_containers[&"soft_walls"] as Node3D).add_child(n)
	_soft_nodes[index] = n
	return n


# ---------------------------------------------------------------- collision

func _body(b: Dictionary) -> StaticBody3D:
	var key: String = b[&"body"]
	if _bodies.has(key):
		return _bodies[key]
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var kind: StringName = b[&"kind"]
	if kind == BuildPlan.BODY_FLOOR:
		body.set_meta(&"surface", FLOOR_SURFACE.get(level.stratum, NoiseModel.DEFAULT_SURFACE))
		body.set_meta(&"floor", true)
	else:
		body.set_meta(&"wall_kind", kind)
	body.set_meta(&"shape_meta", {})
	var soft: int = b.get(&"soft", -1)
	if soft >= 0:
		body.name = "Body"
	else:
		var ch: Vector2i = b[&"chunk"]
		body.name = "%s_%d_%d" % [String(kind).capitalize(), ch.x, ch.y]
	# Shapes go in before the body enters the tree: a body in the physics space rebuilds
	# its compound shape on every added shape.
	_bodies[key] = body
	return body


func _attach_body(body: StaticBody3D, soft: int) -> void:
	if soft >= 0:
		_soft_node(soft).add_child(body)
	else:
		(_containers[&"bodies"] as Node3D).add_child(body)


func _add_shapes(list: Array) -> void:
	for b: Dictionary in list:
		var body := _body(b)
		var size: Vector3 = b[&"size"]
		if not _shapes.has(size):
			var s := BoxShape3D.new()
			s.size = size
			_shapes[size] = s
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, _shapes[size])
		body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, b[&"pos"]))
		(body.get_meta(&"shape_meta") as Dictionary)[owner_id] = b[&"meta"]


## The 07 §7 metadata of a ray or shape-cast hit: (collider, shape index) -> Dictionary.
## Empty for colliders the builder did not make. Doors and props carry their meta on the
## body itself, which is returned when there is no per-shape table.
static func shape_info(collider: Object, shape_index: int) -> Dictionary:
	if not (collider is CollisionObject3D):
		return {}
	var co := collider as CollisionObject3D
	if co.has_meta(&"shape_meta"):
		var table: Dictionary = co.get_meta(&"shape_meta")
		var owner_id := co.shape_find_owner(shape_index)
		return table.get(owner_id, {})
	var out: Dictionary = {}
	for k in co.get_meta_list():
		out[k] = co.get_meta(k)
	return out


# ---------------------------------------------------------------- placements, finish

func _place(p: Dictionary) -> void:
	_placer.place(p, _containers)
	if p[&"kind"] == LevelData.P_SPAWN:
		var c: Vector2i = p[&"cell"]
		spawn_transform = Transform3D(Basis(Vector3.UP, float(p[&"yaw"])), level.grid.world_of(c))


func _finish_geometry() -> void:
	light_pool.reevaluate()
	is_geometry_built = true
	geometry_built.emit()


## 07 §8: floors, ramps and walls from the plan plus props' static colliders, baked on a
## worker thread. Agent radius 0.4, height 1.8, max climb 0.3, cell size 0.25.
func _start_bake() -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = Tuning.NAV_CELL_SIZE
	nm.cell_height = Tuning.NAV_CELL_HEIGHT
	nm.agent_radius = Tuning.NAV_AGENT_RADIUS
	nm.agent_height = Tuning.NAV_AGENT_HEIGHT
	nm.agent_max_climb = Tuning.NAV_MAX_CLIMB
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, _containers[&"furniture"])
	src.add_faces(plan.nav_faces, Transform3D.IDENTITY)
	var map := nav_region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, Tuning.NAV_CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, Tuning.NAV_CELL_HEIGHT)
	_bake_started_us = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _on_baked.bind(nm))


func _on_baked(nm: NavigationMesh) -> void:
	# The callback may arrive off the main thread; touch nodes on the main thread only.
	_apply_bake.call_deferred(nm)


func _apply_bake(nm: NavigationMesh) -> void:
	bake_ms = (Time.get_ticks_usec() - _bake_started_us) / 1000.0
	navigation_ok = nm.get_polygon_count() > 0
	if not navigation_ok:
		push_error("LevelBuilder: navigation bake produced no polygons; errors stay dormant")
	if is_instance_valid(nav_region):
		nav_region.navigation_mesh = nm
	is_built = true
	set_process(false)
	navigation_baked.emit(navigation_ok)
	built.emit()


## Mesh instances made for level geometry (the draw-call proxy for tests).
func mesh_instance_count() -> int:
	var n := 0
	for key in [&"geometry", &"soft_walls"]:
		n += _count_meshes(_containers[key])
	return n


static func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for child in n.get_children():
		c += _count_meshes(child)
	return c


func container(name: StringName) -> Node3D:
	return _containers.get(name)
