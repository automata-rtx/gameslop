extends TestCase
## 10 §4 contact exclusivity (CHANGELOG: owned by the Director): two Stills reach the
## player; the Director approves the first through `Player.contact_gate`, refuses the
## second within 3 s and that error retreats (DIRECTOR_CONTACT_REFUSED_RETREAT); the first
## is Satiated for 20 s. On a FakeClock.

var _world: Node3D
var _p: Player
var _d: Director
var _clock: FakeClock


func before_each() -> void:
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3.ZERO)
	_clock = fake_clock(100.0)
	_d = Director.new()
	_d.time_source = _clock.now
	_world.add_child(_d)
	_d.begin(null, _p)
	await await_physics_frames(2)


func after_each() -> void:
	_world.queue_free()
	await await_frames(2)


func _still(pos: Vector3, seed_value: int) -> ErrorStill:
	var e := _d.spawn_error(&"still", pos) as ErrorStill
	e.set_navigation_ready(true)
	e.wake()
	return e


func test_gate_is_wired_and_given_back() -> void:
	assert_true(_p.contact_gate.is_valid(), "begin sets Player.contact_gate")
	_d.end()
	assert_false(_p.contact_gate.is_valid(), "end clears it")


func test_second_contact_within_3_s_is_refused_and_retreats() -> void:
	var a := _still(Vector3(0.5, 0, 0), 1)
	var b := _still(Vector3(-0.5, 0, 0), 2)
	assert_eq(_d.errors.size(), 2)
	var hits: Array[StringName] = []
	_p.contacted.connect(func(by: StringName) -> void: hits.append(by))
	assert_true(a.try_contact(Tuning.STILL_CONTACT_COST), "the first contact lands")
	assert_eq(a.state, Tuning.ERROR_STATE_SATIATED, "the contacting error is Satiated")
	_clock.advance(1.0)
	assert_false(b.try_contact(Tuning.STILL_CONTACT_COST), "a second contact 1 s later is refused")
	assert_eq(b.state, Tuning.ERROR_STATE_SATIATED, "the refused error retreats")
	assert_approx(b._satiated_left, Tuning.DIRECTOR_CONTACT_REFUSED_RETREAT, 0.01, "for 5 s")
	assert_approx(a._satiated_left, Tuning.ERROR_SATIATED_TIME, 0.05, "the first keeps its 20 s")
	assert_eq(hits.size(), 1, "the player was touched once")
	assert_eq(_d.contacts, 1)
	assert_eq(_d.refused, 1)
	_clock.advance(2.0)
	assert_true(_d.try_contact(b), "3 s after the first, contact is allowed again")


func test_window_boundaries() -> void:
	var a := _still(Vector3(10, 0, 0), 3)
	assert_true(_d.try_contact(a))
	_clock.advance(2.99)
	assert_false(_d.try_contact(a))
	_clock.advance(0.01)
	assert_true(_d.try_contact(a))


func test_contact_ends_the_peak() -> void:
	_d.pacing._enter(DirectorPacing.BUILD)
	_d.pacing.take_actions()
	var a := _still(Vector3(0.5, 0, 0), 4)
	_d.pacing.intensity = 0.9
	a.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	_clock.advance(0.1)
	_d.update()
	assert_eq(_d.phase, DirectorPacing.PEAK, "a chase is on")
	var before := _d.intensity
	assert_true(a.try_contact(Tuning.STILL_CONTACT_COST))
	assert_eq(_d.phase, DirectorPacing.RELIEF, "the bite ends the peak")
	assert_approx(_d.pacing.relief_length, Tuning.DIRECTOR_RELIEF_AFTER_CONTACT_TIME, 0.001)
	assert_approx(_d.intensity, minf(before + Tuning.INTENSITY_CONTACT, Tuning.DIRECTOR_RELIEF_INTENSITY_CAP), 0.0001,
		"−0.40, then Relief's 0.5 clamp")
