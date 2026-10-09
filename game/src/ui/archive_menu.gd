class_name ArchiveMenu
extends MenuPage
## The Archive (04 §7, 13 §5): NOTES, ERRORS, STATISTICS, UNLOCKS. Notes are a 6 × 6 grid,
## one column per stratum, each cell the note ID once found or `··`; selecting a found note
## types its sheet below the grid (90 cps, 04 §8 backings). Errors stay `··` until the first
## encounter (name and glyph), and add the counter line as a builder memo after 3. Statistics
## format meta.stats; unlocks list the 14 milestones with condition and a check or cross.
## Reads GameState.meta; the one write is the notes' read state (13 §5: unread found notes
## blink once in ui_accent the first time the grid shows them, then count as read).

const SECTION_NOTES := &"notes"
const SECTION_ERRORS := &"errors"
const SECTION_STATISTICS := &"statistics"
const SECTION_UNLOCKS := &"unlocks"
## M3.6 (16 §6): the full credits, a page of their own (CreditsMenu) under this id.
const SECTION_CREDITS := &"credits"
const PAGE_CREDITS := &"credits"
## M3.6 compact (720 logical px): the 14 milestones in one column, 7 to a page, as
## `UNLOCKS 1/2` and `UNLOCKS 2/2` (the second page's id is SECTION_UNLOCKS_2).
const SECTION_UNLOCKS_2 := &"unlocks_2"
const UNLOCKS_PER_PAGE_COMPACT := 7
## Two columns of 464 px fill the 960 px detail column (04 §7).
const UNLOCK_ENTRY_WIDTH := UiTokens.GRID * 58
const GRID := Tuning.ARCHIVE_NOTE_GRID
## M3.6: 120 px, so six strata fit the compact detail column (736 px).
const CELL_WIDTH := UiTokens.GRID * 15
## 04 §5 codex glyphs.
const ERROR_GLYPHS: Dictionary = {&"static": &"wave", &"still": &"eye", &"flicker": &"bolt", &"echo": &"steps", &"null": &"null"}
const SHEET_PANELS: Dictionary = {
	&"faller": &"NoteSheetFaller", &"builder": &"NoteSheetBuilder", &"stray": &"NoteSheetStray", &"builder_final": &"NoteSheet",
}

var body: VBoxContainer
## Grid cursor (column = stratum, row = note) and whether the keyboard is in the grid.
var cursor: Vector2i = Vector2i.ZERO
var grid_focus: bool = false
var cells: Array[Label] = []
var sheet: PanelContainer
var sheet_header: Label
var sheet_body: UiTypedLabel
var _grid_ids: Array = []
## Notes blinking now (unread when the grid was built) and the blink's clock.
var blinking: Array[StringName] = []
var _blink_t: float = INF


func build() -> void:
	title = Strings.MENU_ARCHIVE
	_add_sections()
	list.selection_changed.connect(show_section)
	list.activated.connect(_enter)
	list.advanced.connect(_enter)
	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UiTokens.GRID)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(body)


func _add_sections() -> void:
	list.add_item(SECTION_NOTES, Strings.ARCHIVE_NOTES)
	list.add_item(SECTION_ERRORS, Strings.ARCHIVE_ERRORS)
	list.add_item(SECTION_STATISTICS, Strings.ARCHIVE_STATISTICS)
	if UiTokens.compact:
		for i in 2:
			list.add_item(SECTION_UNLOCKS if i == 0 else SECTION_UNLOCKS_2,
					Strings.ARCHIVE_UNLOCKS_PAGE.replace("{page}", str(i + 1)).replace("{pages}", "2"))
	else:
		list.add_item(SECTION_UNLOCKS, Strings.ARCHIVE_UNLOCKS)
	list.add_item(SECTION_CREDITS, Strings.ARCHIVE_CREDITS)


func on_open() -> void:
	grid_focus = false
	list.active = true
	show_section(list.selected_id())


## Rebuilds the open section at the new row height (M3.6).
func apply_compact() -> void:
	var keep := list.selected_id()
	list.clear_items()
	_add_sections()
	list.select_id(keep if list.ids.has(keep) else SECTION_UNLOCKS)
	super.apply_compact()
	if body == null:
		return
	var focus := grid_focus
	show_section(list.selected_id())
	if focus and not cells.is_empty():
		grid_focus = true
		list.active = false
		_refresh_grid()


func handle_cancel() -> bool:
	if grid_focus:
		focus_list()
		return true
	return false


