extends TestCase
## Asserts that tuning.gd mirrors the design numbers (M0.3, 15 §M0). Constants are looked up
## by name so a missing one is a readable failure, not a parse error that hides the rest.

var _map: Dictionary = {}

func before_all() -> void:
	var script: GDScript = load("res://src/core/tuning.gd")
	_map = script.get_script_constant_map()

func _t(name: String) -> Variant:
	if not _map.has(name):
		fail("Tuning.%s is missing" % name)
		return null
	return _map[name]

func _eq(name: String, expected: Variant) -> void:
	var actual: Variant = _t(name)
	if actual == null:
		return
	if typeof(expected) == TYPE_FLOAT or typeof(actual) == TYPE_FLOAT:
		assert_approx(float(actual), float(expected), 0.00001, name)
	else:
		assert_eq(actual, expected, name)

func test_holds_many_constants_and_no_nulls() -> void:
	assert_gt(_map.size(), 500, "Tuning should hold every number in the design")
	for name in _map:
		assert_not_null(_map[name], "Tuning.%s is null" % name)

# --- 06 player ---------------------------------------------------------------------

func test_player_movement() -> void:
	_eq("PLAYER_WALK_SPEED", 3.2)
	_eq("PLAYER_SPRINT_SPEED", 5.6)
	_eq("PLAYER_CROUCH_SPEED", 1.6)
	_eq("PLAYER_CAPSULE_RADIUS", 0.35)
	_eq("PLAYER_CAPSULE_HEIGHT", 1.8)
	_eq("PLAYER_CAPSULE_HEIGHT_CROUCH", 1.1)
	_eq("PLAYER_CAMERA_HEIGHT", 1.65)
	_eq("PLAYER_CAMERA_HEIGHT_CROUCH", 0.95)
	_eq("PLAYER_WADE_SPEED_MULT", 0.6)
	_eq("PLAYER_WADE_NOISE_MULT", 1.6)
	_eq("PLAYER_ACCEL", 12.0)
	_eq("PLAYER_DECEL", 16.0)
	_eq("PLAYER_STEP_HEIGHT", 0.3)
	_eq("PLAYER_MOUSE_RAD_PER_PIXEL", 0.0022)
	assert_lt(_t("PLAYER_CROUCH_SPEED"), _t("PLAYER_WALK_SPEED"))
	assert_lt(_t("PLAYER_WALK_SPEED"), _t("PLAYER_SPRINT_SPEED"))

func test_stamina_flashlight_crank() -> void:
	_eq("STAMINA_MAX", 100.0)
	_eq("STAMINA_SPRINT_DRAIN", 20.0)
	_eq("STAMINA_REGEN", 25.0)
	_eq("STAMINA_REGEN_DELAY", 1.0)
	_eq("STAMINA_LOCKOUT_TIME", 2.0)
	_eq("FLASH_DRAIN", 1.6)
	_eq("FLASH_ENERGY_MIN", 0.5)
	_eq("FLASH_ENERGY_MAX", 1.6)
	_eq("FLASH_CONE_FULL_DEG", 38.0)
	_eq("FLASH_CONE_TIRED_FULL_DEG", 30.0)
	_eq("FLASH_RANGE", 22.0)
	_eq("CRANK_RATE", 25.0)
	_eq("CRANK_NOISE_RADIUS", 12.0)
	_eq("CRANK_NOISE_INTERVAL", 0.5)
	_eq("CRANK_RATE_LIGHTBEARER_MULT", 1.5)

