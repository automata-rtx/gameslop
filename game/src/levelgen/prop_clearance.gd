class_name PropClearance
extends RefCounted
## R13 audit of a built level against its grid (07 §2, §8 additions): every collider the
## grid does not model (props, hide spots, exits, interactables) leaves each cell the grid
## calls walkable its CROSS, so that the Director's spawn cells, Static's cut test, noclip
## landings, drop arrivals and the sim bot can trust the grid:
##   the square LEVEL_PROP_CLEARANCE m either side of the cell's centre, and a lane
##   LEVEL_PROP_CLEARANCE m either side of the centre line to each edge the grid lets a
##   walker step through, from step height (PLAYER_STEP_HEIGHT) to the player's height.
## A prop that cannot keep the cross clear fills its cell, which the grammar blocks
## (LevelGrid.F_BLOCKED, BlockOps). Two readings, by design of the grid:
##   - doors are grid edges (DOOR, with their runtime closed state): a leaf, open or shut,
##     is the edge's own collider, not a prop;
##   - the exit cell is entered, never crossed: its lanes across the exit's facing axis
##     (`dir`) are not required (the Threshold's free-standing frame).
## Checks on the live physics space (layer 1, world), all with the player's capsule:
##   centres():  it fits at every walkable cell's centre (shape query);
##   lanes():    it travels from every walkable cell's centre through each open edge's
##               midpoint to the neighbour's centre (shape casts);
##   crosses():  no foreign collider's box overlaps a walkable cell's cross;
##   hide_exits(): a hide spot lets the player out on a walkable cell with room to stand.

## Height above the floor the capsule starts at: what the player steps over anyway.
const LIFT := Tuning.PLAYER_STEP_HEIGHT
## A box touching the cross is clear of it (props stand flush at LEVEL_PROP_CLEARANCE).
const TOUCH := 0.005


## The player's capsule above step height.
static func capsule() -> CapsuleShape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = Tuning.PLAYER_CAPSULE_RADIUS
	cap.height = Tuning.PLAYER_CAPSULE_HEIGHT - LIFT
	return cap


## Capsule centre over a floor point.
static func _up() -> Vector3:
	return Vector3(0.0, LIFT + (Tuning.PLAYER_CAPSULE_HEIGHT - LIFT) * 0.5, 0.0)


static func _body_label(o: Object) -> String:
	if o is Node:
		var n := o as Node
		var p := n.get_parent()
		return "%s/%s" % [p.name if p != null else "", n.name]
	return str(o)


## Collision RIDs of the grid's door prefabs under `root` (the edge's own colliders).
static func door_rids(root: Node) -> Array[RID]:
	var out: Array[RID] = []
	for b in _door_bodies(root):
		out.append(b.get_rid())
	return out


static func _door_bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	for d in root.find_children("*", "Door", true, false):
		for b in d.find_children("*", "CollisionObject3D", true, false):
			out.append(b as CollisionObject3D)
	return out


