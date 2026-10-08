extends TestCase
## M2.11 settings (12): every option of 12 §2 to §7 exists with its default and range; values
## are validated and clamped; settings.cfg round-trips, migrates from version 0, recovers from a
## corrupt file and writes debounced; rebinding swaps conflicts and resets; presets and tab
## reset; FOV reaches Camera3D; the window change reverts after 10 s; the live application
## reaches the viewport (FSR 2), environments, light pools and the noise textures.

## 12 §2 to §7 as written: key -> [tab, default, min, max] (min/max null for enums and toggles).
const SPEC: Dictionary = {
	&"window_mode": [&"display", &"fullscreen", null, null],
	&"resolution": [&"display", &"native", null, null],
	&"vsync": [&"display", &"on", null, null],
	&"max_fps": [&"display", 0, 30, 360],
	&"render_scale": [&"display", 1.0, 0.5, 1.5],
	&"upscaling": [&"display", &"fsr2", null, null],
	&"ui_scale": [&"display", 1.0, 0.75, 1.5],
	&"brightness": [&"display", 1.0, 0.8, 1.4],
	&"fov": [&"display", 90, 70, 110],
	&"head_bob": [&"display", 1.0, 0.0, 1.0],
	&"screen_shake": [&"display", 1.0, 0.0, 1.0],
	&"preset": [&"graphics", &"medium", null, null],
	&"anti_aliasing": [&"graphics", &"taa", null, null],
	&"shadow_quality": [&"graphics", &"medium", null, null],
	&"ambient_occlusion": [&"graphics", true, null, null],
	&"indirect_lighting": [&"graphics", false, null, null],
	&"volumetric_fog": [&"graphics", &"low", null, null],
	&"glow": [&"graphics", true, null, null],
	&"particles": [&"graphics", &"full", null, null],
	&"light_pool_size": [&"graphics", 16, 10, 32],
	&"texture_detail": [&"graphics", &"high", null, null],
	&"audio_master": [&"audio", 80, 0, 100],
	&"audio_effects": [&"audio", 100, 0, 100],
	&"audio_ambience": [&"audio", 100, 0, 100],
	&"audio_music": [&"audio", 80, 0, 100],
	&"audio_ui": [&"audio", 80, 0, 100],
	&"audio_output_device": [&"audio", "Default", null, null],
	&"mute_unfocused": [&"audio", true, null, null],
	&"mouse_sensitivity": [&"controls", 1.0, 0.1, 3.0],
	&"invert_y": [&"controls", false, null, null],
	&"sprint_mode": [&"controls", &"hold", null, null],
	&"crouch_mode": [&"controls", &"hold", null, null],
	&"raw_mouse": [&"controls", true, null, null],
	&"captions": [&"accessibility", false, null, null],
	&"reduce_visual_noise": [&"accessibility", false, null, null],
	&"reduce_flashing": [&"accessibility", false, null, null],
	&"flicker_intensity": [&"accessibility", 1.0, 0.3, 1.0],
	&"crosshair": [&"accessibility", &"dot_ring", null, null],
	&"hud_mode": [&"accessibility", &"full", null, null],
	&"hints": [&"accessibility", true, null, null],
	&"text_size": [&"accessibility", 1.0, 0.9, 1.4],
	&"hold_to_press": [&"accessibility", false, null, null],
	&"colorblind_accent": [&"accessibility", false, null, null],
	&"show_depth": [&"gameplay", true, null, null],
	&"show_exit_status": [&"gameplay", true, null, null],
	&"auto_sprint": [&"gameplay", false, null, null],
	&"debug_overlay": [&"gameplay", false, null, null],
}
const TEST_DIR := "user://tests/settings_case"

var _prev_dir: String
var _prev_now: Callable
var _now: int = 1_000_000


func before_each() -> void:
	_prev_dir = SettingsManager.directory
	_prev_now = SettingsManager.now_msec
	SettingsManager.directory = TEST_DIR
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	for f in ["settings.cfg", "settings.cfg.bad"]:
		if FileAccess.file_exists(TEST_DIR.path_join(f)):
			DirAccess.remove_absolute(TEST_DIR.path_join(f))
	SettingsManager.now_msec = func() -> int: return _now
	_defaults()


