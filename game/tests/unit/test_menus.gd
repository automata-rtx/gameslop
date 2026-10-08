extends TestCase
## M2.11 menus (04 §7): the shared MenuShell (pages, Esc back), the title (items by mode
## availability, reset notice once, Daily result, loadout cards only when unlocked), settings
## and key bindings driven by keyboard events, the pause menu through Clock.set_menu_pause,
## the Archive showing found notes only, and the summary's items. Headless; time by hand.

var _meta: MetaState
var _host: Node
var _prev_host: Node
var _prev_transition: Object


func before_all() -> void:
	_meta = GameState.meta


func after_all() -> void:
	GameState.meta = _meta


func before_each() -> void:
	GameState.meta = MetaState.new()
	UiMotion.manual_clock = true
	Title.booted = true
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "MenuTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	UiMotion.manual_clock = false
	if Clock.is_menu_paused():
		Clock.set_menu_pause(false)
	for c in _host.get_children():
		c.queue_free()
	await await_frames(2)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()
	for key: StringName in SettingsManager.DEFAULTS:
		SettingsManager.set_value(key, SettingsManager.DEFAULTS[key])
	SettingsManager.reset_bindings()


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_tree().root.push_input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	get_tree().root.push_input(up)


func _title() -> Title:
	var t := (load("res://scenes/title.tscn") as PackedScene).instantiate() as Title
	_host.add_child(t)
	return t


# --- MenuShell -----------------------------------------------------------------------------------

func test_shell_opens_pages_and_goes_back_with_esc() -> void:
	var shell := (load("res://scenes/ui/menu_shell.tscn") as PackedScene).instantiate() as MenuShell
	_host.add_child(shell)
	var a := MenuPage.new()
	a.title = "A"
	a.list.add_item(&"x", "X")
	var b := MenuPage.new()
	b.title = "B"
	shell.register(&"a", a)
	shell.register(&"b", b)
	var closed: Array = []
	shell.closed.connect(func() -> void: closed.append(true))
	shell.open_root(&"a")
	assert_eq(shell.current_id(), &"a")
	assert_true(shell.is_open())
	assert_eq(shell.process_mode, Node.PROCESS_MODE_ALWAYS, "menus run while paused")
	a.open_requested.emit(&"b")
	assert_eq(shell.current_id(), &"b")
	assert_eq(shell.stack, [&"a", &"b"] as Array[StringName])
	_press(&"ui_cancel")
	assert_eq(shell.current_id(), &"a", "Esc goes back one page")
	_press(&"ui_cancel")
	assert_false(shell.is_open())
	assert_eq(closed.size(), 1, "Esc on the first page closes")


func test_menu_list_keyboard_and_disabled_items() -> void:
	var l := MenuList.new()
	_host.add_child(l)
	l.add_item(&"a", "A")
	l.add_item(&"b", "B", false)
	l.add_item(&"c", "C")
	var got: Array = []
	l.activated.connect(func(id: StringName) -> void: got.append(id))
	_press(&"ui_down")
	assert_eq(l.selected_id(), &"b")
	_press(&"ui_accept")
	assert_eq(got, [], "a disabled item does not activate")
	_press(&"ui_down")
	_press(&"ui_accept")
	assert_eq(got, [&"c"])
	l.active = false
	_press(&"ui_up")
	assert_eq(l.selected_id(), &"c", "an inactive list ignores the keyboard")


# --- title ----------------------------------------------------------------------------------------

func test_title_items_follow_mode_availability() -> void:
	var t := _title()
	assert_false(t.is_booting())
	assert_eq(t.menu.ids, [&"descend", &"daily", &"archive", &"settings", &"quit"] as Array[StringName],
			"ENDLESS only after a win")
	assert_false(t.menu.is_item_enabled(&"daily"), "Daily locked until unlock #8")
	t.free()
	GameState.meta.unlocks["daily"] = true
	GameState.meta.unlocks["endless"] = true
	t = _title()
	assert_eq(t.menu.ids, [&"descend", &"daily", &"endless", &"archive", &"settings", &"quit"] as Array[StringName])
	assert_true(t.menu.is_item_enabled(&"daily"))
	t.free()
	GameState.meta.daily[GameState.today_key()] = {"score": 2310, "depth": 3, "cause": "still"}
	t = _title()
	assert_false(t.menu.is_item_enabled(&"daily"), "one attempt per day (13 §4)")
	assert_true(t.page.daily_line.visible)
	assert_eq(t.page.daily_line.text, "DAILY DESCENT · SCORE 2,310 · DEPTH 3")
	t.choose(TitlePage.ITEM_DAILY)
	assert_false(GameState.is_run_active(), "a spent Daily does not start")
	t.free()


