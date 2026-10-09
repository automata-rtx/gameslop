extends TestCase
## M3.6: the title's live corridor (04 §7) and the UI open items. The walk is checked on the
## real seed-0 Halls level; the corridor's clock is stepped by hand (its level is not built
## here: processing is off and the walk is set directly). Rendered by the menu gallery's
## title_corridor and title_flicker states (tools/ci/render.sh).

var _saved: Dictionary = {}


func before_each() -> void:
	for k: StringName in [&"fov", &"reduce_flashing", &"colorblind_accent"]:
		_saved[k] = SettingsManager.get_value(k)


func after_each() -> void:
	for k: StringName in _saved:
		SettingsManager.set_value(k, _saved[k])
	CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_target(CoherenceRenderer.NOCLIP_TARGET_ABSENT, Vector3.ZERO)


func _data() -> LevelData:
	return LevelGenerator.generate(&"halls", 1, Tuning.MENU_TITLE_SEED, false, 1)


## A corridor that never starts its level: processing off, the walk set by hand.
func _corridor(data: LevelData) -> TitleCorridor:
	var c := TitleCorridor.new()
	add_child(c)
	c.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.MENU_TITLE_SEED
	c.points = TitleCorridor.walk_points(data.grid, rng)
	c._length = (c.points.size() - 1) * Tuning.GRID_CELL_SIZE
	return c


func test_the_walk_follows_open_corridor_edges_and_never_doubles_back() -> void:
	var data := _data()
	var g := data.grid
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.MENU_TITLE_SEED
	var cells := TitleCorridor.walk_cells(g, rng)
	assert_gt(cells.size(), 20, "a walk long enough to stroll (%d cells)" % cells.size())
	assert_lt(cells.size(), Tuning.MENU_TITLE_PATH_CELLS + 1)
	var seen := {}
	for i in cells.size():
		var c := cells[i]
		assert_eq(g.kind(c), LevelGrid.FLOOR, "corridor cell %s" % c)
		assert_false(seen.has(c), "never the same cell twice")
		seen[c] = true
		if i > 0:
			var d := LevelGrid.DIRS.find(c - cells[i - 1])
			assert_ne(d, -1, "neighbours")
			assert_eq(g.wall(cells[i - 1], d), LevelGrid.NONE, "no door or wall crossed")
	rng.seed = Tuning.MENU_TITLE_SEED
	assert_eq(TitleCorridor.walk_cells(g, rng), cells, "seeded: the same walk every launch")


func test_flicker_gaps_and_length() -> void:
	var c := _corridor(_data())
	for i in 50:
		var gap := c.next_flicker_delay()
		assert_true(gap >= Tuning.MENU_TITLE_FLICKER_MIN and gap <= Tuning.MENU_TITLE_FLICKER_MAX, "25 to 40 s: %s" % gap)
	SettingsManager.set_value(&"reduce_flashing", false)
	c.flicker_in = 0.05
	c.walk(0.1)
	assert_true(c.is_flickering(), "the flicker starts")
	c.walk(0.05)
	assert_gt(CoherenceRenderer.noclip_charge, 0.0, "the ripple unrenders ahead")
	assert_lt(CoherenceRenderer.noclip_target.distance_to(c.camera.global_position), Tuning.MENU_TITLE_FLICKER_REACH + 4.0)
	c.walk(0.2)
	assert_false(c.is_flickering(), "200 ms and gone")
	assert_eq(CoherenceRenderer.noclip_charge, 0.0)
	assert_gt(c.flicker_in, Tuning.MENU_TITLE_FLICKER_MIN - 0.5, "the next one is 25 to 40 s away")
	c.free()


func test_reduce_flashing_disables_the_flicker() -> void:
	var c := _corridor(_data())
	SettingsManager.set_value(&"reduce_flashing", true)
	for i in 100 * 60:
		c.walk(1.0 / 60.0)   # 100 s: at least two flicker slots
		assert_eq(CoherenceRenderer.noclip_charge, 0.0)
	assert_eq(c.flickers, 0, "12 §6: no unrender flicker")
	SettingsManager.set_value(&"reduce_flashing", false)
	c.flicker_in = 0.01
	c.walk(0.05)
	assert_true(c.is_flickering())
	SettingsManager.set_value(&"reduce_flashing", true)
	assert_false(c.is_flickering(), "turning it on mid-flicker ends it")
	assert_eq(CoherenceRenderer.noclip_charge, 0.0)
	c.free()