func after_each() -> void:
	SettingsManager.revert_display()
	_defaults()
	await _noise_settled()
	SettingsManager.save_settings()
	SettingsManager.directory = _prev_dir
	SettingsManager.now_msec = _prev_now


func _defaults() -> void:
	for key: StringName in SettingsManager.DEFAULTS:
		SettingsManager.set_value(key, SettingsManager.DEFAULTS[key])
	SettingsManager.reset_bindings()


## Noise textures regenerate on a worker thread after a size change; quitting mid-generation
## stalls the engine's exit, so tests that change texture detail wait for `changed`.
func _noise_settled() -> void:
	for path in CoherenceRenderer.NOISE_TEXTURES:
		var tex := load(path) as NoiseTexture2D
		if tex == null:
			continue
		var end := Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < end:
			var img := tex.get_image()
			if img != null and img.get_width() == tex.width:
				break
			await get_tree().process_frame
		await await_frames(2)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


# --- the options -------------------------------------------------------------------------------

func test_every_option_of_12_exists_with_default_and_range() -> void:
	assert_eq(SettingsSchema.DEFAULTS.size(), SPEC.size(), "no option missing or extra")
	for key: StringName in SPEC:
		var spec: Array = SPEC[key]
		var o := SettingsSchema.option(key)
		assert_false(o.is_empty(), "%s exists" % key)
		if o.is_empty():
			continue
		assert_eq(o[&"tab"], spec[0], "%s tab" % key)
		assert_true(SettingsManager.DEFAULTS.has(key), "%s has a default" % key)
		var d: Variant = SettingsManager.DEFAULTS[key]
		assert_eq(String(d) if d is StringName else d, String(spec[1]) if spec[1] is StringName else spec[1], "%s default" % key)
		assert_eq(o[&"default"], SettingsManager.DEFAULTS[key], "%s schema default" % key)
		if spec[2] != null:
			assert_approx(float(o[&"min"]), float(spec[2]), 0.0001, "%s min" % key)
			assert_approx(float(o[&"max"]), float(spec[3]), 0.0001, "%s max" % key)
		assert_true(Strings.SETTING_LABELS.has(key), "%s has a label" % key)
		assert_true(Strings.SETTING_DESCRIPTIONS.has(key), "%s has a description" % key)
		assert_eq(SettingsManager.get_value(key), SettingsSchema.validate(key, SettingsManager.DEFAULTS[key]), "%s live default" % key)


func test_steps_from_12() -> void:
	assert_approx(float(SettingsSchema.option(&"render_scale")[&"step"]), 0.05)
	assert_approx(float(SettingsSchema.option(&"ui_scale")[&"step"]), 0.05)
	assert_approx(float(SettingsSchema.option(&"brightness")[&"step"]), 0.02)
	assert_approx(float(SettingsSchema.option(&"mouse_sensitivity")[&"step"]), 0.01)
	assert_eq(int(SettingsSchema.option(&"fov")[&"step"]), 1)
	assert_eq(SettingsSchema.option(&"anti_aliasing")[&"values"], [&"off", &"fxaa", &"taa", &"msaa2x", &"msaa4x"])
	assert_eq(SettingsSchema.option(&"window_mode")[&"values"], [&"fullscreen", &"exclusive_fullscreen", &"windowed"])