static func _query(exclude: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule()
	q.collision_mask = PlayerLayers.WORLD_MASK
	q.exclude = exclude
	return q


## Walkable cells whose centre has no room for the capsule: "cell centre: colliders".
static func centres(space: PhysicsDirectSpaceState3D, grid: LevelGrid, exclude: Array[RID] = []) -> PackedStringArray:
	var out := PackedStringArray()
	var q := _query(exclude)
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_walkable(c):
			continue
		q.transform = Transform3D(Basis(), grid.world_of(c) + _up())
		var hits := space.intersect_shape(q, 4)
		if hits.is_empty():
			continue
		var names := PackedStringArray()
		for h in hits:
			names.append(_body_label(h[&"collider"]))
		out.append("%s centre: %s" % [c, ", ".join(names)])
	return out


## True for the exit cell's edges across the exit's facing axis (not required, see above).
static func exit_side(level: LevelData, c: Vector2i, d: int) -> bool:
	if c != level.exit_cell:
		return false
	var dir := level.exit_dir
	for p in level.placements_of(LevelData.P_EXIT):
		dir = int((p[&"params"] as Dictionary).get(&"dir", dir))
	return dir >= 0 and d != dir and d != LevelGrid.opposite(dir)


## Open edges (not doors: a closed leaf opens) the capsule cannot cross centre to centre.
static func lanes(space: PhysicsDirectSpaceState3D, level: LevelData, exclude: Array[RID] = []) -> PackedStringArray:
	var grid := level.grid
	var out := PackedStringArray()
	var q := _query(exclude)
	var up := _up()
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_walkable(c):
			continue
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if not grid.can_step(c, d) or grid.wall(c, d) == LevelGrid.DOOR:
				continue
			var o := c + LevelGrid.DIRS[d]
			if exit_side(level, c, d) or exit_side(level, o, LevelGrid.opposite(d)):
				continue
			var dv := LevelGrid.DIRS[d]
			var a := grid.world_of(c) + up
			var b := grid.world_of(o) + up
			var mid := grid.world_of(c) + Vector3(dv.x, 0.0, dv.y) * Tuning.GRID_CELL_SIZE * 0.5
			mid.y = maxf(grid.edge_floor_y(c, d), grid.edge_floor_y(o, LevelGrid.opposite(d)))
			mid += up
			var hit: Variant = _cast(space, q, a, mid)
			if hit == null:
				hit = _cast(space, q, mid, b)
			if hit != null:
				out.append("%s->%s lane: %s" % [c, o, _body_label(hit)])
	return out


## The first collider on the capsule's way from a to b, or null.
static func _cast(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, a: Vector3, b: Vector3) -> Variant:
	q.transform = Transform3D(Basis(), a)
	q.motion = b - a
	var r := space.cast_motion(q)
	q.motion = Vector3.ZERO
	if r.is_empty() or r[0] >= 1.0:
		return null
	# Name what it met: the shape at the unsafe point.
	q.transform = Transform3D(Basis(), a + (b - a) * minf(r[1], 1.0))
	var hits := space.intersect_shape(q, 1)
	return hits[0][&"collider"] if not hits.is_empty() else "?"


## Bodies under `root` that collide with the player and are not the grid's own: the
## builder's chunk bodies (shape_meta, void, rail) and the door prefabs are left out.
static func foreign_bodies(root: Node) -> Array[CollisionObject3D]:
	var doors := _door_bodies(root)
	var out: Array[CollisionObject3D] = []
	for n in root.find_children("*", "CollisionObject3D", true, false):
		var b := n as CollisionObject3D
		if b is Area3D or (b.collision_layer & PlayerLayers.WORLD_MASK) == 0 or doors.has(b):
			continue
		if b.has_meta(&"shape_meta") or b.has_meta(&"void") or b.has_meta(&"rail"):
			continue
		out.append(b)
	return out


## World AABBs of a body's enabled shapes.
static func shape_boxes(b: CollisionObject3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for owner_id in b.get_shape_owners():
		if b.is_shape_owner_disabled(owner_id):
			continue
		var t := b.global_transform * b.shape_owner_get_transform(owner_id)
		for k in b.shape_owner_get_shape_count(owner_id):
			var shape := b.shape_owner_get_shape(owner_id, k)
			var box := _local_aabb(shape)
			if box.size == Vector3.ZERO:
				continue
			# An upright round shape turned about Y keeps its box (a turned box's AABB grows).
			var round := shape is CylinderShape3D or shape is CapsuleShape3D or shape is SphereShape3D
			if round and t.basis.y.normalized().is_equal_approx(Vector3.UP):
				out.append(AABB(t.origin + box.position, box.size))
			else:
				out.append(t * box)
	return out


static func _local_aabb(s: Shape3D) -> AABB:
	if s is BoxShape3D:
		var e := (s as BoxShape3D).size
		return AABB(-e * 0.5, e)
	if s is CylinderShape3D:
		var c := s as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if s is CapsuleShape3D:
		var p := s as CapsuleShape3D
		return AABB(Vector3(-p.radius, -p.height * 0.5, -p.radius), Vector3(p.radius * 2.0, p.height, p.radius * 2.0))
	if s is SphereShape3D:
		var r := (s as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2.0)
	if s is ConvexPolygonShape3D:
		var pts := (s as ConvexPolygonShape3D).points
		if pts.is_empty():
			return AABB()
		var box := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(p)
		return box
	return AABB()


## Rects (XZ, world) of the cross of walkable cell c: the centre square and a lane to each
## edge a walker can step through (the exit cell's side lanes left out, see above).
static func cross_rects(level: LevelData, c: Vector2i) -> Array[Rect2]:
	var grid := level.grid
	var k := Tuning.LEVEL_PROP_CLEARANCE
	var h := Tuning.GRID_CELL_SIZE * 0.5
	var p := grid.world_of(c)
	var centre := Vector2(p.x, p.z)
	var out: Array[Rect2] = [Rect2(centre - Vector2(k, k), Vector2(k, k) * 2.0)]
	for d in 4:
		if not grid.can_step(c, d) or exit_side(level, c, d):
			continue
		var dv := Vector2(LevelGrid.DIRS[d])
		var r := Rect2(centre, Vector2.ZERO).expand(centre + dv * h)
		out.append(r.grow_individual(k if dv.x == 0.0 else 0.0, k if dv.y == 0.0 else 0.0,
			k if dv.x == 0.0 else 0.0, k if dv.y == 0.0 else 0.0))
	return out


## Foreign colliders that intrude on a walkable cell's cross between step height and the
## player's height: "cell cross: body".
static func crosses(root: Node, level: LevelData) -> PackedStringArray:
	var grid := level.grid
	var out := PackedStringArray()
	var seen: Dictionary = {}
	var h := Tuning.GRID_CELL_SIZE * 0.5
	var cs := Tuning.GRID_CELL_SIZE
	for b in foreign_bodies(root):
		for box in shape_boxes(b):
			var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(-TOUCH)
			var c0 := Vector2i(floori((box.position.x + h) / cs), floori((box.position.z + h) / cs))
			var c1 := Vector2i(floori((box.end.x + h) / cs), floori((box.end.z + h) / cs))
			for z in range(c0.y, c1.y + 1):
				for x in range(c0.x, c1.x + 1):
					var c := Vector2i(x, z)
					if not grid.is_walkable(c):
						continue
					var fy := grid.floor_y(c)
					if box.end.y <= fy + LIFT or box.position.y >= fy + Tuning.PLAYER_CAPSULE_HEIGHT:
						continue
					for cr in cross_rects(level, c):
						if cr.intersects(r):
							var key := "%s %s" % [c, _body_label(b)]
							if not seen.has(key):
								seen[key] = true
								out.append("%s cross: %s" % [c, _body_label(b)])
							break
	return out


## Hide spots whose ExitPoint does not stand the player on a walkable cell with room for the
## capsule (the spot's own bodies excluded): "spot: why".
static func hide_exits(space: PhysicsDirectSpaceState3D, root: Node, grid: LevelGrid, exclude: Array[RID] = []) -> PackedStringArray:
	var out := PackedStringArray()
	for n in root.find_children("*", "HideSpot", true, false):
		var spot := n as HideSpot
		var at := spot.exit_point.global_position
		var c := grid.cell_of(at)
		if not grid.is_walkable(c):
			out.append("%s exit at %s: cell %s not walkable" % [spot.name, at, c])
			continue
		var ex: Array[RID] = exclude.duplicate()
		for b in spot.find_children("*", "CollisionObject3D", true, false):
			ex.append((b as CollisionObject3D).get_rid())
		var q := _query(ex)
		q.transform = Transform3D(Basis(), Vector3(at.x, grid.floor_y(c), at.z) + _up())
		var hits := space.intersect_shape(q, 2)
		if not hits.is_empty():
			out.append("%s exit at %s: %s" % [spot.name, at, _body_label(hits[0][&"collider"])])
	return out
