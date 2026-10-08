extends TestCase
## 08 §6 Echo, headless on the flat navigable floor with the real player walking on its own
## input: it follows the heard trail 800 ms behind the newest heard step at the player's
## pace, freezes when the player stops, hears only what the noise model lets it hear (radius,
## walls, aggression), searches without walking into a standing player, is pulled by a
## lure, contacts only through the gates, counts notice and evasion, walks back along its
## own steps when Satiated, mirrors steps and shows the shimmer only within 4 m, waits for
## navigation, takes immediate hints, and is deterministic per seed.

var _world: Node3D
var _p: Player


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(3)


func after_each() -> void:
	Engine.time_scale = 1.0
	PlayerFixture.release_all()
	_world.free()
	await await_physics_frames(1)


func _echo(pos: Vector3, aggression: float = 0.25, seed_value: int = 7) -> ErrorEcho:
	var e := ErrorFixture.spawn(_world, &"echo", pos, _p, seed_value) as ErrorEcho
	e.set_aggression(aggression)
	return e


func _seconds(t: float) -> void:
	await await_physics_frames(int(t * Engine.physics_ticks_per_second))


## Walks the player forward (-Z) for `t` seconds; returns the player's position each frame.
func _walk(t: float, extra: StringName = &"") -> Array[Vector3]:
	var out: Array[Vector3] = []
	Input.action_press(&"move_forward")
	if extra != &"":
		Input.action_press(extra)
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		out.append(_p.global_position)
	Input.action_release(&"move_forward")
	if extra != &"":
		Input.action_release(extra)
	return out


## An Echo 2.5 m behind the player, already following a short walk.
func _following(aggression: float = 0.25) -> ErrorEcho:
	var e := _echo(Vector3(0, 0, 2.5), aggression)
	e.wake()
	await await_physics_frames(2)
	await _walk(1.5)
	return e


# --- the rule: 800 ms behind the newest heard step ------------------------------------------------

func test_follows_the_trail_800_ms_behind_the_newest_heard_step() -> void:
	var e := await _following()
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW, "three heard steps within 5 s: Follow")
	var top := 0.0
	var closest := INF
	var last := e.body_position()
	Input.action_press(&"move_forward")
	for i in 240:
		await get_tree().physics_frame
		var now := e.body_position()
		top = maxf(top, ErrorFixture.flat(now, last) / get_physics_process_delta_time())
		last = now
		closest = minf(closest, ErrorFixture.flat(now, _p.global_position))
		# The target entry is 800 ms before the newest heard entry (never before "now").
		var ti := e.trail.target_index()
		if ti >= 0 and e.trail.size() > 6:
			var lag := e.trail.newest_time() - float(e.trail.entries[ti][&"time"])
			assert_true(lag >= Tuning.ECHO_TRAIL_DELAY - 0.001 and lag < Tuning.ECHO_TRAIL_DELAY + 0.25,
					"target lag %.3f s" % lag)
	Input.action_release(&"move_forward")
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW)
	assert_lt(top, Tuning.PLAYER_WALK_SPEED + 0.15, "it mirrors the walk pace, never faster")
	assert_gt(top, Tuning.PLAYER_WALK_SPEED - 0.4, "and keeps it")
	assert_gt(closest, 2.0, "about three steps behind, never on the player")
	assert_gt(e.steps_played, 10, "its own steps play the player's surface (the tell)")


func test_freezes_when_the_player_stops() -> void:
	var e := await _following()
	await _walk(2.0)
	# Stopped: no new entries; Echo reaches its target (about 2.6 m back) and stands.
	await _seconds(1.5)
	var at := e.body_position()
	var trail_n := e.trail.size()
	await _seconds(2.0)
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW, "still following within the loss timeout")
	assert_lt(ErrorFixture.flat(e.body_position(), at), 0.05, "frozen at its target")
	assert_eq(e.trail.size(), trail_n, "no new entries while the player stands")
	var d := ErrorFixture.flat(e.body_position(), _p.global_position)
	assert_gt(d, 1.8, "stands behind the player (%.2f m)" % d)
	assert_lt(d, 3.6, "about three steps back (%.2f m)" % d)
	# Its stand is the entry 800 ms before the last heard step.
	var target: Vector3 = e.trail.entries[e.trail.target_index()][&"position"]
	assert_lt(ErrorFixture.flat(e.body_position(), target), Tuning.ECHO_ENTRY_ARRIVE_DIST + 0.05)