func test_noise_radii() -> void:
	var steps: Dictionary = _t("NOISE_STEP_RADIUS")
	assert_eq(steps[&"carpet"], 5.0)
	assert_eq(steps[&"tile"], 7.0)
	assert_eq(steps[&"concrete"], 7.0)
	assert_eq(steps[&"raised_floor"], 8.0)
	assert_eq(steps[&"substrate"], 6.0)
	_eq("NOISE_STEP_WATER_RADIUS", 10.0)
	_eq("NOISE_SPRINT_MULT", 1.8)
	_eq("NOISE_CROUCH_MULT", 0.4)
	_eq("NOISE_NOCLIP_COMMIT_RADIUS", 20.0)
	_eq("NOISE_FLASHLIGHT_TOGGLE_RADIUS", 2.0)
	_eq("NOISE_DOOR_SLAM_RADIUS", 18.0)
	_eq("NOISE_ITEM_DROP_RADIUS", 6.0)
	_eq("NOISE_FLARE_BURNING_RADIUS", 14.0)
	_eq("NOISE_RADIO_RADIUS", 10.0)
	_eq("NOISE_BREAKER_RADIUS", 25.0)
	_eq("NOISE_CONTACT_RADIUS", 15.0)
	_eq("NOISE_WALL_ATTENUATION", 0.35)
	_eq("STEP_DISTANCE_WALK", 0.55)
	_eq("STEP_DISTANCE_SPRINT", 0.45)
	_eq("STEP_DISTANCE_CROUCH", 0.7)

func test_noclip_costs_times_and_validity() -> void:
	_eq("NOCLIP_SOFT_COST", 5.0)
	_eq("NOCLIP_WALL_COST", 10.0)
	_eq("NOCLIP_FLOOR_COST", 30.0)
	_eq("NOCLIP_SOFT_TIME", 0.35)
	_eq("NOCLIP_WALL_TIME", 0.6)
	_eq("NOCLIP_FLOOR_TIME", 2.5)
	_eq("NOCLIP_RANGE", 2.5)
	_eq("NOCLIP_COMMIT_HITSTOP_MS", 80)
	_eq("NOCLIP_PASS_TIME_MS", 250)
	_eq("NOCLIP_COOLDOWN", 1.0)
	_eq("NOCLIP_FOV_PUNCH_DEG", 8.0)
	_eq("NOCLIP_FOV_PULL_DEG", 6.0)
	_eq("NOCLIP_WALL_NORMAL_MAX_DEG", 30.0)
	_eq("NOCLIP_FLOOR_NORMAL_MAX_DEG", 20.0)
	assert_eq(_t("NOCLIP_REASON_TOO_THIN"), &"TOO THIN")

func test_coherence_and_contact() -> void:
	_eq("COHERENCE_MAX", 100.0)
	_eq("COHERENCE_GAIN_PROPER_EXIT", 20.0)
	_eq("COHERENCE_GAIN_POLAROID", 25.0)
	_eq("COHERENCE_LOSS_STATIC_PER_S", 4.0)
	_eq("COHERENCE_LOSS_NULL_PER_S", 12.0)
	_eq("COHERENCE_LOSS_CYCLE2_SUBSTRATE_PER_S", 0.2)
	_eq("COHERENCE_CONTACT_STILL", 35.0)
	_eq("COHERENCE_CONTACT_ECHO", 25.0)
	_eq("COHERENCE_CONTACT_FLICKER", 30.0)
	_eq("COHERENCE_DANGER_BELOW", 25.0)
	_eq("COHERENCE_HEARTBEAT_FLOOR_BPM", 90.0)
	_eq("CONTACT_STUN_TIME", 1.2)
	_eq("CONTACT_PUSH_DIST", 1.5)
	_eq("CONTACT_SATIATED_TIME", 20.0)
	_eq("CONTACT_EXCLUSIVITY_TIME", 3.0)
	# 05 §9 rule 5: no single damage event exceeds 35.
	for cost in (_t("ERROR_CONTACT_COST") as Dictionary).values():
		assert_true(cost <= _t("COHERENCE_MAX_SINGLE_HIT"), "contact cost within the single-hit cap")
	# 06 §8: a noclip can never kill, so every cost is below the starting Coherence of every loadout.
	assert_lt(_t("NOCLIP_FLOOR_COST"), 70.0)

# --- 08 errors ---------------------------------------------------------------------

func test_static() -> void:
	_eq("STATIC_RADIUS_MIN", 3.0)
	_eq("STATIC_RADIUS_MAX", 5.0)
	_eq("STATIC_DRAIN_PER_S", 4.0)
	_eq("STATIC_DRIFT_SPEED_LOW", 0.6)
	_eq("STATIC_DRIFT_SPEED_HIGH", 0.9)
	_eq("STATIC_SEARCH_SPEED_HIGH", 1.2)
	_eq("STATIC_FLARE_RANGE", 6.0)
	_eq("STATIC_FLARE_PUSH_SPEED", 1.2)
	_eq("STATIC_FAIR_CUMULATIVE_LIMIT", 40.0)
	_eq("STATIC_DWELL_MIN", 5.0)
	_eq("STATIC_DWELL_MAX", 15.0)

