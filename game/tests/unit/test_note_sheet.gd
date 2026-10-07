extends TestCase
## M1.6: note sheets (04 §8, 01 §7) show a real note per voice with its header and
## backing, type at 90 characters per second, and lower out on a 0.5 s movement hold or
## after 8 s.

const SHEET_SCENE := "res://scenes/ui/note_sheet.tscn"

var sheet: NoteSheet
var _moving: bool = false


func before_each() -> void:
	UiMotion.manual_clock = true
	_moving = false
	sheet = (load(SHEET_SCENE) as PackedScene).instantiate() as NoteSheet
	sheet.movement_held = func() -> bool: return _moving
	add_child(sheet)


func after_each() -> void:
	sheet.free()
	UiMotion.manual_clock = false


func _first_of(v: StringName) -> NoteData:
	for n in DataRegistry.notes():
		if n.voice == v:
			return n
	return null


func test_instantiates_closed() -> void:
	assert_false(sheet.visible)
	assert_eq(sheet.custom_minimum_size.x, float(UiTokens.NOTE_SHEET_WIDTH), "720 px wide")


func test_faller_note() -> void:
	var n := DataRegistry.note(&"H3")
	assert_eq(n.voice, &"faller")
	sheet.show_note(n)
	assert_true(sheet.is_shown())
	assert_eq(sheet.header_text, "NOTE H3 · HANDWRITTEN")
	assert_eq(sheet.panel_type(), &"NoteSheetFaller")
	assert_eq(sheet.body_text, n.text, "faller text verbatim")
	assert_eq(" ".join(sheet.lines()), n.text, "wrapping keeps every word")
	var margins: Dictionary = {}
	for l in sheet.line_labels():
		var sb := l.get_theme_stylebox(&"normal")
		margins[sb.content_margin_left] = true
	assert_gt(margins.size(), 1, "01 §7: a ragged left margin")


func test_builder_note_moves_the_memo_number_to_the_header() -> void:
	var n := DataRegistry.note(&"H4")
	assert_eq(n.voice, &"builder")
	sheet.show_note(n)
	assert_eq(sheet.header_text, "RENDER NOTE 0014")
	assert_eq(sheet.panel_type(), &"NoteSheetBuilder")
	assert_false(sheet.body_text.begins_with("RENDER NOTE"))
	assert_true(n.text.ends_with(sheet.body_text))
	assert_true((sheet.get_node("%Rule") as Control).visible, "01 §7: a form header line")


func test_stray_note_is_centred() -> void:
	var n := _first_of(&"stray")
	assert_not_null(n)
	sheet.show_note(n)
	assert_eq(sheet.header_text, "FOUND OBJECT")
	assert_eq(sheet.panel_type(), &"NoteSheetStray")
	for l in sheet.line_labels():
		assert_eq(l.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	assert_false((sheet.get_node("%Rule") as Control).visible)


func test_builder_final_note() -> void:
	var n := DataRegistry.note(&"U6")
	sheet.show_note(n)
	assert_eq(sheet.header_text, "NOTE U6")
	assert_eq(sheet.panel_type(), &"NoteSheetBuilder")


func test_every_note_fits_the_sheet() -> void:
	for n in DataRegistry.notes():
		sheet.show_note(n)
		var cols := sheet._columns()
		for line in sheet.lines():
			assert_true(line.length() <= cols or not line.contains(" "), "%s wraps within %d columns" % [n.id, cols])
		assert_eq(" ".join(sheet.lines()), NoteSheet.body_for(n).strip_edges())


func test_types_at_90_cps() -> void:
	assert_eq(UiTokens.NOTE_TYPE_CPS, 90.0)
	sheet.show_note(DataRegistry.note(&"H3"))
	assert_eq(sheet.typed_count(), 0)
	UiMotion.step(sheet, 0.1)
	assert_eq(sheet.typed_count(), 9)
	var first := sheet.line_labels()[0]
	assert_eq(first.visible_characters, 10, "9 characters and the cursor")
	assert_true(first.text.contains(UiMotion.CURSOR))
	UiMotion.step(sheet, 5.0)
	assert_false(sheet.is_typing())
	assert_eq(first.visible_characters, -1)
	assert_false(first.text.contains(UiMotion.CURSOR), "the cursor goes when the text is done")


func test_movement_hold_dismisses_after_half_a_second() -> void:
	sheet.show_note(DataRegistry.note(&"H3"))
	UiMotion.step(sheet, 0.2)
	_moving = true
	for i in 29:
		UiMotion.step(sheet, 1.0 / 60.0)
	assert_true(sheet.is_shown(), "0.48 s held: still up")
	_moving = false
	UiMotion.step(sheet, 1.0 / 60.0)
	_moving = true
	for i in 29:
		UiMotion.step(sheet, 1.0 / 60.0)
	assert_true(sheet.is_shown(), "releasing resets the hold")
	for i in 3:
		UiMotion.step(sheet, 1.0 / 60.0)
	assert_eq(sheet.phase, UiShutter.Phase.CLOSING, "a 0.5 s hold lowers it with the shutter")
	UiMotion.step(sheet, 0.13)
	assert_false(sheet.visible)


func test_lowers_by_itself_after_8_s() -> void:
	sheet.show_note(DataRegistry.note(&"G1"))
	UiMotion.step(sheet, Tuning.NOTE_SHEET_AUTO_LOWER_TIME - 0.1)
	assert_true(sheet.is_shown())
	UiMotion.step(sheet, 0.2)
	assert_eq(sheet.phase, UiShutter.Phase.CLOSING)