func test_search_after_the_trail_ends_never_walks_into_a_standing_player() -> void:
	var e := await _following(0.75)  # 4 s loss timeout
	var hits := [0]
	e.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	await _walk(1.0)
	var closest := INF
	var searched := false
	for i in int(16.0 * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		searched = searched or e.state == Tuning.ERROR_STATE_SEARCH
		closest = minf(closest, ErrorFixture.flat(e.body_position(), _p.global_position))
	assert_true(searched, "the trail ended: Search")
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "gave up after 10 s")
	assert_eq(hits[0], 0, "a player who stands still is not walked into")
	assert_gt(closest, Tuning.ECHO_SEARCH_MIN_POINT_DIST - 0.3, "Search keeps off the player's point (%.2f m)" % closest)


func test_search_points_avoid_the_heard_point() -> void:
	var e := _echo(Vector3(0, 0, 3))
	e.wake()
	await await_physics_frames(2)
	var point := Vector3(0, 0, 0)
	var plan := EchoNav.plan_inspection(e, point)
	assert_gt(plan.size(), 0)
	for p in plan:
		assert_gt(ErrorFixture.flat(p, point), Tuning.ECHO_SEARCH_MIN_POINT_DIST - 0.01, "never the point itself")
	var stand := EchoNav.stand_off(e, Vector3(0, 0, 2.5))
	assert_gt(ErrorFixture.flat(stand, Vector3(0, 0, 2.5)), Tuning.ECHO_SEARCH_MIN_POINT_DIST - 0.01, "stands off")


# --- honest senses ------------------------------------------------------------------------------

func test_never_hears_steps_beyond_the_noise_radius() -> void:
	var e := _echo(Vector3(0, 0, 8.0))  # carpet walk step: 5 m
	e.wake()
	await await_physics_frames(2)
	await _walk(1.5)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "8 m+ from 5 m steps: nothing heard")
	assert_eq(e.trail.size(), 0)


func test_never_hears_through_walls_per_the_model() -> void:
	var e := _echo(Vector3(0, 0, 10.0))
	e.wake()
	await await_physics_frames(2)
	PlayerFixture.wall(_world, Vector3(6, 3, 0.2), Vector3(4, 1.5, 8.0))
	await await_physics_frames(2)
	# 4 m through one wall: 5 m x 0.65 = 3.25 m effective. Not heard.
	EventBus.noise_emitted.emit(Vector3(4, 0, 6.0), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "the wall cuts the step to 3.25 m")
	# The same step in the open at 4 m is heard.
	EventBus.noise_emitted.emit(Vector3(0, 0, 14.0), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH, "heard in the open: Search toward it")


func test_aggression_mapping() -> void:
	var e := _echo(Vector3(0, 0, 20.0), 0.25)
	assert_approx(e.senses.hearing_mult, 1.0, 0.0001)
	assert_approx(e.trail_loss_time(), 6.0, 0.0001)
	e.set_aggression(0.5)
	assert_approx(e.senses.hearing_mult, 1.2, 0.0001)
	assert_approx(e.trail_loss_time(), 5.0, 0.0001)
	e.set_aggression(1.0)
	assert_approx(e.senses.hearing_mult, 1.4, 0.0001, "clamped to the 0.75 column")
	assert_approx(e.trail_loss_time(), 4.0, 0.0001)
	e.wake()
	await await_physics_frames(2)
	# 6.5 m from a 5 m step: heard only with the 1.4 multiplier (7 m).
	EventBus.noise_emitted.emit(Vector3(0, 0, 13.5), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)


