extends TestCase
## 10 §2, §9: the sawtooth in simulation. A scripted player and scripted hunters feed the
## pure DirectorPacing at 10 Hz for 10 minutes on a FakeClock; the phases must cycle
## Calm → Build → Peak → Relief → Build with the documented durations, and intensity must
## stay inside [0, 1].

const DT := Tuning.DIRECTOR_TICK


## Runs `seconds` of a scripted level. In Build the player cranks every 4 s (+0.10) until a
## hunter notices; a chase lasts `chase_len` s and ends alternately in evasion and contact.
func _simulate(seconds: float, arrival: StringName, chase_len: float, log: Array[Dictionary]) -> DirectorPacing:
	var clock := fake_clock()
	var p := DirectorPacing.new(42, arrival)
	var chase_left := 0.0
	var crank_left := 0.0
	var chases := 0
	var lo := 1.0
	var hi := 0.0
	var phase := p.phase
	var entered := 0.0
	while clock.now() < seconds:
		clock.advance(DT)
		var chasing := 0
		if p.phase == DirectorPacing.BUILD:
			crank_left -= DT
			if crank_left <= 0.0:
				crank_left = 4.0
				p.on_crank()
			# A hunter notices once the Director has pushed intensity past 0.6.
			if p.intensity >= 0.6:
				chasing = 1
				chase_left = chase_len
		elif p.phase == DirectorPacing.PEAK and chase_left > 0.0:
			chasing = 1
			chase_left -= DT
			if chase_left <= 0.0:
				chases += 1
				if chases % 2 == 0:
					p.on_contact()
				else:
					p.on_evasion()
				chasing = 0
		p.step(DT, 10.0 if chasing > 0 else 25.0, chasing, 1)
		p.take_actions()
		lo = minf(lo, p.intensity)
		hi = maxf(hi, p.intensity)
		if p.phase != phase:
			log.append({&"phase": phase, &"length": clock.now() - entered, &"next": p.phase,
				&"relief": p.relief_length})
			phase = p.phase
			entered = clock.now()
	assert_true(lo >= 0.0 and hi <= 1.0, "intensity stayed in [0, 1] (%.3f..%.3f)" % [lo, hi])
	return p


func test_sawtooth_cycles_over_ten_minutes() -> void:
	var log: Array[Dictionary] = []
	_simulate(600.0, Tuning.RUN_ARRIVE_PROPER, 12.0, log)
	assert_gt(log.size(), 8, "many phase changes in 10 minutes")
	if log.is_empty():
		return
	assert_eq(log[0][&"phase"], DirectorPacing.CALM)
	assert_approx(float(log[0][&"length"]), Tuning.DIRECTOR_CALM_TIME, 0.11, "Calm lasts 30 s")
	var expected := {
		DirectorPacing.CALM: DirectorPacing.BUILD, DirectorPacing.BUILD: DirectorPacing.PEAK,
		DirectorPacing.PEAK: DirectorPacing.RELIEF, DirectorPacing.RELIEF: DirectorPacing.BUILD,
	}
	var cycles := 0
	var contact_reliefs := 0
	for i in log.size():
		var e: Dictionary = log[i]
		assert_eq(e[&"next"], expected[e[&"phase"]], "transition %d from %s" % [i, e[&"phase"]])
		if e[&"phase"] == DirectorPacing.PEAK:
			assert_true(float(e[&"length"]) <= Tuning.DIRECTOR_PEAK_MAX_TIME + 0.11, "Peak ≤ 45 s")
		if e[&"phase"] == DirectorPacing.RELIEF:
			cycles += 1
			var l := float(e[&"length"])
			assert_true(l >= Tuning.DIRECTOR_RELIEF_MIN_TIME - 0.11 and l <= Tuning.DIRECTOR_RELIEF_MAX_TIME + 0.11,
				"Relief %.1f s in [20, 40]" % l)
			assert_approx(l, float(e[&"relief"]), 0.11, "Relief runs its drawn length")
			if is_equal_approx(float(e[&"relief"]), Tuning.DIRECTOR_RELIEF_AFTER_CONTACT_TIME):
				contact_reliefs += 1
	assert_gt(cycles, 3, "at least four full sawtooth cycles")
	assert_gt(contact_reliefs, 0, "a contact gives a 40 s Relief")