func test_still() -> void:
	_eq("STILL_WANDER_SPEED", 1.8)
	_eq("STILL_SEARCH_SPEED", 3.6)
	_eq("STILL_CHASE_SPEED", 5.0)
	_eq("STILL_CHASE_SPEED_CAP", 5.4)
	_eq("STILL_OBSERVE_MAX_DIST", 30.0)
	_eq("STILL_OBSERVE_BEAM_ANGLE", 25.0)
	_eq("STILL_OBSERVE_GLOWSTICK_DIST", 4.0)
	_eq("STILL_OBSERVE_FLARE_DIST", 8.0)
	_eq("STILL_SIGHT_RANGE", 25.0)
	_eq("STILL_CONTACT_RADIUS", 1.0)
	_eq("STILL_SPEED_MULT_LOW", 0.9)
	_eq("STILL_SPEED_MULT_HIGH", 1.15)
	_eq("ERROR_REACTION_WINDOW_LOW", 1.5)
	_eq("ERROR_REACTION_WINDOW_HIGH", 0.8)
	# Sprint must remain an escape even at the highest aggression multiplier.
	assert_lt(_t("STILL_CHASE_SPEED_CAP"), _t("PLAYER_SPRINT_SPEED"))
	assert_gt(float(_t("STILL_CHASE_SPEED")) * float(_t("STILL_SPEED_MULT_HIGH")), float(_t("STILL_CHASE_SPEED_CAP")), "the cap binds at high aggression")

func test_flicker() -> void:
	_eq("FLICKER_HOP_MIN", 6.0)
	_eq("FLICKER_HOP_MAX", 12.0)
	_eq("FLICKER_CHARGE_TIME", 2.0)
	_eq("FLICKER_CHARGE_DRAIN", 2.0)
	_eq("FLICKER_STUTTER_MIN_HZ", 8.0)
	_eq("FLICKER_STUTTER_MAX_HZ", 20.0)
	_eq("FLICKER_LUNGE_RANGE", 6.0)
	_eq("FLICKER_DARK_TIME", 1.5)
	_eq("FLICKER_ATTACH_DIST", 4.0)
	_eq("FLICKER_ATTACH_DIST_LIGHTBEARER", 6.0)
	_eq("FLICKER_ATTACH_TIME", 1.5)
	_eq("FLICKER_SHED_DIST", 10.0)
	_eq("FLICKER_LIT_AREA_DIST", 3.0)
	_eq("FLICKER_GROUP_ADJACENT_DIST", 8.0)

func test_echo_and_null() -> void:
	_eq("ECHO_TRAIL_DELAY_MS", 800)
	_eq("ECHO_TRAIL_DELAY", 0.8)
	_eq("ECHO_FOLLOW_STEPS", 3)
	_eq("ECHO_FOLLOW_STEPS_WINDOW", 5.0)
	_eq("ECHO_HEARING_MULT_LOW", 1.0)
	_eq("ECHO_HEARING_MULT_HIGH", 1.4)
	_eq("ECHO_TRAIL_LOSS_TIME_LOW", 6.0)
	_eq("ECHO_TRAIL_LOSS_TIME_HIGH", 4.0)
	_eq("ECHO_SEARCH_TIME", 10.0)
	_eq("ECHO_SHIMMER_RANGE", 4.0)
	_eq("NULL_SPEED_CYCLE1", 2.4)
	_eq("NULL_SPEED_CYCLE2", 2.8)
	_eq("NULL_UNRENDER_RADIUS", 12.0)
	_eq("NULL_UNRENDER_RADIUS_CYCLE2", 24.0)
	_eq("NULL_CORE_RADIUS", 2.0)
	_eq("NULL_DRAIN_PER_S", 12.0)
	_eq("NULL_SPAWN_PATH_FRACTION", 0.55)
	_eq("NULL_DEAD_END_MAX_CELLS", 4)
	# Null is slower than walking (08 §7).
	assert_lt(_t("NULL_SPEED_CYCLE1"), _t("PLAYER_WALK_SPEED"))

