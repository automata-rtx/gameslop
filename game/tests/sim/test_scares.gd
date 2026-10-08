extends TestCase
## 10 §5 scares (M2.7): the budget (one per 30 s) and each kind's interval, the intensity
## scale, Build only (never Calm, Peak, Relief or Pursuit), never with a hunter near (a scare
## never lands on a contact, pillar 3), a failed placement spends nothing; the Director's
## own scheduling on a built Halls level (FakeClock) with recording executors, and the five
## world events against real props: door slam, payphone ring (Payphone.candidates), Static
## swell, fixture dropout, Echo pre-echo.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const PAYPHONE_SCENE := "res://scenes/props/halls/payphone.tscn"
const MAX_FRAMES := 1500
const BUILD := Tuning.DIRECTOR_PHASE_BUILD

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock
var _ran: Array = []


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


func after_all() -> void:
	_level.queue_free()


func before_each() -> void:
	_ran.clear()
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


## Scares whose executors always succeed and record what ran.
func _recording() -> Scares:
	var s := Scares.new(3)
	_fake(s)
	return s


func _fake(s: Scares) -> void:
	for k in Scares.ORDER:
		s.executors[k] = func() -> bool:
			_ran.append(k)
			return true


func _advance(seconds: float) -> void:
	_clock.advance(seconds)
	_d.update()


# --- pure gating --------------------------------------------------------------------------------

func test_budget_and_per_kind_cooldowns() -> void:
	var s := _recording()
	assert_eq(Scares.min_interval(Scares.DOOR_SLAM), 60.0)
	assert_eq(Scares.min_interval(Scares.PAYPHONE), 90.0)
	assert_eq(Scares.min_interval(Scares.STATIC_SWELL), 45.0)
	assert_eq(Scares.min_interval(Scares.FIXTURE_DROPOUT), 40.0)
	assert_eq(Scares.min_interval(Scares.PRE_ECHO), 50.0)
	assert_true(s.request(Scares.STATIC_SWELL, 100.0))
	for k in Scares.ORDER:
		assert_false(s.request(k, 129.9), "%s: at most one scare per 30 s" % k)
	assert_false(s.request(Scares.STATIC_SWELL, 131.0), "swell: its own 45 s")
	assert_true(s.request(Scares.FIXTURE_DROPOUT, 131.0), "another kind after 30 s")
	assert_true(s.request(Scares.STATIC_SWELL, 161.0), "swell again after 61 s, 30 s after the last")
	assert_false(s.request(Scares.FIXTURE_DROPOUT, 192.0 - 21.0), "dropout: 40 s")
	assert_eq(s.count(), 3)
	assert_eq(s.count(Scares.STATIC_SWELL), 2)
	assert_eq(_ran, [Scares.STATIC_SWELL, Scares.FIXTURE_DROPOUT, Scares.STATIC_SWELL])
	# Over a long Build at full intensity, every kind keeps its spacing and the 30 s budget.
	var s2 := _recording()
	_ran.clear()
	var t := 0.0
	while t < 1200.0:
		s2.try_any(BUILD, 0.9, t)
		t += Tuning.DIRECTOR_SCARE_CHECK_INTERVAL
	for i in range(1, s2.fired.size()):
		var gap := float(s2.fired[i][&"time"]) - float(s2.fired[i - 1][&"time"])
		assert_true(gap >= Tuning.SCARE_MIN_INTERVAL - 0.001, "30 s between scares (%.1f)" % gap)
	for k in Scares.ORDER:
		var times: Array = s2.fired.filter(func(f: Dictionary) -> bool: return f[&"kind"] == k).map(
			func(f: Dictionary) -> float: return float(f[&"time"]))
		assert_gt(times.size(), 0, "%s ran in 20 minutes" % k)
		for i in range(1, times.size()):
			assert_true(float(times[i]) - float(times[i - 1]) >= Scares.min_interval(k) - 0.001, "%s interval" % k)
	assert_true(s2.count() <= 40, "no more than one per 30 s in 20 minutes (%d)" % s2.count())


