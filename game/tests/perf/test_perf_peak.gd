extends TestCase
## M3.5 (14 §10, 15 §3 M3 acceptance): the frame budgets measurable headless, in the Garage
## and the Server at their worst-case peak (PerfBench: depth 11, Cycle 2's full roster, the
## Director forced to Peak, the power wave re-igniting, Flicker hopping, Echo following).
## Wall-clock budgets go through assert_budget: printed in the gate, enforced only by
## tools/ci/checkpoint.sh (NOCLIP_FULL_TESTS=1, 20 s per stratum). Counts (nodes, lights,
## shadows) are deterministic and asserted always. Frame times that need a GPU are in
## docs/qa/perf_checklist.md (the cp-12 human script).

const GATE_SECONDS := 6.0
const FULL_SECONDS := 20.0
const WARMUP := 2.0


func _measure(stratum: StringName) -> Dictionary:
	var bench := PerfBench.new()
	bench.stratum = stratum
	bench.seconds = FULL_SECONDS if full_run() else GATE_SECONDS
	bench.warmup = WARMUP
	add_child(bench)
	var r: Dictionary = await bench.measure()
	bench.queue_free()
	await await_frames(2)
	return r


func _mean(r: Dictionary, key: StringName) -> float:
	return float(((r[&"metrics"] as Dictionary).get(key, {}) as Dictionary).get(&"mean", 0.0))


func _max(r: Dictionary, key: StringName) -> float:
	return float(((r[&"metrics"] as Dictionary).get(key, {}) as Dictionary).get(&"max", 0.0))


func _check(r: Dictionary, stratum: StringName) -> void:
	assert_false(r.has(&"error"), "%s: the bench reached a level" % stratum)
	if r.has(&"error"):
		return
	var tag := String(stratum)
	print("  # %s peak: script %.2f ms (errors %.2f, player %.2f, audio %.2f, light pool %.2f, director %.2f), physics %.2f ms, nodes %d, lights %d, shadowed %d" % [
		tag, _mean(r, &"script"), _mean(r, &"errors_timing"), _mean(r, &"player"), _mean(r, &"audio"),
		_mean(r, &"light_pool"), _mean(r, &"director"), _mean(r, &"physics"), int(_max(r, &"level_nodes")),
		int(_max(r, &"lights")), int(_max(r, &"shadowed"))])
	assert_gt(int((r[&"metrics"] as Dictionary).get(&"frames", 0)), 60, "%s: frames recorded" % tag)
	assert_eq((r[&"roster"] as Array).size(), 6, "%s: Cycle 2 depth 5 roster (3 Static, Still, Echo, Flicker)" % tag)
	assert_gt(float((r[&"chasing"] as Dictionary)[&"max"]), 0.0, "%s: a hunter chased during the window" % tag)
	# 14 §10 counts (deterministic): nodes in a level, the pool's lights, shadowed lights.
	assert_lt(_max(r, &"level_nodes"), float(Tuning.BUDGET_NODES_PER_LEVEL), "%s: nodes in the level" % tag)
	assert_true(_max(r, &"pool_lights") <= float(r[&"pool_size"]), "%s: pooled lights within the pool" % tag)
	assert_true(int(r[&"pool_size"]) <= Tuning.BUDGET_ACTIVE_LIGHTS, "%s: pool within 24" % tag)
	assert_true(_max(r, &"shadowed") <= float(Tuning.BUDGET_SHADOWED_LIGHTS + 1), "%s: shadowed fixtures + flashlight" % tag)
	# Wall-clock budgets (checkpoint only).
	assert_budget(_mean(r, &"errors_timing"), Tuning.BUDGET_ERRORS_SCRIPT_MS, "%s errors' script ms (ErrorTiming)" % tag)
	assert_budget(_mean(r, &"script"), Tuning.BUDGET_SCRIPT_MS, "%s script ms per frame" % tag)
	assert_budget(_mean(r, &"physics"), Tuning.BUDGET_PHYSICS_MS, "%s physics step ms" % tag)
	var build: Dictionary = r[&"build"]
	assert_budget(float(build[&"slice_p90_ms"]), Tuning.LEVELBUILD_SLICE_MS + 0.0001, "%s build slice p90" % tag)
	assert_budget(float(build[&"bake_ms"]), Tuning.NAV_BAKE_BUDGET * 1000.0, "%s navigation bake ms" % tag)


func test_server_at_peak() -> void:
	_check(await _measure(Tuning.STRATUM_SERVER), Tuning.STRATUM_SERVER)


func test_garage_at_peak() -> void:
	_check(await _measure(&"garage"), &"garage")
