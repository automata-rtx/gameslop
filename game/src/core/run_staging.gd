class_name RunStaging
extends RefCounted
## R19 (14 §10 level build slice, 4 ms per frame): the run's work on a new level after the
## builder's last slice, one frame at a time (it all ran inside that slice, 40 to 80 ms in
## one frame): the exit and breaker prefabs (RunLevelSetup.prepare_props), the pickups
## (RunLevelSetup.populate_steps, a slice budget a frame), the light pool lent from the
## spawn's eye (Level.prelight). The arrival itself and the Director's roster follow in
## frames of their own (Run._arrive, DirectorArrival). Each step's main-thread ms goes into
## `ms` (Run.arrival_ms).


## Prepares `level` over the next frames. Returns {exit, breaker} once done, or {} when the
## run's level changed meanwhile (`still`: () -> bool, true while `level` is the run's).
static func prepare(level: Level, data: LevelData, still: Callable, ms: Dictionary) -> Dictionary:
	var tree := level.get_tree()
	await tree.process_frame
	if not still.call():
		return {}
	var t0 := Time.get_ticks_usec()
	var setup := RunLevelSetup.prepare_props(level, data)
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
	level.prelight(Tuning.PLAYER_CAMERA_HEIGHT)
	ms[&"prelight"] = _since(t0)
	await tree.process_frame
	if not still.call():
		return {}
	setup[&"pickups"] = spawned
	return setup


static func _since(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0