func test_shared_error_senses() -> void:
	_eq("ERROR_SUSPICION_STEP", 0.6)
	_eq("ERROR_SUSPICION_LOUD", 1.0)
	_eq("ERROR_SUSPICION_SEEN_PER_S", 0.67)
	_eq("ERROR_SUSPICION_DECAY_PER_S", 0.5)
	_eq("ERROR_SATIATED_TIME", 20.0)
	_eq("ERROR_SPAWN_MIN_DIST", 20.0)
	_eq("AGGR_MIN", 0.25)
	_eq("AGGR_MAX", 0.75)
	assert_eq((_t("ERROR_IDS") as Array).size(), 5)

# --- 10 director -------------------------------------------------------------------

func test_director_phases_and_knobs() -> void:
	_eq("DIRECTOR_CALM_TIME", 30.0)
	_eq("DIRECTOR_CALM_TIME_AFTER_DROP", 15.0)
	_eq("DIRECTOR_PEAK_MAX_TIME", 45.0)
	_eq("DIRECTOR_RELIEF_MIN_TIME", 20.0)
	_eq("DIRECTOR_RELIEF_MAX_TIME", 40.0)
	_eq("DIRECTOR_RELIEF_AFTER_CONTACT_TIME", 40.0)
	_eq("DIRECTOR_HINT_INTERVAL", 20.0)
	_eq("DIRECTOR_HINT_RANGE_MIN", 15.0)
	_eq("DIRECTOR_HINT_RANGE_MAX", 30.0)
	_eq("DIRECTOR_WAKE_INTENSITY", 0.8)
	_eq("DIRECTOR_RELIEF_INTENSITY_CAP", 0.5)
	_eq("SCARE_MIN_INTERVAL", 30.0)
	_eq("DIRECTOR_TIME_PRESSURE_PER_MINUTE", 0.10)
	_eq("DIRECTOR_TIME_PRESSURE_CAP", 0.30)
	_eq("AWAKE_ONE_DROP", 0.15)
	_eq("AWAKE_TWO_DROPS", 0.25)
	_eq("AGGRESSION_CYCLE2_BONUS", 0.15)
	# 10 §8: the doc's own knob names are mirrored one to one.
	_eq("CALM_SECONDS", 30.0)
	_eq("CALM_SECONDS_AFTER_DROP", 15.0)
	_eq("PEAK_MAX_SECONDS", 45.0)
	_eq("RELIEF_MIN", 20.0)
	_eq("RELIEF_MAX", 40.0)
	_eq("RELIEF_AFTER_CONTACT", 40.0)
	_eq("HINT_INTERVAL", 20.0)
	_eq("HINT_RANGE_MIN", 15.0)
	_eq("HINT_RANGE_MAX", 30.0)
	_eq("WAKE_INTENSITY", 0.8)
	_eq("RELIEF_INTENSITY_CAP", 0.5)
	_eq("SCARE_MIN_INTERVAL", 30.0)
	_eq("TIME_PRESSURE_PER_MINUTE", 0.10)
	_eq("TIME_PRESSURE_CAP", 0.30)
	_eq("AWAKE_ONE", 0.15)
	_eq("AWAKE_TWO", 0.25)
	_eq("CYCLE_BONUS", 0.15)
	# Substrate schedule and chaser caps.
	_eq("DIRECTOR_PURSUIT_INTENSITY_FLOOR", 0.6)
	var caps: Dictionary = _t("DIRECTOR_MAX_CHASERS")
	assert_eq([caps[1], caps[3], caps[4], caps[5], caps[6]], [1, 1, 2, 2, 2])

