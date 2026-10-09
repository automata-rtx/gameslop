class_name MenuGallery
extends Control
## Bench for screenshot review of every menu (04 §11, M2.11): title (DESCEND with loadout
## cards, DAILY), each settings tab, the key bindings page and its rebinding prompt, the
## KEEP / REVERT countdown, the LICENSES item and page (engine, a components page), pause and
## its confirmation, the four Archive sections and the run summary. Uses a sample Archive in memory and never writes settings.cfg or meta.json.
## Flags after `--`:
##   --menu-state NAME   show one state
##   --menu-shots DIR    save every state as DIR/menu_<state>_<w>x<h>.png, then quit

const STATES: Array[StringName] = [
	&"title", &"title_daily", &"settings_display", &"settings_graphics", &"settings_audio",
	&"settings_controls", &"settings_accessibility", &"settings_gameplay", &"bindings",
	&"bindings_capture", &"settings_revert", &"settings_licenses", &"licenses_engine",
	&"licenses_components", &"pause", &"pause_abandon", &"archive_notes",
	&"archive_errors", &"archive_statistics", &"archive_unlocks", &"summary",
]
const NOTES_FOUND: Array[StringName] = [&"H1", &"H2", &"H3", &"H4", &"P1", &"P3", &"G2", &"O1", &"S4", &"U1"]

var _current: Node = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	SettingsManager.persist = false
	# The summary state ends a sample run; its meta.json goes to a scratch folder.
	SaveManager.directory = "user://menu_gallery"
	DirAccess.make_dir_recursive_absolute(SaveManager.directory)
	_sample_archive()
	var args := OS.get_cmdline_user_args()
	var shots := _arg(args, "--menu-shots")
	var one := _arg(args, "--menu-state")
	if not shots.is_empty():
		_shots.call_deferred(shots)
	else:
		show_state.call_deferred(StringName(one) if not one.is_empty() else &"title")


## A believable Archive: a dozen runs, one win, some notes and codex entries.
static func _sample_archive() -> void:
	var m := GameState.meta
	m.first_descent_done = true
	m.stats["runs"] = 12
	m.stats["wins"] = 1
	m.stats["best_depth"] = 6
	m.stats["best_score"] = 4880
	m.stats["distance_walked_m"] = 15320.5
	m.stats["walls_passed"] = 41
	m.stats["floors_dropped"] = 7
	m.stats["coherence_spent"] = 1180
	m.stats["deaths_by"] = {"still": 4, "echo": 2, "flicker": 1, "static": 1, "null": 3, "substrate": 0}
	m.notes_found = NOTES_FOUND.duplicate()
	m.codex = {"static": 5, "still": 3, "echo": 1, "flicker": 0, "null": 0}
	for id: StringName in [&"glowstick", &"radio", &"flare", &"cartographer", &"lightbearer", &"daily", &"codex_still"]:
		m.unlocks[String(id)] = true
	m.last_run = {"cause": "still", "depth": 3, "stratum": "garage", "score": 2310, "seed": 1}


