extends TestCase
## R19 (14 §10): the frame a level appears and Relief entry, at the largest level (the
## Server at Cycle 2's depth 5, its full roster). A real run starts at depth 10 and drops into
## depth 11. The arrival's work after the builder's last slice runs in frames of its own
## (Run.arrival_ms: the props, the pickups at a slice a frame, the audio warm-up, the light
## pool's prelight, the arrival itself with Director.begin) and the Director's roster follows
## over the next frames (Director.arrival_work); the staged shares must fit the build slice
## (4 ms); the prelight and the arrival, single calls in frames nothing moves on screen,
## less than a frame (16.6 ms). Relief entry
## (every hunter and Static hinted away at once, one Director tick) must fit the frame's
## script budget (3 ms). Wall-clock readings go through assert_budget (enforced by
## tools/ci/checkpoint.sh); what is deterministic is asserted always: the staged roster is
## the one begin() spawns at once (same ids, cells, draws, awake arrivals and aggression),
## and it is complete before the Director's first tick, so its Calm runs from the arrival.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 90.0
const DEPTH := 11
const RELIEF_SAMPLES := 6
## Frames after arrival watched (the first is the arrival's; the roster finishes inside).
const WATCH_FRAMES := 30

var _meta: MetaState
var _run: Run
var _frames: PackedFloat32Array = PackedFloat32Array()
var _last_us: int = 0


func before_all() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	GameState.meta.hints_retired = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", PerfBench.seed_for(Tuning.STRATUM_SERVER, DEPTH))
	GameState.run.depth = DEPTH - 1
	GameState.run.max_depth = DEPTH - 1
	_run = RUN_SCENE.instantiate() as Run
	_run.capture_mouse = false
	_run.drop_fall_time = 0.2
	add_child(_run)
	await _until(func() -> bool: return _run.phase == Run.PHASE_PLAYING and _run.level.is_ready())
	await await_frames(10)
	# The drop into the Server: the arrival measured.
	get_tree().process_frame.connect(_on_frame)
	_run.commit_drop()
	await _until(func() -> bool: return _run.phase == Run.PHASE_PLAYING and _run.data != null and _run.data.depth == DEPTH)
	await await_frames(WATCH_FRAMES)
	get_tree().process_frame.disconnect(_on_frame)
	await _until(func() -> bool: return _run.level.is_ready())
	await await_physics_frames(20)


func after_all() -> void:
	if is_instance_valid(_run):
		_run.queue_free()
	await await_frames(3)
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = _meta


func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _run.phase == Run.PHASE_PLAYING and _run.data != null and _run.data.depth == DEPTH:
		_frames.append((now - _last_us) / 1000.0)
	_last_us = now


func _until(cond: Callable, seconds: float = TIMEOUT_S) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _director() -> Director:
	return _run.level.find_child("Director", true, false) as Director


func test_the_drop_arrived_in_the_server() -> void:
	assert_eq(_run.data.stratum, Tuning.STRATUM_SERVER)
	assert_eq(_run.arrival, Tuning.RUN_ARRIVE_DROP)
	var d := _director()
	assert_not_null(d)
	assert_false(d.is_arriving(), "the staged roster finished")
	assert_eq(d.errors.size(), d.spawned_roster.size(), "the whole roster spawned")


