extends TestCase
## 10 §3, §4, §6, §7: aggression formula and clamps, the roster per depth (05 §3, §10),
## chaser caps, contact exclusivity window, threat, scares gating.


func test_aggression_formula_and_clamps() -> void:
	assert_approx(DirectorRules.aggression(1, 0, 0.0, 1), 0.25, 0.0001)
	assert_approx(DirectorRules.aggression(3, 0, 0.0, 1), 0.45, 0.0001)
	assert_approx(DirectorRules.aggression(2, 1, 0.0, 1), 0.50, 0.0001, "awake +0.15 after one drop")
	assert_approx(DirectorRules.aggression(2, 2, 0.0, 1), 0.60, 0.0001, "awake +0.25 after two")
	assert_approx(DirectorRules.aggression(2, 7, 0.0, 1), 0.60, 0.0001, "awake never above +0.25 (rule 7)")
	# Time pressure: depth 1 target 180 s, starts beyond 360 s, +0.10 per full minute, cap 0.30.
	assert_approx(DirectorRules.time_pressure(1, 360.0), 0.0, 0.0001)
	assert_approx(DirectorRules.time_pressure(1, 419.0), 0.0, 0.0001, "not a full minute yet")
	assert_approx(DirectorRules.time_pressure(1, 420.0), 0.10, 0.0001)
	assert_approx(DirectorRules.time_pressure(1, 545.0), 0.30, 0.0001)
	assert_approx(DirectorRules.time_pressure(1, 5000.0), 0.30, 0.0001, "cap +0.30 (rule 8)")
	assert_approx(DirectorRules.aggression(7, 0, 0.0, 2), 0.40, 0.0001, "Cycle 2 depth 7: 0.25 + 0.15")
	assert_approx(DirectorRules.aggression(6, 3, 10000.0, 2), 1.0, 0.0001, "clamped to 1")
	for d in range(1, 13):
		for drops in 4:
			var a := DirectorRules.aggression(d, drops, 9999.0, DirectorRules.cycle_of(d))
			assert_true(a >= 0.0 and a <= 1.0, "depth %d drops %d in [0, 1]" % [d, drops])
	# 05 §10: the depth-1 hunter of a later Descent at 0.2; Static keeps the level value.
	assert_approx(DirectorRules.error_aggression(0.25, 1, &"still"), 0.20, 0.0001)
	assert_approx(DirectorRules.error_aggression(0.25, 1, &"static"), 0.25, 0.0001)
	assert_approx(DirectorRules.error_aggression(0.35, 2, &"still"), 0.35, 0.0001)


func _roster(depth: int, stratum: StringName, first: bool = false, met: Array = [], seed_value: int = 1) -> Array[StringName]:
	return DirectorRules.roster(depth, stratum, first, met, make_rng(seed_value))


func _count(r: Array[StringName], id: StringName) -> int:
	return r.count(id)


func test_roster_per_depth() -> void:
	assert_eq(_roster(1, &"halls", true), [&"static"] as Array[StringName], "first Descent: Static only")
	for s in 20:
		var r := _roster(1, &"halls", false, [], s)
		assert_eq(r.size(), 2, "later Descents add one hunter at depth 1")
		assert_eq(r[0], &"static")
		assert_true(r[1] == &"still" or r[1] == &"echo")
	assert_eq(_roster(2, &"garage"), [&"static", &"still"] as Array[StringName])
	assert_eq(_roster(2, &"pools"), [&"static", &"echo"] as Array[StringName])
	assert_eq(_roster(3, &"offices"), [&"static", &"flicker"] as Array[StringName])
	var r4 := _roster(4, &"garage", false, [&"still", &"echo"])
	assert_eq(r4, [&"static", &"still", &"echo"] as Array[StringName], "depth 4: native plus a met hunter")
	var r4p := _roster(4, &"pools", false, [&"still"])
	assert_eq(r4p, [&"static", &"echo", &"still"] as Array[StringName])
	for st: StringName in [&"pools", &"garage", &"offices", &"server"]:
		var r5 := _roster(5, st)
		assert_eq(_count(r5, &"static"), 2, "depth 5 %s: two Statics" % st)
		for id: StringName in [&"still", &"echo", &"flicker"]:
			assert_eq(_count(r5, id), 1, "depth 5 %s: one %s" % [st, id])
	assert_eq(_roster(6, &"substrate"), [&"static", &"static", &"null"] as Array[StringName])
	var server := _roster(4, &"server", false, [&"echo"])
	assert_eq(server[1], &"echo", "Server's native slot is a hunter met this run")
	var c2 := _roster(8, &"garage")
	assert_eq(_count(c2, &"static"), 2, "Cycle 2: +1 Static")
	assert_eq(_count(_roster(12, &"substrate"), &"null"), 1, "Null only in the Substrate")
	assert_eq(_count(_roster(6, &"garage"), &"null"), 0)


