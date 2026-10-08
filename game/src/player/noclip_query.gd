class_name NoclipQuery
extends RefCounted
## Noclip validity (06 §8, 07 §7) as pure physics queries: what the aim names, whether it
## can be passed, why not, and where the body lands. No state of its own (the caller may
## pass a landing cache); NoclipTargeting calls it every physics frame while `noclip` is
## held, and the unit tests call it against synthetic walls. Call only from the physics
## step (or a test after a physics frame).
##
## Order of reasons (06 §8 and the noclip review): beyond 2.5 m TOO FAR (except a ceiling,
## always SOLID), then SOLID (the structure refuses), TOO THIN (Coherence <= cost: a noclip
## can never reduce Coherence to 0), NO SPACE (the far cell is not walkable, or no free
## capsule space 0.3..2.0 m beyond the aimed surface inside it). Floors and ceilings never
## show NO SPACE.

## Target ids (04 Interfaces: wall, soft, floor). TARGET_NONE: nothing aimed at all.
const TARGET_WALL := &"wall"
const TARGET_SOFT := &"soft"
const TARGET_FLOOR := &"floor"
const TARGET_NONE := &""

## Wall kinds (the builder's `wall_kind` meta, 07 Interfaces) that noclip may pass. The
## lowercase forms are the 06 Interfaces examples (`interior`, `soft`) that test fixtures
## and the player bench use; everything else (SOLID, GLASS, PROP, perimeter, no meta)
## refuses with SOLID.
const PASSABLE_KINDS: Array[StringName] = [&"WALL", &"PARTITION", &"DOOR", &"INTERIOR"]
const SOFT_KINDS: Array[StringName] = [&"SOFT"]
const KIND_DOOR := &"DOOR"
## Cell kinds a floor drop may start from (07 §7): FLOOR, ROOM, BASIN.
const DROP_CELL_KINDS: Array[int] = [LevelGrid.FLOOR, LevelGrid.ROOM, LevelGrid.BASIN]

## Reused query objects (one allocation, not one per probe).
static var _shape_q: PhysicsShapeQueryParameters3D
static var _ray_q: PhysicsRayQueryParameters3D


## Charge time in seconds for a target id (06 §8). Unknown ids time as a wall (04).
static func charge_time(target: StringName) -> float:
	match target:
		TARGET_SOFT:
			return Tuning.NOCLIP_SOFT_TIME
		TARGET_FLOOR:
			return Tuning.NOCLIP_FLOOR_TIME
	return Tuning.NOCLIP_WALL_TIME


## Coherence cost for a target id (06 §8).
static func cost(target: StringName) -> float:
	match target:
		TARGET_SOFT:
			return Tuning.NOCLIP_SOFT_COST
		TARGET_FLOOR:
			return Tuning.NOCLIP_FLOOR_COST
	return Tuning.NOCLIP_WALL_COST


## 06 §8 TOO THIN: refused when coherence <= cost, so spending is always survivable.
static func too_thin(coherence: float, target: StringName) -> bool:
	return coherence <= cost(target)


## The GameState.record_spend kind for a target id.
static func spend_kind(target: StringName) -> StringName:
	match target:
		TARGET_SOFT:
			return &"noclip_soft"
		TARGET_FLOOR:
			return &"noclip_floor"
	return &"noclip_wall"