func test_director_intensity_inputs() -> void:
	_eq("INTENSITY_TIME_PER_S", 0.010)
	_eq("INTENSITY_NOISE_SPRINT_STEP", 0.02)
	_eq("INTENSITY_NOISE_CRANK", 0.10)
	_eq("INTENSITY_NOISE_NOCLIP", 0.20)
	_eq("INTENSITY_NOISE_BREAKER", 0.25)
	_eq("INTENSITY_CHASE_PER_S", 0.15)
	_eq("INTENSITY_EXIT_SEEN", -0.15)
	_eq("INTENSITY_EVASION", -0.30)
	_eq("INTENSITY_CONTACT", -0.40)
	_eq("INTENSITY_NOTE", -0.10)
	_eq("INTENSITY_NOCLIP_BROKE_LOS", -0.20)
	_eq("INTENSITY_DECAY_RELIEF_PER_S", -0.03)
	_eq("INTENSITY_DECAY_PER_S", -0.01)
	_eq("SCARE_STATIC_SWELL_DB", 4.0)
	_eq("THREAT_RANGE", 15.0)

func test_aggression_and_roster_tables() -> void:
	var base: Dictionary = _t("AGGRESSION_BASE_BY_DEPTH")
	assert_eq([base[1], base[2], base[3], base[4], base[5], base[6]], [0.25, 0.35, 0.45, 0.55, 0.65, 0.75])
	var roster: Dictionary = _t("ROSTER_BY_DEPTH")
	assert_eq(roster[1], {&"static": 1})
	assert_eq(roster[5][&"static"], 2)
	assert_eq(roster[6], {&"null": 1, &"static": 2})
	var native: Dictionary = _t("STRATUM_NATIVE_ERROR")
	assert_eq(native[&"pools"], &"echo")
	assert_eq(native[&"garage"], &"still")
	assert_eq(native[&"offices"], &"flicker")
	assert_eq(native[&"substrate"], &"null")
	assert_false(native.has(&"server"), "Server has no native error")

# --- 05 run structure --------------------------------------------------------------

func test_walkable_cells_and_grid_sizes() -> void:
	var cells: Dictionary = _t("LEVEL_WALKABLE_CELLS")
	assert_eq([cells[1], cells[2], cells[3], cells[4], cells[5], cells[6]], [300, 380, 460, 520, 580, 360])
	var sizes: Dictionary = _t("GRID_SIZE_BY_DEPTH")
	assert_eq([sizes[1], sizes[2], sizes[3], sizes[4], sizes[5], sizes[6]], [24, 28, 32, 34, 36, 28])
	var time: Dictionary = _t("LEVEL_TARGET_TIME")
	assert_eq([time[1], time[2], time[3], time[4], time[5], time[6]], [180.0, 240.0, 300.0, 300.0, 360.0, 240.0])
	_eq("LEVEL_WALKABLE_TOLERANCE", 0.25)
	_eq("GRID_CELL_SIZE", 2.0)
	_eq("GRID_WALL_THICKNESS", 0.2)

func test_scoring_landing_and_unlocks() -> void:
	_eq("SCORE_PER_DEPTH", 1000)
	_eq("SCORE_PER_PROPER_EXIT", 300)
	_eq("SCORE_PER_COHERENCE", 5)
	_eq("SCORE_PER_NOTE", 150)
	_eq("SCORE_PER_EVASION", 50)
	_eq("SCORE_TIME_BONUS_BASE", 1800.0)
	_eq("SCORE_TIME_BONUS_RATE", 0.5)
	_eq("LANDING_TIME", 6.0)
	_eq("DROP_FALL_TIME", 1.2)
	_eq("UNLOCK_COUNT", 14)
	assert_eq((_t("UNLOCK_IDS") as Array).size(), 14)
	_eq("NOTES_TOTAL", 36)
	_eq("UNLOCK_CARTOGRAPHER_NOTES", 5)
	_eq("UNLOCK_LIGHTBEARER_FLICKER_EVASIONS", 3)
	_eq("UNLOCK_NOTE_U6_NOTES", 35)

func test_loadouts() -> void:
	var l: Dictionary = _t("LOADOUTS")
	assert_eq(l.size(), 4)
	assert_eq(l[&"faller"][&"coherence"], 100)
	assert_eq(l[&"faller"][&"items"], {&"polaroid": 1, &"chalk": 8})
	assert_eq(l[&"cartographer"][&"coherence"], 90)
	assert_eq(l[&"cartographer"][&"items"], {&"chalk": 20, &"radio": 1})
	assert_eq(l[&"lightbearer"][&"crank_mult"], 1.5)
	assert_false(l[&"lightbearer"][&"items"].has(&"polaroid"), "Lightbearer has no Polaroid")
	assert_eq(l[&"diver"][&"start_depth"], 3)
	assert_eq(l[&"diver"][&"coherence"], 70)
	assert_eq(l[&"diver"][&"items"], {&"polaroid": 2})

