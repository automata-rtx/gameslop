extends TestCase
## R12 (pillar 2, the 2026-10-08 ruling: a contact follows a notice and a chase): Still and
## Echo contact only from their chase state. Each case the M2.7 sims found is reproduced
## headless on the flat navigable floor: a Wander or Search walk that meets the player
## (Still, Echo), Still's hide-spot check (it finds the player, chases, then contacts; a
## chase the Director sends away lands nothing), and Echo's Follow carried into Relief (the
## immediate hint ends it, without an evasion).

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


func _spawn(id: StringName, pos: Vector3) -> ErrorBase:
	var e := ErrorFixture.spawn(_world, id, pos, _p)
	e.set_aggression(0.25)
	return e


## Counts approved contacts and the gate's questions; the gate approves.
func _watch(e: ErrorBase) -> Dictionary:
	var w := {"hits": 0, "asked": 0, "states": []}
	e.contacted_player.connect(func(_c: float) -> void: w["hits"] += 1)
	e.contact_request = func(_e: ErrorBase) -> bool:
		w["asked"] += 1
		return true
	e.state_changed.connect(func(_f: StringName, to: StringName) -> void: (w["states"] as Array).append(to))
	return w


func _seconds(t: float) -> void:
	await await_physics_frames(int(t * Engine.physics_ticks_per_second))


## The nearest the error came to the player over `t` seconds.
func _closest_over(e: ErrorBase, t: float) -> float:
	var closest := INF
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		closest = minf(closest, ErrorFixture.flat(e.body_position(), _p.global_position))
	return closest


# --- the gate itself ------------------------------------------------------------------------

func test_contact_states_are_the_chase_states() -> void:
	for st in Tuning.DIRECTOR_CHASE_STATES:
		assert_true(ErrorBase.CONTACT_STATES.has(st), "%s may contact" % st)
	assert_true(ErrorBase.CONTACT_STATES.has(Tuning.ERROR_STATE_LUNGE), "Flicker's lunge ends a Stalk")
	for st in [Tuning.ERROR_STATE_DORMANT, Tuning.ERROR_STATE_WANDER, Tuning.ERROR_STATE_SEARCH,
			Tuning.ERROR_STATE_SATIATED, Tuning.ERROR_STATE_RESIDENT]:
		assert_false(ErrorBase.CONTACT_STATES.has(st), "%s never contacts" % st)


func test_try_contact_outside_a_chase_asks_no_gate() -> void:
	var s := _spawn(&"still", Vector3(0, 0, 0.8)) as ErrorStill
	var w := _watch(s)
	s.wake()
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER)
	assert_false(s.try_contact(Tuning.STILL_CONTACT_COST), "Wander: refused")
	s.transition_to(Tuning.ERROR_STATE_SEARCH, "test")
	assert_false(s.try_contact(Tuning.STILL_CONTACT_COST), "Search: refused")
	assert_eq(w["asked"], 0, "the Director's 3 s window is not started by a refusal here")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)
	s.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	assert_true(s.try_contact(Tuning.STILL_CONTACT_COST), "Chase: the contact lands")
	assert_eq(w["asked"], 1)


# --- Still -----------------------------------------------------------------------------------

## M2.7: a wandering Still walked onto a player facing away and contacted without a Chase.
func test_still_wander_onto_the_player_is_no_contact() -> void:
	var s := _spawn(&"still", Vector3(0, 0, 4)) as ErrorStill
	s.senses.sight_range = 0.0  # never notices: its walk alone must not contact
	var w := _watch(s)
	s.hint(_p.global_position)
	s.wake()
	var closest := await _closest_over(s, 3.0)
	assert_lt(closest, Tuning.STILL_CONTACT_RADIUS, "it walked onto the player (%.2f m)" % closest)
	assert_eq(w["hits"], 0, "no contact without a Chase")
	assert_eq(w["asked"], 0)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)


func test_still_search_onto_the_player_is_no_contact() -> void:
	var s := _spawn(&"still", Vector3(0, 0, 5)) as ErrorStill
	s.senses.sight_range = 0.0
	var w := _watch(s)
	s.start_search(_p.global_position)
	var closest := await _closest_over(s, 3.0)
	assert_lt(closest, Tuning.STILL_CONTACT_RADIUS, "Search went to the player's point (%.2f m)" % closest)
	assert_eq(w["hits"], 0, "no contact from Search")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)


## Still at a hide spot the player occupies, in Search, about to check it.
func _checking(s: ErrorStill, spot: HideSpot) -> void:
	s.senses.sight_range = 0.0
	s.start_search(s.body_position())
	await await_physics_frames(1)
	s._search_arrived = true
	s.state_time = 0.0
	s._inspect = [{"pos": s.body_position(), "spot": spot}]
	s._target = s.body_position()
	s._has_target = true


## 08 §4: checking the player's spot is a contact; finding them there is the notice and the
## Chase, and the contact comes from it.
func test_still_hide_spot_find_is_a_chase_then_a_contact() -> void:
	var s := _spawn(&"still", Vector3(0, 0, 3)) as ErrorStill
	var w := _watch(s)
	var notices := [0]
	s.noticed_player.connect(func() -> void: notices[0] += 1)
	var spot := HideSpot.new()
	spot.occupant = _p
	await _checking(s, spot)
	await await_physics_frames(3)
	var states: Array = w["states"]
	assert_eq(w["hits"], 1, "the check is a contact")
	assert_true(states.has(Tuning.ERROR_STATE_CHASE), "after a Chase")
	assert_lt(states.find(Tuning.ERROR_STATE_CHASE), states.rfind(Tuning.ERROR_STATE_SATIATED), "Chase, then the contact")
	assert_eq(notices[0], 1, "finding the player is the notice")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.STILL_CONTACT_COST, 0.0001)
	spot.free()


