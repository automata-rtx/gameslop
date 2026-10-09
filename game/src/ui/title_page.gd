class_name TitlePage
extends MenuPage
## The title screen's first page (04 §7): the NOCLIP wordmark centred-left at 160 px over a
## 1 px grid of 8 px cells that shows only where the letters are not, the version line in
## ui_dim, the reset notice (13 §2, once) and today's Daily result, then the menu DESCEND,
## DAILY DESCENT, ENDLESS (after a win), ARCHIVE, SETTINGS, QUIT. The detail column follows
## the selection: DESCEND shows best depth, runs, wins, last cause of death and the loadout
## cards (when more than Faller is unlocked); DAILY DESCENT its seed and rules or result.
## Modes and loadouts are asked of GameState before a start (05 §8).

signal start_requested(mode: StringName, loadout: StringName)
signal quit_requested

const ITEM_DESCEND := &"descend"
const ITEM_DAILY := &"daily"
const ITEM_ENDLESS := &"endless"
const ITEM_ARCHIVE := &"archive"
const ITEM_SETTINGS := &"settings"
const ITEM_QUIT := &"quit"
const LEFT_WIDTH := UiTokens.GRID * 100
## M3.6 compact title (a logical height under 1000 px, UI scale above 1.08): the wordmark
## prints at 112 px (its 0.18 em tracking kept) and the gap above the menu halves, so the
## menu and the DESCEND column fit 720 logical px without scaling down.
const WORDMARK_COMPACT_PX := UiTokens.GRID * 14
## The menu row keeps the DESCEND column's height whatever is selected, so the wordmark never
## moves with the selection (it has the tallest detail: stats, the loadout cards and help).
const COLUMNS_HEIGHT := UiTokens.GRID * 52
const COLUMNS_HEIGHT_COMPACT := UiTokens.GRID * 50
## Compact: the list column narrows to what its longest item needs, for the four cards.
const LIST_WIDTH_COMPACT := UiTokens.GRID * 40

var wordmark: Label
var subline: Label
var notice: Label
var daily_line: Label
var cards: LoadoutCards = null
var info: VBoxContainer
var _menu_gap: Control
var _stack: VBoxContainer
var _cols: HBoxContainer
var _compact_font: FontVariation = null
## The archive reset notice (consumed once by the title).
var reset_notice: String = ""


func build() -> void:
	show_header = false
	title = Strings.TITLE_WORDMARK
	# The wordmark block spans the top; the list and the detail sit side by side beneath it.
	remove_child(left)
	remove_child(detail_fit)
	var stack := VBoxContainer.new()
	_stack = stack
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(stack)
	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(top_space)
	var grid := WordmarkGrid.new()
	wordmark = grid.label
	stack.add_child(grid)
	subline = _line(&"TitleSubline", Title.version_line())
	stack.add_child(subline)
	notice = _line(&"AccentLabel", "")
	stack.add_child(notice)
	daily_line = _line(&"TitleSubline", "")
	stack.add_child(daily_line)
	_menu_gap = Control.new()
	stack.add_child(_menu_gap)
	var cols := HBoxContainer.new()
	_cols = cols
	cols.add_theme_constant_override(&"separation", COLUMN_GAP)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.size_flags_stretch_ratio = 1.6
	stack.add_child(cols)
	cols.add_child(left)
	cols.add_child(detail_fit)
	info = VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 0)
	detail.add_child(info)
	list.selection_changed.connect(func(_id: StringName) -> void: show_detail())
	list.activated.connect(choose)
	_apply_title_compact()


func apply_compact() -> void:
	super.apply_compact()
	_apply_title_compact()


