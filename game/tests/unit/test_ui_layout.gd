extends TestCase
## M3.6 polish pass (04, 12 §2 UI scale 0.75 to 1.5, 12 §9): every menu screen of the menu
## gallery and every HUD state of the UI gallery is laid out at the extreme UI scale and
## resolution combinations, and no visible Control may leave the viewport or the Container
## that laid it out (UiLayoutCheck). The UI scale is the root window's content scale, so a
## (resolution, UI scale) pair is one logical viewport; the pairs are mapped and deduplicated,
## then each screen is laid out in a SubViewport of that size. Text size 1.4 (12 §9) runs on
## the smallest viewport for the screens it changes (notes, captions).

## 12 §2: the resolution floor and the 1440p ceiling, at the UI scale extremes; plus the two
## other aspect ratios a 1.5 scale meets at their narrowest (21:9 and 5:4).
const COMBOS: Array = [
	[Vector2i(1280, 720), 0.75], [Vector2i(1280, 720), 1.5],
	[Vector2i(2560, 1440), 0.75], [Vector2i(2560, 1440), 1.5],
	[Vector2i(2560, 1080), 1.5], [Vector2i(1280, 1024), 1.5],
	[Vector2i(1920, 1080), 1.0],
]
const TEXT_SIZE_STATES: Array[StringName] = [&"note_faller", &"note_builder", &"note_stray", &"captions_stack"]
const TEXT_SIZE_MENU_STATES: Array[StringName] = [&"archive_notes", &"archive_errors"]

var _meta: MetaState
var _saved: Dictionary = {}
var _root_scale: float = 1.0


func before_all() -> void:
	_meta = GameState.meta
	# The headless root window is tiny, so its content scale (and UiTokens.hairline()) is
	# not what a real window gets; the screens here are laid out at the scale they are seen at.
	_root_scale = get_tree().root.content_scale_factor
	get_tree().root.content_scale_factor = 1.0
	for k: StringName in [&"ui_scale", &"text_size", &"colorblind_accent", &"captions", &"hints"]:
		_saved[k] = SettingsManager.get_value(k)


func after_all() -> void:
	GameState.meta = _meta
	get_tree().root.content_scale_factor = _root_scale
	for k: StringName in _saved:
		SettingsManager.set_value(k, _saved[k])
	UiAccessibility.apply_colorblind(bool(_saved[&"colorblind_accent"]))
	UiMotion.manual_clock = false
	UiTokens.compact = false


func before_each() -> void:
	GameState.meta = MetaState.new()
	MenuGallery.sample_archive()
	Title.booted = true


func after_each() -> void:
	UiMotion.manual_clock = false
	if Clock.is_menu_paused():
		Clock.set_menu_pause(false)


static func logical_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Array in COMBOS:
		var s := UiLayoutCheck.logical_size(c[0], c[1])
		if not out.has(s):
			out.append(s)
	return out


func test_logical_sizes_cover_the_extremes() -> void:
	var sizes := logical_sizes()
	assert_true(sizes.has(Vector2i(1280, 720)), "UI 1.5 at 720p (and at 1440p) lays out in 1280 x 720")
	assert_true(sizes.has(Vector2i(2560, 1440)), "UI 0.75 at 1440p (and at 720p) lays out in 2560 x 1440")
	assert_true(sizes.has(Vector2i(900, 720)), "5:4 at UI 1.5 is the narrowest")


func test_the_check_finds_overflow_and_respects_fit_scale() -> void:
	var vp := _viewport(Vector2i(640, 360))
	var root := Control.new()
	vp.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.size = Vector2(100, 100)
	root.add_child(box)
	var wide := Control.new()
	wide.custom_minimum_size = Vector2(800, 50)
	box.add_child(wide)
	await await_frames(2)
	var v := UiLayoutCheck.violations(root, Rect2(Vector2.ZERO, Vector2(640, 360)))
	assert_gt(v.size(), 0, "an 800 px child in a 640 px viewport is reported")
	box.free()
	var fit := UiFitBox.new()
	fit.position = Vector2(20, 20)
	fit.size = Vector2(400, 200)
	root.add_child(fit)
	var big := Control.new()
	big.custom_minimum_size = Vector2(800, 100)
	fit.add_child(big)
	await await_frames(2)
	assert_approx(fit.fit_scale, 0.5, 0.001, "400 / 800")
	assert_eq(UiLayoutCheck.violations(root, Rect2(Vector2.ZERO, Vector2(640, 360))).size(), 0, "scaled to fit")
	vp.free()


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	add_child(vp)
	return vp


func _check(root: Control, size: Vector2i, what: String) -> void:
	for v in UiLayoutCheck.violations(root, Rect2(Vector2.ZERO, Vector2(size))):
		fail("%s at %dx%d: %s" % [what, size.x, size.y, v])
	for f in root.find_children("*", "UiFitBox", true, false):
		var fb := f as UiFitBox
		if fb.is_visible_in_tree() and fb.fit_scale < 0.999:
			print("  # fit %s at %dx%d: %s %.3f" % [what, size.x, size.y, root.get_path_to(fb), fb.fit_scale])


func _menu(vp: SubViewport, state: StringName) -> MenuGallery:
	var g := MenuGallery.new()
	g.auto_run = false
	vp.add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.size = Vector2(vp.size)
	await g.show_state(state)
	await await_frames(2)
	UiMotion.manual_clock = true
	UiMotion.step(g, 5.0)
	await await_frames(2)
	return g