## One evaluation of the aim. Arguments:
## - `eye`, `dir`: the camera position and its forward (normalised here).
## - `body_pos`: the body origin (feet); `shape`: the body's current collision shape
##   (standing or crouched capsule), placed with its base on the landing floor.
## - `coherence`: the player's Coherence; `floor_solid`: true on the run's last depth.
## - `cache`: an optional Dictionary the caller keeps between frames (find_landing_cached);
##   null computes every landing afresh.
## Returns {target, valid, reason, point, normal, distance, key, landing, has_landing,
## wall_kind, plane, far_cell, has_far_cell, far_floor_y}. `key` names the aim for display
## and debugging; same_target() decides whether two aims are one target.
static func evaluate(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, body_pos: Vector3,
		shape: Shape3D, coherence: float, floor_solid: bool, exclude: Array[RID] = [],
		cache: Variant = null) -> Dictionary:
	var d := dir.normalized()
	var out := {&"target": TARGET_NONE, &"valid": false, &"reason": Tuning.NOCLIP_REASON_TOO_FAR,
		&"point": Vector3.ZERO, &"normal": Vector3.ZERO, &"distance": INF, &"key": "",
		&"landing": body_pos, &"has_landing": false, &"wall_kind": &"", &"plane": 0.0,
		&"far_cell": Vector2i.ZERO, &"has_far_cell": false, &"far_floor_y": body_pos.y}
	var hit := _ray(space, eye, eye + d * Tuning.NOCLIP_PROBE_RANGE, exclude)
	if hit.is_empty():
		# The builder makes no ceiling colliders: an upward aim that meets nothing is the
		# ceiling, which is never valid (06 §8). Anything else is simply out of reach.
		if d.y > 0.0:
			out[&"target"] = TARGET_WALL
			out[&"reason"] = Tuning.NOCLIP_REASON_SOLID
		return out
	var n: Vector3 = hit[&"normal"]
	var p: Vector3 = hit[&"position"]
	var info := LevelBuilder.shape_info(hit[&"collider"], int(hit[&"shape"]))
	out[&"point"] = p
	out[&"normal"] = n
	out[&"distance"] = eye.distance_to(p)
	out[&"plane"] = n.dot(p)
	var kind := classify(hit, floor_solid, info)
	out[&"target"] = kind[&"target"]
	out[&"wall_kind"] = kind[&"wall_kind"]
	if kind[&"target"] == TARGET_FLOOR and kind[&"solid"] == false:
		out[&"key"] = String(TARGET_FLOOR)
	else:
		out[&"key"] = "%s:%s:%d,%d,%d:%d" % [kind[&"target"], kind[&"wall_kind"], roundi(n.x * 100.0),
				roundi(n.y * 100.0), roundi(n.z * 100.0), roundi(float(out[&"plane"]) / Tuning.NOCLIP_PLANE_TOLERANCE)]
	# Beyond 2.5 m the answer is TOO FAR whatever the surface is, except a ceiling.
	if out[&"distance"] > Tuning.NOCLIP_RANGE and not is_ceiling(n):
		return out
	if kind[&"solid"]:
		out[&"reason"] = Tuning.NOCLIP_REASON_SOLID
		return out
	if out[&"distance"] > Tuning.NOCLIP_RANGE:
		return out
	if too_thin(coherence, out[&"target"]):
		out[&"reason"] = Tuning.NOCLIP_REASON_TOO_THIN
		return out
	if out[&"target"] != TARGET_FLOOR:
		# 07 §7 / orchestrator rule: the grid decides first. A far-side cell that is not
		# walkable is NO SPACE whatever the shape cast finds (hollow void blocks). The
		# landing must then lie in that very cell, on its floor within a step.
		var far := far_side(info, n)
		if far[&"known"] and not far[&"walkable"]:
			out[&"reason"] = Tuning.NOCLIP_REASON_NO_SPACE
			return out
		if far[&"has_cell"]:
			out[&"far_cell"] = far[&"cell"]
			out[&"has_far_cell"] = true
		if far[&"has_floor_y"]:
			out[&"far_floor_y"] = far[&"floor_y"]
		var landing: Variant = find_landing_cached(cache, space, p, n, d, float(out[&"far_floor_y"]),
				shape, exclude, far)
		if landing == null:
			out[&"reason"] = Tuning.NOCLIP_REASON_NO_SPACE
			return out
		out[&"landing"] = landing
		out[&"has_landing"] = true
	out[&"valid"] = true
	out[&"reason"] = &""
	return out