func _apply_title_compact() -> void:
	var c := UiTokens.compact
	_stack.add_theme_constant_override(&"separation", UiTokens.GRID * (1 if c else 2))
	_menu_gap.custom_minimum_size.y = UiTokens.GRID * (2 if c else 4)
	_cols.custom_minimum_size.y = COLUMNS_HEIGHT_COMPACT if c else COLUMNS_HEIGHT
	left.custom_minimum_size.x = LIST_WIDTH_COMPACT if c else LIST_WIDTH
	if not UiTokens.compact:
		wordmark.remove_theme_font_size_override(&"font_size")
		wordmark.remove_theme_font_override(&"font")
		return
	if _compact_font == null:
		var base := UiAccessibility.project_theme().get_font(&"font", &"Wordmark")
		_compact_font = FontVariation.new()
		_compact_font.base_font = base.base_font if base is FontVariation else base
		_compact_font.spacing_glyph = UiTokens.tracking_px(WORDMARK_COMPACT_PX, UiTokens.TRACKING_WORDMARK_EM)
	wordmark.add_theme_font_override(&"font", _compact_font)
	wordmark.add_theme_font_size_override(&"font_size", WORDMARK_COMPACT_PX)


func on_open() -> void:
	list.active = true
	_rebuild_items()
	subline.text = Title.version_line()
	notice.text = reset_notice
	notice.visible = not reset_notice.is_empty()
	var played := GameState.meta.daily_result(GameState.today_key())
	daily_line.visible = not played.is_empty()
	if not played.is_empty():
		daily_line.text = Strings.MENU_DAILY + " · " + daily_result_text(played)
	show_detail()


func _rebuild_items() -> void:
	var keep := list.selected_id()
	list.clear_items()
	list.add_item(ITEM_DESCEND, Strings.MENU_DESCEND)
	list.add_item(ITEM_DAILY, Strings.MENU_DAILY, GameState.is_mode_available(Tuning.MODE_DAILY))
	if GameState.is_mode_available(Tuning.MODE_ENDLESS):
		list.add_item(ITEM_ENDLESS, Strings.MENU_ENDLESS)
	list.add_item(ITEM_ARCHIVE, Strings.MENU_ARCHIVE)
	list.add_item(ITEM_SETTINGS, Strings.MENU_SETTINGS)
	list.add_item(ITEM_QUIT, Strings.MENU_QUIT)
	var i := list.ids.find(keep)
	list.selected = maxi(i, 0)
	list.active = true


static func daily_result_text(r: Dictionary) -> String:
	return Strings.TITLE_DAILY_DONE.replace("{score}", RunSummary.format_score(int(r.get("score", 0)))) \
			.replace("{depth}", str(int(r.get("depth", 1))))


## Rebuilds the detail column for the selected item.
func show_detail() -> void:
	MenuPage.clear_children(info)
	cards = null
	var stats: Dictionary = GameState.meta.stats
	match list.selected_id():
		ITEM_DESCEND:
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_BEST_DEPTH, _num(stats.get("best_depth", 0))))
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_RUNS, _num(stats.get("runs", 0))))
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_WINS, _num(stats.get("wins", 0))))
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_LAST_CAUSE, last_cause_text()))
			if LoadoutCards.has_choice():
				_gap(info, 2 if UiTokens.compact else 4)
				var head := _line(&"DimLabel", Strings.TITLE_LABEL_LOADOUT)
				info.add_child(head)
				_gap(info, 1)
				cards = LoadoutCards.new()
				info.add_child(cards)
				_gap(info, 1)
				info.add_child(MenuPage.description_label(Strings.TITLE_LOADOUT_HELP))
		ITEM_DAILY:
			var today := GameState.today_key()
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_SEED, today))
			var played := GameState.meta.daily_result(today)
			if not played.is_empty():
				info.add_child(MenuPage.leader_row(Strings.MENU_DAILY, daily_result_text(played), UiTokens.UI_DIM))
				_gap(info, 2)
				info.add_child(MenuPage.description_label(Strings.TITLE_DAILY_PLAYED))
			elif not GameState.meta.is_unlocked(&"daily"):
				_gap(info, 2)
				info.add_child(MenuPage.description_label(String(Strings.UNLOCK_DESCRIPTIONS[&"daily"])))
			else:
				_gap(info, 2)
				info.add_child(MenuPage.description_label(Strings.TITLE_DAILY_RULES))
		ITEM_ENDLESS:
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_ENDLESS_BEST, _num(GameState.meta.endless_best_depth)))
			_gap(info, 2)
			info.add_child(MenuPage.description_label(Strings.TITLE_ENDLESS_RULES))
		ITEM_ARCHIVE:
			var found := Strings.TITLE_NOTES_COUNT.replace("{found}", str(GameState.meta.notes_found.size())) \
					.replace("{total}", str(DataRegistry.notes().size()))
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_NOTES, found))
			var met := 0
			for id in Tuning.ERROR_IDS:
				if int(GameState.meta.codex.get(String(id), 0)) >= Tuning.META_CODEX_FIRST_NOTICE:
					met += 1
			info.add_child(MenuPage.leader_row(Strings.TITLE_LABEL_ERRORS, "%d / %d" % [met, Tuning.ERROR_IDS.size()]))
			_gap(info, 2)
			info.add_child(MenuPage.description_label(Strings.TITLE_ARCHIVE_DESC))
		ITEM_SETTINGS:
			info.add_child(MenuPage.description_label(Strings.TITLE_SETTINGS_DESC))