func test_title_shows_the_reset_notice_once() -> void:
	SaveManager._reset_notice = true
	var t := _title()
	assert_true(t.page.notice.visible)
	assert_eq(t.page.notice.text, Strings.TITLE_ARCHIVE_RESET)
	t.free()
	t = _title()
	assert_false(t.page.notice.visible, "once")
	t.free()


func test_title_navigates_by_keyboard_into_settings_and_back() -> void:
	var t := _title()
	assert_eq(t.menu.selected_id(), &"descend")
	_press(&"ui_down")
	_press(&"ui_down")
	_press(&"ui_down")
	assert_eq(t.menu.selected_id(), &"settings")
	_press(&"ui_accept")
	assert_eq(t.shell.current_id(), &"settings")
	var s := t.shell.current() as SettingsMenu
	_press(&"ui_accept")
	assert_true(s.rows.active, "Enter on a tab moves into its options")
	assert_eq(s.rows.current().id, &"window_mode")
	_press(&"ui_down")
	_press(&"ui_down")
	assert_eq(s.rows.current().id, &"vsync")
	_press(&"ui_right")
	assert_eq(SettingsManager.get_value(&"vsync"), &"adaptive", "right steps the value")
	_press(&"ui_cancel")
	assert_false(s.rows.active, "Esc leaves the options for the tabs")
	assert_eq(t.shell.current_id(), &"settings")
	_press(&"ui_cancel")
	assert_eq(t.shell.current_id(), &"title")
	_press(&"ui_cancel")
	assert_eq(t.shell.current_id(), &"title", "the title page never closes")
	t.free()


func test_boot_line_then_title() -> void:
	Title.booted = false
	var t := _title()
	assert_true(t.is_booting())
	assert_false(t.shell.visible)
	t.advance(Tuning.MENU_BOOT_TIME + 0.01)
	assert_false(t.is_booting())
	assert_true(t.shell.visible)
	t.free()


func test_loadout_cards_only_when_unlocked() -> void:
	var t := _title()
	assert_null(t.page.cards, "only Faller: no selector (04 §7)")
	t.free()
	GameState.meta.unlocks["lightbearer"] = true
	t = _title()
	assert_not_null(t.page.cards)
	assert_eq(t.page.selected_loadout(), &"faller")
	_press(&"ui_right")
	assert_eq(t.page.selected_loadout(), &"lightbearer", "locked Cartographer is skipped")
	_press(&"ui_right")
	assert_eq(t.page.selected_loadout(), &"lightbearer", "Diver is locked")
	t.free()


func test_title_starts_a_descent_with_the_chosen_loadout() -> void:
	GameState.meta.unlocks["cartographer"] = true
	var t := _title()
	var got: Array = []
	t.page.start_requested.disconnect(t.start)   # no run scene here; the run flow sim covers it
	t.page.start_requested.connect(func(m: StringName, l: StringName) -> void: got.append([m, l]))
	_press(&"ui_right")
	_press(&"ui_accept")
	assert_eq(got, [[Tuning.MODE_DESCENT, &"cartographer"]], "Enter on DESCEND starts with the selected card")
	# Title.start asks GameState first: an unavailable mode starts nothing (the run scene is not
	# routed here; the run flow sim covers that).
	t.start(Tuning.MODE_ENDLESS, &"faller")
	assert_false(GameState.is_run_active(), "Endless before a win starts nothing")
	t.free()


# --- settings and bindings ------------------------------------------------------------------------

func test_settings_rows_cover_each_tab() -> void:
	var s := SettingsMenu.new()
	_host.add_child(s)
	for tab in SettingsSchema.TABS:
		s.show_tab(tab)
		var ids: Array[StringName] = []
		for r in s.rows.rows():
			ids.append(r.id)
		for key in SettingsSchema.keys_for(tab):
			if key == &"light_pool_size" or (key == &"debug_overlay" and not OS.is_debug_build()):
				continue
			assert_contains(ids, key)
		assert_eq(ids[-1], SettingsMenu.ROW_RESET, "RESET TAB TO DEFAULTS at the bottom")
	SettingsManager.set_value(&"preset", &"custom")
	s.show_tab(SettingsSchema.TAB_GRAPHICS)
	assert_not_null(s.rows.find_row(&"light_pool_size"), "light pool size under Custom only")