func test_crouch_walking_breaks_the_trail() -> void:
	var e := await _following(0.75)
	await _walk(5.5, &"crouch")  # crouch steps: 2 m, under its follow distance
	assert_ne(e.state, Tuning.ERROR_STATE_FOLLOW, "crouch-walking is the second counter")


func test_three_steps_within_5_s_to_follow_and_one_step_is_search() -> void:
	var e := _echo(Vector3(0, 0, 10.0))
	var notices := [0]
	e.noticed_player.connect(func() -> void: notices[0] += 1)
	e.wake()
	await await_physics_frames(2)
	EventBus.noise_emitted.emit(Vector3(0, 0, 6.0), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	await _seconds(0.3)
	EventBus.noise_emitted.emit(Vector3(0, 0, 6.2), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	await _seconds(0.3)
	EventBus.noise_emitted.emit(Vector3(0, 0, 6.4), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW, "three heard steps within 5 s")
	assert_eq(notices[0], 1, "noticed once on Follow")
	assert_eq(e.trail.size(), 3, "the trail starts at the earliest heard step")


# --- the lure -------------------------------------------------------------------------------------

func test_a_lure_pulls_it() -> void:
	var e := await _following()
	await _seconds(1.0)  # the player stands; Echo stands at its target
	var lure := e.body_position() + Vector3(6.0, 0, 1.0)
	EventBus.noise_emitted.emit(lure, Tuning.ECHO_LURE_IMPACT_RADIUS * 1.5, Tuning.NOISE_KIND_IMPACT)
	assert_eq(e.lure, lure, "standing at its target, a heard lure redirects it")
	await _seconds(3.0)
	assert_lt(ErrorFixture.flat(e.body_position(), lure), Tuning.ECHO_SEARCH_MIN_POINT_DIST + 0.8, "walked to it")
	assert_gt(ErrorFixture.flat(e.body_position(), _p.global_position), 4.0, "away from the player")
	# The trail then ends at the lure: Search there, not at the player.
	await _seconds(4.0)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	assert_eq(e.last_heard, lure)


# --- contact, notice, evasion, Satiated -------------------------------------------------------------

func test_contact_only_through_the_gate() -> void:
	var e := _echo(Vector3(0, 0, 0.8))
	e.hint(_p.global_position)  # its Wander leg ends on the player: it stays in reach
	var asked := [0]
	e.contact_request = func(_e: ErrorBase) -> bool:
		asked[0] += 1
		return false
	var hits := [0]
	e.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	e.wake()
	await await_physics_frames(20)
	assert_gt(asked[0], 0, "the gate was asked")
	assert_eq(hits[0], 0)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001, "refused: nothing applied")
	_p.contact_gate = func(_e: Node3D) -> bool: return false
	e.contact_request = func(_e: ErrorBase) -> bool: return true
	await await_physics_frames(10)
	assert_eq(hits[0], 0, "the player's own gate refuses too")
	_p.contact_gate = Callable()
	await await_physics_frames(6)
	assert_eq(hits[0], 1)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.ECHO_CONTACT_COST, 0.0001, "25 on contact")
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED)


func test_evasion_when_the_trail_breaks() -> void:
	var e := _echo(Vector3(0, 0, 2.5), 0.75)
	var notices := [0]
	var lost := [0]
	e.noticed_player.connect(func() -> void: notices[0] += 1)
	e.lost_player.connect(func() -> void: lost[0] += 1)
	e.wake()
	await await_physics_frames(2)
	await _walk(2.5)
	assert_eq(notices[0], 1, "Follow is the notice")
	assert_eq(lost[0], 0)
	await _seconds(4.5)  # 4 s without a heard step
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	assert_eq(lost[0], 0, "not yet: Search may pick the steps up again")
	Engine.time_scale = 2.0
	await _seconds(11.0 / 2.0 * 2.0)
	Engine.time_scale = 1.0
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER)
	assert_eq(lost[0], 1, "left Follow via Search without contact: an evasion")