static func last_cause_text() -> String:
	var cause := String(GameState.meta.last_run.get("cause", ""))
	if cause.is_empty():
		return Strings.TITLE_VALUE_NONE
	return String(Strings.CAUSE_LINES.get(StringName(cause), cause.to_upper()))


func selected_loadout() -> StringName:
	return cards.selected if cards != null else &"faller"


func choose(id: StringName) -> void:
	match id:
		ITEM_DESCEND:
			start_requested.emit(Tuning.MODE_DESCENT, selected_loadout())
		ITEM_DAILY:
			if GameState.is_mode_available(Tuning.MODE_DAILY):
				start_requested.emit(Tuning.MODE_DAILY, Tuning.MODE_DAILY_LOADOUT)
		ITEM_ENDLESS:
			if GameState.is_mode_available(Tuning.MODE_ENDLESS):
				start_requested.emit(Tuning.MODE_ENDLESS, selected_loadout())
		ITEM_ARCHIVE:
			open_requested.emit(&"archive")
		ITEM_SETTINGS:
			open_requested.emit(&"settings")
		ITEM_QUIT:
			quit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if cards == null or not is_visible_in_tree() or list.selected_id() != ITEM_DESCEND:
		return
	if event.is_action_pressed(&"ui_left", true):
		cards.move(-1)
	elif event.is_action_pressed(&"ui_right", true):
		cards.move(1)
	else:
		return
	get_viewport().set_input_as_handled()


static func _num(v: Variant) -> String:
	return RunSummary.format_score(int(v))


static func _line(variation: StringName, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


static func _gap(parent: Node, units: int) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = UiTokens.GRID * units
	parent.add_child(c)


## 04 §7: the wordmark with a 1 px grid of 8 px cells behind it; the solid letters cover the
## grid, so it renders only where the letters are not.
class WordmarkGrid extends MarginContainer:
	var label: Label

	func _init() -> void:
		label = Label.new()
		label.theme_type_variation = &"Wordmark"
		label.text = Strings.TITLE_WORDMARK
		add_child(label)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var cell := Tuning.MENU_TITLE_GRID_CELL
		var c := Color(UiTokens.UI_DIM, 0.3)
		var x := 0
		while x <= int(size.x):
			draw_line(Vector2(x + 0.5, 0), Vector2(x + 0.5, size.y), c, UiTokens.LINE)
			x += cell
		var y := 0
		while y <= int(size.y):
			draw_line(Vector2(0, y + 0.5), Vector2(size.x, y + 0.5), c, UiTokens.LINE)
			y += cell

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