func show_section(id: StringName) -> void:
	MenuPage.clear_children(body)
	body.add_theme_constant_override(&"separation", UiTokens.GRID)
	cells.clear()
	sheet = null
	match id:
		SECTION_NOTES:
			_build_notes()
		SECTION_ERRORS:
			_build_errors()
		SECTION_STATISTICS:
			_build_statistics()
		SECTION_UNLOCKS:
			_build_unlocks(0)
		SECTION_UNLOCKS_2:
			_build_unlocks(1)
		SECTION_CREDITS:
			body.add_child(MenuPage.description_label(Strings.ARCHIVE_CREDITS_DESC))
			body.add_child(MenuPage.description_label(Strings.ARCHIVE_CREDITS_HELP))


## Enter or Right on a section: the notes grid takes the keyboard; CREDITS opens its page.
func _enter(id: StringName) -> void:
	if id == SECTION_NOTES:
		focus_grid()
	elif id == SECTION_CREDITS:
		open_requested.emit(PAGE_CREDITS)


# --- notes --------------------------------------------------------------------------------------

## Note ids by grid position: column = stratum (05 §2 order), row = the stratum's notes in order.
static func note_grid() -> Array:
	var cols: Array = []
	for stratum in DataRegistry.STRATUM_ORDER:
		var ids: Array[StringName] = []
		for n in DataRegistry.notes_for(stratum):
			ids.append(n.id)
		cols.append(ids)
	return cols


static func is_found(id: StringName) -> bool:
	return GameState.meta.notes_found.has(id)


## What a cell shows: the ID once found, `··` before (04 §7).
static func cell_text(id: StringName) -> String:
	return String(id) if is_found(id) else Strings.ARCHIVE_LOCKED_CELL


func _build_notes() -> void:
	_grid_ids = note_grid()
	var total := 0
	for col: Array in _grid_ids:
		total += col.size()
	var count := MenuPage.leader_row(Strings.ARCHIVE_NOTES, Strings.TITLE_NOTES_COUNT
			.replace("{found}", str(GameState.meta.notes_found.size())).replace("{total}", str(total)))
	body.add_child(count)
	var grid := GridContainer.new()
	grid.columns = GRID.x
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	for stratum in DataRegistry.STRATUM_ORDER:
		var h := Label.new()
		h.theme_type_variation = &"Description"
		h.text = String(Strings.STRATUM_NAMES.get(stratum, String(stratum).to_upper()))
		h.custom_minimum_size = Vector2(CELL_WIDTH, UiTokens.row_height())
		h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		grid.add_child(h)
	for r in GRID.y:
		for c in GRID.x:
			var id: StringName = _grid_ids[c][r] if c < _grid_ids.size() and r < (_grid_ids[c] as Array).size() else &""
			var l := Label.new()
			l.theme_type_variation = &"MenuItemLabel"
			l.custom_minimum_size = Vector2(CELL_WIDTH, UiTokens.row_height())
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.text = "  " + (cell_text(id) if id != &"" else "")
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			var at := Vector2i(c, r)
			l.mouse_entered.connect(func() -> void: _hover_cell(at))
			grid.add_child(l)
			cells.append(l)
	body.add_child(grid)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiTokens.GRID * 2
	body.add_child(gap)
	sheet = PanelContainer.new()
	sheet.custom_minimum_size.x = UiTokens.NOTE_SHEET_WIDTH
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTokens.GRID)
	sheet.add_child(box)
	sheet_header = Label.new()
	sheet_header.theme_type_variation = &"NoteHeader"
	box.add_child(sheet_header)
	sheet_body = UiTypedLabel.new()
	sheet_body.theme_type_variation = &"NoteBody"
	sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.custom_minimum_size.x = UiTokens.NOTE_SHEET_WIDTH - UiTokens.NOTE_SHEET_PADDING * 2
	box.add_child(sheet_body)
	body.add_child(sheet)
	var help := MenuPage.description_label(Strings.ARCHIVE_NOTES_HELP)
	body.add_child(help)
	_start_blink()
	_refresh_grid()


## 13 §5: the found notes the Archive has not shown blink once, and are read from now on.
func _start_blink() -> void:
	var meta := GameState.meta
	blinking = meta.unread_notes() if meta != null else ([] as Array[StringName])
	_blink_t = 0.0 if not blinking.is_empty() else INF
	if not blinking.is_empty() and meta.mark_notes_read(blinking):
		SaveManager.save_meta()