# --- 09 items ----------------------------------------------------------------------

func test_item_caps_and_effects() -> void:
	var caps: Dictionary = _t("ITEM_CAP")
	assert_eq([caps[&"polaroid"], caps[&"glowstick"], caps[&"flare"], caps[&"chalk"], caps[&"radio"], caps[&"fuse"]], [3, 4, 2, 20, 1, 1])
	_eq("ITEM_BELT_SLOTS", 4)
	_eq("GLOWSTICK_LIFETIME", 90.0)
	_eq("GLOWSTICK_LIGHT_RANGE", 4.0)
	_eq("FLARE_BURN_TIME", 40.0)
	_eq("FLARE_LIGHT_RANGE", 8.0)
	_eq("CHALK_PICKUP_USES", 8)
	_eq("CHALK_MAX_DECALS", 40)
	_eq("RADIO_CHARGES", 3)
	_eq("RADIO_CHARGE_TIME", 30.0)
	_eq("POLAROID_USE_TIME", 1.2)
	_eq("FUSE_INSERT_TIME", 0.8)
	var w: Dictionary = _t("ITEM_WEIGHT")
	assert_eq([w[&"polaroid"], w[&"glowstick"], w[&"chalk"], w[&"flare"], w[&"radio"], w[&"fuse"]], [3, 3, 2, 2, 1, 1])
	for kind in _t("ITEM_KINDS"):
		assert_contains(caps, kind)

# --- 07 level generation -----------------------------------------------------------

func test_levelgen_numbers() -> void:
	_eq("LEVELGEN_RETRIES", 8)
	_eq("CYCLED_SEALED_TIME", 70.0)
	_eq("CYCLED_OPEN_TIME", 20.0)
	_eq("CYCLED_WARNING_TIME", 5.0)
	_eq("SOFT_WALL_MIN_SAVING", 20.0)
	_eq("SUBSTRATE_PATH_MIN", 140.0)
	_eq("SUBSTRATE_PATH_MAX", 220.0)
	_eq("SUBSTRATE_SOFT_WALLS", 6)
	_eq("HALLS_SOFT_WALLS", 4)
	_eq("GARAGE_CAR_FILL", 0.35)
	_eq("OFFICES_DARK_GROUP_FRACTION", 0.40)
	_eq("POOLS_WADE_LIMIT", 1.3)
	assert_eq(_t("HALLS_ROOM_SIZE_MAX"), Vector2i(6, 5))
	assert_eq(_t("POOLS_FILL_WEIGHTS"), [30, 40, 30])
	var heights: Dictionary = _t("STRATUM_CEILING_HEIGHT")
	assert_eq([heights[&"halls"], heights[&"pools"], heights[&"garage"], heights[&"server"]], [3.0, 6.0, 3.2, 3.5])
	var depth1: Dictionary = _t("LOCK_WEIGHTS_DEPTH1")
	assert_eq(depth1, {&"open": 40, &"powered": 60})
	assert_eq(_t("LOCK_WEIGHTS_DEPTH4_5"), {&"powered": 30, &"keyed": 35, &"cycled": 35})

# --- 02 visual, 03 audio -----------------------------------------------------------

func test_post_stack_and_world_shader() -> void:
	_eq("POST_CA_MAX", 0.012)
	_eq("POST_SAT_MIN", 0.08)
	_eq("POST_GRAIN_MIN", 0.02)
	_eq("POST_GRAIN_MAX", 0.18)
	_eq("POST_VIGNETTE_MIN", 0.15)
	_eq("POST_VIGNETTE_MAX", 0.45)
	_eq("POST_REDUCED_GRAIN_CAP", 0.06)
	_eq("POST_REDUCED_CA_CAP", 0.004)
	_eq("WORLD_JITTER_MAX", 0.012)
	_eq("WORLD_GRID_SPACING", 0.5)
	_eq("LIGHT_BREAKER_WAVE_SPEED", 12.0)
	_eq("LIGHT_POOL_REEVAL_INTERVAL", 0.25)