func test_spawnable_is_static_still_echo_and_flicker() -> void:
	assert_true(DirectorRules.spawnable(&"static"))
	assert_true(DirectorRules.spawnable(&"still"))
	assert_true(DirectorRules.spawnable(&"echo"), "Echo is built (M2.4)")
	assert_true(DirectorRules.spawnable(&"flicker"), "Flicker is built (M2.5)")
	assert_false(DirectorRules.spawnable(&"null"), "Null arrives in M2.6")


func test_chaser_caps_and_awake_hunters() -> void:
	for d in [1, 2, 3]:
		assert_eq(DirectorRules.max_chasers(d), 1)
	assert_eq(DirectorRules.max_chasers(4), 2)
	assert_eq(DirectorRules.max_chasers(5), 2)
	assert_eq(DirectorRules.max_chasers(6), 2, "Null plus 1")
	assert_eq(DirectorRules.awake_hunters(0), 0)
	assert_eq(DirectorRules.awake_hunters(1), 1)
	assert_eq(DirectorRules.awake_hunters(2), 2)
	assert_eq(DirectorRules.awake_hunters(5), 2)


func test_contact_window_is_3_s() -> void:
	assert_true(DirectorRules.contact_allowed(0, -1), "the first contact")
	assert_false(DirectorRules.contact_allowed(1000, 0))
	assert_false(DirectorRules.contact_allowed(2999, 0))
	assert_true(DirectorRules.contact_allowed(3000, 0))


func test_threat() -> void:
	assert_approx(DirectorRules.hunter_threat(0.0, true), 1.0, 0.0001)
	assert_approx(DirectorRules.hunter_threat(7.5, false), 0.25, 0.0001)
	assert_approx(DirectorRules.hunter_threat(20.0, true), 0.0, 0.0001)
	assert_approx(DirectorRules.threat_target(0.2, true, INF), 0.5, 0.0001, "+0.3 inside Static")
	assert_approx(DirectorRules.threat_target(0.0, false, 6.0), 0.5, 0.0001, "1 − d/12 inside Null")
	assert_approx(DirectorRules.threat_target(0.9, true, 0.0), 1.0, 0.0001, "clamped")
	var up := DirectorRules.smooth_threat(0.0, 1.0, 0.5)
	assert_approx(up, 1.0 - exp(-1.0), 0.0001, "0.5 s up")
	var down := DirectorRules.smooth_threat(1.0, 0.0, 2.0)
	assert_approx(down, exp(-1.0), 0.0001, "2 s down")


func test_scares_gating() -> void:
	var s := Scares.new()
	assert_true(s.available(Tuning.DIRECTOR_PHASE_CALM, 0.9, 100.0).is_empty(), "never in Calm")
	assert_true(s.available(Tuning.DIRECTOR_PHASE_PEAK, 0.9, 100.0).is_empty(), "never in Peak")
	assert_true(s.available(Tuning.DIRECTOR_PHASE_RELIEF, 0.9, 100.0).is_empty(), "never in Relief")
	assert_true(s.available(Tuning.DIRECTOR_PHASE_BUILD, 0.1, 100.0).is_empty(), "none below 0.2")
	assert_eq(s.available(Tuning.DIRECTOR_PHASE_BUILD, 0.6, 100.0).size(), Scares.ORDER.size(), "all above 0.5")
	assert_eq(s.available(Tuning.DIRECTOR_PHASE_BUILD, 0.21, 100.0).size(), 1)
	assert_false(s.request(Scares.STATIC_SWELL, 100.0), "no executor bound: nothing runs (M2.7: test_scares)")
	s.last_any = 90.0
	assert_true(s.available(Tuning.DIRECTOR_PHASE_BUILD, 0.9, 100.0).is_empty(), "one per 30 s")


## M2.5: the temporary Still substitution is gone; every native has a scene except Null.
func test_every_native_but_null_is_spawnable() -> void:
	for id: StringName in [&"static", &"still", &"echo", &"flicker"]:
		assert_true(DirectorRules.spawnable(id), "%s has a scene" % id)
	assert_false(DirectorRules.new().has_method(&"substitute_unbuilt_native"), "the substitution is deleted")