func is_blink_lit(id: StringName) -> bool:
	return blinking.has(id) and _blink_t < Tuning.ARCHIVE_NEW_BLINK_S * 0.5


func advance(dt: float) -> void:
	if _blink_t == INF:
		return
	var was := _blink_t < Tuning.ARCHIVE_NEW_BLINK_S * 0.5
	_blink_t += dt
	if was != (_blink_t < Tuning.ARCHIVE_NEW_BLINK_S * 0.5) and not cells.is_empty():
		_refresh_grid()
	if _blink_t >= Tuning.ARCHIVE_NEW_BLINK_S:
		_blink_t = INF
		blinking.clear()


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func focus_grid() -> void:
	if cells.is_empty():
		return
	grid_focus = true
	list.active = false
	_refresh_grid()


func focus_list() -> void:
	grid_focus = false
	list.active = true
	_refresh_grid()


func _hover_cell(at: Vector2i) -> void:
	if list.selected_id() != SECTION_NOTES:
		return
	if not grid_focus:
		grid_focus = true
		list.active = false
	move_cursor_to(at)


func move_cursor_to(at: Vector2i) -> void:
	var c := Vector2i(clampi(at.x, 0, GRID.x - 1), clampi(at.y, 0, GRID.y - 1))
	if c != cursor:
		cursor = c
		AudioManager.play_2d(&"ui_move")
	_refresh_grid()


func cursor_note() -> StringName:
	if cursor.x < _grid_ids.size() and cursor.y < (_grid_ids[cursor.x] as Array).size():
		return _grid_ids[cursor.x][cursor.y]
	return &""


## True while a sheet is showing (a found note under the cursor).
func sheet_visible() -> bool:
	return sheet != null and sheet.visible


func _refresh_grid() -> void:
	for i in cells.size():
		var at := Vector2i(i % GRID.x, i / GRID.x)
		var id: StringName = _grid_ids[at.x][at.y] if at.x < _grid_ids.size() and at.y < (_grid_ids[at.x] as Array).size() else &""
		var on := grid_focus and at == cursor
		cells[i].text = (Strings.MENU_SELECTED_PREFIX if on else "  ") + (cell_text(id) if id != &"" else "")
		var col := UiTokens.UI_FG if is_found(id) else UiTokens.UI_DIM
		if on or is_blink_lit(id):
			col = UiTokens.accent()
		UiTokens.paint(cells[i], col)
	if sheet == null:
		return
	var id := cursor_note() if grid_focus else &""
	var n := DataRegistry.note(id) if id != &"" and is_found(id) else null
	sheet.visible = n != null
	if n == null:
		return
	if sheet_header.text == NoteSheet.header_for(n) and sheet_body.full_text == NoteSheet.body_for(n).strip_edges():
		return
	sheet.theme_type_variation = SHEET_PANELS.get(n.voice, &"NoteSheet")
	sheet_header.text = NoteSheet.header_for(n)
	sheet_body.type_text(NoteSheet.body_for(n).strip_edges(), UiTokens.NOTE_TYPE_CPS)


func _unhandled_input(event: InputEvent) -> void:
	if not grid_focus or not is_visible_in_tree():
		return
	var d := Vector2i.ZERO
	if event.is_action_pressed(&"ui_left", true):
		d = Vector2i.LEFT
	elif event.is_action_pressed(&"ui_right", true):
		d = Vector2i.RIGHT
	elif event.is_action_pressed(&"ui_up", true):
		d = Vector2i.UP
	elif event.is_action_pressed(&"ui_down", true):
		d = Vector2i.DOWN
	elif not event.is_action_pressed(&"ui_accept"):
		return
	get_viewport().set_input_as_handled()
	if d == Vector2i.LEFT and cursor.x == 0:
		focus_list()
		return
	move_cursor_to(cursor + d)


# --- errors, statistics, unlocks ----------------------------------------------------------------

func _build_errors() -> void:
	body.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	for id in Tuning.ERROR_IDS:
		var count := int(GameState.meta.codex.get(String(id), 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
		row.custom_minimum_size.y = UiTokens.row_height()
		var glyph := TextureRect.new()
		glyph.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)
		if count < Tuning.META_CODEX_FIRST_NOTICE:
			row.add_child(TitlePage._line(&"DimLabel", Strings.ARCHIVE_LOCKED_CELL))
			body.add_child(row)
			continue
		glyph.texture = UiTokens.glyph(ERROR_GLYPHS[id])
		var name_row := MenuPage.leader_row(String(Strings.ERROR_NAMES[id]),
				Strings.ARCHIVE_ENCOUNTERS.replace("{count}", str(count)), UiTokens.UI_DIM)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_row)
		body.add_child(row)
		if count >= Tuning.META_CODEX_COUNTER_LINE:
			var memo := PanelContainer.new()
			memo.theme_type_variation = &"NoteSheetBuilder"
			var t := MenuPage.description_label(String(Strings.ERROR_CODEX[id]))
			t.theme_type_variation = &"NoteBody"
			memo.add_child(t)
			body.add_child(memo)


