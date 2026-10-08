class_name Title
extends Control
## The title screen (04 §7). A background hook (%Background: the live Halls corridor of 04 §7
## arrives in M3 through set_background), the MenuShell with the title page, SETTINGS (and
## its key bindings page) and the ARCHIVE. Boot: on the first title of a session, 1.2 s of
## black with the typed line `rendering`, then the shutter reveals the title; skippable once
## the player has a Descent behind them. The title asks GameState whether a mode or loadout is
## available before it starts a run (05 §8), and shows SaveManager's reset notice once.

const RUN_SCENE := "res://scenes/run.tscn"
const VERSION := Version.VERSION   # 16 §1: single source
const PAGE_TITLE := &"title"
const PAGE_SETTINGS := &"settings"
const PAGE_BINDINGS := &"bindings"
const PAGE_ARCHIVE := &"archive"
## Kept for callers of the M1.9 title.
const ITEM_DESCEND := TitlePage.ITEM_DESCEND
const ITEM_SETTINGS := TitlePage.ITEM_SETTINGS
const ITEM_QUIT := TitlePage.ITEM_QUIT

## The page the next title opens on (the summary's ARCHIVE item sets it).
static var open_on_enter: StringName = &""
## The boot line plays once per session.
static var booted: bool = false

var shell: MenuShell
var page: TitlePage
var menu: MenuList
var background: Control
var boot_line: UiTypedLabel = null
var _boot_left: float = 0.0
var _leaving: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	background = get_node_or_null(^"%Background") as Control
	if background == null:
		background = Control.new()
		background.name = "Background"
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	shell = MenuShell.new()
	add_child(shell)
	page = TitlePage.new()
	page.reset_notice = SaveManager.consume_reset_notice()
	shell.register(PAGE_TITLE, page)
	shell.register(PAGE_SETTINGS, SettingsMenu.new())
	shell.register(PAGE_BINDINGS, BindingsMenu.new())
	shell.register(PAGE_ARCHIVE, ArchiveMenu.new())
	page.ensure_built()
	menu = page.list
	page.start_requested.connect(start)
	page.quit_requested.connect(quit)
	# Esc on the title page itself does nothing; the shell never closes here.
	shell.closed.connect(func() -> void: shell.open_root(PAGE_TITLE))
	shell.open_root(PAGE_TITLE)
	if open_on_enter != &"":
		shell.open(open_on_enter)
		open_on_enter = &""
	if not booted:
		booted = true
		_begin_boot()


## M3 hook (04 §7): the live corridor goes behind the menu; the shell's background turns to
## the pause-style overlay so the corridor shows through.
func set_background(node: Node) -> void:
	for c in background.get_children():
		c.queue_free()
	background.add_child(node)
	shell.overlay = node != null


## `v1.0.0 · MADE BY AN AI · SEED OF THE DAY 20261008` (UTC date, 13 §4).
static func version_line() -> String:
	return Strings.TITLE_VERSION_LINE.replace("{version}", VERSION).replace("{seed}", GameState.today_key())


## Starts a Descent if GameState allows the mode and loadout (debug launches skip this).
func start(mode: StringName, loadout: StringName) -> void:
	if _leaving or not GameState.is_mode_available(mode):
		return
	if not GameState.is_loadout_available(loadout):
		loadout = &"faller"
	_leaving = true
	var run_seed := GameState.daily_seed() if mode == Tuning.MODE_DAILY else Run.new_seed()
	GameState.start_run(mode, loadout, run_seed)
	SceneRouter.change_to(RUN_SCENE)


func quit() -> void:
	if _leaving:
		return
	_leaving = true
	SettingsManager.flush()
	get_tree().quit(0)


## Kept for callers of the M1.9 title (tests drive the menu through it).
func choose(id: StringName) -> void:
	page.choose(id)


# --- boot (04 §7) --------------------------------------------------------------------------------

func _begin_boot() -> void:
	shell.visible = false
	var black := ColorRect.new()
	black.name = "Boot"
	black.color = UiTokens.UI_BG
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	boot_line = UiTypedLabel.new()
	boot_line.theme_type_variation = &"TitleSubline"
	boot_line.position = Vector2(MenuShell.MARGIN, MenuShell.MARGIN)
	black.add_child(boot_line)
	boot_line.type_text(Strings.TITLE_BOOT_LINE)
	AudioManager.play_2d(&"ui_title_boot")
	_boot_left = Tuning.MENU_BOOT_TIME


func is_booting() -> bool:
	return boot_line != null


func finish_boot() -> void:
	if boot_line == null:
		return
	boot_line.get_parent().queue_free()
	boot_line = null
	shell.reveal()


func advance(dt: float) -> void:
	if boot_line == null:
		return
	_boot_left -= dt
	if _boot_left <= 0.0:
		finish_boot()


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if boot_line == null:
		return
	get_viewport().set_input_as_handled()
	var skippable := GameState.meta.first_descent_done or int(GameState.meta.stats.get("runs", 0)) > 0
	if skippable and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		finish_boot()