func test_calm_window_at_start_and_after_drop() -> void:
	for arrival: StringName in [Tuning.RUN_ARRIVE_START, Tuning.RUN_ARRIVE_PROPER, Tuning.RUN_ARRIVE_DROP]:
		var p := DirectorPacing.new(1, arrival)
		var calm := Tuning.DIRECTOR_CALM_TIME_AFTER_DROP if arrival == Tuning.RUN_ARRIVE_DROP else Tuning.DIRECTOR_CALM_TIME
		var steps := roundi(calm / DT)
		# Loud player and a chasing hunter: Calm still holds for its full length.
		for i in steps - 1:
			p.on_crank()
			p.step(DT, 5.0, 1, 1)
		assert_eq(p.phase, DirectorPacing.CALM, "%s: still Calm at %.1f s" % [arrival, p.level_time])
		p.step(DT, 5.0, 1, 1)
		assert_eq(p.phase, DirectorPacing.BUILD, "%s: Build at %.1f s" % [arrival, p.level_time])


func test_peak_cap_retreats_chasers_after_45_s() -> void:
	var p := DirectorPacing.new(3)
	p._enter(DirectorPacing.BUILD)
	p.take_actions()
	p.step(DT, 8.0, 1, 1)
	assert_eq(p.phase, DirectorPacing.PEAK)
	var t := 0.0
	var acts: Array[StringName] = []
	while p.phase == DirectorPacing.PEAK and t < 60.0:
		p.step(DT, 8.0, 1, 1)
		t += DT
		acts.append_array(p.take_actions())
	assert_approx(t, Tuning.DIRECTOR_PEAK_MAX_TIME, 0.11, "Peak capped at 45 s")
	assert_eq(p.phase, DirectorPacing.RELIEF)
	assert_true(acts.has(DirectorPacing.ACT_RETREAT_CHASERS), "the chaser retreats")


## M1.13 ruling: the 0.8 wake stays in Build (once per Build, re-armed below 0.8); only a
## chase begins Peak.
func test_wake_at_intensity_0_8_stays_in_build() -> void:
	var p := DirectorPacing.new(4)
	p._enter(DirectorPacing.BUILD)
	p.take_actions()
	p.intensity = 0.85
	p.step(DT, INF, 0, 0)
	assert_eq(p.phase, DirectorPacing.BUILD, "no hunter on the level: stays in Build")
	assert_false(p.take_actions().has(DirectorPacing.ACT_WAKE_NEAREST), "and wakes nothing")
	p.step(DT, INF, 0, 1)
	assert_eq(p.phase, DirectorPacing.BUILD, "the 0.8 wake does not begin Peak")
	assert_true(p.take_actions().has(DirectorPacing.ACT_WAKE_NEAREST))
	var again := 0
	for i in 100:
		p.step(DT, INF, 0, 1)
		again += p.take_actions().count(DirectorPacing.ACT_WAKE_NEAREST)
	assert_eq(again, 0, "once while intensity stays at or above 0.8")
	p.on_note()
	p.on_note()
	p.step(DT, INF, 0, 1)
	p.take_actions()
	p.intensity = 0.85
	p.step(DT, INF, 0, 1)
	assert_true(p.take_actions().has(DirectorPacing.ACT_WAKE_NEAREST), "re-armed after falling below 0.8")
	p.step(DT, 12.0, 1, 1)
	assert_eq(p.phase, DirectorPacing.PEAK, "a chase begins Peak")


func test_build_hints_every_20_s_and_relief_hints_away() -> void:
	var p := DirectorPacing.new(5)
	var hints := 0
	var t := 0.0
	while t < Tuning.DIRECTOR_CALM_TIME + 61.0:
		p.step(DT, INF, 0, 1)
		t += DT
		for a in p.take_actions():
			if a == DirectorPacing.ACT_HINT_TOWARD:
				hints += 1
	assert_eq(hints, 4, "hint at Build entry, then at 20, 40 and 60 s")
	p.on_contact()
	assert_eq(p.phase, DirectorPacing.RELIEF, "a contact in Build ends it")
	assert_approx(p.relief_length, Tuning.DIRECTOR_RELIEF_AFTER_CONTACT_TIME, 0.001)
	assert_true(p.take_actions().has(DirectorPacing.ACT_HINT_AWAY_NOW), "hunters away at Relief entry")
	var later := 0
	for i in roundi((Tuning.DIRECTOR_HINT_INTERVAL + 0.5) / DT):
		p.step(DT, INF, 0, 1)
		later += p.take_actions().count(DirectorPacing.ACT_HINT_AWAY)
	assert_eq(later, 1, "and again every 20 s")


