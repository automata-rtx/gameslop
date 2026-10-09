extends TestCase
## M2.16 coverage: the public helpers of the settings schema (12 §2, §3), the standalone
## rebinding table (12 §5), the meta schema and Archive read state (13 §2, §5) and the
## run seed (05 §8) that no earlier file reached by name.


# --- 12 resolutions and presets ----------------------------------------------------------------

func test_resolution_text_round_trips_and_rejects_junk() -> void:
	assert_eq(SettingsSchema.parse_resolution("1920x1080"), Vector2i(1920, 1080))
	assert_eq(SettingsSchema.resolution_text(Vector2i(2560, 1440)), "2560x1440")
	for bad in ["", "1920", "1920x", "x1080", "axb", "1920x1080x2", "native"]:
		assert_eq(SettingsSchema.parse_resolution(bad), Vector2i.ZERO, "'%s'" % bad)


func test_resolutions_for_a_screen_offer_only_what_fits() -> void:
	var list := SettingsSchema.resolutions_for(Vector2i(1920, 1080))
	assert_eq(list[0], SettingsSchema.NATIVE, "native first")
	assert_true(list.has(&"1280x720"))
	assert_true(list.has(&"1920x1080"))
	assert_false(list.has(&"2560x1440"), "nothing larger than the screen")
	assert_false(list.has(&"1920x1200"))
	var odd := SettingsSchema.resolutions_for(Vector2i(2000, 1100))
	assert_true(odd.has(&"2000x1100"), "the screen's own size is offered")
	var count := 0
	for r in odd:
		if r == &"2000x1100":
			count += 1
	assert_eq(count, 1, "once")
	var unknown := SettingsSchema.resolutions_for(Vector2i.ZERO)
	assert_eq(unknown.size(), 1 + Tuning.SETTINGS_RESOLUTIONS.size(), "an unknown screen offers every size")


func test_resolution_option_validates_against_the_minimum() -> void:
	assert_eq(SettingsSchema.validate(&"resolution", "1920x1080"), &"1920x1080")
	assert_eq(SettingsSchema.validate(&"resolution", "native"), SettingsSchema.NATIVE)
	assert_eq(SettingsSchema.validate(&"resolution", "640x480"), SettingsSchema.NATIVE, "under 1280x720 falls back")
	assert_eq(SettingsSchema.validate(&"resolution", 12), SettingsSchema.NATIVE)


func test_keys_and_kinds() -> void:
	assert_true(SettingsSchema.has_key(&"fov"))
	assert_false(SettingsSchema.has_key(&"not_an_option"))
	assert_eq(SettingsSchema.kind_of(&"fov"), SettingsSchema.KIND_INT)
	assert_eq(SettingsSchema.kind_of(&"captions"), SettingsSchema.KIND_BOOL)
	assert_eq(SettingsSchema.kind_of(&"nope"), &"")
	assert_eq(SettingsSchema.validate(&"nope", 7), 7, "unknown keys pass through")


func test_presets_follow_the_quality_table() -> void:
	for p: StringName in [&"low", &"medium", &"high"]:
		var v := SettingsSchema.preset_values(p)
		var row: Dictionary = Tuning.QUALITY_PRESETS[p]
		assert_eq(v[&"light_pool_size"], int(row[&"lights"]), "%s lights" % p)
		assert_eq(v[&"anti_aliasing"], row[&"aa"], "%s aa" % p)
		assert_approx(float(v[&"render_scale"]), float(row[&"render_scale"]), 0.0001)
		assert_eq(v[&"ambient_occlusion"], bool(row[&"ssao"]))
		# Every key a preset sets is a real option and holds a valid value for it.
		for k: StringName in v:
			assert_true(SettingsSchema.has_key(k), "%s is an option" % k)
			assert_eq(SettingsSchema.validate(k, v[k]), v[k], "%s=%s is valid" % [k, v[k]])
	assert_true(SettingsSchema.preset_values(&"ultra").is_empty(), "no such preset")
	assert_lt(SettingsSchema.preset_values(&"low")[&"light_pool_size"], SettingsSchema.preset_values(&"high")[&"light_pool_size"])


# --- 12 §5 the rebinding table on its own ----------------------------------------------------------

func _key(code: int, loc: int = 0) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	k.location = loc as KeyLocation
	return k


func test_input_comparison_ignores_unspecified_location() -> void:
	assert_true(SettingsBindings.same_input(_key(KEY_E), _key(KEY_E)))
	assert_false(SettingsBindings.same_input(_key(KEY_E), _key(KEY_F)))
	assert_true(SettingsBindings.same_input(_key(KEY_SHIFT, KEY_LOCATION_LEFT), _key(KEY_SHIFT)), "unspecified matches either side")
	assert_false(SettingsBindings.same_input(_key(KEY_SHIFT, KEY_LOCATION_LEFT), _key(KEY_SHIFT, KEY_LOCATION_RIGHT)))
	var a := InputEventMouseButton.new()
	a.button_index = MOUSE_BUTTON_LEFT
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_RIGHT
	assert_false(SettingsBindings.same_input(a, b))
	assert_false(SettingsBindings.same_input(a, _key(KEY_E)), "different kinds never match")
	assert_false(SettingsBindings.same_input(null, a))


func test_only_keys_and_mouse_buttons_can_be_bound() -> void:
	assert_null(SettingsBindings.normalized(InputEventMouseMotion.new()))
	assert_null(SettingsBindings.normalized(InputEventKey.new()), "a key with no code")
	var n := SettingsBindings.normalized(_key(KEY_Q)) as InputEventKey
	assert_eq(n.physical_keycode, KEY_Q)
	assert_eq(SettingsBindings.event_to_text(InputEventMouseMotion.new()), "")


