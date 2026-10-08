extends TestCase
## M2.12: every 12 §6 accessibility option (and UI scale, head bob, screen shake from 12 §2)
## toggled through SettingsManager, observed where it lands: the theme, the HUD, the menus,
## the post stack, the camera and the interactor. Each test restores what it changed.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const KEYS: Array[StringName] = [
	&"captions", &"reduce_visual_noise", &"reduce_flashing", &"crosshair", &"hud_mode", &"hints",
	&"text_size", &"hold_to_press", &"colorblind_accent", &"ui_scale", &"head_bob", &"screen_shake",
]

var _saved: Dictionary = {}
var _meta: MetaState


func before_each() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()
	for k in KEYS:
		_saved[k] = SettingsManager.get_value(k)
	UiMotion.manual_clock = true


func after_each() -> void:
	for k: StringName in _saved:
		SettingsManager.set_value(k, _saved[k])
	GameState.meta = _meta
	UiMotion.manual_clock = false


func _hud() -> Hud:
	var h := (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child(h)
	return h


func test_every_accessibility_option_is_covered_here() -> void:
	for key in SettingsSchema.keys_for(SettingsSchema.TAB_ACCESSIBILITY):
		if key == &"flicker_intensity":
			continue  # owned by the fixtures and Flicker (02 §6, 08 §4); see the M2.12 report
		assert_contains(KEYS, key, "12 §6 option %s has an end-to-end test" % key)


func test_colorblind_accent_swaps_tokens_live() -> void:
	var hud := _hud()
	hud.set_depth(3, &"garage")
	assert_eq(hud.depth.numeral_color(), UiTokens.UI_ACCENT)
	var theme := UiAccessibility.project_theme()
	SettingsManager.set_value(&"colorblind_accent", true)
	assert_eq(UiTokens.accent(), UiTokens.UI_ACCENT_CB)
	assert_eq(theme.get_color(&"font_color", &"AccentLabel"), UiTokens.UI_ACCENT_CB, "theme accent text")
	assert_eq(theme.get_color(&"font_focus_color", &"Button"), UiTokens.UI_ACCENT_CB)
	assert_eq(theme.get_constant(&"outline_size", &"AccentLabel"), 1, "a 1 px outline on accent text")
	assert_eq(theme.get_color(&"ui_accent", UiTokens.THEME_TOKEN_TYPE), UiTokens.UI_ACCENT, "the token table keeps its values")
	assert_eq(hud.depth.numeral_color(), UiTokens.UI_ACCENT_CB, "the HUD repaints live")
	var num := hud.depth.find_children("*", "Label", true, false)[1] as Label
	assert_eq(num.get_theme_constant(&"outline_size"), 1)
	# danger adds `!`, cold adds `~`
	hud.set_coherence(10.0, -90.0)
	UiMotion.step(hud, 5.0)
	assert_true(hud.coherence.numeral_text().ends_with("!"), hud.coherence.numeral_text())
	hud.set_depth(6, &"substrate")
	assert_true(hud.depth.depth_text().contains("06 ~"), hud.depth.depth_text())
	# a menu row paints with the new accent
	var row := MenuList.new()
	add_child(row)
	row.add_item(&"a", "A")
	row.add_item(&"b", "B")
	row.active = true
	row.select(0)
	assert_eq(row._labels[0].get_theme_color(&"font_color"), UiTokens.UI_ACCENT_CB)
	SettingsManager.set_value(&"colorblind_accent", false)
	assert_eq(theme.get_color(&"font_color", &"AccentLabel"), UiTokens.UI_ACCENT)
	assert_eq(theme.get_constant(&"outline_size", &"AccentLabel"), 0)
	assert_eq(hud.depth.numeral_color(), UiTokens.UI_COLD)
	assert_false(hud.depth.depth_text().contains("~"))
	row.free()
	hud.free()


func test_text_size_scales_notes_and_captions_only() -> void:
	var theme := UiAccessibility.project_theme()
	SettingsManager.set_value(&"text_size", 1.4)
	assert_eq(theme.get_font_size(&"font_size", &"Caption"), 28)
	assert_eq(theme.get_font_size(&"font_size", &"NoteBody"), 28)
	assert_eq(theme.get_font_size(&"font_size", &"Prompt"), UiTokens.FONT_PROMPT)
	assert_eq(theme.get_font_size(&"font_size", &"MenuItemLabel"), UiTokens.FONT_MENU_ITEM)
	SettingsManager.set_value(&"text_size", 0.9)
	assert_eq(theme.get_font_size(&"font_size", &"Caption"), 18)
	SettingsManager.set_value(&"text_size", 1.0)
	assert_eq(theme.get_font_size(&"font_size", &"Caption"), UiTokens.FONT_CAPTION)


func test_reduce_visual_noise_caps_grain_and_ca() -> void:
	SettingsManager.set_value(&"reduce_visual_noise", false)
	CoherenceRenderer.set_coherence(5.0)
	CoherenceRenderer._update_post()
	var full: Dictionary = CoherenceRenderer.post_params.duplicate()
	SettingsManager.set_value(&"reduce_visual_noise", true)
	CoherenceRenderer._update_post()
	var capped: Dictionary = CoherenceRenderer.post_params
	assert_lt(float(capped[&"grain"]), float(full[&"grain"]))
	assert_lt(float(capped[&"grain"]), Tuning.POST_REDUCED_GRAIN_CAP + 0.0001)
	assert_lt(float(capped[&"ca"]), Tuning.POST_REDUCED_CA_CAP + 0.0001)
	assert_eq(float(capped[&"scan"]), 0.0)
	assert_approx(float(capped[&"sat"]), float(full[&"sat"]), 0.0001, "desaturation stays")
	CoherenceRenderer.set_coherence(100.0)
	CoherenceRenderer._update_post()


func test_reduce_flashing_turns_flashes_into_a_soft_fade() -> void:
	assert_eq(CoherencePost.flash_amount(0, 0.0, false), 1.0, "a 2-frame white flash")
	SettingsManager.set_value(&"reduce_flashing", true)
	assert_true(CoherenceRenderer.reduce_flashing)
	var soft := CoherencePost.compute(1.0, 0.0, 0.0, {&"hit": 0.0}, {&"hit": 0}, 0.0, false, CoherenceRenderer.reduce_flashing)
	assert_eq(float(soft[&"invert"]), 0.0, "no inversion")
	assert_lt(float(soft[&"flash"]), 0.61, "at most 60% white")


func test_crosshair_and_hud_mode() -> void:
	var hud := _hud()
	SettingsManager.set_value(&"crosshair", &"dot")
	assert_eq(hud.crosshair.style, &"dot")
	SettingsManager.set_value(&"hud_mode", &"off")
	assert_false(hud.captions.visible)
	assert_false(hud.hints.visible)
	assert_true(hud.coherence.visible)
	hud.free()


func test_captions_option() -> void:
	var hud := _hud()
	SettingsManager.set_value(&"captions", false)
	EventBus.audio_cue.emit("[tear]", Vector3.ZERO)
	assert_false(hud.captions.is_shown())
	SettingsManager.set_value(&"captions", true)
	EventBus.audio_cue.emit("[tear]", Vector3.ZERO)
	assert_true(hud.captions.is_shown())
	hud.free()


func test_hints_option() -> void:
	var hud := _hud()
	SettingsManager.set_value(&"hints", false)
	EventBus.level_entered.emit(1, &"halls", &"start")
	assert_eq(hud.hints.current(), FirstRunHints.NONE)
	SettingsManager.set_value(&"hints", true)
	EventBus.level_entered.emit(1, &"halls", &"start")
	assert_eq(hud.hints.current(), FirstRunHints.MOVE)
	hud.free()


func test_hold_to_press_converts_holds_but_not_noclip() -> void:
	var i := Interactable.new()
	i.hold_time = Tuning.INTERACT_HOLD_TIME
	SettingsManager.set_value(&"hold_to_press", true)
	assert_eq(Interactor.effective_hold(i), 0.0, "breaker, leave hide spot: a press")
	assert_gt(NoclipQuery.charge_time(NoclipQuery.TARGET_WALL), 0.0, "noclip stays a hold")
	SettingsManager.set_value(&"hold_to_press", false)
	assert_eq(Interactor.effective_hold(i), Tuning.INTERACT_HOLD_TIME)
	i.free()


func test_ui_scale_multiplies_the_root_content_scale() -> void:
	var root := get_tree().root
	SettingsManager.set_value(&"ui_scale", 1.5)
	var h := float(root.size.y) if root.size.y > 0 else float(Tuning.SETTINGS_UI_REFERENCE_HEIGHT)
	assert_approx(root.content_scale_factor, SettingsApply.content_scale(h, 1.5), 0.0001)
	SettingsManager.set_value(&"ui_scale", 1.0)
	assert_approx(root.content_scale_factor, SettingsApply.content_scale(h, 1.0), 0.0001)


func test_head_bob_and_screen_shake_scale_the_camera() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world)
	var rig := p.rig
	rig.feed_motion(1.0, false, 1.0, 0.0)
	SettingsManager.set_value(&"head_bob", 1.0)
	var full := rig.bob_amount()
	SettingsManager.set_value(&"head_bob", 0.0)
	assert_eq(rig.bob_amount(), 0.0)
	assert_true(full >= 0.0)
	SettingsManager.set_value(&"screen_shake", 0.0)
	rig.trauma = 1.0
	rig._process(0.016)
	var motion := rig.get_node("%Motion") as Node3D
	assert_lt(motion.position.length(), 0.0001, "no shake at 0")
	SettingsManager.set_value(&"screen_shake", 1.0)
	rig.trauma = 1.0
	rig._process(0.1)
	assert_gt(motion.position.length() + motion.rotation.length(), 0.0, "shake at 1")
	world.free()
