class_name ArenaFlickerShots
extends RefCounted
## The error arena's Flicker signature frames (02 §8, 02 §13), on an Offices level:
## flicker_stutter_a / _b (its group stuttering, two moments), flicker_lunge_flash (the
## group's white flash, held for the capture), flicker_lunge_dark (the 1.5 s dark), and
## flicker_attached_on / _off (attached: the beam at an on and an off instant of its
## stutter). Flicker's own ticking is paused so no lunge lands during the captures.


static func capture(arena: ErrorArena, dir: String) -> void:
	var pick := _vantage(arena)
	if pick.is_empty():
		push_warning("arena: no lit fixture group with a vantage")
		return
	var g: int = pick[&"group"]
	var pool := arena.level.light_pool
	var p := arena.player
	_pose(arena, pick[&"stand"], pool.group_centroid(g))
	p.flashlight.set_on(false, true)
	var c := pool.group_centroid(g)
	var e := arena.spawn(&"flicker", Vector3(c.x, p.global_position.y, c.z)) as ErrorFlicker
	e.respawn_at(g)
	e.set_physics_process(false)
	await arena.shot(dir, "flicker_stutter_a")
	await arena.get_tree().create_timer(0.07).timeout
	await arena.shot(dir, "flicker_stutter_b")
	# The lunge flash lasts 2 frames; hold it for the capture.
	for i in ErrorArena.SETTLE_FRAMES + 1:
		pool.group_lunge_flash(g)
		await RenderingServer.frame_post_draw
	pool.group_lunge_flash(g)
	var img := arena.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("flicker_lunge_flash.png"))
	await RenderingServer.frame_post_draw
	pool.set_group_lunge_dark(g, true)
	await arena.shot(dir, "flicker_lunge_dark")
	pool.set_group_lunge_dark(g, false)
	# Attached: the beam carries it; look down the room with the flashlight on.
	p.flashlight.set_on(true, true)
	e._attach()
	p.rig.add_pitch(deg_to_rad(-12.0))
	p.flashlight.stutter = 1.0
	p.flashlight.refresh()
	await arena.shot(dir, "flicker_attached_on")
	p.flashlight.stutter = 1.0 - Fixture.flicker_depth()
	p.flashlight.refresh()
	await arena.shot(dir, "flicker_attached_off")
	FlickerPresent.beam_steady(p.flashlight)
	arena.free_error(e)


## A lit group and a walkable cell 5 to 9 m from its centroid that sees the most of its
## fixtures along clear grid lines (ties: the farther cell), outside the spawn room.
static func _vantage(arena: ErrorArena) -> Dictionary:
	var pool := arena.level.light_pool
	var grid := arena.data.grid
	var ids: Array = pool.group_ids()
	ids.sort()
	var best := {}
	var best_score := 0.0
	for g: int in ids:
		if not pool.is_group_lit(g) or pool.group(g).size() < 3:
			continue
		var c := pool.group_centroid(g)
		for i in grid.cell_count():
			var cell := grid.cell_at(i)
			if not grid.is_walkable(cell) or grid.has_flag(cell, LevelGrid.F_SPAWN_ROOM):
				continue
			var w := grid.world_of(cell)
			var d := FlickerHabitat.flat(w, c)
			if d < 5.0 or d > 9.0:
				continue
			var seen := 0
			for f in pool.group(g):
				if SightOps.clear(grid, w, Vector3(f.global_position.x, w.y, f.global_position.z)):
					seen += 1
			var score := seen + d * 0.01
			if seen >= 3 and score > best_score:
				best_score = score
				best = {&"group": g, &"stand": w}
	return best


static func _pose(arena: ErrorArena, stand: Vector3, look: Vector3) -> void:
	var p := arena.player
	p.global_position = stand + Vector3.UP * 0.05
	var to := look - stand
	p.rotation = Vector3(0, atan2(-to.x, -to.z), 0)
	p.velocity = Vector3.ZERO
	p.rig.reset_pitch()
	var eye := stand.y + Tuning.PLAYER_CAMERA_HEIGHT
	p.rig.add_pitch(atan2(look.y - eye, Vector2(to.x, to.z).length()) * 0.8)
	arena.level.light_pool.reevaluate()
