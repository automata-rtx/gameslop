class_name Title
extends Control
## Minimal title screen (04 §7, M1.9): black, the NOCLIP wordmark (160 px Bold, 0.18 em),
## the version line in ui_dim, and the menu DESCEND, SETTINGS (placeholder until M2.11),
## QUIT. The live corridor background, boot line, Daily, Archive and the loadout column are
## the full title's (M2.11).

const RUN_SCENE := "res://scenes/run.tscn"
const VERSION := Version.VERSION   # 16 §1: single source
const ITEM_DESCEND := &"descend"
const ITEM_SETTINGS := &"settings"
const ITEM_QUIT := &"quit"

var menu: MenuList
var _leaving: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = UiTokens.UI_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	add_child(col)
	var mark := Label.new()
	mark.theme_type_variation = &"Wordmark"
	mark.text = Strings.TITLE_WORDMARK
	col.add_child(mark)
	var sub := Label.new()
	sub.theme_type_variation = &"TitleSubline"
	sub.text = version_line()
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiTokens.GRID * 6
	col.add_child(gap)
	menu = MenuList.new()
	menu.add_item(ITEM_DESCEND, Strings.MENU_DESCEND)
	menu.add_item(ITEM_SETTINGS, Strings.MENU_SETTINGS, false)
	menu.add_item(ITEM_QUIT, Strings.MENU_QUIT)
	menu.activated.connect(choose)
	col.add_child(menu)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	col.position.x = UiTokens.SAFE_MARGIN * 6


## `v1.0.0 · MADE BY AN AI · SEED OF THE DAY 20261008` (UTC date, 13 §4).
static func version_line() -> String:
	var d := Time.get_date_dict_from_system(true)
	var ymd := "%04d%02d%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
	return Strings.TITLE_VERSION_LINE.replace("{version}", VERSION).replace("{seed}", ymd)


func choose(id: StringName) -> void:
	if _leaving:
		return
	match id:
		ITEM_DESCEND:
			_leaving = true
			GameState.start_run(Tuning.MODE_DESCENT, &"faller", Run.new_seed())
			SceneRouter.change_to(RUN_SCENE)
		ITEM_QUIT:
			_leaving = true
			get_tree().quit(0)
