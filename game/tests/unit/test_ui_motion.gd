extends TestCase
## M1.6: the shared motion helpers (04 §4, 11 §5): shutter timings, typing at 60 cps with
## the 2 Hz cursor, the expo value tween, the numeral tick, key-cap segmentation.

func before_each() -> void:
	UiMotion.manual_clock = true


func after_each() -> void:
	UiMotion.manual_clock = false


func test_shutter_band_timings() -> void:
	assert_approx(UiMotion.SHUTTER_TIME, 0.12, 0.0001, "04 §4: 120 ms")
	assert_eq(UiMotion.SHUTTER_BANDS, 6)
	assert_approx(UiMotion.SHUTTER_BAND_TIME, 0.07, 0.0001, "the last band starts at 50 ms and ends at 120 ms")
	assert_eq(UiMotion.shutter_band(0, 0.0), 0.0)
	assert_approx(UiMotion.shutter_band(0, 0.035), 0.5, 0.001, "band 0 half open at 35 ms")
	assert_eq(UiMotion.shutter_band(0, 0.07), 1.0, "band 0 open at 70 ms")
	for band in 6:
		assert_eq(UiMotion.shutter_band(band, band * 0.01 - 0.0001), 0.0, "band %d waits for its 10 ms stagger" % band)
		assert_gt(UiMotion.shutter_band(band, band * 0.01 + 0.005), 0.0, "band %d moves after its stagger" % band)
		assert_eq(UiMotion.shutter_band(band, 0.12), 1.0, "band %d open at 120 ms" % band)
		assert_eq(UiMotion.shutter_band_closing(band, 0.12), 0.0, "band %d closed at 120 ms" % band)
	assert_lt(UiMotion.shutter_band(5, 0.119), 1.0, "the last band finishes exactly at 120 ms")


func test_band_slice_opens_from_the_centre_line() -> void:
	var s := UiMotion.band_slice(0, 60.0, 0.5)
	assert_approx(s.y, 5.0, 0.001, "half of a 10 px band")
	assert_approx(s.x, 2.5, 0.001, "centred in the band")
	var full := UiMotion.band_slice(5, 60.0, 1.0)
	assert_approx(full.x, 50.0, 0.001)
	assert_approx(full.y, 10.0, 0.001)


func test_ui_shutter_in_and_out() -> void:
	var s := UiShutter.new()
	add_child(s)
	assert_false(s.visible, "closed is invisible")
	s.shutter_in()
	assert_true(s.visible)
	assert_eq(s.phase, UiShutter.Phase.OPENING)
	s.advance(0.06)
	assert_eq(s.band_open(0), 1.0 * UiMotion.shutter_band(0, 0.06))
	assert_lt(s.band_open(5), s.band_open(0), "lower bands lag")
	s.advance(0.06)
	assert_eq(s.phase, UiShutter.Phase.OPEN, "open after 120 ms")
	s.shutter_out()
	s.advance(0.119)
	assert_true(s.visible, "still closing at 119 ms")
	s.advance(0.002)
	assert_eq(s.phase, UiShutter.Phase.CLOSED)
	assert_false(s.visible, "gone after 120 ms")
	s.free()


func test_ui_shutter_turns_around_mid_motion() -> void:
	var s := UiShutter.new()
	add_child(s)
	s.shutter_in()
	s.advance(0.1)
	s.shutter_out()
	assert_eq(s.phase, UiShutter.Phase.CLOSING)
	assert_approx(s.elapsed(), 0.02, 0.0001, "closing resumes from the coverage reached")
	s.advance(0.1)
	assert_eq(s.phase, UiShutter.Phase.CLOSED)
	s.free()


func test_typing_is_60_cps() -> void:
	assert_eq(UiTokens.TYPE_CPS, 60.0)
	assert_eq(UiMotion.typed_count(0.0, 60.0, 100), 0)
	assert_eq(UiMotion.typed_count(0.1, 60.0, 100), 6)
	assert_eq(UiMotion.typed_count(1.0, 60.0, 100), 60)
	assert_eq(UiMotion.typed_count(5.0, 60.0, 20), 20)
	assert_approx(UiMotion.typing_time(20, 60.0), 0.3333, 0.001)