func test_camera_strolls_and_follows_the_fov_setting() -> void:
	var c := _corridor(_data())
	SettingsManager.set_value(&"fov", 110)
	assert_approx(c.camera.fov, CameraRig.hfov_to_vfov(110.0), 0.001, "12 §2 FOV, live")
	SettingsManager.set_value(&"fov", 70)
	assert_approx(c.camera.fov, CameraRig.hfov_to_vfov(70.0), 0.001)
	assert_eq(c.camera.keep_aspect, Camera3D.KEEP_HEIGHT)
	c._place()
	var from := c.camera.global_position
	c.walk(10.0)
	assert_approx(c.s, 10.0 * Tuning.MENU_TITLE_CAMERA_SPEED, 0.001, "a slow stroll")
	assert_gt(c.camera.global_position.distance_to(from), 1.0)
	assert_approx(c.camera.global_position.y, c.sample(c.s).y, 0.05, "eye height over the floor")
	c.s = c._length
	c.walk(0.1)
	assert_lt(c.s, 1.0, "the walk loops back to its start")
	c.free()


func test_title_hosts_the_corridor_through_set_background() -> void:
	assert_false(Title.wants_corridor(), "headless: no live corridor by default")
	Title.booted = true
	var t := (load("res://scenes/title.tscn") as PackedScene).instantiate() as Title
	add_child(t)
	assert_null(t.corridor)
	var bg := t.shell.get_child(0) as ColorRect
	assert_eq(bg.color, UiTokens.UI_BG, "full black without a corridor")
	var stand_in := Node3D.new()
	t.set_background(stand_in)
	assert_eq(stand_in.get_parent(), t.background)
	assert_approx(bg.color.a, Tuning.MENU_TITLE_BACKDROP_ALPHA, 0.001, "the corridor shows through")
	t.set_background(null)
	assert_eq(bg.color, UiTokens.UI_BG)
	t.free()


# --- UI open items (M3.6) ----------------------------------------------------------------------

func test_exit_unlocked_prints_once_a_level_for_cycled_exits() -> void:
	UiMotion.manual_clock = true
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	var count := func() -> int:
		return Array(hud.notifications.lines()).count(Strings.MSG_EXIT_UNLOCKED)
	EventBus.level_entered.emit(4, &"halls", &"proper")
	for cycle in 3:
		hud.set_exit_status(&"sealed", 70.0)
		hud.set_exit_status(&"open", 20.0)
		UiMotion.step(hud, 0.5)
	assert_true(hud.exit_unlock_notified)
	assert_eq(count.call(), 1, "one EXIT UNLOCKED for three openings")
	EventBus.level_entered.emit(5, &"halls", &"proper")
	assert_false(hud.exit_unlock_notified, "a new level may print it again")
	hud.free()
	UiMotion.manual_clock = false


func test_colorblind_outline_keeps_small_accent_text_its_hue() -> void:
	UiMotion.manual_clock = true
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.set_depth(3, &"garage")
	SettingsManager.set_value(&"colorblind_accent", true)
	var num := hud.depth.find_children("*", "Label", true, false)[1] as Label
	assert_eq(num.get_theme_constant(&"outline_size"), UiTokens.LINE, "the 1 px outline (12 §6)")
	assert_eq(num.get_theme_color(&"font_outline_color"), UiTokens.UI_BG, "18 px: a dark outline")
	var list := MenuList.new()
	add_child(list)
	list.add_item(&"a", "A")
	list.active = true
	list.select(0)
	assert_eq(list._labels[0].get_theme_color(&"font_outline_color"), UiTokens.UI_FG, "22 px menu items keep ui_fg")
	SettingsManager.set_value(&"colorblind_accent", false)
	list.free()
	hud.free()
	UiMotion.manual_clock = false