func test_standalone_table_round_trips_through_texts() -> void:
	var acts: Array[StringName] = [&"m216_a", &"m216_b"]
	for a in acts:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a)
	InputMap.action_add_event(&"m216_a", _key(KEY_Z))
	InputMap.action_add_event(&"m216_b", _key(KEY_X))
	InputMap.action_add_event(&"m216_b", _key(KEY_C))
	var t := SettingsBindings.new(acts)
	t.capture_defaults()
	assert_eq(t.defaults[&"m216_b"].size(), SettingsBindings.SLOTS, "padded to the slot count")
	# A swap: Z moves to b slot 0, a gets X's old input... the partner is the previous holder.
	var partner := t.rebind(&"m216_b", _key(KEY_Z), 0)
	assert_eq(partner, &"m216_a")
	assert_true(SettingsBindings.same_input(t.get_event(&"m216_b", 0), _key(KEY_Z)))
	var texts := t.to_texts()
	var u := SettingsBindings.new(acts)
	u.capture_defaults()
	u.from_texts(texts)
	assert_eq(u.to_texts(), texts, "from_texts(to_texts()) is the identity")
	# A malformed entry loads as an empty slot, never an error.
	u.from_texts({"m216_a": ["junk", 3, ""]})
	assert_null(u.get_event(&"m216_a", 0))
	t.reset()
	assert_eq(t.to_texts(), t.defaults, "reset restores the captured map")
	for a in acts:
		InputMap.erase_action(a)


# --- 13 meta schema and the Archive read state ------------------------------------------------------

func test_unread_notes_and_mark_read() -> void:
	var m := MetaState.new()
	m.notes_found = [&"H1", &"H2", &"P1"] as Array[StringName]
	assert_eq(m.unread_notes(), [&"H1", &"H2", &"P1"] as Array[StringName], "in the order found")
	assert_true(m.mark_notes_read([&"H2"] as Array[StringName]))
	assert_eq(m.unread_notes(), [&"H1", &"P1"] as Array[StringName])
	assert_false(m.mark_notes_read([&"H2", &"ZZ9"] as Array[StringName]), "already read, or never found")
	assert_true(m.mark_notes_read([&"H1", &"P1"] as Array[StringName]))
	assert_true(m.unread_notes().is_empty())


func test_has_daily_and_result() -> void:
	var m := MetaState.new()
	assert_false(m.has_daily("20261008"))
	assert_true(m.daily_result("20261008").is_empty())
	m.record_run({"cause": "static", "depth": 3, "score": 1200, "mode": Tuning.MODE_DAILY, "daily_key": "20261008"})
	assert_true(m.has_daily("20261008"))
	assert_false(m.has_daily("20261009"))
	assert_eq(int(m.daily_result("20261008")["score"]), 1200)


func test_validate_stats_repairs_a_hand_edited_file() -> void:
	var s := MetaSchema.validate_stats({"runs": -5, "wins": 1e300, "best_depth": 5000, "time_played_s": "x",
			"deaths_by": {"static": 2, "weird": "a"}, "depth_reached_counts": {"2": 3, "0": 5, "x": 1, "5000": 1},
			"strata_reached": ["halls", "halls", "moon", 4], "extra": 1})
	assert_eq(s["runs"], 0, "negative counters clamp")
	assert_eq(s["wins"], MetaSchema.COUNTER_MAX, "a huge counter clamps, never overflows")
	assert_eq(s["best_depth"], Tuning.META_DEPTH_MAX)
	assert_eq(s["time_played_s"], 0.0)
	assert_eq(s["deaths_by"]["static"], 2)
	assert_eq(s["deaths_by"]["weird"], 0)
	assert_eq((s["depth_reached_counts"] as Dictionary).keys(), ["2"], "only real depths")
	assert_eq(s["strata_reached"], ["halls"], "known strata once")
	assert_eq(s["extra"], 1, "unknown keys are preserved")
	var fresh := MetaSchema.validate_stats("not a dictionary")
	assert_eq(fresh, MetaSchema.default_stats())
	assert_true(MetaSchema.now_iso().ends_with("Z"))
	assert_true(MetaSchema.to_bool("yes", true), "a non-bool takes the default")
	assert_false(MetaSchema.to_bool(null, false))


func test_run_seeds_differ_between_calls() -> void:
	# The one seed that is not derived (05 §8): two calls a few microseconds apart differ.
	var a := Run.new_seed()
	OS.delay_usec(50)
	var b := Run.new_seed()
	assert_ne(a, b)
	assert_true(a >= 0 and b >= 0)


## docs/qa/fixtures/meta_m2_mid_save.json is the save the human check list copies into the user
## directory: it must stay a valid meta.json that unlocks what that list uses.
func test_the_human_check_save_fixture_loads_clean() -> void:
	var text := FileAccess.get_file_as_string("res://../docs/qa/fixtures/meta_m2_mid_save.json")
	assert_false(text.is_empty(), "the fixture exists")
	var d: Variant = JSON.parse_string(text)
	assert_true(d is Dictionary)
	var m := MetaSchema.from_dict(MetaSchema.migrate(d as Dictionary))
	for id: StringName in [&"glowstick", &"radio", &"flare", &"fuse", &"cartographer", &"lightbearer", &"diver", &"daily"]:
		assert_true(m.is_unlocked(id), "%s is unlocked" % id)
	assert_false(m.is_unlocked(&"endless"), "the ending is still to be earned")
	assert_eq(m.notes_found.size(), 14)
	assert_eq(m.unread_notes().size(), 12, "twelve notes blink in the Archive")
	assert_true(m.hints_retired)
	assert_eq(m.to_dict()["notes_found"], (d as Dictionary)["notes_found"], "round trip")