func test_every_menu_fits_every_extreme() -> void:
	for size in logical_sizes():
		var vp := _viewport(size)
		for state in MenuGallery.STATES:
			GameState.meta = MetaState.new()
			MenuGallery.sample_archive()
			var g := await _menu(vp, state)
			_check(g, size, "menu %s" % state)
			g.free()
			await await_frames(1)
		vp.free()


func test_every_hud_state_fits_every_extreme() -> void:
	for size in logical_sizes():
		var vp := _viewport(size)
		for state in HudGalleryStates.STATES:
			await _hud_state(vp, state, size)
		vp.free()
	UiAccessibility.apply_colorblind(false)


## M3.6 ruling (04 §8 is silent): a note sheet never covers the caption stack.
func test_note_sheet_never_covers_the_captions() -> void:
	for ts: float in [1.0, Tuning.SETTINGS_TEXT_SIZE_MAX]:
		SettingsManager.set_value(&"text_size", ts)
		for size in logical_sizes():
			var vp := _viewport(size)
			var root := Control.new()
			vp.add_child(root)
			root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.size = Vector2(size)
			var hud := HudGalleryStates.build(root, &"note_captions")
			await await_frames(2)
			HudGalleryStates._step(hud, 0.1)
			assert_eq(hud.captions.lines().size(), 3, "three captions")
			assert_true(hud.note_sheet.is_shown(), "the sheet")
			var sheet := UiLayoutCheck._rect(hud.note_sheet)
			for l in hud.captions.labels():
				var r := UiLayoutCheck._rect(l)
				assert_lt(r.end.y, sheet.position.y + 0.5, "caption %s ends above the sheet at %s, text %s" % [l.text, size, ts])
			hud.note_sheet.show_now(false)
			HudGalleryStates._step(hud, 0.1)
			var free := hud.captions.stack_rect()
			assert_approx(free.end.y, 0.0, 1.0, "back to its own place once the sheet is gone")
			vp.free()
	SettingsManager.set_value(&"text_size", 1.0)


## M3.1 ruling (04 §6, §8): at UI scale 1.5 the tallest note sheet reaches the prompt line.
## The line then rises to a grid unit above the sheet (never onto the crosshair), the
## captions end above the line, and where nothing overlaps the line keeps its 04 §6 place.
func test_prompt_line_clears_the_note_sheet() -> void:
	var lifted_somewhere := false
	for ts: float in [1.0, Tuning.SETTINGS_TEXT_SIZE_MAX]:
		SettingsManager.set_value(&"text_size", ts)
		for size in logical_sizes():
			var vp := _viewport(size)
			var root := Control.new()
			vp.add_child(root)
			root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.size = Vector2(size)
			var hud := HudGalleryStates.build(root, &"note_prompt")
			await await_frames(2)
			HudGalleryStates._step(hud, 0.3)
			var tag := "at %s text %s" % [size, ts]
			assert_true(hud.note_sheet.is_shown(), "the sheet " + tag)
			assert_true(hud.prompt.is_shown(), "the prompt " + tag)
			var sheet := UiLayoutCheck._rect(hud.note_sheet)
			var line := UiLayoutCheck._rect(hud.prompt.shutter)
			var cross_y := hud.prompt.global_position.y - float(Tuning.HUD_PROMPT_OFFSET_Y)
			assert_true(line.end.y <= sheet.position.y + 0.5, "the prompt line is not under the sheet " + tag)
			for l in hud.captions.labels():
				var r := UiLayoutCheck._rect(l)
				assert_true(r.end.y <= line.position.y + 0.5, "caption %s above the prompt line %s" % [l.text, tag])
			if hud.prompt.lift() > 0.0:
				lifted_somewhere = true
				assert_true(line.end.y <= cross_y - float(Tuning.HUD_PROMPT_CROSSHAIR_CLEAR) + 1.0, "off the crosshair " + tag)
				assert_true(hud.prompt.lift() <= 1080.0, "a sane lift")
				assert_approx(hud.hints.line.lift(), hud.prompt.lift(), 0.01, "the hint line rises with it " + tag)
			else:
				assert_approx(line.get_center().y, cross_y + float(Tuning.HUD_PROMPT_OFFSET_Y), 1.5, "04 §6 place kept " + tag)
			hud.note_sheet.show_now(false)
			HudGalleryStates._step(hud, 0.3)
			assert_approx(hud.prompt.lift(), 0.0, 0.01, "back to the 04 §6 place when the sheet is gone " + tag)
			vp.free()
	assert_true(lifted_somewhere, "the extremes include a combination where the sheet reaches the line")
	SettingsManager.set_value(&"text_size", 1.0)


func test_text_size_14_fits_the_smallest_viewport() -> void:
	SettingsManager.set_value(&"text_size", Tuning.SETTINGS_TEXT_SIZE_MAX)
	var size := Vector2i(1280, 720)
	var vp := _viewport(size)
	for state in TEXT_SIZE_STATES:
		await _hud_state(vp, state, size, " text 1.4")
	for state in TEXT_SIZE_MENU_STATES:
		var g := await _menu(vp, state)
		_check(g, size, "menu %s text 1.4" % state)
		g.free()
	vp.free()
	SettingsManager.set_value(&"text_size", 1.0)


func _hud_state(vp: SubViewport, state: StringName, size: Vector2i, tag: String = "") -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(size)
	HudGalleryStates.build(root, state)
	await await_frames(2)
	_check(root, size, "HUD %s%s" % [state, tag])
	root.free()
	UiAccessibility.apply_colorblind(false)
	await await_frames(1)