func test_settings_rows_grey_aa_under_fsr_and_type_numbers() -> void:
	var s := SettingsMenu.new()
	_host.add_child(s)
	SettingsManager.set_value(&"render_scale", 0.75)
	s.show_tab(SettingsSchema.TAB_GRAPHICS)
	var aa := s.rows.find_row(&"anti_aliasing") as SettingRow
	assert_false(aa.enabled)
	assert_eq(aa.value_label.text, "FSR 2")
	s.show_tab(SettingsSchema.TAB_CONTROLS)
	var sens := s.rows.find_row(&"mouse_sensitivity") as SettingRow
	assert_not_null(sens.slider, "a slider")
	assert_not_null(sens.field, "with a numeric field (00 §9)")
	sens.submit_text("2.5")
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 2.5)
	sens.submit_text("nonsense")
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 2.5)
	sens.adjust(1)
	assert_approx(float(SettingsManager.get_value(&"mouse_sensitivity")), 2.51)
	assert_eq(sens.field.text, "2.51")


func test_settings_window_change_asks_keep_or_revert() -> void:
	var s := SettingsMenu.new()
	_host.add_child(s)
	s.show_tab(SettingsSchema.TAB_DISPLAY)
	s.focus_rows()
	(s.rows.find_row(&"window_mode") as SettingRow).adjust(1)
	assert_true(SettingsManager.is_display_pending())
	assert_true(s.revert_box.visible)
	assert_true(s.revert_line.text.begins_with("REVERTING IN"))
	assert_true(s.handle_cancel(), "Esc reverts")
	assert_false(SettingsManager.is_display_pending())
	assert_false(s.revert_box.visible)
	assert_eq(SettingsManager.get_value(&"window_mode"), &"fullscreen")


func test_rebind_prompt_swaps_and_flashes() -> void:
	var b := BindingsMenu.new()
	_host.add_child(b)
	b.on_open()
	b.begin_capture(&"interact", 0)
	assert_true(b.is_capturing())
	var row := b.rows.find_row(&"interact") as BindingRow
	assert_eq(row.caps[0].text, Strings.CONTROLS_REBIND_PROMPT)
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	assert_true(b.capture(f))
	assert_false(b.is_capturing())
	assert_eq((SettingsManager.binding(&"interact", 0) as InputEventKey).physical_keycode, KEY_F)
	assert_eq((SettingsManager.binding(&"flashlight", 0) as InputEventKey).physical_keycode, KEY_E)
	assert_gt(row.flash, 0.0, "both rows flash ui_accent")
	assert_gt(b.rows.find_row(&"flashlight").flash, 0.0)
	assert_eq(row.label_color(), UiTokens.UI_ACCENT)
	assert_eq(row.caps[0].text, "F")


func test_rebind_prompt_esc_cancels_and_backspace_clears() -> void:
	var b := BindingsMenu.new()
	_host.add_child(b)
	b.on_open()
	b.begin_capture(&"crank", 0)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	b.capture(esc)
	assert_false(b.is_capturing())
	assert_eq((SettingsManager.binding(&"crank", 0) as InputEventKey).physical_keycode, KEY_R, "unchanged")
	b.begin_capture(&"crank", 0)
	var bs := InputEventKey.new()
	bs.physical_keycode = KEY_BACKSPACE
	bs.pressed = true
	b.capture(bs)
	assert_null(SettingsManager.binding(&"crank", 0), "Backspace clears")
	assert_true(b.handle_cancel() == false, "Esc outside a capture goes back")


# --- pause ----------------------------------------------------------------------------------------

class FakeRun extends Node:
	var phase: StringName = &"playing"
	var capture_mouse: bool = false
	var player: Node = null


func test_pause_menu_uses_clock_menu_pause() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 7)
	var run := FakeRun.new()
	_host.add_child(run)
	var pm := PauseMenu.create(run)
	run.add_child(pm)
	assert_eq(pm.process_mode, Node.PROCESS_MODE_ALWAYS)
	_press(&"pause")
	assert_true(pm.is_open())
	assert_true(Clock.is_menu_paused(), "the pause menu holds Clock's menu pause")
	assert_true(get_tree().paused)
	assert_eq(pm.shell.page(PauseMenu.PAGE_PAUSE).list.ids,
			[&"resume", &"settings", &"abandon", &"quit_title"] as Array[StringName])
	_press(&"ui_cancel")
	assert_false(pm.is_open())
	assert_false(Clock.is_menu_paused())
	assert_false(get_tree().paused)
	run.phase = &"dissolving"
	_press(&"pause")
	assert_false(pm.is_open(), "no pause while dissolving")
	GameState.end_run(&"abandoned")


