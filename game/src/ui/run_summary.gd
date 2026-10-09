class_name RunSummary
extends Control
## The Run Summary (04 §7): full black; the top line typed (`DISSOLVED BY STILL · DEPTH 03 ·
## GARAGE`, ui_danger; a win in ui_accent), a line reporting the cause (00 §5), then the
## table typed line by line at 60 cps, then the items `DESCEND AGAIN` (default; Enter
## restarts within 1 s) and `TITLE`. Reads GameState and Clock; writes nothing but the
## next GameState.start_run. SCORE and BEST come from GameState (05 §5); unlocks earned this
## run follow the table in ui_accent, worded as the HUD notifications (04 §6, §7).
## Items (04 §7): DESCEND AGAIN, ARCHIVE (the title opens on the Archive), TITLE. A spent
## Daily Descent restarts as a Descent (05 §8: one attempt per day).

const RUN_SCENE := "res://scenes/run.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const WIN_CAUSE := &"threshold"
const ITEM_AGAIN := &"descend_again"
const ITEM_ARCHIVE := &"archive"
const ITEM_TITLE := &"title"

var lines: Array[UiTypedLabel] = []
var frame: MarginContainer
var menu: MenuList
var _texts: Array[String] = []
var _typing: int = -1
var _leaving: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTokens.UI_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# M3.6: the table sits 128 px in at 1080p; on a short logical screen (UI scale above 1.0,
	# 720p) the frame keeps the 32 px safe area and the column scales down if it still
	# does not fit (UiFitBox).
	frame = MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_apply_margins()
	resized.connect(_apply_margins)
	var fit := UiFitBox.new()
	frame.add_child(fit)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UiTokens.GRID)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fit.add_child(col)
	var win := GameState.last_cause() == WIN_CAUSE
	_add_line(col, top_line() if win else UiTokens.danger_mark(top_line()), &"AccentLabel" if win else &"DangerLabel")
	_add_line(col, cause_explanation(GameState.last_cause()), &"DimLabel")
	var spacer := Control.new()
	spacer.custom_minimum_size.y = UiTokens.GRID * 3
	col.add_child(spacer)
	for t in table_lines():
		_add_line(col, t, &"MenuItemLabel")
	for t in unlock_lines():
		_add_line(col, t, &"AccentLabel")
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = UiTokens.GRID * 4
	col.add_child(spacer2)
	menu = MenuList.new()
	menu.add_item(ITEM_AGAIN, Strings.SUMMARY_DESCEND_AGAIN)
	menu.add_item(ITEM_ARCHIVE, Strings.SUMMARY_ARCHIVE)
	menu.add_item(ITEM_TITLE, Strings.SUMMARY_TITLE)
	menu.activated.connect(choose)
	col.add_child(menu)
	_type_next()


func _apply_margins() -> void:
	if frame == null:
		return
	var m := UiTokens.SAFE_MARGIN * (1 if size.y > 0.0 and size.y < MenuShell.COMPACT_HEIGHT else 4)
	for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		frame.add_theme_constant_override(side, m)


func _add_line(parent: Node, text: String, variation: StringName) -> void:
	var l := UiTypedLabel.new()
	l.theme_type_variation = variation
	l.sound = true
	l.text = ""
	parent.add_child(l)
	lines.append(l)
	_texts.append(text)
	l.finished.connect(_type_next)


func _type_next() -> void:
	_typing += 1
	if _typing < lines.size():
		lines[_typing].type_text(_texts[_typing])
	elif _typing == lines.size():
		AudioManager.play_2d(&"ui_summary_stamp")


## Prints every line at once (any key skips the typing).
func finish_typing() -> void:
	for i in lines.size():
		lines[i].show_full(_texts[i])
	_typing = lines.size() + 1


func is_typing() -> bool:
	return _typing < lines.size()