## Whether two evaluations name the same target; a charge continues while this holds
## (06 §8: looking away cancels). Floors: any valid floor. Walls: the same target id and
## wall kind on the same plane (normal within NOCLIP_PLANE_NORMAL_DOT, plane offset within
## NOCLIP_PLANE_TOLERANCE), whichever collider shape carries it, so strafing along one
## wall keeps the charge across the 2 m segment seams.
static func same_target(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a[&"target"] != b[&"target"]:
		return false
	if a[&"target"] == TARGET_FLOOR:
		return a[&"key"] == b[&"key"]
	if a[&"wall_kind"] != b[&"wall_kind"]:
		return false
	var na: Vector3 = a[&"normal"]
	var nb: Vector3 = b[&"normal"]
	return na.dot(nb) >= Tuning.NOCLIP_PLANE_NORMAL_DOT \
			and absf(float(a[&"plane"]) - float(b[&"plane"])) <= Tuning.NOCLIP_PLANE_TOLERANCE


## A surface facing down by more than 30 deg below horizontal: a ceiling (never valid).
static func is_ceiling(n: Vector3) -> bool:
	return n.y < -sin(deg_to_rad(Tuning.NOCLIP_WALL_NORMAL_MAX_DEG))


## What a ray hit is to noclip: {target, solid, wall_kind}. Floors by normal (within 20
## deg of up), walls by normal (within 30 deg of horizontal); anything else (ceilings,
## slopes) is a solid wall-glyph target. A wall's kind comes from the builder metadata
## (07 §7); `info` is LevelBuilder.shape_info of the hit when the caller already has it.
static func classify(hit: Dictionary, floor_solid: bool, info: Variant = null) -> Dictionary:
	var n: Vector3 = hit[&"normal"]
	var meta: Dictionary = info if info is Dictionary else LevelBuilder.shape_info(hit[&"collider"], int(hit[&"shape"]))
	if n.y >= cos(deg_to_rad(Tuning.NOCLIP_FLOOR_NORMAL_MAX_DEG)):
		return {&"target": TARGET_FLOOR, &"wall_kind": &"",
			&"solid": floor_solid or not is_drop_floor(hit[&"collider"], meta)}
	var wk := wall_kind_of(hit[&"collider"], meta)
	if absf(n.y) > sin(deg_to_rad(Tuning.NOCLIP_WALL_NORMAL_MAX_DEG)):
		return {&"target": TARGET_WALL, &"solid": true, &"wall_kind": wk}
	# 07 §7: a door edge is a candidate only while its leaf is closed. Whatever carries the
	# leaf's `closed` state (the leaf, the jambs) follows it; a DOOR edge without it (the
	# header above the opening) is SOLID.
	var closed: Variant = meta.get(&"closed", null)
	var is_closed := closed is bool and bool(closed)
	if closed is bool and not is_closed:
		return {&"target": TARGET_WALL, &"solid": true, &"wall_kind": wk}
	if wk in SOFT_KINDS:
		return {&"target": TARGET_SOFT, &"solid": false, &"wall_kind": wk}
	var wt: Variant = meta.get(&"wall_type", -1)
	if wk == KIND_DOOR or (wt is int and int(wt) == LevelGrid.DOOR):
		return {&"target": TARGET_WALL, &"solid": not is_closed, &"wall_kind": wk}
	return {&"target": TARGET_WALL, &"solid": not (wk in PASSABLE_KINDS), &"wall_kind": wk}


## Whether the cell beyond the aimed wall face is walkable, from the builder's edge
## metadata {cell, dir, walkable, other_walkable}: 1 yes, 0 no, -1 unknown (no metadata).
static func far_side_walkable(info: Dictionary, normal: Vector3) -> int:
	var far := far_side(info, normal)
	if not far[&"known"]:
		return -1
	return 1 if far[&"walkable"] else 0


## The far side of an aimed wall face from the builder's edge metadata {cell, dir,
## walkable, other_walkable, floor_y, other_floor_y}: {known, walkable, has_cell, cell,
## has_floor_y, floor_y}. The face's normal points back at the aiming side, so the far
## side is the `dir` neighbour of `cell` when the normal points against `dir`, else `cell`.
static func far_side(info: Dictionary, normal: Vector3) -> Dictionary:
	var out := {&"known": false, &"walkable": true, &"has_cell": false, &"cell": Vector2i.ZERO,
		&"has_floor_y": false, &"floor_y": 0.0}
	if not (info.has(&"dir") and info.has(&"walkable") and info.has(&"other_walkable")):
		return out
	var dv: Vector2i = LevelGrid.DIRS[int(info[&"dir"])]
	var beyond := normal.x * dv.x + normal.z * dv.y < 0.0
	out[&"known"] = true
	out[&"walkable"] = bool(info[&"other_walkable"] if beyond else info[&"walkable"])
	if info.get(&"cell") is Vector2i:
		var c: Vector2i = info[&"cell"]
		out[&"has_cell"] = true
		out[&"cell"] = c + dv if beyond else c
	var fy_key := &"other_floor_y" if beyond else &"floor_y"
	if info.has(fy_key):
		out[&"has_floor_y"] = true
		out[&"floor_y"] = float(info[fy_key])
	return out


## The upper-cased wall kind of a hit (per-shape builder metadata first, then the body).
static func wall_kind_of(collider: Object, info: Dictionary) -> StringName:
	var wk: Variant = info.get(&"wall_kind", null)
	if wk == null and collider != null and collider.has_meta(NoiseModel.WALL_META):
		wk = collider.get_meta(NoiseModel.WALL_META)
	if wk is StringName or wk is String:
		return StringName(String(wk).to_upper())
	return &""


## 07 §7: floor colliders carry the cell kind; drops start from FLOOR, ROOM or BASIN.
## A body marked `floor` without a cell kind (a synthetic floor) is a valid floor too;
## tops of props, partitions and anything unmarked are solid.
static func is_drop_floor(collider: Object, info: Dictionary) -> bool:
	if info.has(&"wall_kind"):
		return false
	if info.has(&"kind") and (info[&"kind"] is int):
		return int(info[&"kind"]) in DROP_CELL_KINDS
	return collider != null and collider.has_meta(&"floor") and bool(collider.get_meta(&"floor"))


## The grid cell of a world position (LevelGrid.cell_of without a grid).
static func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / Tuning.GRID_CELL_SIZE), roundi(pos.z / Tuning.GRID_CELL_SIZE))


