extends TestCase
## M3.4: the Offices light dilemma (08 §1 "Still wants your light on it; Flicker wants your
## light off", 08 §5), as a truth table with both errors awake on one floor: the real player,
## Still, Flicker and a hand-built LightPool registered as the player's light query (what
## `Level.attach_player` does). Groups of Halls tubes 3 m up along +X: A (x 0, 4) and the
## room B (x 10, 14), adjacent; D far away (x -30). The player stands under B at (12, 2)
## facing -Z; Still stands at (12, -4), inside B's light range (7 m) and in view.
##   B powered, light off   -> Still held by the fixtures; Flicker in B stalks and lunges.
##   B dark,    light off   -> Flicker cannot live in B (no Stalk); Still is not observed and walks.
##   B dark,    light on    -> the beam holds Still; Flicker in A, 8 m off, neither stalks nor attaches.
##   B powered, light on    -> the beam holds Still, but Flicker in B attaches to it.
##   B dark, then the breaker's wave -> B is habitable again: the safe dark is gone.
## No game rule is tested here that the error suites do not already cover one by one; this
## is the conflict between the two counters, verified (15 §2 M3).

const TUBE := "res://scenes/props/halls/fixture_tube.tscn"
const HEIGHT := 3.0
const GROUPS := {0: [0.0, 4.0], 1: [10.0, 14.0], 3: [-30.0]}
const ROOM := 1
const NEXT := 0
const PLAYER_AT := Vector3(12, 0, 2)
const STILL_AT := Vector3(12, 0, -4)

var _world: Node3D
var _p: Player
var _pool: LightPool
var _contacts: Dictionary = {}


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(PLAYER_AT.x, 0.05, PLAYER_AT.z))
	_p.rotation = Vector3.ZERO  # facing -Z, toward Still
	_pool = LightPool.new()
	_world.add_child(_pool)
	_pool.configure(load("res://data/strata/halls.tres") as StratumData)
	for g: int in GROUPS:
		for x: float in GROUPS[g]:
			var f := (load(TUBE) as PackedScene).instantiate() as Fixture
			_world.add_child(f)
			f.global_position = Vector3(x, HEIGHT, 0)
			f.group_id = g
			_pool.register_fixture(f)
	_p.add_light_query(_pool.is_lit)
	_contacts = {}
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()
	await await_physics_frames(1)


func _gate(id: StringName) -> Callable:
	return func(_e: ErrorBase) -> bool:
		_contacts[id] = int(_contacts.get(id, 0)) + 1
		return true


func _flicker(group: int) -> ErrorFlicker:
	var c := _pool.group_centroid(group)
	var e := ErrorFixture.spawn(_world, &"flicker", Vector3(c.x, 0, c.z), _p, 7) as ErrorFlicker
	e.light_pool = _pool
	e.set_aggression(0.25)
	e.contact_request = _gate(&"flicker")
	e.wake()
	return e


func _still() -> ErrorStill:
	var s := ErrorFixture.spawn(_world, &"still", STILL_AT, _p) as ErrorStill
	s.set_aggression(0.25)
	s.contact_request = _gate(&"still")
	s.hint(_p.global_position)
	s.wake()
	return s


## Watches both errors for `t` seconds with the player standing still: the frames Still was
## observed, how far it moved, whether Flicker stalked or attached, its lunges.
func _watch(still: ErrorStill, fl: ErrorFlicker, t: float) -> Dictionary:
	var start := still.body_position()
	var out := {&"observed": 0, &"frames": 0, &"moved": 0.0, &"stalked": false, &"attached": false}
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		_p.global_position = Vector3(PLAYER_AT.x, _p.global_position.y, PLAYER_AT.z)
		_p.velocity = Vector3.ZERO
		out[&"frames"] = int(out[&"frames"]) + 1
		out[&"observed"] = int(out[&"observed"]) + (1 if _p.is_observing(still) else 0)
		out[&"moved"] = maxf(float(out[&"moved"]), still.body_position().distance_to(start))
		out[&"stalked"] = bool(out[&"stalked"]) or fl.state == Tuning.ERROR_STATE_STALK
		out[&"attached"] = bool(out[&"attached"]) or fl.is_attached()
	out[&"lunges"] = fl.lunges
	return out


func test_lit_room_holds_still_and_feeds_flicker() -> void:
	_p.flashlight.set_on(false, true)
	var fl := _flicker(ROOM)
	var still := _still()
	var w := await _watch(still, fl, 4.0)
	assert_eq(w[&"observed"], w[&"frames"], "the powered fixtures light Still: observed every frame")
	assert_eq(w[&"moved"], 0.0, "Still holds")
	assert_true(w[&"stalked"], "standing in the room's light, Flicker stalks")
	assert_gt(int(w[&"lunges"]), 0, "and lunges")
	assert_eq(int(_contacts.get(&"flicker", 0)), 1, "the lunge lands (30)")
	assert_eq(int(_contacts.get(&"still", 0)), 0)


func test_dark_room_starves_flicker_and_frees_still() -> void:
	_pool.set_group_powered(ROOM, false)
	_p.flashlight.set_on(false, true)
	var fl := _flicker(NEXT)
	var still := _still()
	var w := await _watch(still, fl, 4.0)
	assert_eq(w[&"observed"], 0, "in the dark, looking is not enough")
	assert_gt(float(w[&"moved"]), 1.0, "Still walks")
	assert_false(w[&"stalked"], "no Stalk in an unpowered group")
	assert_eq(int(w[&"lunges"]), 0)
	assert_false(FlickerHabitat.habitable(_pool, ROOM), "Flicker cannot hop into the dark room")


func test_beam_in_the_dark_holds_still_away_from_flicker() -> void:
	_pool.set_group_powered(ROOM, false)
	_p.flashlight.set_on(true, true)
	var fl := _flicker(NEXT)
	var still := _still()
	var w := await _watch(still, fl, 4.0)
	assert_eq(w[&"observed"], w[&"frames"], "the beam lights Still")
	assert_eq(w[&"moved"], 0.0, "Still holds")
	assert_false(w[&"stalked"], "Flicker's group is 8 m off: no lit area here")
	assert_false(w[&"attached"], "and no fixture of its group within 4 m to attach from")
	assert_eq(_contacts, {}, "no contact")


func test_beam_in_a_lit_room_gets_flicker_attached() -> void:
	_p.flashlight.set_on(true, true)
	var fl := _flicker(ROOM)
	var still := _still()
	var w := await _watch(still, fl, 2.0)
	assert_eq(w[&"moved"], 0.0, "Still holds")
	assert_true(w[&"attached"], "the beam on near Flicker's fixtures: it attaches")


func test_breaker_wave_ends_the_safe_dark() -> void:
	_pool.set_group_powered(ROOM, false)
	assert_false(FlickerHabitat.habitable(_pool, ROOM))
	_p.flashlight.set_on(false, true)
	var fl := _flicker(NEXT)
	var t := _pool.power_wave(Vector3(-30, 0, 0))
	await await_physics_frames(int((t + 0.5) * Engine.physics_ticks_per_second))
	assert_true(FlickerHabitat.habitable(_pool, ROOM), "the wave powers the room: Flicker can live there")
	assert_true(FlickerHabitat.habitable_neighbours(_pool, NEXT).has(ROOM), "and hop in from the next group")
	var still := _still()
	var w := await _watch(still, fl, 1.0)
	assert_eq(w[&"observed"], w[&"frames"], "and Still is held by the light again")