func test_never_in_calm_peak_relief_or_pursuit() -> void:
	var s := _recording()
	for phase: StringName in [Tuning.DIRECTOR_PHASE_CALM, Tuning.DIRECTOR_PHASE_PEAK, Tuning.DIRECTOR_PHASE_RELIEF,
			Tuning.DIRECTOR_PHASE_PURSUIT]:
		for i in [0.0, 0.5, 1.0]:
			assert_true(s.available(phase, i, 1000.0).is_empty(), "%s at %.1f" % [phase, i])
			assert_eq(s.try_any(phase, i, 1000.0), &"", "%s: nothing runs" % phase)
	assert_true(_ran.is_empty(), "no executor was called outside Build")


func test_intensity_scale() -> void:
	var s := _recording()
	assert_true(s.available(BUILD, 0.19, 100.0).is_empty(), "none below 0.2")
	assert_eq(s.available(BUILD, 0.21, 100.0), [Scares.STATIC_SWELL] as Array[StringName], "the cheapest first")
	assert_eq(s.available(BUILD, 0.35, 100.0).size(), 3)
	assert_eq(s.available(BUILD, 0.5, 100.0).size(), Scares.ORDER.size(), "all at 0.5 and above")
	assert_eq(s.available(BUILD, 1.0, 100.0).size(), Scares.ORDER.size())


## Pillar 3: a scare is never the way an error kills, so none plays with a hunter near.
func test_never_with_a_hunter_near() -> void:
	var s := _recording()
	assert_true(s.available(BUILD, 0.9, 100.0, 5.0).is_empty())
	assert_true(s.available(BUILD, 0.9, 100.0, Tuning.SCARE_HUNTER_CLEAR_DIST - 0.1).is_empty())
	assert_eq(s.try_any(BUILD, 0.9, 100.0, 10.0), &"")
	assert_false(s.available(BUILD, 0.9, 100.0, Tuning.SCARE_HUNTER_CLEAR_DIST).is_empty())
	assert_false(s.available(BUILD, 0.9, 100.0, INF).is_empty(), "no awake hunter")


func test_a_scare_with_nowhere_to_happen_spends_nothing() -> void:
	var s := Scares.new(1)
	s.executors[Scares.STATIC_SWELL] = func() -> bool: return false
	assert_false(s.request(Scares.STATIC_SWELL, 100.0))
	assert_eq(s.last_any, -INF, "the budget is untouched")
	assert_eq(s.count(), 0)
	assert_false(s.request(Scares.DOOR_SLAM, 100.0), "no executor bound")
	_fake(s)
	assert_eq(s.try_any(BUILD, 0.9, 100.0) != &"", true)


func test_try_any_is_seeded() -> void:
	var a := _recording()
	var b := _recording()
	for t in range(0, 600, 5):
		assert_eq(a.try_any(BUILD, 0.9, float(t)), b.try_any(BUILD, 0.9, float(t)))


func test_pure_choices() -> void:
	var pts: Array[Vector3] = [Vector3(0, 0, -25), Vector3(0, 0, 25), Vector3(10, 0, 0), Vector3(0, 0, 50)]
	var eye := Vector3(0, 1.6, 0)
	var fwd := Vector3(0, 0, -1)
	var half := deg_to_rad(50.0)
	assert_eq(ScareEvents.pick_far_out_of_view(pts, Vector3.ZERO, eye, fwd, half, 20.0, 40.0), 1,
		"the door behind, not the one in view, not 10 m, not 50 m")
	assert_eq(ScareEvents.pick_far_out_of_view(pts, Vector3.ZERO, eye, Vector3(0, 0, 1), half, 20.0, 40.0), 0)
	assert_eq(ScareEvents.pick_far(pts, Vector3.ZERO, 12.0, 40.0), 0, "the nearest ≥ 12 m")
	assert_eq(ScareEvents.pick_far(pts, Vector3.ZERO, 60.0, 80.0), -1)
	assert_true(ScareEvents.pre_echo_ok(Tuning.ERROR_STATE_DORMANT, 30.0))
	assert_true(ScareEvents.pre_echo_ok(Tuning.ERROR_STATE_WANDER, 25.0))
	assert_false(ScareEvents.pre_echo_ok(Tuning.ERROR_STATE_WANDER, 24.0), "too near")
	for st: StringName in [Tuning.ERROR_STATE_SEARCH, Tuning.ERROR_STATE_FOLLOW, Tuning.ERROR_STATE_SATIATED]:
		assert_false(ScareEvents.pre_echo_ok(st, 40.0), "not while Echo is %s" % st)