## find_landing through a cache the caller keeps (NoclipLanding.cached).
static func find_landing_cached(cache: Variant, space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3,
		aim: Vector3, ref_y: float, shape: Shape3D, exclude: Array[RID] = [], far: Dictionary = {}) -> Variant:
	return NoclipLanding.cached(cache, space, point, normal, aim, ref_y, shape, exclude, far)


## 06 §8 free space behind a wall, inside the far cell (NoclipLanding.find).
static func find_landing(space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3, aim: Vector3,
		ref_y: float, shape: Shape3D, exclude: Array[RID] = [], far: Dictionary = {}) -> Variant:
	return NoclipLanding.find(space, point, normal, aim, ref_y, shape, exclude, far)


## The floor height under `at` within a step of at.y (06 §3 step height), or null when
## there is no walkable floor there (a void cell, a basin drop, a prop top).
static func floor_under(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID] = []) -> Variant:
	var reach := Tuning.PLAYER_STEP_HEIGHT + Tuning.NOCLIP_LANDING_LIFT
	var from := at + Vector3.UP * Tuning.NOCLIP_FLOOR_PROBE
	var hit := _ray(space, from, at + Vector3.DOWN * Tuning.NOCLIP_FLOOR_PROBE, exclude)
	if hit.is_empty():
		return null
	var n: Vector3 = hit[&"normal"]
	var y: float = (hit[&"position"] as Vector3).y
	if n.y < cos(deg_to_rad(Tuning.PLAYER_FLOOR_MAX_ANGLE)) or absf(y - at.y) > reach:
		return null
	return y


## True when `shape` placed with its base at `origin` overlaps nothing on the world layer.
static func is_free(space: PhysicsDirectSpaceState3D, origin: Vector3, shape: Shape3D, exclude: Array[RID] = []) -> bool:
	if _shape_q == null:
		_shape_q = PhysicsShapeQueryParameters3D.new()
		_shape_q.collision_mask = PlayerLayers.WORLD_MASK
		_shape_q.collide_with_areas = false
	_shape_q.shape = shape
	_shape_q.transform = Transform3D(Basis.IDENTITY, origin + Vector3.UP * shape_half_height(shape))
	_shape_q.exclude = exclude
	return space.intersect_shape(_shape_q, 1).is_empty()


static func shape_half_height(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height * 0.5
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y * 0.5
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	return Tuning.PLAYER_CAPSULE_HEIGHT * 0.5


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	if _ray_q == null:
		_ray_q = PhysicsRayQueryParameters3D.new()
		_ray_q.collision_mask = PlayerLayers.WORLD_MASK
		_ray_q.collide_with_areas = false
		_ray_q.hit_from_inside = false
	_ray_q.from = from
	_ray_q.to = to
	_ray_q.exclude = exclude
	var hit := space.intersect_ray(_ray_q)
	if not hit.is_empty() and (hit[&"normal"] as Vector3).length_squared() < 0.5:
		return {}  # started inside a shape: not a surface
	return hit
