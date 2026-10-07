extends TestCase
## cp-01 review fixes (R1): font coverage of Strings, settings defaults, run counters,
## data/Tuning/Strings agreement, item glyphs.

const PLAYER_SETTING_KEYS: Array[StringName] = [
	&"fov", &"mouse_sensitivity", &"invert_y", &"head_bob", &"screen_shake",
	&"sprint_mode", &"crouch_mode", &"hold_to_press",
]


func _color_eq(a: Color, hex: String, msg: String) -> void:
	assert_true(a.is_equal_approx(Color(hex)), msg)


# ---------------------------------------------------------------- fonts

func test_every_non_ascii_character_in_strings_is_in_the_font() -> void:
	var font := load(UiTokens.FONT_REGULAR_PATH) as FontFile
	var script: GDScript = load("res://src/core/strings.gd")
	var seen: Dictionary = {}
	var stack: Array = script.get_script_constant_map().values()
	while not stack.is_empty():
		var v: Variant = stack.pop_back()
		if v is String or v is StringName:
			var t := String(v)
			for i in t.length():
				var c := t.unicode_at(i)
				if c > 127:
					seen[c] = true
		elif v is Array:
			stack.append_array(v)
		elif v is Dictionary:
			stack.append_array((v as Dictionary).keys())
			stack.append_array((v as Dictionary).values())
	assert_gt(seen.size(), 0, "strings.gd uses non-ASCII characters")
	for c in seen:
		assert_true(font.has_char(c), "JetBrains Mono Regular has U+%04X" % c)
	assert_eq(Strings.MENU_CURSOR, "▌")


# ---------------------------------------------------------------- settings

func test_settings_have_defaults_for_every_key_the_player_reads() -> void:
	for key in PLAYER_SETTING_KEYS:
		assert_not_null(SettingsManager.get_value(key), "default for %s" % key)
	assert_approx(SettingsManager.get_value(&"fov"), Tuning.CAMERA_FOV_DEFAULT)
	assert_approx(SettingsManager.get_value(&"mouse_sensitivity"), Tuning.PLAYER_MOUSE_SENS_DEFAULT)
	assert_eq(SettingsManager.get_value(&"sprint_mode"), &"hold")
	assert_eq(SettingsManager.get_value(&"crouch_mode"), &"hold")
	assert_eq(SettingsManager.get_value(&"hold_to_press"), false)
	assert_eq(SettingsManager.get_value(&"invert_y"), false)
	assert_eq(SettingsManager.get_value(&"audio_master"), Tuning.SETTINGS_AUDIO_MASTER_DEFAULT)
	assert_eq(SettingsManager.REBINDABLE_ACTIONS, Tuning.INPUT_ACTIONS)


# ---------------------------------------------------------------- run counters

func test_run_state_counters() -> void:
	var r := RunState.new()
	for f in ["walls_passed", "coherence_spent", "drops_total", "distance_m", "max_depth", "evasions_by", "evasions"]:
		assert_true(f in r, "RunState.%s" % f)


func test_game_state_record_calls() -> void:
	GameState.record_notice(&"still")  # no run: ignored, no crash
	GameState.start_run(&"descent", &"faller", 1)
	GameState.record_notice(&"still")
	GameState.record_notice(&"still")
	GameState.record_evasion(&"flicker")
	GameState.record_evasion(&"flicker")
	GameState.record_evasion(&"echo")
	GameState.record_spend(&"noclip_wall", 30.0)
	GameState.record_spend(&"noclip_floor", 30.0)
	GameState.record_wall_pass()
	GameState.record_drop()
	var r := GameState.run
	assert_eq(r.encounters[&"still"], 2)
	assert_eq(r.evasions, 3)
	assert_eq(r.evasions_by, {&"flicker": 2, &"echo": 1})
	assert_approx(r.coherence_spent, 60.0)
	assert_eq(r.walls_passed, 1)
	assert_eq(r.drops_total, 1)
	GameState.descend(true)
	assert_eq(r.max_depth, 2)
	GameState.end_run(&"abandoned")


func test_start_run_uses_the_loadout_start_depth() -> void:
	GameState.start_run(&"descent", &"diver", 1)
	assert_eq(GameState.run.depth, 3)
	assert_eq(GameState.run.max_depth, 3)
	GameState.end_run(&"abandoned")
	GameState.start_run(&"descent", &"faller", 1)
	assert_eq(GameState.run.depth, 1)
	GameState.end_run(&"abandoned")


func test_meta_depth_reached_counts() -> void:
	var m := MetaState.new()
	assert_true(m.stats.has("depth_reached_counts"))
	assert_eq(m.depth_reached(4), 1)
	assert_eq(m.depth_reached(4), 2, "unlock #7: depth 4 twice")
	assert_eq(m.depth_reached(3), 1)


# ---------------------------------------------------------------- constants

func test_state_and_tier_constants() -> void:
	assert_eq(Tuning.ERROR_STATE_FOLLOW, &"follow")
	assert_eq(Tuning.ERROR_STATE_RESIDENT, &"resident")
	assert_eq(Tuning.ERROR_STATE_STALK, &"stalk")
	assert_eq(Tuning.ERROR_STATE_LUNGE, &"lunge")
	assert_eq(Tuning.ERROR_STATE_ATTACHED, &"attached")
	assert_eq(NoteData.TIER_FIRST_RUN, 1)
	assert_eq(NoteData.TIER_STRATUM_REACHED, 2)
	assert_eq(NoteData.TIER_ARCHIVE_ONLY, 3)