# --- the Director's scheduling ---------------------------------------------------------------

func _build_at(intensity: float) -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	_fake(_d.scares)
	_advance(Tuning.DIRECTOR_CALM_TIME + 0.05)
	assert_eq(_d.phase, DirectorPacing.BUILD)
	_d.pacing.intensity = intensity


## Holds intensity (the time input would raise it toward the 0.8 wake) while time passes.
func _hold(seconds: float, intensity: float) -> void:
	var t := 0.0
	while t < seconds:
		_d.pacing.intensity = intensity
		_advance(0.5)
		t += 0.5


func test_director_schedules_scares_in_build_only() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	_fake(_d.scares)
	for i in 70:
		_d.pacing.intensity = 0.9
		_advance(0.5)
		if _d.phase != DirectorPacing.CALM:
			break
	assert_true(_ran.is_empty(), "no scare in Calm")
	assert_eq(_d.phase, DirectorPacing.BUILD)
	for h in _d.errors:
		if is_instance_valid(h) and DirectorRules.is_hunter(h.error_id):
			h.sleep()  # keep every hunter out of the way (none near)
	_hold(120.0, 0.6)
	assert_eq(_d.phase, DirectorPacing.BUILD)
	assert_gt(_ran.size(), 1, "scares in two minutes of Build")
	assert_true(_ran.size() <= 4, "at most one per 30 s (%d)" % _ran.size())
	assert_true(_d.telemetry.to_csv().contains(String(_ran[0])), "the telemetry row names the scare")
	# Relief: none.
	var n := _ran.size()
	_d.on_error_contact(8.0, _d.errors[0])
	assert_eq(_d.phase, DirectorPacing.RELIEF)
	_hold(Tuning.DIRECTOR_RELIEF_AFTER_CONTACT_TIME - 1.0, 0.45)
	assert_eq(_ran.size(), n, "no scare in Relief")
	# Peak: none.
	_d.pacing._enter(DirectorPacing.PEAK)
	_hold(30.0, 0.9)
	assert_eq(_ran.size(), n, "no scare in Peak")
	assert_true(_d.request_scare() == false, "request_scare refuses outside Build")


## A scare never coincides with a contact: none with a hunter within 15 m, none in the
## Relief a contact opens, and none in the 30 s after one runs.
func test_scare_never_coincides_with_contact() -> void:
	_build_at(0.9)
	var h: ErrorBase = null
	for e in _d.errors:
		if is_instance_valid(e) and DirectorRules.is_hunter(e.error_id):
			h = e
	if h == null:
		h = _d.hunters.spawn(&"still", _level.data.grid.world_of(_level.data.critical_path[_level.data.critical_path.size() - 1]))
	h.wake()
	if h is ErrorStill:
		(h as ErrorStill).place_at(_p.global_position + Vector3(8.0, 0.0, 0.0))
	else:
		h.global_position = _p.global_position + Vector3(8.0, 0.0, 0.0)
	_hold(40.0, 0.9)
	assert_true(_ran.is_empty(), "a hunter 8 m away: no scare (%s)" % [_ran])
	assert_false(_d.request_scare(), "not on request either")
	h.sleep()
	_hold(6.0, 0.9)
	assert_eq(_ran.size(), 1, "the hunter gone dormant: a scare")
	var t_scare := _d.pacing.level_time
	_d.on_error_contact(8.0, h)
	assert_eq(_d.phase, DirectorPacing.RELIEF, "the bite opens Relief")
	_hold(20.0, 0.9)
	assert_eq(_ran.size(), 1, "nothing during that Relief")
	assert_true(_d.pacing.level_time - t_scare >= 19.9, "20 s on (%.1f)" % (_d.pacing.level_time - t_scare))