func test_intensity_inputs_and_clamps() -> void:
	var p := DirectorPacing.new(6)
	for i in 50:
		p.on_breaker()
	assert_eq(p.intensity, 1.0, "clamped at 1")
	for i in 50:
		p.on_contact()
	assert_eq(p.intensity, 0.0, "clamped at 0")
	p.on_coherence(40.0)
	p.on_coherence(29.0)
	assert_approx(p.intensity, Tuning.INTENSITY_LOW_COHERENCE, 0.0001, "+0.10 when crossing below 30")
	p.on_coherence(50.0)
	p.on_coherence(20.0)
	assert_approx(p.intensity, Tuning.INTENSITY_LOW_COHERENCE, 0.0001, "only once per level")
	p.intensity = 0.5
	p.on_exit_seen()
	p.on_exit_seen()
	assert_approx(p.intensity, 0.35, 0.0001, "exit seen −0.15 once")
	p.on_noclip_broke_los()
	assert_approx(p.intensity, 0.15, 0.0001)
	p.on_crank()
	assert_approx(p.intensity, 0.15, 0.0001, "held lowered for 15 s after a pass that broke sight")
	for i in int(Tuning.NOCLIP_DIRECTOR_RELIEF_TIME / DT) + 1:
		p.step(DT)
	var before := p.intensity
	p.on_crank()
	assert_approx(p.intensity, before + Tuning.INTENSITY_NOISE_CRANK, 0.0001, "rises again after 15 s")


func test_relief_decays_faster() -> void:
	var a := DirectorPacing.new(7)
	a._enter(DirectorPacing.BUILD)
	a.intensity = 0.5
	var b := DirectorPacing.new(7)
	b._enter(DirectorPacing.RELIEF)
	b.intensity = 0.5
	for i in 10:
		a.step(DT)
		b.step(DT)
	assert_approx(a.intensity, 0.51, 0.0001, "Build: the time input, no decay on a tick with input")
	assert_approx(b.intensity, 0.47, 0.0001, "Relief: no time input, −0.03 decay")
	# Calm has no time input: a quiet tick decays at −0.01/s.
	var c := DirectorPacing.new(7)
	c.intensity = 0.5
	for i in 10:
		c.step(DT)
	assert_approx(c.intensity, 0.49, 0.0001, "Calm: −0.01 decay")


func test_depth_6_pursuit_has_no_relief() -> void:
	var p := DirectorPacing.new(8, Tuning.RUN_ARRIVE_DROP, true)
	assert_approx(p.calm_length, Tuning.DIRECTOR_PURSUIT_CALM_TIME, 0.001)
	var t := 0.0
	var statics := 0
	var null_wake := 0
	while t < 300.0:
		p.step(DT, 6.0, 1, 1)
		t += DT
		for a in p.take_actions():
			statics += 1 if a == DirectorPacing.ACT_HINT_STATIC_ACROSS else 0
			null_wake += 1 if a == DirectorPacing.ACT_WAKE_NULL else 0
		if t > Tuning.DIRECTOR_PURSUIT_CALM_TIME + DT:
			assert_eq(p.phase, DirectorPacing.PURSUIT)
			assert_true(p.intensity >= Tuning.DIRECTOR_PURSUIT_INTENSITY_FLOOR, "floor 0.6")
			if p.phase != DirectorPacing.PURSUIT:
				break
		elif t < Tuning.DIRECTOR_PURSUIT_CALM_TIME - DT:
			assert_eq(null_wake, 0, "Null never woken before Calm ends")
	assert_eq(null_wake, 1)
	assert_eq(statics, 5, "Static across the path at entry, then every 60 s")
	assert_false(p.history.has(DirectorPacing.RELIEF))


## cp-04 review, M1.13 ruling: a quiet player (no noise, no hunter near) still sees the
## intensity rise: Calm 30 s, Build, then the time input alone reaches 0.8 within
## 0.8 / 0.010 = 80 s of Build, which wakes the nearest hunter once; with no chase the
## phase stays Build (no Peak without a chase, no Peak re-hint).
func test_quiet_player_rises_to_the_wake_but_peak_needs_a_chase() -> void:
	var p := DirectorPacing.new(9)
	var build_at := -1.0
	var wake_at := -1.0
	var wake := 0
	while p.level_time < 400.0:
		p.step(DT, INF, 0, 1)
		for a in p.take_actions():
			if a == DirectorPacing.ACT_WAKE_NEAREST:
				wake += 1
				wake_at = p.level_time if wake_at < 0.0 else wake_at
		if p.phase == DirectorPacing.BUILD and build_at < 0.0:
			build_at = p.level_time
	var to_wake := Tuning.DIRECTOR_WAKE_INTENSITY / Tuning.INTENSITY_TIME_PER_S
	assert_approx(build_at, Tuning.DIRECTOR_CALM_TIME, 0.11, "Build after the 30 s Calm")
	assert_true(wake_at > 0.0 and wake_at <= Tuning.DIRECTOR_CALM_TIME + to_wake + 0.21,
		"the 0.8 wake by %.0f s from the time input alone (at %.1f s)" % [Tuning.DIRECTOR_CALM_TIME + to_wake, wake_at])
	assert_eq(wake, 1, "one 0.8 wake")
	assert_eq(p.phase, DirectorPacing.BUILD, "no chase, no Peak")
	assert_false(p.history.has(DirectorPacing.PEAK))


