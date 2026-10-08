class_name NoclipLanding
extends RefCounted
## Where a wall pass lands (06 §8): free capsule space 0.3..2.0 m beyond the aimed point,
## inside the far cell the grid approved, on its floor within a step; probed coarse then
## fine, and cached by quantized pose for a held aim (noclip review). NoclipQuery calls it.

## Landing cache entries kept before the cache is cleared.
const CACHE_MAX := 128


## find_landing through a cache the caller keeps: the key is the quantized pose (aimed
## point, aim, normal, reference floor, shape, far cell); an entry lives for
## NOCLIP_LANDING_CACHE_FRAMES physics frames, so a moving world is seen again quickly.
## The pass re-checks the spot when it ends, so a stale entry never lands in geometry.
static func cached(cache: Variant, space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3,
		aim: Vector3, ref_y: float, shape: Shape3D, exclude: Array[RID] = [], far: Dictionary = {}) -> Variant:
	if not (cache is Dictionary):
		return find(space, point, normal, aim, ref_y, shape, exclude, far)
	var c: Dictionary = cache
	var q := Tuning.NOCLIP_LANDING_CACHE_QUANT
	var key := "%d,%d,%d|%d,%d|%d,%d|%d|%d|%s" % [roundi(point.x / q), roundi(point.y / q), roundi(point.z / q),
		roundi(aim.x * 64.0), roundi(aim.z * 64.0), roundi(normal.x * 64.0), roundi(normal.z * 64.0),
		roundi(ref_y / q), shape.get_instance_id(), far.get(&"cell", "")]
	var now := Engine.get_physics_frames()
	var entry: Variant = c.get(key)
	if entry is Array and now - int(entry[0]) <= Tuning.NOCLIP_LANDING_CACHE_FRAMES:
		return entry[1]
	var r: Variant = find(space, point, normal, aim, ref_y, shape, exclude, far)
	if c.size() >= CACHE_MAX:
		c.clear()
	c[key] = [now, r]
	return r


## 06 §8 free space behind a wall: the body's capsule, standing on a floor within a step of
## `ref_y` (the far cell's floor when the builder says it, else the body's), at the first
## spot 0.3..2.0 m beyond the aimed point along the horizontal aim (the pass moves along
## the aim), and inside the far cell when `far` names it (far_side). When the aim line
## leaves the far cell without a spot, the line straight through the wall is tried.
## Probes coarse first (every NOCLIP_LANDING_COARSE_STEP), then fine (NOCLIP_LANDING_STEP)
## back to the previous coarse sample; the answer is the first free fine sample, as an
## all-fine scan would find. Returns the body origin, or null.
static func find(space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3, aim: Vector3,
		ref_y: float, shape: Shape3D, exclude: Array[RID] = [], far: Dictionary = {}) -> Variant:
	var into := -Vector3(normal.x, 0.0, normal.z)
	if into.length_squared() < 0.0001:
		return null
	into = into.normalized()
	var along := Vector3(aim.x, 0.0, aim.z)
	if along.length_squared() < 0.0001 or along.normalized().dot(into) <= 0.05:
		along = into
	along = along.normalized()
	var r: Variant = _scan(space, point, along, ref_y, shape, exclude, far)
	if r == null and along.dot(into) < 0.999:
		r = _scan(space, point, into, ref_y, shape, exclude, far)
	return r


static func _scan(space: PhysicsDirectSpaceState3D, point: Vector3, along: Vector3, ref_y: float, shape: Shape3D,
		exclude: Array[RID], far: Dictionary) -> Variant:
	var count := int(floor((Tuning.NOCLIP_FREE_SPACE_MAX - Tuning.NOCLIP_FREE_SPACE_MIN) / Tuning.NOCLIP_LANDING_STEP + 0.0001)) + 1
	var stride := maxi(1, roundi(Tuning.NOCLIP_LANDING_COARSE_STEP / Tuning.NOCLIP_LANDING_STEP))
	var want_cell: bool = far.get(&"has_cell", false)
	var cell: Vector2i = far.get(&"cell", Vector2i.ZERO)
	var coarse: Array[int] = []
	var i := 0
	while i < count:
		coarse.append(i)
		i += stride
	if coarse[-1] != count - 1:
		coarse.append(count - 1)
	var prev := -1
	for ci in coarse:
		var hit: Variant = _probe(space, point, along, ci, ref_y, shape, exclude, want_cell, cell)
		if hit != null:
			for fi in range(prev + 1, ci):
				var fine: Variant = _probe(space, point, along, fi, ref_y, shape, exclude, want_cell, cell)
				if fine != null:
					return fine
			return hit
		prev = ci
	# No coarse sample is free: a free window narrower than the coarse step may remain.
	for fi in count:
		if fi % stride != 0 and fi != count - 1:
			var fine: Variant = _probe(space, point, along, fi, ref_y, shape, exclude, want_cell, cell)
			if fine != null:
				return fine
	return null


static func _probe(space: PhysicsDirectSpaceState3D, point: Vector3, along: Vector3, index: int, ref_y: float,
		shape: Shape3D, exclude: Array[RID], want_cell: bool, cell: Vector2i) -> Variant:
	var xz := point + along * (Tuning.NOCLIP_FREE_SPACE_MIN + index * Tuning.NOCLIP_LANDING_STEP)
	if want_cell and NoclipQuery.cell_at(xz) != cell:
		return null
	var fy: Variant = NoclipQuery.floor_under(space, Vector3(xz.x, ref_y, xz.z), exclude)
	if fy == null:
		return null
	var origin := Vector3(xz.x, float(fy) + Tuning.NOCLIP_LANDING_LIFT, xz.z)
	return origin if NoclipQuery.is_free(space, origin, shape, exclude) else null