func test_values_are_validated_and_clamped() -> void:
	SettingsManager.set_value(&"fov", 300)
	assert_eq(SettingsManager.get_value(&"fov"), 110)
	SettingsManager.set_value(&"fov", 12)
	assert_eq(SettingsManager.get_value(&"fov"), 70)
	SettingsManager.set_value(&"mouse_sensitivity", 10.0)
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 3.0)
	SettingsManager.set_value(&"mouse_sensitivity", 0.0)
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 0.1)
	SettingsManager.set_value(&"mouse_sensitivity", 1.234)
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 1.23, 0.0001, "snapped to 0.01")
	SettingsManager.set_value(&"render_scale", 0.73)
	assert_approx(float(SettingsManager.get_value(&"render_scale")), 0.75, 0.0001, "snapped to 0.05")
	SettingsManager.set_value(&"max_fps", 10)
	assert_eq(SettingsManager.get_value(&"max_fps"), 30)
	SettingsManager.set_value(&"max_fps", 0)
	assert_eq(SettingsManager.get_value(&"max_fps"), 0, "0 is Unlimited")
	SettingsManager.set_value(&"vsync", &"sometimes")
	assert_eq(SettingsManager.get_value(&"vsync"), &"on", "unknown enum value falls back to the default")
	SettingsManager.set_value(&"invert_y", "yes")
	assert_eq(SettingsManager.get_value(&"invert_y"), false, "wrong type falls back to the default")
	assert_eq(SettingsSchema.validate(&"resolution", "800x600"), &"native", "below 1280 x 720 is refused")
	assert_eq(SettingsSchema.validate(&"resolution", "2560x1440"), &"2560x1440")


# --- persistence (12 §8, 13 §1) ----------------------------------------------------------------

func test_persistence_round_trip() -> void:
	SettingsManager.set_value(&"fov", 104)
	SettingsManager.set_value(&"mouse_sensitivity", 2.37)
	SettingsManager.set_value(&"vsync", &"adaptive")
	SettingsManager.set_value(&"invert_y", true)
	SettingsManager.set_value(&"audio_music", 35)
	SettingsManager.apply_preset(&"high")
	SettingsManager.rebind(&"interact", _key(KEY_G), 0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_MIDDLE
	SettingsManager.rebind(&"crank", wheel, 1)
	assert_true(SettingsManager.save_settings())
	assert_true(FileAccess.file_exists(SettingsManager.settings_path()))
	_defaults()
	assert_eq(SettingsManager.get_value(&"fov"), 90)
	SettingsManager.load_settings()
	assert_eq(SettingsManager.get_value(&"fov"), 104)
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 2.37)
	assert_eq(SettingsManager.get_value(&"vsync"), &"adaptive")
	assert_eq(SettingsManager.get_value(&"invert_y"), true)
	assert_eq(SettingsManager.get_value(&"audio_music"), 35)
	assert_eq(SettingsManager.get_value(&"preset"), &"high")
	assert_eq(SettingsManager.get_value(&"light_pool_size"), 24)
	var ev := SettingsManager.binding(&"interact", 0) as InputEventKey
	assert_not_null(ev)
	if ev != null:
		assert_eq(ev.physical_keycode, KEY_G, "physical keycodes are stored (12 §5)")
	var crank2 := SettingsManager.binding(&"crank", 1) as InputEventMouseButton
	assert_not_null(crank2, "mouse buttons are bindable")
	assert_eq(InputMap.action_get_events(&"crank").size(), 2, "the InputMap follows the loaded slots")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SettingsManager.settings_path()), OK)
	assert_eq(cfg.get_value("meta", "settings_version"), Tuning.SETTINGS_VERSION)


func test_missing_keys_get_defaults_and_are_written() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "settings_version", Tuning.SETTINGS_VERSION)
	cfg.set_value("settings", "fov", 77)
	cfg.set_value("settings", "brightness", 9.0)
	cfg.save(SettingsManager.settings_path())
	SettingsManager.load_settings()
	assert_eq(SettingsManager.get_value(&"fov"), 77)
	assert_approx(float(SettingsManager.get_value(&"brightness")), 1.4, 0.0001, "out of range is clamped on load")
	assert_eq(SettingsManager.get_value(&"hud_mode"), &"full", "missing key gets its default")
	assert_true(SettingsManager.is_dirty(), "defaults for missing keys are written back")


func test_migration_from_version_0() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "sensitivity", 2.5)
	cfg.set_value("settings", "master_volume", 40)
	cfg.save(SettingsManager.settings_path())
	SettingsManager.load_settings()
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 2.5)
	assert_eq(SettingsManager.get_value(&"audio_master"), 40)
	assert_true(SettingsManager.is_dirty(), "a migrated file is rewritten at the new version")
	assert_eq(SettingsManager.migrate({"sensitivity": 1.5}, 1), {"sensitivity": 1.5}, "version 1 needs no step")