## M1.13 ruling: Relief clamps intensity to ≤ 0.5 on entry and stops the time and
## nearest-hunter inputs; it hints every hunter away at once.
func test_relief_clamps_and_stops_time_and_nearest_inputs() -> void:
	var p := DirectorPacing.new(10)
	p._enter(DirectorPacing.BUILD)
	p.step(DT, 10.0, 1, 1)
	assert_eq(p.phase, DirectorPacing.PEAK)
	p.intensity = 1.0
	p.take_actions()
	p.on_evasion(true)
	assert_eq(p.phase, DirectorPacing.RELIEF)
	assert_approx(p.intensity, Tuning.DIRECTOR_RELIEF_INTENSITY_CAP, 0.0001, "1.0 − 0.30, clamped to 0.5")
	assert_true(p.take_actions().has(DirectorPacing.ACT_HINT_AWAY_NOW), "every hunter away at once")
	# A hunter 2 m away and the clock: neither raises intensity in Relief; it decays (the
	# first tick carries the evasion event, so it does not decay).
	for i in 11:
		p.step(DT, 2.0, 0, 1)
	assert_approx(p.intensity, Tuning.DIRECTOR_RELIEF_INTENSITY_CAP - 0.03, 0.0001, "−0.03/s, no time or near input")
	# A contact from low intensity is not raised by the clamp.
	var q := DirectorPacing.new(11)
	q._enter(DirectorPacing.BUILD)
	q.intensity = 0.3
	q.on_contact()
	assert_eq(q.phase, DirectorPacing.RELIEF)
	assert_approx(q.intensity, 0.0, 0.0001, "0.3 − 0.40 clamps at 0, not raised")
	# The Peak cap's Relief clamps too.
	var r := DirectorPacing.new(12)
	r._enter(DirectorPacing.BUILD)
	r.step(DT, 10.0, 1, 1)
	r.intensity = 1.0
	while r.phase == DirectorPacing.PEAK:
		r.step(DT, 10.0, 1, 1)
	assert_eq(r.phase, DirectorPacing.RELIEF)
	assert_true(r.intensity <= Tuning.DIRECTOR_RELIEF_INTENSITY_CAP + 0.0001, "Peak cap Relief ≤ 0.5")
	# Build still has the nearest-hunter input.
	var b := DirectorPacing.new(13)
	b._enter(DirectorPacing.BUILD)
	b.intensity = 0.2
	b.step(DT, 0.0, 0, 1)
	assert_approx(b.intensity, 0.2 + (Tuning.INTENSITY_TIME_PER_S + Tuning.INTENSITY_NEAREST_HUNTER_PER_S) * DT, 0.0001)


## cp-04 review: a Static release is weather letting go, not an evasion (no −0.30, Peak holds).
func test_static_release_is_not_an_evasion() -> void:
	var p := DirectorPacing.new(12)
	p._enter(DirectorPacing.BUILD)
	p.step(DT, 10.0, 1, 1)
	assert_eq(p.phase, DirectorPacing.PEAK)
	p.intensity = 0.7
	p.on_evasion(false)
	assert_approx(p.intensity, 0.7, 0.0001, "Static release: intensity unchanged")
	assert_eq(p.phase, DirectorPacing.PEAK, "and the Peak holds")
	p.on_evasion(true)
	assert_approx(p.intensity, 0.4, 0.0001, "a hunter's evasion: −0.30")
	assert_eq(p.phase, DirectorPacing.RELIEF)


## The decay only runs on ticks without input: an event on a Calm tick skips that tick's decay.
func test_events_suppress_the_tick_decay() -> void:
	var p := DirectorPacing.new(13)
	p.intensity = 0.5
	p.on_note()
	p.step(DT)
	assert_approx(p.intensity, 0.4, 0.0001, "−0.10 note and no decay on that tick")
	p.step(DT)
	assert_approx(p.intensity, 0.399, 0.0001, "the next quiet tick decays")
