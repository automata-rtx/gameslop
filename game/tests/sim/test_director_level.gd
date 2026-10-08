extends TestCase
## The Director on a built Halls level (headless, FakeClock): the roster spawns at fair
## cells (≥ 20 m, out of view), Static awake and hunters Dormant; Calm holds 30 s (15 s
## after a drop) and Build wakes a hunter; awake arrivals search 30 m out; aggression
## reaches the errors; the F3 lines and the telemetry CSV.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock
var _phases: Array[StringName] = []


func before_all() -> void:
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"halls", 1, 5))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_level.attach_player(_p, _p.rig.camera)
	await await_physics_frames(5)
	EventBus.director_phase.connect(_on_phase)


func after_all() -> void:
	EventBus.director_phase.disconnect(_on_phase)
	_level.queue_free()


func _on_phase(p: StringName) -> void:
	_phases.append(p)


func before_each() -> void:
	_phases.clear()
	_level.attach_player(_p, _p.rig.camera)
	_clock = fake_clock(0.0)
	_d = Director.new()
	_d.time_source = _clock.now
	_level.add_child(_d)


func after_each() -> void:
	_d.queue_free()
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


func _begin(arrival: StringName = Tuning.RUN_ARRIVE_START) -> void:
	_d.begin(_level, _p, arrival)
	# Depth 1 adds a Still or an Echo; Echo has no scene in M1, so make sure one hunter exists.
	if _hunter() == null:
		_d.hunters.spawn_roster([&"still"] as Array[StringName])


func _hunter() -> ErrorBase:
	for e in _d.errors:
		if is_instance_valid(e) and DirectorRules.is_hunter(e.error_id):
			return e
	return null


func _advance(seconds: float) -> void:
	_clock.advance(seconds)
	_d.update()


func test_roster_spawns_fairly() -> void:
	_begin()
	assert_eq(_d.roster[0], &"static")
	assert_eq(_d.roster.size(), 2, "depth 1 of a later Descent: Static plus one hunter")
	assert_eq(_d.errors.size() + _d.skipped.size(), _d.roster.size() + (1 if _d.skipped.size() > 0 else 0))
	var g := _level.data.grid
	var eye := _p.eye_position()
	for e in _d.errors:
		var pos := e.body_position()
		assert_true(DirectorSpawn.flat_dist(pos, _p.global_position) >= Tuning.ERROR_SPAWN_MIN_DIST, "%s ≥ 20 m" % e.error_id)
		assert_false(_p.rig.camera.is_position_in_frustum(pos + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT), "%s out of the frustum" % e.error_id)
		assert_false(SightOps.clear(g, eye, pos + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT), "%s out of sight" % e.error_id)
		if e.error_id == &"static":
			assert_false(e.is_dormant(), "Static starts awake")
		else:
			assert_true(e.is_dormant(), "hunters start Dormant")
	assert_eq(_phases, [DirectorPacing.CALM] as Array[StringName])
	assert_true(_p.contact_gate.is_valid())


func test_calm_30_s_then_build_wakes_a_hunter() -> void:
	_begin()
	var h := _hunter()
	_advance(Tuning.DIRECTOR_CALM_TIME - 0.15)
	assert_eq(_d.phase, DirectorPacing.CALM)
	assert_true(h.is_dormant(), "no hunter wakes during Calm")
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.BUILD)
	assert_false(h.is_dormant(), "Build wakes a hunter")
	assert_true(h.has_hint(), "and hints it toward the player's region")
	assert_true(_phases.has(DirectorPacing.BUILD))


func test_calm_after_drop_is_15_s() -> void:
	_begin(Tuning.RUN_ARRIVE_DROP)
	_advance(Tuning.DIRECTOR_CALM_TIME_AFTER_DROP - 0.15)
	assert_eq(_d.phase, DirectorPacing.CALM)
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.BUILD)


func test_a_chase_during_calm_is_sent_away() -> void:
	_begin()
	var h := _hunter()
	h.wake()
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	assert_eq(h.state, Tuning.ERROR_STATE_SATIATED, "no chase in the calm window (10 §7 rule 2)")