func test_pause_abandon_ends_the_run_and_shows_the_summary() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 8)
	var run := FakeRun.new()
	_host.add_child(run)
	var pm := PauseMenu.create(run)
	run.add_child(pm)
	pm.open()
	pm.shell.page(PauseMenu.PAGE_PAUSE).list.activate(2)
	assert_eq(pm.shell.current_id(), PauseMenu.PAGE_ABANDON, "ABANDON DESCENT asks first")
	var confirm := pm.shell.current() as ConfirmPage
	assert_eq(confirm.list.selected_id(), ConfirmPage.ITEM_NO, "BACK is selected first")
	assert_eq(confirm.message, Strings.PAUSE_ABANDON_CONFIRM)
	confirm.list.activate(0)
	assert_false(GameState.is_run_active())
	assert_eq(GameState.last_cause(), &"abandoned")
	assert_true(Clock.is_menu_paused(), "the world stays frozen through the cut")
	var end := Time.get_ticks_msec() + 5000
	while not (SceneRouter.current_scene() is RunSummary) and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	assert_true(SceneRouter.current_scene() is RunSummary)
	assert_false(Clock.is_menu_paused(), "the pause lifts once the summary is in")
	assert_eq(RunSummary.top_line().split(" · ")[0], "DESCENT ABANDONED")


# --- archive and summary -------------------------------------------------------------------------

func test_archive_shows_found_notes_only() -> void:
	GameState.meta.notes_found = [&"H1", &"P3"] as Array[StringName]
	var a := ArchiveMenu.new()
	_host.add_child(a)
	a.on_open()
	assert_eq(ArchiveMenu.cell_text(&"H1"), "H1")
	assert_eq(ArchiveMenu.cell_text(&"H2"), Strings.ARCHIVE_LOCKED_CELL)
	var texts: Array[String] = []
	for c in a.cells:
		texts.append(c.text.strip_edges())
	assert_eq(texts.size(), 36, "6 x 6")
	assert_eq(texts.count("H1"), 1)
	assert_eq(texts.count("P3"), 1)
	assert_eq(texts.count(Strings.ARCHIVE_LOCKED_CELL), 34)
	a.focus_grid()
	a.move_cursor_to(Vector2i(0, 1))
	assert_eq(a.cursor_note(), &"H2")
	assert_false(a.sheet_visible(), "an unfound note shows nothing")
	a.move_cursor_to(Vector2i(0, 0))
	assert_true(a.sheet_visible())
	assert_eq(a.sheet_header.text, "NOTE H1 · HANDWRITTEN")
	a.move_cursor_to(Vector2i(1, 2))
	assert_eq(a.cursor_note(), &"P3")
	assert_true(a.sheet_visible())
	assert_true(a.handle_cancel(), "Esc leaves the grid first")
	assert_false(a.grid_focus)


func test_archive_codex_follows_encounters() -> void:
	GameState.meta.codex = {"still": 3, "echo": 1}
	var a := ArchiveMenu.new()
	_host.add_child(a)
	a.show_section(ArchiveMenu.SECTION_ERRORS)
	var text := ""
	for n in a.body.find_children("*", "Label", true, false):
		text += (n as Label).text + "\n"
	assert_true(text.contains("STILL"))
	assert_true(text.contains(String(Strings.ERROR_CODEX[&"still"])), "3 encounters: the counter line")
	assert_true(text.contains("ECHO"))
	assert_false(text.contains(String(Strings.ERROR_CODEX[&"echo"])), "1 encounter: name only")
	assert_false(text.contains("FLICKER"), "never met: locked")
	a.show_section(ArchiveMenu.SECTION_UNLOCKS)
	a.show_section(ArchiveMenu.SECTION_STATISTICS)
	assert_gt(a.body.get_child_count(), 10)


func test_summary_items_and_spent_daily() -> void:
	GameState.meta.unlocks["daily"] = true
	GameState.start_run(Tuning.MODE_DAILY, &"faller", GameState.daily_seed())
	GameState.end_run(&"still")
	var s := (load("res://scenes/summary.tscn") as PackedScene).instantiate() as RunSummary
	_host.add_child(s)
	assert_eq(s.menu.ids, [&"descend_again", &"archive", &"title"] as Array[StringName])
	assert_eq(RunSummary.again_mode(), Tuning.MODE_DESCENT, "a spent Daily restarts as a Descent")
	s.free()