func test_steps_after_a_hide_resume_follow_at_once() -> void:
	var e := await _following(0.75)
	await _seconds(4.5)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	EventBus.noise_emitted.emit(_p.global_position, 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW, "one heard step resumes the engagement")


func test_satiated_walks_back_along_its_own_steps() -> void:
	var e := await _following()
	await _walk(2.0)
	var steps_before := e.steps_played
	var at := e.body_position()
	e.retreat(20.0)
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED)
	await _seconds(2.0)
	assert_gt(ErrorFixture.flat(e.body_position(), _p.global_position), ErrorFixture.flat(at, _p.global_position) + 2.0,
			"walks back the way it came")
	assert_gt(e.steps_played, steps_before + 4, "playing its steps (the sound recedes)")
	EventBus.noise_emitted.emit(_p.global_position, 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED, "no chase while Satiated")


# --- presentation, dormancy, hints, determinism -------------------------------------------------------

func test_shimmer_and_breath_only_within_4_m() -> void:
	var e := _echo(Vector3(0, 0, 3.0))
	e.wake()
	await await_physics_frames(4)
	assert_approx(e.presence, 1.0, 0.0001)
	assert_true(e.shimmer.visible)
	assert_gt(e.breaths, 0, "a swell on entering 4 m")
	e.sleep()
	e.place_at(Vector3(0, 0, 8.0))
	e.wake()
	await await_physics_frames(4)
	assert_approx(e.presence, 0.0, 0.0001)
	assert_false(e.shimmer.visible)
	assert_approx(EchoPresent.presence_at(4.0), 1.0, 0.0001, "full at 4 m")
	assert_approx(EchoPresent.presence_at(4.0 + Tuning.ECHO_SHIMMER_FADE), 0.0, 0.0001)


func test_dormant_until_navigation_is_ready() -> void:
	var e := ErrorBase.create(&"echo") as ErrorEcho
	e.setup(_p, null, 3)
	_world.add_child(e)
	e.global_position = Vector3(0, 0, 3)
	e.wake()
	await await_physics_frames(10)
	assert_eq(e.state, Tuning.ERROR_STATE_DORMANT, "no navigation: dormant")
	EventBus.noise_emitted.emit(Vector3(0, 0, 2), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.trail.size(), 0, "dormant errors do not listen")
	e.set_navigation_ready(true)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "the remembered wake")


func test_immediate_hint_retargets_wander_and_search() -> void:
	var e := _echo(Vector3(0, 0, 20.0))
	e.wake()
	await await_physics_frames(2)
	e.hint(Vector3(15, 0, 15), true)
	assert_lt(ErrorFixture.flat(e._target, Vector3(15, 0, 15)), 0.3, "Wander walks to it now")
	EventBus.noise_emitted.emit(Vector3(0, 0, 16.0), 5.0, Tuning.NOISE_KIND_STEP)
	assert_eq(e.state, Tuning.ERROR_STATE_SEARCH)
	e.hint(Vector3(-15, 0, 20), true)
	assert_lt(ErrorFixture.flat(e._target, Vector3(-15, 0, 20)), 0.3, "Search inspects it now")


func test_deterministic_per_seed() -> void:
	var a := _echo(Vector3(0, 0, 10), 0.25, 42)
	var b := _echo(Vector3(0, 0, 10), 0.25, 42)
	var c := _echo(Vector3(0, 0, 10), 0.25, 43)
	var pa := EchoNav.plan_inspection(a, Vector3(0, 0, 4))
	var pb := EchoNav.plan_inspection(b, Vector3(0, 0, 4))
	var pc := EchoNav.plan_inspection(c, Vector3(0, 0, 4))
	assert_eq(pa, pb, "same seed, same Search")
	assert_ne(pa, pc, "another seed, another Search")
	assert_eq(EchoNav.random_point_near(a, Vector3.ZERO, 10.0), EchoNav.random_point_near(b, Vector3.ZERO, 10.0))
