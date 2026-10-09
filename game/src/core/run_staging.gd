class_name RunStaging
extends RefCounted
## R19 (14 §10 level build slice, 4 ms per frame): the run's work on a new level after the
## builder's last slice, one frame at a time (it all ran inside that slice, 40 to 80 ms in
## one frame): the exit and breaker prefabs (RunLevelSetup.prepare_props), the pickups
## (RunLevelSetup.populate_steps, a slice budget a frame), the room tone, hums and error
## scenes loaded (`warm_audio`, `take_error_scenes`), the light pool lent from the spawn's
## eye (Level.prelight, behind the drop's black or before the first level shows). The
## arrival itself and the Director's roster follow in frames of their own (Run._arrive,
## DirectorArrival). Each step's main-thread ms goes into `ms` (Run.arrival_ms).


## Prepares `level` over the next frames. Returns {exit, breaker} once done, or {} when the
## run's level changed meanwhile (`still`: () -> bool, true while `level` is the run's).
## `prelight` false (the Landing cabin is on screen; its arrival is under the transition)
## leaves the pool's first lending to the covered arrival frame.
static func prepare(level: Level, data: LevelData, still: Callable, ms: Dictionary, prelight: bool = true) -> Dictionary:
	var tree := level.get_tree()
	await tree.process_frame
	if not still.call():
		return {}
	var t0 := Time.get_ticks_usec()
	var held := take_prefabs(data)  # cached while prepare_props instances them
	var setup := RunLevelSetup.prepare_props(level, data)
	held.clear()
	ms[&"props"] = _since(t0)
	await tree.process_frame
	if not still.call():
		return {}
	var pickups := StepQueue.new()
	var spawned: Array[Node3D] = []
	pickups.append_all(RunLevelSetup.populate_steps(level, data, spawned))
	var done := false
	while not done:
		done = pickups.run(StepQueue.slice_budget_ms())
		await tree.process_frame
		if not still.call():
			return {}
	ms[&"pickups"] = Array(pickups.frame_ms).max()
	t0 = Time.get_ticks_usec()
	warm_audio(level, data.stratum)
	take_error_scenes()
	ms[&"audio"] = _since(t0)
	await tree.process_frame
	if not still.call():
		return {}
	t0 = Time.get_ticks_usec()
	if prelight:
		level.prelight(Tuning.PLAYER_CAMERA_HEIGHT)
	ms[&"prelight"] = _since(t0)
	await tree.process_frame
	if not still.call():
		return {}
	setup[&"pickups"] = spawned
	return setup


## Loads the stratum's room tone and the fixtures' hums into AudioManager's library now (it
## caches them), so neither the light pool's first lending nor the level_entered that starts
## the room tone reads a file in a later frame.
static func warm_audio(level: Level, stratum: StringName) -> void:
	var lib := AudioManager.library
	if lib == null:
		return
	var ids: Array[StringName] = [StringName("room_tone_%s" % stratum)]
	for f in level.light_pool.fixtures():
		if f.hum_id != &"" and not ids.has(f.hum_id):
			ids.append(f.hum_id)
	for id in ids:
		if lib.has(id):
			lib.stream(id)


## The scenes the arrival will instance, loaded on a worker while the level builds (the run
## calls this when the level data is ready): the exit and breaker prefabs and the error
## scenes not held yet. Unheld, each was read from disk again in the arrival's frames.
static func request_prefabs(data: LevelData) -> void:
	for path in _prefab_paths(data):
		ResourceLoader.load_threaded_request(path, "PackedScene")
	for id: StringName in ErrorBase.SCENES:
		if not ErrorBase.has_scene(id):
			ResourceLoader.load_threaded_request(ErrorBase.SCENES[id], "PackedScene")


## The exit and breaker prefabs requested for `data`, taken from the worker (waiting for one
## not done yet). The caller holds them while instancing so `load` finds them cached.
static func take_prefabs(data: LevelData) -> Array[Resource]:
	var out: Array[Resource] = []
	for path in _prefab_paths(data):
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var res := ResourceLoader.load_threaded_get(path)
			if res != null:
				out.append(res)
	return out


static func _prefab_paths(data: LevelData) -> PackedStringArray:
	var out := PackedStringArray()
	for p in data.placements_of(LevelData.P_EXIT):
		var path := RunLevelSetup.exit_scene_for((p.get(&"params", {}) as Dictionary).get(&"exit_kind", &""))
		if not out.has(path):
			out.append(path)
	if not data.placements_of(LevelData.P_BREAKER).is_empty():
		out.append(RunLevelSetup.BREAKER_SCENE)
	return out


## Hands the scenes the worker finished to ErrorBase (one still loading is left: a spawn
## then loads it itself, waiting for the worker).
static func take_error_scenes() -> void:
	for id: StringName in ErrorBase.SCENES:
		var path: String = ErrorBase.SCENES[id]
		if not ErrorBase.has_scene(id) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ErrorBase.provide(id, ResourceLoader.load_threaded_get(path) as PackedScene)


static func _since(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0