func test_corrupt_file_is_backed_up_and_recreated() -> void:
	var f := FileAccess.open(SettingsManager.settings_path(), FileAccess.WRITE)
	f.store_string("[settings\nfov = = =\n")
	f.close()
	SettingsManager.load_settings()
	assert_true(FileAccess.file_exists(SettingsManager.bad_path()), "settings.cfg.bad kept")
	assert_eq(SettingsManager.get_value(&"fov"), 90, "defaults after a corrupt file")
	SettingsManager.flush()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SettingsManager.settings_path()), OK, "a fresh file is written")


func test_changes_are_written_debounced() -> void:
	SettingsManager.save_settings()
	SettingsManager.set_value(&"fov", 95)
	assert_true(SettingsManager.is_dirty())
	_now += 400
	SettingsManager._process(0.0)
	assert_true(SettingsManager.is_dirty(), "not before 0.5 s")
	_now += 200
	SettingsManager._process(0.0)
	assert_false(SettingsManager.is_dirty(), "written after 0.5 s")
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.settings_path())
	assert_eq(cfg.get_value("settings", "fov"), 95)


# --- rebinding (12 §5) ---------------------------------------------------------------------------

func test_rebind_conflict_swaps() -> void:
	var partner := SettingsManager.rebind(&"interact", _key(KEY_F), 0)
	assert_eq(partner, &"flashlight", "the action that held F gives it up")
	assert_eq((SettingsManager.binding(&"interact", 0) as InputEventKey).physical_keycode, KEY_F)
	assert_eq((SettingsManager.binding(&"flashlight", 0) as InputEventKey).physical_keycode, KEY_E, "swapped")
	var f := _key(KEY_F)
	assert_true(f.is_action(&"interact"), "the InputMap follows")
	assert_false(f.is_action(&"flashlight"))
	assert_true(_key(KEY_E).is_action(&"flashlight"))


func test_rebind_into_an_empty_slot_moves_the_input() -> void:
	var partner := SettingsManager.rebind(&"crank", _key(KEY_W), 1)
	assert_eq(partner, &"move_forward")
	assert_null(SettingsManager.binding(&"move_forward", 0), "the old slot was empty, so W's slot empties")
	assert_eq(SettingsManager.bindings()[&"crank"].size(), 2)


func test_rebind_mouse_buttons_swap() -> void:
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(SettingsManager.rebind(&"noclip", rmb, 0), &"use_item")
	assert_eq((SettingsManager.binding(&"use_item", 0) as InputEventMouseButton).button_index, MOUSE_BUTTON_LEFT)


func test_clear_and_reset_bindings() -> void:
	SettingsManager.clear_binding(&"interact", 0)
	assert_null(SettingsManager.binding(&"interact", 0))
	assert_eq(InputMap.action_get_events(&"interact").size(), 0)
	SettingsManager.rebind(&"sprint", _key(KEY_Q), 0)
	SettingsManager.reset_tab(SettingsSchema.TAB_CONTROLS)
	assert_eq((SettingsManager.binding(&"interact", 0) as InputEventKey).physical_keycode, KEY_E, "RESET TAB TO DEFAULTS restores the map")
	assert_eq((SettingsManager.binding(&"sprint", 0) as InputEventKey).physical_keycode, KEY_SHIFT)
	for action in SettingsManager.REBINDABLE_ACTIONS:
		assert_eq(InputMap.action_get_events(action).size(), 1, "%s back to one default binding" % action)


func test_binding_text_round_trip() -> void:
	for t in ["key:69:0", "key:4194325:1", "mouse:1", "mouse:5"]:
		assert_eq(SettingsBindings.event_to_text(SettingsBindings.text_to_event(t)), t)
	assert_null(SettingsBindings.text_to_event(""))
	assert_null(SettingsBindings.text_to_event("joy:3"))
	assert_null(SettingsBindings.text_to_event("key:abc"))


# --- presets, tabs ---------------------------------------------------------------------------------

