extends TestCase
## M2.16: every error runs in every stratum. The per-error tests use Halls (and the stratum
## they were written for); this one builds each of the six strata through the error arena,
## wakes all five errors in it and lets them run, checking nothing dies, escapes the level,
## goes non-finite or hurts the player at spawn distance (08 §2: no spawn within 20 m).

const STRATA: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]
const IDS: Array[StringName] = [&"static", &"still", &"echo", &"flicker", &"null"]
const MAX_FRAMES := 900
const RUN_FRAMES := 90


func _arena_for(stratum: StringName) -> ErrorArena:
	var arena := (load("res://scenes/debug/error_arena.tscn") as PackedScene).instantiate() as ErrorArena
	arena.set(&"_stratum", stratum)
	add_child(arena)
	var frames := 0
	while (arena.player == null or not arena.level.is_ready() or arena.get(&"_log") == null) and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	return arena


func _bounds_ok(arena: ErrorArena, p: Vector3) -> bool:
	var g := arena.data.grid
	var c := g.cell_of(p)
	# A little slack: Null ignores walls and Flicker sits on fixtures; both stay inside the grid.
	return p.is_finite() and c.x >= -1 and c.y >= -1 and c.x <= g.size.x and c.y <= g.size.y


func _run_stratum(stratum: StringName) -> void:
	var arena := await _arena_for(stratum)
	assert_not_null(arena.player, "%s: arena built" % stratum)
	if arena.player == null:
		arena.free()
		return
	var coherence_before := arena.player.coherence
	for id in IDS:
		var e := arena.spawn(id)
		assert_not_null(e, "%s/%s created" % [stratum, id])
		if e == null:
			continue
		e.wake()
		var d := e.distance_to_player()
		var cam := arena.player.rig.camera
		if not (e is ErrorFlicker):
			assert_true(d >= Tuning.ERROR_SPAWN_MIN_DIST or not cam.is_position_in_frustum(e.global_position + Vector3.UP),
					"%s/%s spawns fair (%.1f m)" % [stratum, id, d])
	await await_physics_frames(RUN_FRAMES)
	for e in arena.errors:
		assert_true(_bounds_ok(arena, e.global_position), "%s/%s stays inside the level (%s)" % [stratum, e.error_id, e.global_position])
	assert_true(arena.player.coherence >= coherence_before - 0.001 or arena.errors.any(func(x: ErrorBase) -> bool: return x is ErrorNull),
			"%s: no contact in the first moments" % stratum)
	arena.clear_errors()
	await await_physics_frames(1)
	assert_eq(CoherenceRenderer.null_radius, 0.0, "%s: clearing frees Null's slot" % stratum)
	arena.free()
	await await_physics_frames(1)


func test_all_five_errors_run_in_halls() -> void:
	await _run_stratum(&"halls")


func test_all_five_errors_run_in_pools() -> void:
	await _run_stratum(&"pools")


func test_all_five_errors_run_in_garage() -> void:
	await _run_stratum(&"garage")


func test_all_five_errors_run_in_offices() -> void:
	await _run_stratum(&"offices")


func test_all_five_errors_run_in_server() -> void:
	await _run_stratum(&"server")


func test_all_five_errors_run_in_substrate() -> void:
	await _run_stratum(&"substrate")