func show_state(state: StringName) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
		await get_tree().process_frame
	GameState.meta.daily.erase(GameState.today_key())
	match state:
		&"title", &"title_daily":
			if state == &"title_daily":
				GameState.meta.daily[GameState.today_key()] = {"score": 2310, "depth": 3, "cause": "still"}
			Title.booted = true
			var t := (load("res://scenes/title.tscn") as PackedScene).instantiate() as Title
			_mount(t)
			if state == &"title_daily":
				t.page.on_open()
				t.menu.select_id(TitlePage.ITEM_DAILY)
		&"settings_display", &"settings_graphics", &"settings_audio", &"settings_controls", \
				&"settings_accessibility", &"settings_gameplay", &"settings_revert", &"settings_licenses":
			var shell := _shell_with(&"settings", _title_settings())
			var s := shell.current() as SettingsMenu
			var tab := StringName(String(state).trim_prefix("settings_"))
			if state == &"settings_revert":
				tab = SettingsSchema.TAB_DISPLAY
			s.list.select_id(tab)
			if state != &"settings_licenses":
				s.focus_rows()
			match state:
				&"settings_display":
					s.rows.select_id(&"brightness")
				&"settings_graphics":
					s.rows.select_id(&"shadow_quality")
				&"settings_controls":
					s.rows.select_id(&"mouse_sensitivity")
				&"settings_revert":
					s.rows.select_id(&"window_mode")
					s._on_value_chosen(&"window_mode", &"windowed")
		&"bindings", &"bindings_capture":
			var shell := _shell_with(&"bindings", BindingsMenu.new())
			var b := shell.current() as BindingsMenu
			b.rows.select_id(&"sprint")
			if state == &"bindings_capture":
				b.begin_capture(&"crouch", 0)
		&"licenses_engine", &"licenses_components":
			var shell := _shell_with(&"settings", _title_settings())
			shell.open(SettingsMenu.PAGE_LICENSES)
			var lm := shell.current() as LicensesMenu
			if state == &"licenses_components":
				lm.list.select_id(LicensesMenu.component_section(0))
		&"pause", &"pause_abandon":
			_pause_backdrop()
			var pm := PauseMenu.new()
			_mount_extra(pm)
			pm.shell.open_root(PauseMenu.PAGE_PAUSE)
			if state == &"pause_abandon":
				pm.shell.open(PauseMenu.PAGE_ABANDON)
		&"archive_notes", &"archive_errors", &"archive_statistics", &"archive_unlocks":
			var shell := _shell_with(&"archive", ArchiveMenu.new())
			var a := shell.current() as ArchiveMenu
			a.list.select_id(StringName(String(state).trim_prefix("archive_")))
			if state == &"archive_notes":
				a.focus_grid()
				a.move_cursor_to(Vector2i(0, 2))
		&"summary":
			GameState.start_run(Tuning.MODE_DESCENT, &"faller", 1)
			GameState.run.depth = 3
			GameState.run.notes_found = [&"G2", &"P3"]
			GameState.run.coherence_spent = 112
			GameState.run.walls_passed = 4
			GameState.run.drops_total = 1
			GameState.run.evasions = 5
			GameState.run.unlocks_earned = [&"radio"]
			GameState.end_run(&"still")
			_mount((load("res://scenes/summary.tscn") as PackedScene).instantiate())


func _shell_with(id: StringName, p: MenuPage) -> MenuShell:
	var shell := MenuShell.new()
	_mount(shell)
	shell.register(id, p)
	if id == &"settings":
		shell.register(&"bindings", BindingsMenu.new())
		shell.register(SettingsMenu.PAGE_LICENSES, LicensesMenu.new())
	shell.open_root(id)
	return shell


## The settings page as the title opens it (with LICENSES, 16 §6).
static func _title_settings() -> SettingsMenu:
	var s := SettingsMenu.new()
	s.show_licenses = true
	return s


## A stand-in for the frozen frame under the pause overlay: the HUD over a warm field.
func _pause_backdrop() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	var field := ColorRect.new()
	field.color = Color("#6b5a2e")
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(field)
	holder.add_child((load("res://scenes/ui/hud.tscn") as PackedScene).instantiate())
	_mount(holder)


func _mount(n: Node) -> void:
	_current = n
	add_child(n)


func _mount_extra(n: Node) -> void:
	_current.add_child(n)


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	UiMotion.manual_clock = true
	for state in STATES:
		await show_state(state)
		for i in 3:
			await get_tree().process_frame
		UiMotion.step(self, 5.0)
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var sz := get_viewport().get_visible_rect().size
		var path := dir.path_join("menu_%s_%dx%d.png" % [state, img.get_width(), img.get_height()])
		img.save_png(path)
		print("menu_gallery: %s (%dx%d logical)" % [path, sz.x, sz.y])
	get_tree().quit(0)


static func _arg(args: PackedStringArray, flag: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i != -1 and i + 1 < args.size() else ""
