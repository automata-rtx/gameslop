extends TestCase
## R17 (review M2.17 S5, 16 §6): the ending's roll prints 16 §6's lines only, with no backing;
## the engine's MIT notice in full and its components live on the LICENSES page reachable
## from the title's settings (not from pause), a page at a time so nothing scrolls (04 §7).
## Also the ending bench's absolute `--shots` path (review N9). Headless.

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
	_host.name = "LicensesTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	UiMotion.manual_clock = false
	for c in _host.get_children():
		c.queue_free()
	await await_frames(2)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_tree().root.push_input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	get_tree().root.push_input(up)


# --- the roll -----------------------------------------------------------------------------------

func test_roll_prints_16_6_lines_only() -> void:
	var lines := Credits.roll_text().split("\n")
	assert_eq(Array(lines), [Strings.CREDITS_AI, Strings.CREDITS_GODOT, Strings.CREDITS_FONT,
			Strings.CREDITS_FONT_COPYRIGHT, Strings.CREDITS_SOUND, Strings.CREDITS_LICENSES_NOTE,
			Strings.CREDITS_THANKS], "16 §6, in order")
	var roll := CreditsRoll.new()
	roll.size = CreditsRoll.REFERENCE_SIZE
	add_child(roll)
	await await_frames(2)
	var printed := roll.printed_text()
	for l in Credits.godot_license_lines():
		if l != Strings.CREDITS_GODOT:
			assert_false(printed.contains(l), "the MIT notice is not rolled: %s" % l)
	for c in Credits.components():
		assert_false(printed.contains(String(c["name"]) + " · "), "no component line in the roll")
	assert_eq(roll.find_children("*", "ColorRect", true, false).size(), 0, "no panel behind the roll")
	assert_eq(roll.find_children("*", "Panel", true, false).size(), 0)
	# 04 §2: each line on its own caption backing, tight to the text, so the corridor shows.
	roll.start()
	roll.advance(0.0)
	await await_frames(2)
	var boxes := roll.find_children("*", "PanelContainer", true, false)
	assert_eq(boxes.size(), lines.size(), "one backing per line")
	for b: Node in boxes:
		var box := b as PanelContainer
		assert_eq(box.theme_type_variation, &"Backing")
		assert_eq(box.get_child_count(), 1)
		var label := box.get_child(0) as Label
		assert_lt(box.size.x, label.get_minimum_size().x + UiTokens.GRID * 3, "tight to %s" % label.text)
		assert_lt(box.size.x, roll.size.x * 0.75)
	roll.free()


func test_full_entries_keep_the_notice_and_every_component() -> void:
	var t := Credits.text()
	for l in Credits.roll_text().split("\n"):
		assert_contains(t, l)
	for l in Credits.godot_license_lines():
		assert_contains(t, l)
	assert_eq(Credits.component_lines().size(), Credits.components().size())
	assert_gt(Credits.components().size(), 10)


# --- the LICENSES page --------------------------------------------------------------------------

func test_title_settings_list_licenses_and_open_the_page() -> void:
	var t := (load("res://scenes/title.tscn") as PackedScene).instantiate() as Title
	_host.add_child(t)
	t.shell.open(Title.PAGE_SETTINGS)
	var s := t.shell.current() as SettingsMenu
	assert_eq(s.list.ids[-1], SettingsMenu.ITEM_LICENSES, "LICENSES ends the left column")
	s.list.select_id(SettingsMenu.ITEM_LICENSES)
	assert_eq(s.rows.rows().size(), 0, "LICENSES is not a tab: no option rows")
	assert_eq(s.description.text, Strings.LICENSES_DESCRIPTION)
	_press(&"ui_accept")
	assert_eq(t.shell.current_id(), Title.PAGE_LICENSES)
	assert_eq(t.shell.current().title, Strings.MENU_LICENSES)
	_press(&"ui_cancel")
	assert_eq(t.shell.current_id(), Title.PAGE_SETTINGS, "Esc goes back to settings")
	s.list.select_id(SettingsSchema.TAB_AUDIO)
	assert_gt(s.rows.rows().size(), 1, "a tab after LICENSES still lists its options")
	t.free()


func test_pause_settings_have_no_licenses_item() -> void:
	var s := SettingsMenu.new()
	add_child(s)
	assert_false(s.list.ids.has(SettingsMenu.ITEM_LICENSES), "16 §6: from the title's settings")
	assert_eq(s.list.ids.size(), SettingsSchema.TABS.size())
	s.free()


func test_licenses_page_shows_the_notice_and_every_component_a_page_at_a_time() -> void:
	var page := LicensesMenu.new()
	add_child(page)
	page.on_open()
	var pages := LicensesMenu.component_pages()
	var n := Credits.components().size()
	assert_eq(pages, ceili(float(n) / LicensesMenu.COMPONENTS_PER_PAGE))
	assert_eq(page.list.ids.size(), pages + 3, "ENGINE, the component pages, TYPEFACE, SOUND")
	assert_lt(page.list.ids.size() * UiTokens.MENU_ROW_HEIGHT, 1080 - 2 * MenuShell.MARGIN,
			"04 §7: the list fits one screen")
	var engine := page.section_text(LicensesMenu.SECTION_ENGINE)
	assert_contains(engine, Strings.CREDITS_GODOT)
	assert_contains(engine, Engine.get_license_text().strip_edges(), "the MIT notice in full")
	var seen := 0
	for i in pages:
		var text := page.section_text(LicensesMenu.component_section(i))
		var rows := page.body.find_children("*", "HBoxContainer", true, false).size()
		assert_lt(rows, LicensesMenu.COMPONENTS_PER_PAGE + 1)
		seen += rows
		for j in range(i * LicensesMenu.COMPONENTS_PER_PAGE, mini((i + 1) * LicensesMenu.COMPONENTS_PER_PAGE, n)):
			assert_contains(text, String(Credits.components()[j]["name"]))
			assert_contains(text, String(Credits.components()[j]["license"]))
	assert_eq(seen, n, "every component once")
	var typeface := page.section_text(LicensesMenu.SECTION_TYPEFACE)
	assert_contains(typeface, Strings.CREDITS_FONT)
	assert_contains(typeface, Strings.CREDITS_FONT_COPYRIGHT)
	assert_contains(page.section_text(LicensesMenu.SECTION_AUDIO_CREDITS), Strings.CREDITS_SOUND)
	assert_eq(page.footer.text, Strings.CREDITS_LICENSES_NOTE)
	page.free()


func test_licenses_strings_follow_the_writing_rules() -> void:
	for s in [Strings.MENU_LICENSES, Strings.LICENSES_COMPONENTS_PAGE.replace("{page}", "1").replace("{pages}", "4")]:
		assert_eq(s, s.to_upper(), "04 §2: headings in uppercase")
	assert_false(Strings.LICENSES_DESCRIPTION.contains("!"))


# --- the ending bench ---------------------------------------------------------------------------

func test_ending_bench_honours_absolute_shot_paths() -> void:
	assert_eq(EndingBench.abs_dir("/tmp/noclip_ending"), "/tmp/noclip_ending")
	var rel := EndingBench.abs_dir("build/ending")
	assert_true(rel.is_absolute_path())
	assert_true(rel.ends_with("build/ending"))
	assert_false(rel.contains("//tmp"))