func _build_statistics() -> void:
	if UiTokens.compact:
		body.add_theme_constant_override(&"separation", 0)   # M3.6: 17 rows in 720 px
	var s: Dictionary = GameState.meta.stats
	var fmt := func(v: Variant) -> String: return RunSummary.format_score(int(v))
	body.add_child(MenuPage.leader_row(Strings.STAT_RUNS, fmt.call(s.get("runs", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_WINS, fmt.call(s.get("wins", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_BEST_DEPTH, fmt.call(s.get("best_depth", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_BEST_SCORE, fmt.call(s.get("best_score", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_DEATHS_BY, ""))
	var deaths: Dictionary = s.get("deaths_by", {})
	for cause in MetaSchema.DEATH_CAUSES:
		var label := "  " + String(Strings.ERROR_NAMES.get(StringName(cause), Strings.STRATUM_NAMES.get(StringName(cause), String(cause).to_upper())))
		body.add_child(MenuPage.leader_row(label, fmt.call(deaths.get(cause, 0)), UiTokens.UI_DIM))
	body.add_child(MenuPage.leader_row(Strings.STAT_DISTANCE_WALKED,
			Strings.ARCHIVE_DISTANCE.replace("{value}", fmt.call(s.get("distance_walked_m", 0.0)))))
	body.add_child(MenuPage.leader_row(Strings.STAT_WALLS_PASSED, fmt.call(s.get("walls_passed", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_FLOORS_DROPPED, fmt.call(s.get("floors_dropped", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_COHERENCE_SPENT, fmt.call(s.get("coherence_spent", 0))))
	body.add_child(MenuPage.leader_row(Strings.STAT_NOTES_FOUND, fmt.call(GameState.meta.notes_found.size())))
	body.add_child(MenuPage.leader_row(Strings.STAT_POLAROIDS_SEEN, fmt.call(GameState.meta.polaroids_seen.size())))


func _build_unlocks(page: int) -> void:
	var earned := 0
	for id in Tuning.UNLOCK_IDS:
		if GameState.meta.is_unlocked(id):
			earned += 1
	body.add_child(MenuPage.leader_row(Strings.ARCHIVE_UNLOCKS, Strings.ARCHIVE_UNLOCKED_COUNT
			.replace("{earned}", str(earned)).replace("{total}", str(Tuning.UNLOCK_IDS.size()))))
	var grid := GridContainer.new()
	grid.columns = 1 if UiTokens.compact else 2
	grid.add_theme_constant_override(&"h_separation", UiTokens.GRID * 4)
	grid.add_theme_constant_override(&"v_separation", UiTokens.GRID * (1 if UiTokens.compact else 2))
	for id in unlock_page(page):
		var on := GameState.meta.is_unlocked(id)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override(&"separation", 0)
		entry.custom_minimum_size.x = 0 if UiTokens.compact else UNLOCK_ENTRY_WIDTH
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", UiTokens.GRID)
		var g := TextureRect.new()
		g.texture = UiTokens.glyph(&"check" if on else &"cross")
		g.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.modulate = UiTokens.UI_FG if on else UiTokens.UI_DIM
		head.add_child(g)
		var n := TitlePage._line(&"MenuItemLabel", String(Strings.UNLOCK_NAMES[id]))
		n.add_theme_color_override(&"font_color", UiTokens.UI_FG if on else UiTokens.UI_DIM)
		head.add_child(n)
		entry.add_child(head)
		entry.add_child(MenuPage.description_label(String(Strings.UNLOCK_DESCRIPTIONS[id])))
		grid.add_child(entry)
	body.add_child(grid)


## The milestones on unlock page `page` (all of them unless compact, M3.6).
static func unlock_page(page: int) -> Array[StringName]:
	if not UiTokens.compact:
		return Tuning.UNLOCK_IDS.duplicate()
	var n := UNLOCKS_PER_PAGE_COMPACT
	return Tuning.UNLOCK_IDS.slice(page * n, (page + 1) * n)