## M2.7 (the Calm-end case): a chase the Director sends away at once (Calm, Relief) never
## lands, the hide-spot check included.
func test_still_hide_spot_find_sent_away_lands_nothing() -> void:
	var s := _spawn(&"still", Vector3(0, 0, 3)) as ErrorStill
	var w := _watch(s)
	s.state_changed.connect(func(_f: StringName, to: StringName) -> void:
		if to == Tuning.ERROR_STATE_CHASE:
			s.retreat(5.0))  # as Director.on_error_state answers a chase in Calm or Relief
	var spot := HideSpot.new()
	spot.occupant = _p
	await _checking(s, spot)
	await await_physics_frames(3)
	assert_eq(w["hits"], 0)
	assert_eq(w["asked"], 0, "no contact was attempted")
	assert_eq(s.state, Tuning.ERROR_STATE_SATIATED, "sent away")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)
	spot.free()


# --- Echo -------------------------------------------------------------------------------------

## M2.7: Echo's Wander leg ended on the player and contacted without a Follow.
func test_echo_wander_onto_the_player_is_no_contact() -> void:
	var e := _spawn(&"echo", Vector3(0, 0, 0.8)) as ErrorEcho
	var w := _watch(e)
	e.hint(_p.global_position)
	e.wake()
	var closest := await _closest_over(e, 1.0)
	assert_lt(closest, Tuning.ECHO_CONTACT_RADIUS)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "a standing player makes no step")
	assert_eq(w["hits"], 0, "no contact from Wander")
	assert_eq(w["asked"], 0)


## M2.7: Echo in Search (one heard step, no Follow) walked through a player in its way.
func test_echo_search_through_the_player_is_no_contact() -> void:
	var e := _spawn(&"echo", Vector3(0, 0, 5)) as ErrorEcho
	var w := _watch(e)
	e.wake()
	e.transition_to(Tuning.ERROR_STATE_SEARCH, "test")
	e._search_toward(Vector3(0, 0, -7))  # its stand-off lies past the player
	var closest := await _closest_over(e, 4.0)
	assert_lt(closest, Tuning.ECHO_CONTACT_RADIUS, "it brushed the player (%.2f m)" % closest)
	assert_eq(w["hits"], 0, "no contact from Search")
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)


## Walks the player forward (-Z) for `t` seconds.
func _walk(t: float) -> void:
	Input.action_press(&"move_forward")
	await _seconds(t)
	Input.action_release(&"move_forward")


## M2.7: Echo's Follow carried on into Relief; the immediate hint was only stored and the
## trail walk reached the player. Now the hint ends the Follow (no evasion: the player did
## not break the trail) and steps heard after it start over.
func test_echo_relief_hint_ends_follow() -> void:
	var e := _spawn(&"echo", Vector3(0, 0, 2.5)) as ErrorEcho
	var w := _watch(e)
	var lost := [0]
	e.lost_player.connect(func() -> void: lost[0] += 1)
	e.wake()
	await await_physics_frames(2)
	await _walk(1.5)
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW)
	assert_true(e.is_engaged())
	var away := Vector3(20, 0, 20)
	e.hint(away, true)  # DirectorHunters ACT_HINT_AWAY_NOW
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER, "the Relief hint ends the Follow")
	assert_eq(e.trail.size(), 0, "the trail is dropped")
	assert_false(e.is_engaged())
	assert_eq(lost[0], 0, "not an evasion")
	var d0 := ErrorFixture.flat(e.body_position(), away)
	await _seconds(2.0)
	assert_lt(ErrorFixture.flat(e.body_position(), away), d0 - 2.0, "it walks to the hint")
	assert_eq(w["hits"], 0)


## With the Director answering a Follow that starts in Relief (retreat), a player who walks
## back into the released Echo is not contacted.
func test_echo_relief_no_contact_when_the_player_walks_back() -> void:
	var e := _spawn(&"echo", Vector3(0, 0, 2.5)) as ErrorEcho
	var w := _watch(e)
	e.state_changed.connect(func(_f: StringName, to: StringName) -> void:
		if to == Tuning.ERROR_STATE_FOLLOW and e.state_time == 0.0 and w.get("relief", false):
			e.retreat(5.0))
	e.wake()
	await await_physics_frames(2)
	await _walk(1.5)
	assert_eq(e.state, Tuning.ERROR_STATE_FOLLOW)
	w["relief"] = true
	e.hint(e.body_position() + Vector3(0, 0, 20), true)
	Input.action_press(&"move_back")
	var closest := await _closest_over(e, 2.0)
	Input.action_release(&"move_back")
	assert_eq(w["hits"], 0, "no contact in Relief (closest %.2f m)" % closest)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)


## The rule still bites: a Follow that reaches the player contacts.
func test_echo_follow_contacts() -> void:
	var e := _spawn(&"echo", Vector3(0, 0, 0.8)) as ErrorEcho
	var w := _watch(e)
	e.wake()
	e.transition_to(Tuning.ERROR_STATE_FOLLOW, "test")
	await await_physics_frames(6)
	assert_eq(w["hits"], 1, "contact from Follow")
	assert_eq(e.state, Tuning.ERROR_STATE_SATIATED)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.ECHO_CONTACT_COST, 0.0001)