func test_typed_label_prints_with_cursor_then_drops_it() -> void:
	var l := UiTypedLabel.new()
	add_child(l)
	var line := "ITEM UNLOCKED: RADIO"
	l.type_text(line)
	assert_true(l.is_typing())
	assert_eq(l.visible_text(), UiMotion.CURSOR, "cursor first, nothing typed")
	l.advance(0.1)
	assert_eq(l.typed_count(), 6)
	assert_eq(l.visible_text(), "ITEM U" + UiMotion.CURSOR, "6 characters at 100 ms, cursor lit")
	l.advance(0.2)
	assert_eq(l.typed_count(), 18)
	assert_eq(l.visible_text(), "ITEM UNLOCKED: RAD", "cursor dark in the second half of its 2 Hz period")
	var done := [false]
	l.finished.connect(func() -> void: done[0] = true)
	l.advance(0.04)
	assert_false(l.is_typing(), "20 characters take 333 ms")
	assert_true(done[0])
	assert_eq(l.visible_text(), line, "the cursor disappears when the line finishes")
	assert_eq(l.text.length(), line.length())
	l.free()


func test_cursor_blinks_at_2_hz() -> void:
	assert_true(UiMotion.cursor_visible(0.0))
	assert_true(UiMotion.cursor_visible(0.24))
	assert_false(UiMotion.cursor_visible(0.26))
	assert_true(UiMotion.cursor_visible(0.5))
	assert_eq(UiMotion.CURSOR, "▌", "U+258C (CHANGELOG 04)")


func test_value_tween_is_expo_out_180_ms() -> void:
	assert_eq(UiMotion.value_tween(0.0, 1.0, 0.0), 0.0)
	assert_eq(UiMotion.value_tween(0.0, 1.0, 0.18), 1.0)
	assert_gt(UiMotion.value_tween(0.0, 1.0, 0.09), 0.9, "expo out is mostly there at half time")


func test_tick_toward_is_rate_limited() -> void:
	assert_eq(UiMotion.tick_toward(100.0, 70.0, 30.0, 0.5), 85.0)
	assert_eq(UiMotion.tick_toward(85.0, 70.0, 30.0, 1.0), 70.0, "never overshoots")
	assert_eq(UiMotion.tick_toward(50.0, 75.0, 30.0, 0.5), 65.0)


func test_select_pulse() -> void:
	assert_approx(UiMotion.pulse(0.0), 1.15, 0.0001)
	assert_eq(UiMotion.pulse(0.1), 1.0)
	assert_eq(UiMotion.pulse(INF), 1.0)


func test_key_segments() -> void:
	var press := UiKeys.segments(Strings.PROMPT_PRESS, {&"text": "OPEN DOOR"}, {&"key": "E"})
	assert_eq(UiKeys.plain(press), "[E] OPEN DOOR")
	assert_eq(press.size(), 2)
	var hold := UiKeys.segments(Strings.PROMPT_HOLD, {&"text": "LEAVE"}, {&"key": "E"})
	assert_eq(UiKeys.plain(hold), "HOLD [E] LEAVE", "only the key name is boxed")
	var hint := UiKeys.segments(Strings.HINT_MOVE, {}, {&"move_forward": "W", &"move_left": "A", &"move_back": "S", &"move_right": "D"})
	assert_eq(UiKeys.plain(hint), "[W] [A] [S] [D] MOVE · [MOUSE] LOOK", "a group without actions is one key cap")
	var given := UiKeys.segments("[E] READ", {}, {})
	assert_eq(UiKeys.plain(given), "[E] READ")


func test_key_names_from_bindings() -> void:
	assert_eq(UiKeys.key_name(&"interact"), "E", "default interact binding (06 §2)")
	assert_eq(UiKeys.key_name(&"no_such_action"), Strings.BINDING_NONE)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	assert_eq(UiKeys.event_name(mb), Strings.BINDING_MOUSE_LEFT)