## 04 §7 top line from GameState.
static func top_line() -> String:
	var run := GameState.run
	var depth := run.depth if run != null else 1
	var cause := GameState.last_cause()
	if cause == WIN_CAUSE:
		return Strings.SUMMARY_WIN_LINE.replace("{depth}", "%02d" % depth)
	var cause_text := String(Strings.CAUSE_LINES.get(cause, Strings.CAUSE_DISSOLVED_BY.replace("{error}", String(cause).to_upper())))
	var stratum := generated_stratum()
	return Strings.SUMMARY_TOP_LINE.replace("{cause}", cause_text).replace("{depth}", "%02d" % depth) \
			.replace("{stratum}", String(Strings.STRATUM_NAMES.get(stratum, String(stratum).to_upper())))


## 04 §7 (CHANGELOG 2026-10-08): the stratum the last level was generated as, as the HUD
## named it; the planned one only when no level was entered.
static func generated_stratum() -> StringName:
	var run := GameState.run
	if run == null:
		return Tuning.STRATUM_DEPTH1
	if run.stratum != &"":
		return run.stratum
	return GameState.stratum_for(run.depth)


static func cause_explanation(cause: StringName) -> String:
	return String(Strings.CAUSE_EXPLANATIONS.get(cause, Strings.CAUSE_EXPLANATION_DEFAULT))


## The table (04 §7), in its order. Time from Clock.run_seconds (pause excluded).
static func table_lines() -> Array[String]:
	var run := GameState.run
	var out: Array[String] = []
	if run == null:
		return out
	out.append(Strings.SUMMARY_LINE_DEPTH.replace("{value}", str(run.depth)))
	out.append(Strings.SUMMARY_LINE_TIME.replace("{value}", format_time(Clock.run_seconds())))
	out.append(Strings.SUMMARY_LINE_COHERENCE_SPENT.replace("{value}", str(roundi(run.coherence_spent))))
	out.append(Strings.SUMMARY_LINE_WALLS_PASSED.replace("{value}", str(run.walls_passed)))
	out.append(Strings.SUMMARY_LINE_FLOORS_DROPPED.replace("{value}", str(run.drops_total)))
	out.append(Strings.SUMMARY_LINE_NOTES_FOUND.replace("{value}", str(run.notes_found.size())))
	out.append(Strings.SUMMARY_LINE_ERRORS_EVADED.replace("{value}", str(run.evasions)))
	out.append(Strings.SUMMARY_LINE_SCORE.replace("{value}", format_score(run.score)))
	out.append(Strings.SUMMARY_LINE_BEST.replace("{value}", format_score(int(GameState.meta.stats.get("best_score", 0)))))
	return out


## 04 §7: one line per unlock earned this run (`ITEM UNLOCKED: RADIO`).
static func unlock_lines() -> Array[String]:
	var out: Array[String] = []
	if GameState.run != null:
		for id in GameState.run.unlocks_earned:
			out.append(Hud.unlock_message(id))
	return out


## 04 §7: `2,310`.
static func format_score(score: int) -> String:
	var digits := str(absi(score))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if score < 0 else "") + digits + out


static func format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%02d:%02d" % [s / 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	if is_typing() and event is InputEventKey and event.is_pressed() and not event.is_action(&"ui_accept"):
		finish_typing()
		get_viewport().set_input_as_handled()


## DESCEND AGAIN starts a new Descent with the same mode and loadout; TITLE goes back.
func choose(id: StringName) -> void:
	if _leaving:
		return
	_leaving = true
	if id == ITEM_AGAIN:
		var mode := again_mode()
		var run := GameState.run
		var loadout: StringName = run.loadout if run != null else &"faller"
		if not GameState.is_loadout_available(loadout):
			loadout = &"faller"
		GameState.start_run(mode, loadout, GameState.daily_seed() if mode == Tuning.MODE_DAILY else Run.new_seed())
		SceneRouter.change_to(RUN_SCENE)
	else:
		if id == ITEM_ARCHIVE:
			Title.open_on_enter = Title.PAGE_ARCHIVE
		SceneRouter.change_to(TITLE_SCENE)


## The mode DESCEND AGAIN starts: the same one if it is still available, else Descent.
static func again_mode() -> StringName:
	var mode: StringName = GameState.run.mode if GameState.run != null else Tuning.MODE_DESCENT
	return mode if GameState.is_mode_available(mode) else Tuning.MODE_DESCENT