func test_fake_clock_now_usec() -> void:
	var c := fake_clock(1.5)
	assert_eq(c.now_usec(), 1500000)


func test_registry_orders_follow_tuning() -> void:
	assert_eq(DataRegistry.STRATUM_ORDER, Tuning.STRATA_ALL)
	assert_eq(DataRegistry.ERROR_ORDER, Tuning.ERROR_IDS)
	assert_eq(DataRegistry.ITEM_ORDER, Tuning.ITEM_KINDS + [&"keycard"] as Array[StringName])


# ---------------------------------------------------------------- items

func test_every_item_has_a_glyph() -> void:
	for i in DataRegistry.items():
		assert_not_null(i.glyph, "glyph of %s" % i.kind)


# ---------------------------------------------------------------- data equals Tuning

func test_data_equals_tuning() -> void:
	for kind in Tuning.ITEM_KINDS:
		var item := DataRegistry.item(kind)
		assert_eq(item.cap, Tuning.ITEM_CAP[kind], "cap " + String(kind))
		assert_eq(item.weight, Tuning.ITEM_WEIGHT[kind], "weight " + String(kind))
	for id in Tuning.LOADOUTS:
		var t: Dictionary = Tuning.LOADOUTS[id]
		var l := DataRegistry.loadout(id)
		assert_approx(l.start_coherence, float(t[&"coherence"]), 0.0001, "coherence " + String(id))
		assert_eq(l.start_depth, t[&"start_depth"], "depth " + String(id))
		assert_eq(l.start_items, t[&"items"], "items " + String(id))
		assert_approx(l.crank_rate_mult, float(t[&"crank_mult"]), 0.0001, "crank " + String(id))
		assert_approx(l.flicker_attract_mult, float(t[&"flicker_attract_mult"]), 0.0001, "attract " + String(id))
	for id in Tuning.STRATA_ALL:
		var s := DataRegistry.stratum(id)
		assert_approx(s.fog_density, Tuning.STRATUM_FOG_DENSITY[id], 0.00001, "fog " + String(id))
		var c: Dictionary = Tuning.STRATUM_COLORS[id]
		_color_eq(s.fog_color, c[&"fog"], "fog colour " + String(id))
		_color_eq(s.ambient_color, c[&"ambient"], "ambient colour " + String(id))
		if c.has(&"fixture_light"):
			_color_eq(s.fixture_light_color, c[&"fixture_light"], "fixture light " + String(id))
			_color_eq(s.fixture_emission_color, c[&"fixture_emission"], "fixture emission " + String(id))
		var rv: Dictionary = Tuning.AUDIO_REVERB[id]
		assert_approx(s.reverb_room_size, rv[&"room"], 0.0001, "reverb room " + String(id))
		assert_approx(s.reverb_damping, rv[&"damping"], 0.0001, "reverb damping " + String(id))
		assert_approx(s.reverb_wet, rv[&"wet"], 0.0001, "reverb wet " + String(id))
		assert_approx(s.reverb_predelay_ms, float(rv.get(&"predelay_ms", 0)), 0.0001, "predelay " + String(id))
		assert_approx(s.reverb_highpass_hz, float(rv.get(&"highpass_hz", 0)), 0.0001, "highpass " + String(id))
	_color_eq(UiTokens.UI_FG, Tuning.UI_COLOR_FG, "ui_fg")
	_color_eq(UiTokens.UI_DIM, Tuning.UI_COLOR_DIM, "ui_dim")
	_color_eq(UiTokens.UI_BG, Tuning.UI_COLOR_BG, "ui_bg")
	_color_eq(UiTokens.UI_ACCENT, Tuning.UI_COLOR_ACCENT, "ui_accent")
	_color_eq(UiTokens.UI_DANGER, Tuning.UI_COLOR_DANGER, "ui_danger")
	_color_eq(UiTokens.UI_COLD, Tuning.UI_COLOR_COLD, "ui_cold")
	_color_eq(UiTokens.UI_ACCENT_CB, Tuning.UI_COLOR_ACCENT_CB, "ui_accent_cb")
	assert_approx(UiTokens.PAUSE_OVERLAY.a, Tuning.UI_PAUSE_OVERLAY_ALPHA)


# ---------------------------------------------------------------- data equals Strings (04 §11)

func test_data_text_equals_strings() -> void:
	for e in DataRegistry.errors():
		assert_eq(e.display_name, Strings.ERROR_NAMES[e.id], "error name " + String(e.id))
		assert_eq(e.codex_text, Strings.ERROR_CODEX[e.id], "codex " + String(e.id))
	for l in DataRegistry.loadouts():
		assert_eq(l.display_name, Strings.LOADOUT_NAMES[l.id], "loadout name " + String(l.id))
		assert_eq(l.description, Strings.LOADOUT_DESCRIPTIONS[l.id], "loadout description " + String(l.id))
	for i in DataRegistry.items():
		assert_eq(i.display_name, Strings.ITEM_NAMES[i.kind], "item name " + String(i.kind))
	for s in DataRegistry.strata():
		assert_eq(s.display_name, Strings.STRATUM_NAMES[s.id], "stratum name " + String(s.id))
	for id in Strings.LOADOUT_DESCRIPTIONS:
		var d: String = Strings.LOADOUT_DESCRIPTIONS[id]
		assert_ne(d, d.to_upper(), "sentence case " + String(id))
		assert_false(d.to_lower().contains("notice"), "glossary term misused in " + String(id))