func test_arrival_frames_fit_the_build_slice() -> void:
	var d := _director()
	var steps: Dictionary = _run.arrival_ms
	for key: StringName in [&"props", &"pickups", &"audio", &"prelight", &"arrive"]:
		assert_true(steps.has(key), "arrival step %s measured" % key)
	var roster: Array = Array(d.arrival_work.queue.frame_ms)
	print("  # arrival (drop into the Server, depth 11): props %.2f ms, pickups %.2f ms (worst frame), audio %.2f ms, prelight %.2f ms, arrive %.2f ms; roster %s ms over %d frames; worst frame of the %d after arrival %.2f ms headless" % [
		steps.get(&"props", 0.0), steps.get(&"pickups", 0.0), steps.get(&"audio", 0.0), steps.get(&"prelight", 0.0), steps.get(&"arrive", 0.0),
		", ".join(roster.map(func(v: float) -> String: return "%.2f" % v)), roster.size(), WATCH_FRAMES,
		Array(_frames).max() if not _frames.is_empty() else 0.0])
	assert_gt(roster.size(), 1, "the roster spread over frames")
	# The staged work: a build slice a frame (14 §10).
	for key: StringName in [&"props", &"pickups", &"audio"]:
		assert_budget(float(steps[key]), float(Tuning.LEVELBUILD_SLICE_MS), "arrival step %s ms" % key)
	for ms: float in roster:
		assert_budget(ms, float(Tuning.LEVELBUILD_SLICE_MS), "the Director's roster, one frame's share")
	# Two single calls that cannot split further, each in a frame nothing moves on screen:
	# the pool's first lending (16 lights and their hum players; behind the drop's black, or
	# at a proper exit in the arrival frame under the transition) and the arrival frame (the
	# player placed, level_entered's listeners, Director.begin; covered after a drop and a
	# proper exit). Neither may cost a whole frame; the listeners' share is filed in
	# docs/qa/open_items.md (R19).
	for key: StringName in [&"prelight", &"arrive"]:
		assert_budget(float(steps[key]), Tuning.RENDER_FRAME_BUDGET_MS, "arrival step %s ms" % key)


func test_relief_entry_fits_the_script_budget() -> void:
	var d := _director()
	for e in d.errors:
		if is_instance_valid(e) and not (e is ErrorStatic):
			e.wake()
	await await_physics_frames(5)
	var worst := 0.0
	var total := 0.0
	for i in RELIEF_SAMPLES:
		var t0 := Time.get_ticks_usec()
		d.hunters.act(DirectorPacing.ACT_HINT_AWAY_NOW)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		await await_physics_frames(3)
	print("  # Relief entry (hint_away_now, %d hunters and Statics): mean %.2f ms, worst %.2f ms" % [d.errors.size(), total / RELIEF_SAMPLES, worst])
	assert_budget(total / RELIEF_SAMPLES, float(Tuning.BUDGET_SCRIPT_MS), "Relief entry ms (one Director tick)")


## M3.8 review condition: Relief entry is cheaper (cached searches), not spread over ticks;
## every hunter already chasing is retreated on the entry tick itself, and the hint-away
## re-targets every free hunter in that same tick.
func test_relief_entry_retreats_every_chaser_on_the_entry_tick() -> void:
	var d := _director()
	var still: ErrorBase = null
	var free: Array[ErrorBase] = []
	for e in d.errors:
		if not is_instance_valid(e) or e is ErrorStatic or e.error_id == &"null":
			continue
		e.wake()
		if still == null and e is ErrorStill:
			still = e
		else:
			free.append(e)
	await await_physics_frames(3)
	assert_not_null(still, "the Server roster has Still")
	# Peak (a chase in Calm or Relief is sent away by the Director's own rule).
	d.pacing._enter(DirectorPacing.PEAK)
	still.transition_to(Tuning.ERROR_STATE_CHASE, "R19 test", true)
	assert_true(DirectorRules.is_chasing_state(still.state), "Still chases before the entry")
	d.pacing.take_actions()
	d.pacing.on_contact()
	assert_eq(d.pacing.phase, DirectorPacing.RELIEF, "a contact enters Relief")
	var actions := d.pacing.take_actions()
	assert_true(actions.has(DirectorPacing.ACT_RETREAT_CHASERS), "the entry retreats the chasers")
	assert_true(actions.has(DirectorPacing.ACT_HINT_AWAY_NOW), "and hints every hunter away")
	for a in actions:
		d.hunters.act(a)
	assert_eq(still.state, Tuning.ERROR_STATE_SATIATED, "the chaser retreated on the entry tick")
	for e in free:
		if e.state == Tuning.ERROR_STATE_WANDER or e.state == Tuning.ERROR_STATE_SEARCH:
			assert_false(e.has_hint(), "%s re-targeted in the entry tick (the hint is consumed)" % e.error_id)
	assert_eq(d.hunters.chasers().size(), 0, "no hunter chases after the entry tick")


