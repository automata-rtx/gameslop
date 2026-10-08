class_name FeedbackRecipesBase
extends RefCounted
## Helpers the row recipes share: standing the player in front of things, finding noclip
## walls, spawning errors and pickups. A recipe is `func <row id>(b: FeedbackBench)`; it sets
## the scene up, calls b.arm() when it is quiet, calls b.anchor() (or b.anchor_on(signal))
## at the trigger and fires the row through the game's own code path.

const DOOR_STAND := [1.0, 1.3, 1.6]


## Adds a probe for a row: channel &"I"/&"S"/&"M"/&"R", a name and a Callable -> Variant.
func probe(b: FeedbackBench, ch: StringName, probe_name: String, fn: Callable) -> void:
	if not b.spy.extra.has(ch):
		b.spy.extra[ch] = {}
	b.spy.extra[ch][probe_name] = fn


## Stands the player where the camera ray hits `it`'s collider, looking at it. True when the
## interactor then targets it.
func face_interactable(b: FeedbackBench, it: Interactable, aim_up: float = 0.0) -> bool:
	var body := it.get_parent() as Node3D
	if body == null:
		return false
	var p := b.player()
	var space := p.get_world_3d().direct_space_state
	var centre := body.global_position + Vector3(0.0, aim_up, 0.0)
	var offsets: Array[Vector3] = []
	for dist: float in DOOR_STAND:
		for axis: Vector3 in [body.global_basis.z, -body.global_basis.z, body.global_basis.x, -body.global_basis.x]:
			var flat := Vector3(axis.x, 0.0, axis.z).normalized()
			offsets.append(flat * dist)
	var g := b.run.data.grid
	for off in offsets:
		var feet := Vector3(centre.x + off.x, b.run.level.global_position.y, centre.z + off.z)
		var c := g.cell_of(feet)
		if not g.in_bounds(c) or not g.is_walkable(c):
			continue
		var eye := feet + Vector3(0.0, LevelShots.EYE, 0.0)
		var aim := centre if aim_up > 0.0 else Vector3(centre.x, eye.y - 0.2, centre.z)
		var q := PhysicsRayQueryParameters3D.create(eye, eye + (aim - eye).normalized() * Tuning.INTERACT_RANGE,
				PlayerLayers.WORLD_MASK | PlayerLayers.INTERACTABLE_MASK)
		q.collide_with_areas = true
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or Interactable.find_on(hit["collider"]) != it:
			continue
		var flat_dir := aim - eye
		b.place(feet, FeedbackBench.yaw_to(eye, aim), atan2(flat_dir.y, Vector2(flat_dir.x, flat_dir.z).length()))
		await b.ticks(6)
		if p.interactor.target == it:
			return true
	return false


## Every (cell, dir) wall of the level with its NoclipQuery verdict from 0.4 m back of the
## cell centre: the first valid one and the first refused for NO SPACE. {good: [cell, dir],
## bad: [cell, dir]} (empty arrays when none).
func noclip_spots(b: FeedbackBench) -> Dictionary:
	var p := b.player()
	var g := b.run.data.grid
	var space := p.get_world_3d().direct_space_state
	var good: Array = []
	var bad: Array = []
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c):
				continue
			for d in 4:
				if not good.is_empty() and not bad.is_empty():
					return {&"good": good, &"bad": bad}
				var o := c + LevelGrid.DIRS[d]
				var base := g.world_of(c)
				var dv := LevelGrid.DIRS[d]
				var back := base - Vector3(dv.x, 0, dv.y) * 0.4
				var a := NoclipQuery.evaluate(space, back + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT,
						Vector3(dv.x, -0.1, dv.y), back, p.collision.shape, 100.0, false, [p.get_rid()])
				if good.is_empty() and a[&"valid"] and g.in_bounds(o) and g.is_walkable(o) \
						and g.wall(c, d) == LevelGrid.WALL:
					good = [c, d]
				if bad.is_empty() and not a[&"valid"] and a[&"distance"] < Tuning.NOCLIP_RANGE \
						and a[&"reason"] == Tuning.NOCLIP_REASON_NO_SPACE:
					bad = [c, d]
	return {&"good": good, &"bad": bad}


## Stands the player 0.4 m back from the centre of the (cell, dir) edge facing it, a little down.
func face_edge(b: FeedbackBench, e: Array) -> void:
	var g := b.run.data.grid
	var dv := LevelGrid.DIRS[int(e[1])]
	var fwd := Vector3(dv.x, 0, dv.y)
	b.place(g.world_of(e[0]) - fwd * 0.4 + Vector3.UP * 0.02, atan2(-fwd.x, -fwd.z), deg_to_rad(-6.0))
	b.player().flashlight.set_on(true, true)
	b.run.level.light_pool.reevaluate()
	await b.ticks(10)


## An error of `id` in the level next to the player (dormant). Free it with free_error().
func spawn_error(b: FeedbackBench, id: StringName, pos: Vector3) -> ErrorBase:
	var e := ErrorBase.create(id)
	e.setup(b.player(), b.run.level, 7)
	b.run.level.content.add_child(e)
	if e is ErrorStill:
		(e as ErrorStill).place_at(pos)
	else:
		e.global_position = pos
	e.set_navigation_ready(true)
	return e


func free_error(e: ErrorBase) -> void:
	if e != null and is_instance_valid(e):
		e.get_parent().remove_child(e)
		e.free()


## A point `dist` metres ahead of the player on the floor.
func ahead(b: FeedbackBench, dist: float) -> Vector3:
	var p := b.player()
	var f := -p.global_transform.basis.z
	f.y = 0.0
	return p.global_position + f.normalized() * dist


func press_tap(b: FeedbackBench, action: StringName, ticks: int = 3) -> void:
	b.press(action)
	await b.ticks(ticks)
	b.release(action)