func test_camera_and_fov() -> void:
	_eq("CAMERA_FOV_MIN", 70)
	_eq("CAMERA_FOV_MAX", 110)
	_eq("CAMERA_FOV_DEFAULT", 90)
	_eq("SETTINGS_FOV_MIN", 70)
	_eq("SETTINGS_FOV_MAX", 110)
	_eq("SETTINGS_FOV_DEFAULT", 90)
	assert_true(_t("CAMERA_FOV_DEFAULT") >= _t("CAMERA_FOV_MIN") and _t("CAMERA_FOV_DEFAULT") <= _t("CAMERA_FOV_MAX"))
	_eq("CAMERA_NEAR", 0.05)
	_eq("CAMERA_FAR", 120.0)
	_eq("CAMERA_SHAKE_MAX_TRANSLATION", 0.04)
	_eq("CAMERA_SHAKE_MAX_ROTATION", 1.2)

func test_quality_presets() -> void:
	var p: Dictionary = _t("QUALITY_PRESETS")
	assert_eq(p[&"low"][&"lights"], 10)
	assert_eq(p[&"medium"][&"lights"], 16)
	assert_eq(p[&"high"][&"lights"], 24)
	assert_eq([p[&"low"][&"shadowed"], p[&"medium"][&"shadowed"], p[&"high"][&"shadowed"]], [0, 2, 4])
	assert_eq([p[&"low"][&"shadow_atlas"], p[&"medium"][&"shadow_atlas"], p[&"high"][&"shadow_atlas"]], [2048, 4096, 8192])
	assert_eq(p[&"low"][&"render_scale"], 0.8)
	assert_true(p[&"high"][&"ssil"])
	assert_false(p[&"medium"][&"ssil"])
	assert_eq(_t("QUALITY_PRESET_DEFAULT"), &"medium")

func test_stratum_look_scalars() -> void:
	var fog: Dictionary = _t("STRATUM_FOG_DENSITY")
	assert_eq([fog[&"halls"], fog[&"pools"], fog[&"garage"], fog[&"offices"], fog[&"server"], fog[&"substrate"]], [0.02, 0.035, 0.015, 0.02, 0.03, 0.0])
	var rev: Dictionary = _t("AUDIO_REVERB")
	assert_eq(rev[&"pools"][&"predelay_ms"], 40)
	assert_eq(rev[&"substrate"][&"room"], 1.0)
	assert_eq(rev[&"substrate"][&"highpass_hz"], 300)
	_eq("AUDIO_LIMITER_CEILING_DB", -1.0)
	_eq("AUDIO_OCCLUSION_LOWPASS_HZ", 800.0)

# --- 04 ui, 11 feedback, 12 settings, 13 meta -----------------------------------------

func test_ui_numbers() -> void:
	_eq("UI_FONT_HUD_BODY", 18)
	_eq("UI_FONT_WORDMARK", 160)
	_eq("UI_COLOR_ACCENT", "#FFB000")
	_eq("UI_COLOR_DANGER", "#FF3B3B")
	_eq("UI_COLOR_COLD", "#3B8BFF")
	_eq("UI_TWEEN_MS", 180)
	_eq("UI_SHUTTER_MS", 120)
	_eq("UI_SHUTTER_BANDS", 6)
	_eq("UI_TYPING_CPS", 60)
	_eq("UI_NOTE_TYPING_CPS", 90)
	_eq("CAPTION_NEAR_DIST", 6.0)
	_eq("CAPTION_FAR_DIST", 20.0)
	_eq("HINT_COUNT", 7)
	_eq("HUD_NOTIFY_TIME", 4.0)

func test_feedback_numbers() -> void:
	_eq("FEEDBACK_MAX_LATENCY_MS", 50)
	_eq("FEEDBACK_NOCLIP_COMMIT_TRAUMA", 0.8)
	_eq("FEEDBACK_ITEM_PULSE", 1.15)
	_eq("CONTACT_HITSTOP_MS", 60)
	_eq("FEEDBACK_SPRINT_FOV_DEG", 4.0)
	_eq("CAMERA_TRAUMA_DECAY", 1.5)