## The staged roster is begin()'s roster: two Directors begun on this level from the same
## pose, one at once and one over frames, spawn the same ids at the same cells with the same
## rng draws, the same awake arrivals and the same aggression; the staged one finishes
## before its first tick.
func test_staged_roster_is_the_roster_begun_at_once() -> void:
	var lvl := _run.level
	var p := _run.player
	GameState.run.drops_in_a_row = 2
	var a := await _begin(lvl, p, false)
	var b := await _begin(lvl, p, true)
	assert_gt((a[&"spawns"] as Array).size(), 0, "errors spawned")
	assert_eq(b[&"spawns"], a[&"spawns"], "the same ids at the same spawn points, in order")
	assert_eq(b[&"rng"], a[&"rng"], "the same rng draws")
	assert_eq(b[&"awake"], a[&"awake"], "the same awake arrivals")
	assert_eq(b[&"pending"], a[&"pending"], "the same pending hunters")
	assert_eq(b[&"aggression"], a[&"aggression"])


## Begins a fresh Director on `lvl` (staged or not), waits until its roster is complete, and
## returns what it spawned (in order, with their spawn points), then frees it and its errors.
func _begin(lvl: Level, p: Player, staged: bool) -> Dictionary:
	var spawns: Array = []
	var on_child := func(n: Node) -> void:
		if n is ErrorBase:
			# Read at the end of the frame (the spawn sets the position after add_child), as
			# a cell: an awake Static may have drifted a step by then.
			(func() -> void: spawns.append([String((n as ErrorBase).error_id), lvl.data.grid.cell_of((n as Node3D).global_position)])).call_deferred()
	lvl.child_entered_tree.connect(on_child)
	var d := Director.new()
	d.name = "R19Director"
	d.staged = staged
	lvl.add_child(d)
	d.begin(lvl, p, Tuning.RUN_ARRIVE_DROP)
	var frames := 0
	while d.is_arriving() and frames < 120:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	lvl.child_entered_tree.disconnect(on_child)
	var awake: Array = []
	for e in d.hunters.awake:
		awake.append(String(e.error_id))
	var aggr: Array = [d.aggression]
	for e in d.errors:
		aggr.append(e.aggression)
	var out := {&"spawns": spawns, &"rng": d.rng.state, &"awake": awake, &"pending": Array(d.hunters.pending),
		&"aggression": aggr}
	d.end()
	for e in d.errors:
		if is_instance_valid(e):
			e.queue_free()
	d.queue_free()
	await await_frames(2)
	return out


## A staged roster still waiting when the first 0.1 s tick comes runs whole before it: the
## tick sees every error, as it would without staging (the Calm and the clock unchanged).
func test_the_first_tick_waits_for_the_whole_roster() -> void:
	var lvl := _run.level
	var clock := [0.0]
	var d := Director.new()
	d.name = "R19TickDirector"
	d.staged = true
	d.time_source = func() -> float: return clock[0]
	lvl.add_child(d)
	d.begin(lvl, _run.player, Tuning.RUN_ARRIVE_DROP)
	assert_true(d.is_arriving(), "the roster waits for the next frames")
	assert_eq(d.errors.size(), 0, "nothing spawned inside begin")
	assert_approx(d.pacing.level_time, 0.0, 0.0001)
	clock[0] = Tuning.DIRECTOR_TICK
	d.update()
	assert_false(d.is_arriving(), "the first tick ran the rest first")
	assert_eq(d.errors.size() + d.hunters.pending.size(), d.spawned_roster.size(), "every id spawned or pending")
	assert_approx(d.pacing.level_time, Tuning.DIRECTOR_TICK, 0.0001, "one tick from begin")
	d.end()
	for e in d.errors:
		if is_instance_valid(e):
			e.queue_free()
	d.queue_free()
	await await_frames(2)