func test_presets_set_the_graphics_tab_and_editing_makes_custom() -> void:
	SettingsManager.apply_preset(&"low")
	assert_eq(SettingsManager.get_value(&"preset"), &"low")
	assert_eq(SettingsManager.get_value(&"anti_aliasing"), &"fxaa", "02 §12 Low")
	assert_eq(SettingsManager.get_value(&"shadow_quality"), &"low")
	assert_eq(SettingsManager.get_value(&"ambient_occlusion"), false)
	assert_eq(SettingsManager.get_value(&"volumetric_fog"), &"off")
	assert_eq(SettingsManager.get_value(&"light_pool_size"), 10)
	assert_eq(SettingsManager.get_value(&"particles"), &"low")
	assert_approx(float(SettingsManager.get_value(&"render_scale")), 0.8)
	await _noise_settled()
	SettingsManager.set_value(&"preset", &"medium")
	assert_eq(SettingsManager.get_value(&"shadow_quality"), &"medium")
	assert_eq(SettingsManager.get_value(&"volumetric_fog"), &"low")
	SettingsManager.set_value(&"glow", false)
	assert_eq(SettingsManager.get_value(&"preset"), &"custom", "12 §3: editing any item switches to Custom")


func test_reset_tab_restores_that_tab_only() -> void:
	SettingsManager.set_value(&"fov", 105)
	SettingsManager.set_value(&"brightness", 1.2)
	SettingsManager.set_value(&"captions", true)
	SettingsManager.reset_tab(SettingsSchema.TAB_DISPLAY)
	assert_eq(SettingsManager.get_value(&"fov"), 90)
	assert_approx(float(SettingsManager.get_value(&"brightness")), 1.0)
	assert_eq(SettingsManager.get_value(&"captions"), true, "other tabs untouched")


# --- FOV, sensitivity (12 §2, §5) ---------------------------------------------------------------

func test_fov_conversion_applied_to_the_camera() -> void:
	assert_approx(CameraRig.hfov_to_vfov(90.0), 58.7155, 0.001, "2 atan(tan(45°) x 9/16)")
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world)
	SettingsManager.set_value(&"fov", 100)
	assert_approx(p.rig.camera.fov, CameraRig.hfov_to_vfov(100.0), 0.01)
	assert_eq(p.rig.camera.keep_aspect, Camera3D.KEEP_HEIGHT, "21:9 gains width, never loses height")
	# At 21:9 with KEEP_HEIGHT the horizontal FOV is wider than the 16:9 setting.
	var v := deg_to_rad(p.rig.camera.fov)
	var h21 := rad_to_deg(2.0 * atan(tan(v * 0.5) * 21.0 / 9.0))
	assert_gt(h21, 100.0)
	assert_approx(rad_to_deg(2.0 * atan(tan(v * 0.5) * 16.0 / 9.0)), 100.0, 0.01, "16:9 shows exactly the setting")
	world.free()


# --- window change with revert (12 §1) --------------------------------------------------------

func test_window_change_reverts_after_10_s() -> void:
	SettingsManager.try_display(&"window_mode", &"windowed")
	assert_true(SettingsManager.is_display_pending())
	assert_eq(SettingsManager.get_value(&"window_mode"), &"windowed", "applied at once")
	assert_eq(SettingsManager.display_seconds_left(), 10)
	_now += 9000
	SettingsManager._process(0.0)
	assert_true(SettingsManager.is_display_pending())
	_now += 1100
	SettingsManager._process(0.0)
	assert_false(SettingsManager.is_display_pending())
	assert_eq(SettingsManager.get_value(&"window_mode"), &"fullscreen", "reverted")


func test_window_change_kept_on_confirm() -> void:
	var got: Array = []
	SettingsManager.display_resolved.connect(func(k: bool) -> void: got.append(k), CONNECT_ONE_SHOT)
	SettingsManager.try_display(&"resolution", &"1600x900")
	SettingsManager.keep_display()
	_now += 20000
	SettingsManager._process(0.0)
	assert_eq(SettingsManager.get_value(&"resolution"), &"1600x900")
	assert_eq(got, [true])


# --- live application ----------------------------------------------------------------------------