func test_settings_and_meta() -> void:
	_eq("SETTINGS_SAVE_DEBOUNCE", 0.5)
	_eq("SETTINGS_REVERT_COUNTDOWN", 10.0)
	_eq("SETTINGS_RENDER_SCALE_MIN", 0.5)
	_eq("SETTINGS_RENDER_SCALE_MAX", 1.5)
	_eq("SETTINGS_BRIGHTNESS_MIN", 0.8)
	_eq("SETTINGS_BRIGHTNESS_MAX", 1.4)
	_eq("SETTINGS_AUDIO_MASTER_DEFAULT", 80)
	_eq("SETTINGS_AUDIO_MUSIC_DEFAULT", 80)
	_eq("SETTINGS_AUDIO_UI_DEFAULT", 80)
	_eq("SETTINGS_FLICKER_INTENSITY_MIN", 0.3)
	_eq("PLAYER_MOUSE_SENS_MIN", 0.1)
	_eq("PLAYER_MOUSE_SENS_MAX", 3.0)
	_eq("PLAYER_MOUSE_SENS_DEFAULT", 1.0)
	_eq("META_VERSION", 1)
	_eq("META_DEPTH_MAX", 999)
	assert_eq(_t("SEED_DAILY_PREFIX"), "NOCLIP:")
	assert_eq(_t("SEED_DERIVE_FORMAT") % [7, "depth:1"], "7:depth:1")

func test_budgets_and_layers() -> void:
	_eq("BUDGET_DRAW_CALLS", 1500)
	_eq("BUDGET_ACTIVE_LIGHTS", 24)
	_eq("LAYER_WORLD", 1)
	_eq("LAYER_THROWN", 8)
	_eq("AUDIO_PLAYER_POOL_SIZE", 32)

func test_internal_consistency() -> void:
	# Aliases and mirrored values agree wherever the design states one number twice.
	assert_eq(_t("STILL_CONTACT_COST"), _t("COHERENCE_CONTACT_STILL"))
	assert_eq(_t("ECHO_CONTACT_COST"), _t("COHERENCE_CONTACT_ECHO"))
	assert_eq(_t("FLICKER_LUNGE_COST"), _t("COHERENCE_CONTACT_FLICKER"))
	assert_eq(_t("DROP_FALL_TIME"), _t("NOCLIP_FLOOR_FALL_TIME"))
	assert_eq(_t("NOISE_CRANK_RADIUS"), _t("CRANK_NOISE_RADIUS"))
	assert_eq(_t("FLARE_NOISE_RADIUS"), _t("NOISE_FLARE_BURNING_RADIUS"))
	assert_eq(_t("LIGHT_POOL_SIZE_MEDIUM"), (_t("QUALITY_PRESETS") as Dictionary)[&"medium"][&"lights"])
	assert_eq(_t("SETTINGS_FOV_DEFAULT"), _t("CAMERA_FOV_DEFAULT"))
	var contact: Dictionary = _t("ERROR_CONTACT_COST")
	assert_eq(contact[&"still"], _t("COHERENCE_CONTACT_STILL"))
	assert_eq(contact[&"echo"], _t("COHERENCE_CONTACT_ECHO"))
	assert_eq(contact[&"flicker"], _t("COHERENCE_CONTACT_FLICKER"))
	# Min/max pairs are ordered.
	for pair in [["STATIC_RADIUS_MIN", "STATIC_RADIUS_MAX"], ["DIRECTOR_RELIEF_MIN_TIME", "DIRECTOR_RELIEF_MAX_TIME"],
			["DIRECTOR_HINT_RANGE_MIN", "DIRECTOR_HINT_RANGE_MAX"], ["FLICKER_HOP_MIN", "FLICKER_HOP_MAX"],
			["SUBSTRATE_PATH_MIN", "SUBSTRATE_PATH_MAX"], ["CAMERA_FOV_MIN", "CAMERA_FOV_MAX"],
			["STATIC_DWELL_MIN", "STATIC_DWELL_MAX"], ["MUSIC_VOICE_CHANGE_MIN", "MUSIC_VOICE_CHANGE_MAX"]]:
		assert_lt(_t(pair[0]), _t(pair[1]), "%s < %s" % pair)