# --- the world events on a real level ----------------------------------------------------------

func test_fixture_dropout_goes_dark_for_good() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	var breakers: Array[Breaker] = []
	for n in get_tree().get_nodes_in_group(&"breakers"):
		if n is Breaker and _level.is_ancestor_of(n) and not (n as Breaker).is_thrown:
			breakers.append(n as Breaker)
	if not breakers.is_empty():
		assert_false(_d.scare_events.fixture_dropout(), "not before the breaker (its wave would relight it)")
		for b in breakers:
			b.is_thrown = true
	var ok := _d.scare_events.fixture_dropout()
	for b in breakers:
		b.is_thrown = false
	assert_true(ok, "a Halls level has a fixture 12 to 40 m away")
	var dropped: Fixture = null
	for n in get_tree().get_nodes_in_group(&"fixtures"):
		if n.has_meta(&"dropped_out"):
			dropped = n as Fixture
	assert_not_null(dropped)
	assert_false(dropped.powered, "dark")
	assert_false(dropped.is_flickering(), "not a flicker (02 §6)")
	var d := DirectorSpawn.flat_dist(dropped.global_position, _p.global_position)
	assert_true(d >= 12.0 and d <= 40.0, "12 to 40 m away (%.1f)" % d)
	dropped.set_powered(true)
	dropped.remove_meta(&"dropped_out")


func test_payphone_ring_is_wired_to_candidates() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	for n in get_tree().get_nodes_in_group(Payphone.GROUP):
		(n as Node).remove_from_group(Payphone.GROUP)  # only the test's phones
	var near := (load(PAYPHONE_SCENE) as PackedScene).instantiate() as Payphone
	var far := (load(PAYPHONE_SCENE) as PackedScene).instantiate() as Payphone
	_level.add_child(near)
	_level.add_child(far)
	near.global_position = _p.global_position + Vector3(5.0, 0.0, 0.0)
	far.global_position = _p.global_position + Vector3(0.0, 0.0, 22.0)
	assert_true(_d.scare_events.payphone())
	assert_false(near.ringing, "5 m is too near")
	assert_true(far.ringing, "the payphone 22 m away rings")
	assert_eq(_d.scare_events.ringing_count(), 1)
	assert_false(_d.scare_events.payphone(), "no second phone in range")
	_d.scare_events.stop_ongoing()
	far.tick(0.1)
	assert_false(far.ringing, "Build ended: it falls silent")
	near.queue_free()
	far.queue_free()


func test_static_swell_is_4_db_for_3_s() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	var st: ErrorStatic = null
	for e in _d.errors:
		if e is ErrorStatic:
			st = e as ErrorStatic
	assert_not_null(st, "Halls spawns a Static")
	await await_physics_frames(3)
	var hum := ScareEvents._hum_player(st)
	if hum == null:
		assert_false(_d.scare_events.static_swell(), "no hum playing: nothing to swell")
		return
	var base := float(hum.get_meta(AudioLoop.META_BASE, 0.0))
	var radius := st.radius
	var state := st.state
	assert_true(_d.scare_events.static_swell())
	assert_approx(float(hum.get_meta(AudioLoop.META_BASE, 0.0)), base + Tuning.SCARE_STATIC_SWELL_DB, 0.001, "+4 dB")
	_clock.advance(Tuning.SCARE_STATIC_SWELL_TIME - 0.2)
	_d.scare_events.tick(_d.now())
	assert_approx(float(hum.get_meta(AudioLoop.META_BASE, 0.0)), base + Tuning.SCARE_STATIC_SWELL_DB, 0.001)
	_clock.advance(0.3)
	_d.scare_events.tick(_d.now())
	assert_approx(float(hum.get_meta(AudioLoop.META_BASE, 0.0)), base, 0.001, "back after 3 s")
	assert_eq(st.radius, radius, "no gameplay change: the field is the same")
	assert_eq(st.state, state)