func test_awake_arrival_searches_30_m_out() -> void:
	_begin(Tuning.RUN_ARRIVE_DROP)
	var h := _hunter()
	_d.hunters.awake_arrivals(1)
	assert_eq(h.state, Tuning.ERROR_STATE_SEARCH)
	var d := DirectorSpawn.flat_dist(h.senses.last_known_pos, _p.global_position)
	assert_true(absf(d - Tuning.AWAKE_SEARCH_DIST) <= Tuning.DIRECTOR_HINT_DIST_TOLERANCE + 0.01,
		"last_known_pos is a cell 30 m from the player, not the player (%.1f m)" % d)


func test_aggression_reaches_errors() -> void:
	_begin()
	assert_approx(_d.aggression, 0.25, 0.0001)
	for e in _d.errors:
		var want := DirectorRules.error_aggression(0.25, 1, e.error_id)
		assert_approx(e.aggression, want, 0.0001, "%s aggression" % e.error_id)
	_d.depth = 3
	_advance(1.1)
	assert_approx(_d.aggression, 0.45, 0.0001, "re-applied within a second of a change")
	assert_approx(_hunter().aggression, 0.45, 0.0001)


func test_debug_lines_threat_and_telemetry() -> void:
	_begin()
	_advance(5.0)
	var info := _d.debug_info()
	for key in ["director", "intensity", "aggression", "threat"]:
		assert_true(info.has(key), "F3 line %s" % key)
	assert_true(String(info["director"]).begins_with("CALM"))
	assert_true(_d.telemetry.size() >= 5, "a row per second")
	var path := "user://test_director_telemetry.csv"
	assert_eq(_d.telemetry.dump_csv(path), OK)
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.begins_with(DirectorTelemetry.HEADER))
	assert_eq(text.strip_edges().split("\n").size(), _d.telemetry.size() + 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(_d.threat >= 0.0 and _d.threat <= 1.0)


func test_end_releases_the_gate() -> void:
	_begin()
	_d.end()
	assert_false(_p.contact_gate.is_valid())
	_advance(40.0)
	assert_eq(_d.phase, DirectorPacing.CALM, "an ended Director no longer runs")


func _into_build() -> void:
	_advance(Tuning.DIRECTOR_CALM_TIME + 0.05)
	assert_eq(_d.phase, DirectorPacing.BUILD)


## cp-04 review: a chase that starts in Relief is sent away as in Calm, and is not an encounter.
func test_a_chase_in_relief_is_sent_away() -> void:
	_begin()
	var h := _hunter()
	_into_build()
	_d.pacing._enter(DirectorPacing.RELIEF, 30.0)
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	assert_eq(h.state, Tuning.ERROR_STATE_SATIATED, "no chase in Relief")
	assert_approx(h._satiated_left, 30.0, 0.15, "sent away for the rest of Relief")
	assert_eq(_d.retreated_chases, 1)
	assert_eq(_d.encounters, 0, "a sent-away chase is not an encounter")
	_d.pacing._enter(DirectorPacing.BUILD)
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	assert_eq(h.state, Tuning.ERROR_STATE_CHASE, "Build lets a chase run")
	assert_eq(_d.encounters, 1)


## 05 §10: on the first Descent depth 1 keeps a hunter dormant through Build and the 0.8
## wake, and Static drifts inside a side loop off the critical path.
func test_first_descent_keeps_hunters_dormant_and_static_off_path() -> void:
	var was := _level.data.first_run
	_level.data.first_run = true
	_begin()
	_level.data.first_run = was
	assert_eq(_d.roster, [&"static"] as Array[StringName], "first Descent depth 1: Static only")
	var h := _hunter()
	_into_build()
	assert_true(h.is_dormant(), "Build does not wake it")
	_d.pacing.intensity = 0.9
	_advance(0.2)
	assert_true(h.is_dormant(), "nor does intensity 0.8")
	assert_eq(_d.phase, DirectorPacing.BUILD, "no Peak without a hunter it may wake")
	_level.data.first_run = true
	var f := _d.statics.bound_statics_off_path()
	_level.data.first_run = was
	assert_true(f.is_valid(), "a wander filter for Static")
	var g := _level.data.grid
	var band := DirectorSpawn.breaker_exit_band(_level.data)
	var inside := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		inside += 1 if bool(f.call(c)) else 0
		if not band.is_empty():
			assert_eq(bool(f.call(c)), band.has(c), "the filter is the breaker-to-exit band at %s" % c)
			assert_eq(bool(f.call(g.world_of(c))), band.has(c), "also as a world position")
	if band.is_empty():
		# No breaker on this level: the side loop off the critical path (R8).
		for c in _level.data.critical_path:
			assert_false(bool(f.call(c)), "critical path cell %s is outside the loop" % c)
	assert_true(inside >= 3, "room to drift (%d cells)" % inside)


## 10 §2 crank row: the Flashlight's crank tick counts, a 12 m mech noise alone does not.
func test_crank_counts_from_the_flashlight_tick() -> void:
	_begin()
	_into_build()
	var i0 := _d.intensity
	EventBus.noise_emitted.emit(_p.global_position, Tuning.NOISE_CRANK_RADIUS, Tuning.NOISE_KIND_MECH)
	assert_approx(_d.intensity, i0, 0.0001, "a mech noise of the crank's radius is not a crank")
	_p.flashlight.crank_tick.emit()
	assert_approx(_d.intensity, i0 + Tuning.INTENSITY_NOISE_CRANK, 0.0001, "+0.10 per crank tick")


## M1.13 ruling: the 0.8 wake hints the nearest hunter to a cell 12 m out and stays in
## Build; only a chase begins Peak. There is no Peak re-hint.
func test_wake_at_0_8_stays_in_build_and_a_chase_begins_peak() -> void:
	_begin()
	var h := _hunter()
	_into_build()
	h.clear_hint()
	_d.pacing.intensity = 0.85
	_advance(0.1)
	assert_eq(_d.phase, DirectorPacing.BUILD, "the 0.8 wake does not begin Peak")
	assert_false(h.is_dormant())
	assert_true(h.has_hint(), "the woken hunter is hinted")
	var d := DirectorSpawn.flat_dist(h._hint, _p.global_position)
	assert_true(absf(d - Tuning.DIRECTOR_WAKE_HINT_DIST) <= Tuning.DIRECTOR_HINT_DIST_TOLERANCE + 0.01,
		"to a cell 12 m out, not the player (%.1f m)" % d)
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	_advance(0.1)
	assert_eq(_d.phase, DirectorPacing.PEAK, "a chase begins Peak")


## M1.13 ruling: Relief clamps intensity to 0.5 and hints every awake hunter away at once
## (25 to 40 m), not 20 s later.
func test_relief_entry_hints_hunters_away_at_once() -> void:
	_begin()
	var h := _hunter()
	_into_build()
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	_advance(0.1)
	assert_eq(_d.phase, DirectorPacing.PEAK)
	h.transition_to(Tuning.ERROR_STATE_SEARCH, "test")
	h.clear_hint()
	h._hint = Vector3.ZERO
	_d.pacing.intensity = 0.95
	_d.pacing.on_evasion(true)
	_advance(0.1)
	assert_eq(_d.phase, DirectorPacing.RELIEF)
	assert_true(_d.intensity <= Tuning.DIRECTOR_RELIEF_INTENSITY_CAP + 0.0001, "intensity ≤ 0.5 (%.2f)" % _d.intensity)
	# The immediate hint (R9) re-targets a Searching Still at once and may consume the flag;
	# the destination it was given stays in `_hint`.
	assert_ne(h._hint, Vector3.ZERO, "hinted on the Relief tick")
	var d := DirectorSpawn.flat_dist(h._hint, _p.global_position)
	assert_true(d >= Tuning.DIRECTOR_RELIEF_HINT_AWAY_DIST - 0.01 and d <= Tuning.DIRECTOR_HINT_AWAY_MAX + 0.01,
		"25 to 40 m from the player (%.1f m)" % d)


## M1.13 (R10): a hunter with no fair cell at entry waits and is spawned by the 1 s retry as
## soon as one exists; after Calm it wakes at once.
func test_pending_hunter_spawns_on_retry() -> void:
	_begin()
	var before := _d.errors.size()
	_into_build()
	_d.hunters.pending.append(&"still")
	_advance(Tuning.DIRECTOR_CALM_CHECK_INTERVAL + 0.05)
	assert_true(_d.hunters.pending.is_empty(), "spawned within a second")
	assert_eq(_d.errors.size(), before + 1)
	var e := _d.errors[_d.errors.size() - 1]
	assert_eq(e.error_id, &"still")
	assert_true(DirectorSpawn.flat_dist(e.body_position(), _p.global_position) >= Tuning.ERROR_SPAWN_MIN_DIST, "at a fair cell")
	assert_false(e.is_dormant(), "after Calm it wakes at once")
