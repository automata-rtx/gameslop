class_name NoclipQuery
extends RefCounted
## Noclip validity (06 §8, 07 §7) as pure physics queries: what the aim names, whether it
## can be passed, why not, and where the body lands. No state; NoclipTargeting calls it
## every physics frame while `noclip` is held, and the unit tests call it against
## synthetic walls. Call only from the physics step (or a test after a physics frame).
##
## Order of reasons: SOLID (the structure refuses), TOO FAR (the aim is beyond 2.5 m),
## TOO THIN (Coherence <= cost: a noclip can never reduce Coherence to 0), NO SPACE (no
## free capsule space 0.3..2.0 m beyond the aimed surface). Floors and ceilings never
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
## Cell kinds a floor drop may start from (07 §7): FLOOR, ROOM, BASIN.
const DROP_CELL_KINDS: Array[int] = [LevelGrid.FLOOR, LevelGrid.ROOM, LevelGrid.BASIN]


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
## Returns {target, valid, reason, point, normal, distance, key, landing, has_landing}.
## `key` names the aimed thing (collider and shape) so a charge can tell when the aim left
## it; every valid floor shares one key, so walking while charging a drop keeps the charge.
static func evaluate(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, body_pos: Vector3,
		shape: Shape3D, coherence: float, floor_solid: bool, exclude: Array[RID] = []) -> Dictionary:
	var d := dir.normalized()
	var out := {&"target": TARGET_NONE, &"valid": false, &"reason": Tuning.NOCLIP_REASON_TOO_FAR,
		&"point": Vector3.ZERO, &"normal": Vector3.ZERO, &"distance": INF, &"key": "",
		&"landing": body_pos, &"has_landing": false}
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
	out[&"point"] = p
	out[&"normal"] = n
	out[&"distance"] = eye.distance_to(p)
	out[&"key"] = "%d:%d" % [hit[&"collider_id"], hit[&"shape"]]
	var kind := classify(hit, floor_solid)
	out[&"target"] = kind[&"target"]
	if kind[&"target"] == TARGET_FLOOR and kind[&"solid"] == false:
		out[&"key"] = String(TARGET_FLOOR)
	if kind[&"solid"]:
		out[&"reason"] = Tuning.NOCLIP_REASON_SOLID
		return out
	if out[&"distance"] > Tuning.NOCLIP_RANGE:
		out[&"reason"] = Tuning.NOCLIP_REASON_TOO_FAR
		return out
	if too_thin(coherence, out[&"target"]):
		out[&"reason"] = Tuning.NOCLIP_REASON_TOO_THIN
		return out
	if out[&"target"] != TARGET_FLOOR:
		# 07 §7 / orchestrator rule: the grid decides first. A far-side cell that is not
		# walkable is NO SPACE whatever the shape cast finds (hollow void blocks).
		if far_side_walkable(LevelBuilder.shape_info(hit[&"collider"], int(hit[&"shape"])), n) == 0:
			out[&"reason"] = Tuning.NOCLIP_REASON_NO_SPACE
			return out
		var landing: Variant = find_landing(space, p, n, d, body_pos.y, shape, exclude)
		if landing == null:
			out[&"reason"] = Tuning.NOCLIP_REASON_NO_SPACE
			return out
		out[&"landing"] = landing
		out[&"has_landing"] = true
	out[&"valid"] = true
	out[&"reason"] = &""
	return out


## What a ray hit is to noclip: {target, solid}. Floors by normal (within 20 deg of up),
## walls by normal (within 30 deg of horizontal); anything else (ceilings, slopes) is a
## solid wall-glyph target. A wall's kind comes from the builder metadata (07 §7).
static func classify(hit: Dictionary, floor_solid: bool) -> Dictionary:
	var n: Vector3 = hit[&"normal"]
	var info := LevelBuilder.shape_info(hit[&"collider"], int(hit[&"shape"]))
	if n.y >= cos(deg_to_rad(Tuning.NOCLIP_FLOOR_NORMAL_MAX_DEG)):
		return {&"target": TARGET_FLOOR, &"solid": floor_solid or not is_drop_floor(hit[&"collider"], info)}
	if absf(n.y) > sin(deg_to_rad(Tuning.NOCLIP_WALL_NORMAL_MAX_DEG)):
		return {&"target": TARGET_WALL, &"solid": true}
	var wk := wall_kind_of(hit[&"collider"], info)
	if wk in SOFT_KINDS:
		return {&"target": TARGET_SOFT, &"solid": false}
	if wk in PASSABLE_KINDS:
		# 07 §7: a door is a candidate only while closed (the leaf carries `closed`).
		var closed: Variant = info.get(&"closed", true)
		return {&"target": TARGET_WALL, &"solid": closed is bool and not closed}
	return {&"target": TARGET_WALL, &"solid": true}


## Whether the cell beyond the aimed wall face is walkable, from the builder's edge
## metadata {cell, dir, walkable, other_walkable}: 1 yes, 0 no, -1 unknown (no metadata).
## The face's normal points back at the aiming side, so the far side is `other_cell` when
## the normal points against `dir`, else `cell`.
static func far_side_walkable(info: Dictionary, normal: Vector3) -> int:
	if not (info.has(&"dir") and info.has(&"walkable") and info.has(&"other_walkable")):
		return -1
	var dv: Vector2i = LevelGrid.DIRS[int(info[&"dir"])]
	var facing := normal.x * dv.x + normal.z * dv.y
	var far: bool = info[&"other_walkable"] if facing < 0.0 else info[&"walkable"]
	return 1 if far else 0


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


## 06 §8 free space behind a wall: the body's capsule, standing on a floor within a step of
## the current one, at the first spot 0.3..2.0 m beyond the aimed point along the
## horizontal aim (the pass moves along the aim). Returns the body origin, or null.
static func find_landing(space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3, aim: Vector3,
		body_y: float, shape: Shape3D, exclude: Array[RID] = []) -> Variant:
	var along := Vector3(aim.x, 0.0, aim.z)
	var into := -Vector3(normal.x, 0.0, normal.z)
	if into.length_squared() < 0.0001:
		return null
	into = into.normalized()
	if along.length_squared() < 0.0001 or along.normalized().dot(into) <= 0.05:
		along = into
	along = along.normalized()
	var dist := Tuning.NOCLIP_FREE_SPACE_MIN
	while dist <= Tuning.NOCLIP_FREE_SPACE_MAX + 0.0001:
		var xz := point + along * dist
		var fy: Variant = floor_under(space, Vector3(xz.x, body_y, xz.z), exclude)
		if fy != null:
			var origin := Vector3(xz.x, float(fy) + Tuning.NOCLIP_LANDING_LIFT, xz.z)
			if is_free(space, origin, shape, exclude):
				return origin
		dist += Tuning.NOCLIP_LANDING_STEP
	return null


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
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, origin + Vector3.UP * shape_half_height(shape))
	q.collision_mask = PlayerLayers.WORLD_MASK
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_shape(q, 1).is_empty()


static func shape_half_height(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height * 0.5
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y * 0.5
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	return Tuning.PLAYER_CAPSULE_HEIGHT * 0.5


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, PlayerLayers.WORLD_MASK, exclude)
	q.collide_with_areas = false
	q.hit_from_inside = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit[&"normal"] as Vector3).length_squared() < 0.5:
		return {}  # started inside a shape: not a surface
	return hit
