extends TestCase
## The autoloads expose every function their Interfaces name (02, 03, 05, 12, 13),
## and the parts M0.2 implements behave: CoherenceRenderer feeding, GameState lifecycle.


func _has_all(node: Object, methods: Array, who: String) -> void:
	for m: String in methods:
		assert_true(node.has_method(m), "%s.%s" % [who, m])


func test_interface_methods_exist() -> void:
	_has_all(GameState, ["start_run", "descend", "end_run", "compute_score"], "GameState")
	_has_all(SettingsManager, ["get_value", "set_value", "apply_preset", "reset_tab", "bindings", "rebind"], "SettingsManager")
	assert_true(SettingsManager.has_signal(&"changed"), "SettingsManager.changed")
	_has_all(SaveManager, ["load_meta", "save_meta", "reset_meta", "backup_corrupt"], "SaveManager")
	_has_all(AudioManager, ["play_3d", "play_2d", "start_loop", "set_stratum", "duck"], "AudioManager")
	_has_all(CoherenceRenderer, ["set_coherence", "pulse", "set_threat", "set_null"], "CoherenceRenderer")
	_has_all(Clock, ["hitstop"], "Clock")
	_has_all(MetaState.new(), ["is_unlocked", "earn", "note_found", "codex_notice", "record_run"], "MetaState")


func test_run_state_fields() -> void:
	var r := RunState.new()
	for f in ["run_seed", "mode", "loadout", "depth", "strata_order", "coherence", "items",
			"proper_exits", "drops_in_a_row", "notes_found", "evasions", "encounters", "started_at_ms"]:
		assert_true(f in r, "RunState.%s (05 Interfaces)" % f)


func test_meta_state_accessors() -> void:
	var m := MetaState.new()
	assert_false(m.is_unlocked(&"radio"))
	assert_true(m.earn(&"radio"))
	assert_false(m.earn(&"radio"), "earned once")
	assert_true(m.is_unlocked(&"radio"))
	assert_true(m.note_found(&"H1"))
	assert_false(m.note_found(&"H1"))
	assert_eq(m.codex_notice(&"still"), 1)
	assert_eq(m.codex_notice(&"still"), 2)


func test_coherence_renderer_feeding() -> void:
	CoherenceRenderer.set_coherence(25.0)
	assert_approx(CoherenceRenderer.coherence01, 0.25)
	CoherenceRenderer.set_coherence(150.0)
	assert_approx(CoherenceRenderer.coherence01, 1.0, 0.0001, "clamped")
	EventBus.threat_changed.emit(0.6)
	assert_approx(CoherenceRenderer.threat, 0.6, 0.0001, "fed by EventBus.threat_changed")
	CoherenceRenderer.set_null(Vector3(1, 0, 2), 12.0)
	assert_eq(CoherenceRenderer.null_pos, Vector3(1, 0, 2))
	CoherenceRenderer.pulse(&"noclip_commit")
	assert_lt(CoherenceRenderer.pulse_age(&"noclip_commit"), 0.05)
	assert_eq(CoherenceRenderer.noclip_commit, 1.0, "commit global raised by the pulse")
	await Clock.wall_timer(0.1).timeout
	await get_tree().process_frame
	assert_eq(CoherenceRenderer.noclip_commit, 1.0, "held at 1.0 during the 250 ms pass (06 §8)")
	await Clock.wall_timer(0.5).timeout
	await get_tree().process_frame
	assert_eq(CoherenceRenderer.noclip_commit, 0.0, "decayed 300 ms after the pass (02 §4)")
	EventBus.run_started.emit(&"descent", 1)
	assert_approx(CoherenceRenderer.coherence01, 1.0, 0.0001, "reset at run start")
	assert_eq(CoherenceRenderer.null_radius, 0.0)
	assert_eq(CoherenceRenderer.threat, 0.0)


func test_game_state_lifecycle_emits_bus_signals() -> void:
	var seen: Array = []
	var on_start := func(mode: StringName, s: int) -> void: seen.append(["start", mode, s])
	var on_left := func(proper: bool) -> void: seen.append(["left", proper])
	var on_end := func(cause: StringName, score: int) -> void: seen.append(["end", cause, score])
	EventBus.run_started.connect(on_start)
	EventBus.level_left.connect(on_left)
	EventBus.run_ended.connect(on_end)
	GameState.start_run(&"descent", &"faller", 1234)
	assert_true(GameState.is_run_active())
	assert_eq(GameState.run.run_seed, 1234)
	assert_eq(GameState.run.depth, 1)
	GameState.descend(true)
	GameState.descend(false)
	assert_eq(GameState.run.depth, 3)
	assert_eq(GameState.run.proper_exits, 1)
	assert_eq(GameState.run.drops_in_a_row, 1)
	GameState.end_run(&"still")
	assert_false(GameState.is_run_active())
	EventBus.run_started.disconnect(on_start)
	EventBus.level_left.disconnect(on_left)
	EventBus.run_ended.disconnect(on_end)
	assert_eq(seen.size(), 4)
	if seen.size() == 4:
		assert_eq(seen[0], ["start", &"descent", 1234])
		assert_eq(seen[1], ["left", true])
		assert_eq(seen[2], ["left", false])
		assert_eq(seen[3][1], &"still")


func test_settings_set_value_announces() -> void:
	var got: Array = []
	var cb := func(k: StringName, v: Variant) -> void: got.append([k, v])
	EventBus.settings_changed.connect(cb)
	SettingsManager.set_value(&"test_key", 3)
	SettingsManager.set_value(&"test_key", 3)
	EventBus.settings_changed.disconnect(cb)
	assert_eq(SettingsManager.get_value(&"test_key"), 3)
	assert_eq(got.size(), 1, "unchanged value is not re-announced")