func test_pre_echo_needs_a_far_quiet_echo_and_the_door_slam_a_far_closed_door() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	for e in _d.errors.duplicate():
		if is_instance_valid(e) and e.error_id == &"echo":
			_d.errors.erase(e)
			e.queue_free()
	assert_false(_d.scare_events.pre_echo(), "no Echo on the level")
	var g := _level.data.grid
	var far_cell := DirectorSpawn.cell_at_distance(g, _p.global_position, 30.0, make_rng(4))
	var echo := _d.hunters.spawn(&"echo", g.world_of(far_cell))
	assert_true(echo.is_dormant())
	assert_true(_d.scare_events.pre_echo(), "dormant Echo 30 m away: one step plays there")
	echo.global_position = _p.global_position + Vector3(6.0, 0.0, 0.0)
	assert_false(_d.scare_events.pre_echo(), "too near")
	# Door slam: a closed door 20 to 40 m away, out of view, slams open.
	var doors: Array[Door] = []
	for n in get_tree().get_nodes_in_group(&"doors"):
		if n is Door and _level.is_ancestor_of(n):
			doors.append(n as Door)
	assert_gt(doors.size(), 0, "Halls has doors")
	for dr in doors:
		dr.close()
	# Stand 25 to 35 m from the first door, facing away from it.
	var home := _p.global_position
	var home_rot := _p.rotation
	var spot := Vector3.INF
	for i in g.cell_count():
		var w := g.world_of(g.cell_at(i))
		var dd := DirectorSpawn.flat_dist(w, doors[0].global_position)
		if g.is_walkable(g.cell_at(i)) and dd >= 25.0 and dd <= 35.0:
			spot = w
			break
	assert_ne(spot, Vector3.INF, "a cell 25 to 35 m from the door")
	_p.global_position = spot
	var away := spot - doors[0].global_position
	_p.rotation = Vector3(0.0, atan2(-away.x, -away.z), 0.0)
	var heard: Array = []
	var on_noise := func(pos: Vector3, radius: float, kind: StringName) -> void:
		heard.append([pos, radius, kind])
	EventBus.noise_emitted.connect(on_noise)
	var ok := _d.scare_events.door_slam()
	EventBus.noise_emitted.disconnect(on_noise)
	assert_true(ok, "a closed door 25 to 35 m behind the player slams")
	var slammed: Door = null
	for dr in doors:
		if dr.is_open:
			slammed = dr
	assert_not_null(slammed)
	var dist := DirectorSpawn.flat_dist(slammed.global_position, _p.global_position)
	assert_true(dist >= 20.0 and dist <= 40.0, "20 to 40 m (%.1f)" % dist)
	assert_eq(heard.size(), 1)
	assert_approx(float(heard[0][1]), 18.0, 0.001, "an 18 m door noise")
	assert_eq(heard[0][2], Tuning.NOISE_KIND_DOOR)
	assert_true(DirectorSpawn.flat_dist(heard[0][0], _p.global_position) >= 20.0, "at the door, never at the player")
	var cam := _p.rig.camera
	assert_false(DirectorSpawn.in_cone(_p.eye_position(), -cam.global_transform.basis.z,
		DirectorSpawn.half_fov_h(cam.fov, 16.0 / 9.0), slammed.global_position + Vector3.UP), "out of the frustum")
	slammed.close()
	_p.global_position = home
	_p.rotation = home_rot