func test_fsr2_below_render_scale_1() -> void:
	var vp := SubViewport.new()
	add_child(vp)
	var vals := SettingsSchema.DEFAULTS.duplicate()
	vals[&"render_scale"] = 0.75
	assert_true(SettingsApply.fsr_active(vals))
	StratumEnvironment.apply_viewport_profile(vp, SettingsApply.graphics_profile(vals))
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR2)
	assert_approx(vp.scaling_3d_scale, 0.75)
	assert_false(vp.use_taa, "FSR 2 replaces anti-aliasing")
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED)
	vals[&"upscaling"] = &"bilinear"
	assert_false(SettingsApply.fsr_active(vals))
	StratumEnvironment.apply_viewport_profile(vp, SettingsApply.graphics_profile(vals))
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)
	assert_true(vp.use_taa)
	vals[&"render_scale"] = 1.25
	vals[&"upscaling"] = &"fsr2"
	vals[&"anti_aliasing"] = &"msaa4x"
	StratumEnvironment.apply_viewport_profile(vp, SettingsApply.graphics_profile(vals))
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "above 1.0 is bilinear supersampling")
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X)
	assert_false(vp.use_taa)
	StratumEnvironment.apply_viewport_preset(vp, &"low")
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "a bare 02 §12 Low preset stays FXAA, bilinear")
	SettingsManager.apply_preset(&"low")
	await _noise_settled()
	assert_true(SettingsApply.fsr_active({&"render_scale": SettingsManager.get_value(&"render_scale"),
			&"upscaling": SettingsManager.get_value(&"upscaling")}), "the player's Low upscales with FSR 2 (12 §2 default)")
	vp.free()


func test_graphics_reach_environments_and_light_pools() -> void:
	var holder := Node.new()
	add_child(holder)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.5, 0.4, 0.2)
	we.environment = env
	holder.add_child(we)
	var pool := LightPool.new()
	holder.add_child(pool)
	var vals := SettingsSchema.DEFAULTS.duplicate()
	vals[&"volumetric_fog"] = &"off"
	vals[&"ambient_occlusion"] = false
	vals[&"glow"] = false
	vals[&"brightness"] = 1.2
	vals[&"light_pool_size"] = 12
	vals[&"shadow_quality"] = &"high"
	SettingsApply.graphics(holder, vals)
	assert_false(env.volumetric_fog_enabled)
	assert_true(env.fog_enabled, "Off becomes distance fog")
	assert_approx(env.fog_density, 0.03, 0.0001, "of the same density")
	assert_false(env.ssao_enabled)
	assert_false(env.glow_enabled)
	assert_approx(env.adjustment_brightness, 1.2)
	assert_eq(pool.pool_size, 12)
	assert_eq(pool.shadowed, 4)
	vals[&"volumetric_fog"] = &"high"
	SettingsApply.graphics(holder, vals)
	assert_true(env.volumetric_fog_enabled, "and back")
	assert_approx(env.volumetric_fog_density, 0.03, 0.0001)
	holder.free()


func test_texture_detail_key_reaches_the_renderer() -> void:
	SettingsManager.set_value(&"texture_detail", &"low")
	var tex := load(CoherenceRenderer.NOISE_TEXTURES[0]) as NoiseTexture2D
	if tex != null:
		assert_eq(tex.width, Tuning.QUALITY_TEXTURE_SIZE_LOW)
	await _noise_settled()
	SettingsManager.set_value(&"texture_detail", &"high")
	if tex != null:
		assert_eq(tex.width, Tuning.QUALITY_TEXTURE_SIZE_HIGH)
	await _noise_settled()


func test_ui_scale_follows_the_window_height() -> void:
	assert_approx(SettingsApply.content_scale(1080.0, 1.0), 1.0)
	assert_approx(SettingsApply.content_scale(720.0, 1.0), 0.6667, 0.001)
	assert_approx(SettingsApply.content_scale(1440.0, 1.5), 2.0)


func test_other_settings_apply() -> void:
	SettingsManager.set_value(&"max_fps", 144)
	assert_eq(Engine.max_fps, 144)
	SettingsManager.set_value(&"max_fps", 0)
	assert_eq(Engine.max_fps, 0)
	SettingsManager.set_value(&"raw_mouse", false)
	assert_true(Input.use_accumulated_input)
	SettingsManager.set_value(&"raw_mouse", true)
	assert_false(Input.use_accumulated_input, "12 §5 raw input: accumulated input off")
