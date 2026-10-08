class_name PauseMenu
extends CanvasLayer
## The pause menu (04 §7): opens on the `pause` action during play, holds the tree pause
## through Clock.set_menu_pause (14 additions: nothing else writes get_tree().paused except
## the hitstop), overlays the frozen frame with 70% black after the glitch hold, and offers
## RESUME, SETTINGS, ABANDON DESCENT (confirmed: the run ends with cause `abandoned` and the
## summary follows) and QUIT TO TITLE (13 §1: quitting abandons the run; confirmed the same
## way). The run scene adds it (run.gd) and is read for its phase, player and mouse capture.

signal resumed

const LAYER := 40
const PAGE_PAUSE := &"pause"
const PAGE_ABANDON := &"abandon"
const PAGE_QUIT := &"quit"
const PAGE_SETTINGS := &"settings"
const PAGE_BINDINGS := &"bindings"
const ITEM_RESUME := &"resume"
const ITEM_SETTINGS := &"settings"
const ITEM_ABANDON := &"abandon"
const ITEM_QUIT := &"quit_title"
const ABANDON_CAUSE := &"abandoned"
const SUMMARY_SCENE := "res://scenes/summary.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
## Run phases in which the player may pause (not mid-transition, not dissolving).
const PAUSABLE_PHASES: Array[StringName] = [&"playing", &"landing"]

## The Run (duck-typed: `phase`, `player`, `capture_mouse`). Null in benches.
var run: Node = null
var shell: MenuShell
var page: PausePage
var _leaving: bool = false


static func create(r: Node) -> PauseMenu:
	var m := PauseMenu.new()
	m.name = "PauseMenu"
	m.run = r
	return m


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	shell = MenuShell.new()
	shell.overlay = true
	add_child(shell)
	page = PausePage.new()
	shell.register(PAGE_PAUSE, page)
	var abandon := ConfirmPage.new(Strings.PAUSE_ABANDON, Strings.PAUSE_ABANDON_CONFIRM, Strings.PAUSE_ABANDON_YES)
	abandon.confirmed.connect(abandon_run)
	shell.register(PAGE_ABANDON, abandon)
	var quit := ConfirmPage.new(Strings.PAUSE_QUIT_TITLE, Strings.PAUSE_QUIT_CONFIRM, Strings.PAUSE_QUIT_YES)
	quit.confirmed.connect(quit_to_title)
	shell.register(PAGE_QUIT, quit)
	shell.register(PAGE_SETTINGS, SettingsMenu.new())
	shell.register(PAGE_BINDINGS, BindingsMenu.new())
	page.chosen.connect(_on_chosen)
	shell.closed.connect(_on_shell_closed)


func is_open() -> bool:
	return shell.is_open()


func can_pause() -> bool:
	if _leaving or is_open() or SceneRouter.is_loading() or not GameState.is_run_active():
		return false
	if run != null and "phase" in run and not (StringName(run.get(&"phase")) in PAUSABLE_PHASES):
		return false
	return true


func open() -> void:
	if not can_pause():
		return
	Clock.set_menu_pause(true)
	_set_mouse(false)
	shell.open_root(PAGE_PAUSE)
	# 04 §7: the frozen frame takes the glitch hold, then the overlay and the menu.
	var t: Object = SceneRouter.transition
	if t != null and t.has_method(&"play"):
		await t.call(&"play", &"out")
		t.call(&"play", &"in")


func resume() -> void:
	if is_open():
		shell.close()


func _on_shell_closed() -> void:
	if _leaving:
		return
	SettingsManager.flush()
	Clock.set_menu_pause(false)
	_set_mouse(true)
	resumed.emit()


func _on_chosen(id: StringName) -> void:
	match id:
		ITEM_RESUME:
			resume()
		ITEM_SETTINGS:
			shell.open(PAGE_SETTINGS)
		ITEM_ABANDON:
			shell.open(PAGE_ABANDON)
		ITEM_QUIT:
			shell.open(PAGE_QUIT)


## ABANDON confirmed: the Descent ends with cause `abandoned`; the summary follows.
func abandon_run() -> void:
	_leave(SUMMARY_SCENE)


## QUIT TO TITLE confirmed: the run is abandoned (13 §1) and the title follows.
func quit_to_title() -> void:
	_leave(TITLE_SCENE)


func _leave(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	SettingsManager.flush()
	if GameState.is_run_active():
		var player: Variant = run.get(&"player") if run != null and "player" in run else null
		if player != null and is_instance_valid(player) and "coherence" in player:
			GameState.run.coherence = float(player.get(&"coherence"))
		GameState.end_run(ABANDON_CAUSE)
	# The world stays frozen through the cut; the pause lifts once the next scene is in.
	SceneRouter.scene_changed.connect(Clock.set_menu_pause.bind(false).unbind(1), CONNECT_ONE_SHOT)
	SceneRouter.scene_failed.connect(Clock.set_menu_pause.bind(false).unbind(1), CONNECT_ONE_SHOT)
	SceneRouter.change_to(path)


func _set_mouse(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if captured and (run == null or not ("capture_mouse" in run) or bool(run.get(&"capture_mouse"))):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if not is_open():
		if can_pause():
			get_viewport().set_input_as_handled()
			open()
	elif not event.is_action(&"ui_cancel") and shell.current_id() == PAGE_PAUSE:
		# A pause key that is not Esc closes the menu from its first page.
		get_viewport().set_input_as_handled()
		resume()


## The first page: RESUME, SETTINGS, ABANDON DESCENT, QUIT TO TITLE; the detail column
## reports where the Descent stands.
class PausePage extends MenuPage:
	signal chosen(id: StringName)

	func build() -> void:
		title = Strings.PAUSE_TITLE
		list.add_item(ITEM_RESUME, Strings.PAUSE_RESUME)
		list.add_item(ITEM_SETTINGS, Strings.PAUSE_SETTINGS)
		list.add_item(ITEM_ABANDON, Strings.PAUSE_ABANDON)
		list.add_item(ITEM_QUIT, Strings.PAUSE_QUIT_TITLE)
		list.activated.connect(func(id: StringName) -> void: chosen.emit(id))

	func on_open() -> void:
		list.active = true
		MenuPage.clear_children(detail)
		var r := GameState.run
		if r == null:
			return
		var stratum := GameState.stratum_for(r.depth)
		detail.add_child(MenuPage.leader_row(Strings.HUD_DEPTH_LINE.replace("{depth}", "%02d" % r.depth)
				.replace("{stratum}", String(Strings.STRATUM_NAMES.get(stratum, String(stratum).to_upper()))),
				String(Strings.MODE_NAMES.get(r.mode, String(r.mode).to_upper())), UiTokens.UI_DIM))
		detail.add_child(MenuPage.leader_row(Strings.SUMMARY_LINE_TIME.replace(" {value}", ""),
				RunSummary.format_time(Clock.run_seconds())))
		detail.add_child(MenuPage.leader_row(Strings.SUMMARY_LINE_NOTES_FOUND.replace(" {value}", ""), str(r.notes_found.size())))
