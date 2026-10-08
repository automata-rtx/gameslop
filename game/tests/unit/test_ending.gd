extends TestCase
## M2.15 the ending (01 §8, 16 §6): the variant condition, the first-viewing rule, the
## Coherence restore and the white cut's Reduce flashing fade; the credits carry the AI
## disclosure, the engine's MIT notice, every engine component with its license and the
## bundled font's copyright line; no ending text uses a forbidden word (01 §2); the
## sequence reaches the summary on its own, skips only after the first viewing, and the
## variant's DESCEND starts the next Descent.

const FORBIDDEN := "\\b(backrooms|liminal|level 0|almond water|entity|entities|smiler|bacteria|partygoer|monster|monsters|enemy|enemies)\\b"
const ENDING_SCENE := preload("res://scenes/ending.tscn")
const FONT_LICENSE := "res://assets/fonts/OFL.txt"

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
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "EndingTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	for c in _host.get_children():
		c.queue_free()
	await await_frames(3)
	if GameState.is_run_active():
		GameState.end_run(&"abandoned")
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()


func _all_notes_but_u6(meta: MetaState) -> void:
	for n: NoteData in DataRegistry.notes():
		if n.id != GameState.NOTE_U6:
			meta.note_found(n.id)


## A won Descent, as the run leaves it when the ending starts.
func _won_run(wins_before: int) -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 77)
	GameState.run.coherence = 40.0
	GameState.meta.stats["wins"] = wins_before
	GameState.end_run(GameState.WIN_CAUSE)


func _ending() -> Ending:
	var e := ENDING_SCENE.instantiate() as Ending
	e.capture_mouse = false
	_host.add_child(e)
	SceneRouter.set_host(_host)
	return e


func _until(cond: Callable, seconds: float = 20.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


# --- rules -----------------------------------------------------------------------------------

func test_variant_needs_all_35_other_notes() -> void:
	var m := MetaState.new()
	assert_false(Ending.variant_for(m), "a fresh save plays the plain ending")
	_all_notes_but_u6(m)
	assert_eq(m.notes_count_except(GameState.NOTE_U6), Tuning.UNLOCK_NOTE_U6_NOTES)
	assert_true(Ending.variant_for(m), "01 §8: all 36 notes (35 found, U6 earned with them)")
	var one_short := MetaState.new()
	for n: NoteData in DataRegistry.notes():
		if n.id != GameState.NOTE_U6 and n.id != &"H1":
			one_short.note_found(n.id)
	assert_false(Ending.variant_for(one_short), "34 of the 35 is not enough")
	var earned := MetaState.new()
	earned.earn(&"note_u6")
	assert_true(Ending.variant_for(earned), "unlock #14 earned")
	assert_false(Ending.variant_for(null))


func test_variant_through_game_state_unlocks_u6() -> void:
	GameState.meta = MetaState.new()
	for n: NoteData in DataRegistry.notes():
		if n.id != GameState.NOTE_U6:
			GameState.record_note(n.id)
	assert_true(GameState.meta.is_unlocked(&"note_u6"), "05 §6 #14")
	assert_true(Ending.variant_for(GameState.meta))


func test_skippable_after_the_first_viewing_only() -> void:
	var m := MetaState.new()
	m.stats["wins"] = 1
	assert_false(Ending.is_skippable(m), "the first win's ending plays whole")
	m.stats["wins"] = 2
	assert_true(Ending.is_skippable(m))
	assert_false(Ending.is_skippable(null))


func test_coherence_restores_over_six_seconds() -> void:
	assert_approx(Ending.coherence_at(0.0, 23.0), 23.0, 0.001)
	assert_approx(Ending.coherence_at(3.0, 20.0), 60.0, 0.001, "linear")
	assert_approx(Ending.coherence_at(Tuning.COHERENCE_ENDING_RESTORE_TIME, 5.0), 100.0, 0.001)
	assert_approx(Ending.coherence_at(60.0, 5.0), 100.0, 0.001)


func test_white_cut_is_hard_unless_reduce_flashing() -> void:
	assert_approx(Ending.white_alpha(0.0, false), 1.0, 0.0001, "01 §8: a hard cut")
	assert_approx(Ending.white_alpha(0.0, true), 0.0, 0.0001, "12 §6: no two-frame white")
	assert_approx(Ending.white_alpha(Tuning.ENDING_WHITE_SOFT_FADE * 0.5, true), 0.5, 0.001)
	assert_approx(Ending.white_alpha(Tuning.ENDING_WHITE_SOFT_FADE, true), 1.0, 0.001)
	assert_gt(Tuning.ENDING_WHITE_SOFT_FADE, 2.0 / 60.0, "longer than a two-frame flash")


# --- credits (16 §6) -----------------------------------------------------------------------

func test_credits_carry_the_disclosure_and_every_license() -> void:
	var t := Credits.text()
	assert_contains(t, "an AI (Claude, Anthropic)", "00 §6, 16 §6")
	assert_eq(Strings.CREDITS_AI, "NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine.")
	for l in Strings.CREDITS_LINES:
		assert_contains(t, l)
	# The engine's MIT notice in full.
	for l in Engine.get_license_text().split("\n"):
		if not l.strip_edges().is_empty():
			assert_contains(t, l.strip_edges())
	# Every third-party component of the engine, with each of its licenses.
	var components := 0
	for info: Dictionary in Engine.get_copyright_info():
		var n := String(info["name"])
		if n == Credits.ENGINE_ENTRY:
			continue
		components += 1
		assert_contains(t, n + " · ", "component %s" % n)
		for part: Dictionary in info["parts"]:
			assert_contains(t, String(part["license"]))
	assert_gt(components, 10, "the engine's notices are listed")
	assert_eq(Credits.component_lines().size(), components)
	# The bundled font: the OFL file's copyright line.
	var ofl := FileAccess.get_file_as_string(FONT_LICENSE)
	var first := ofl.split("\n")[0]
	assert_true(first.begins_with("Copyright 2020 The JetBrains Mono Project Authors"))
	assert_contains(Strings.CREDITS_FONT_COPYRIGHT, "Copyright 2020 The JetBrains Mono Project Authors")
	assert_contains(t, "SIL Open Font License 1.1")
	assert_true(t.ends_with(Strings.CREDITS_THANKS), "the last line")


func test_credits_name_no_model() -> void:
	var re := RegEx.new()
	re.compile("(?i)\\b(opus|sonnet|haiku|claude-)")
	assert_null(re.search(Credits.text() + "\n" + "\n".join(Ending.printed_texts())),
			"the credits say an AI (Claude, Anthropic) and nothing more specific")


func test_no_forbidden_words_in_ending_text() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("(?i)" + FORBIDDEN), OK)
	for s in Ending.printed_texts():
		var m := re.search(s)
		assert_null(m, "forbidden word in the ending: %s" % (m.get_string() if m != null else ""))
	for s in [Strings.ENDING_DEPTH, Strings.ENDING_TITLE_CARD, Strings.ENDING_SKIP]:
		assert_false(s.contains("!") or s.contains("..."), "01 §6 writing rules")


func test_roll_prints_every_entry_and_finishes() -> void:
	var roll := CreditsRoll.new()
	roll.size = CreditsRoll.REFERENCE_SIZE
	add_child(roll)
	await await_frames(2)
	var printed := roll.printed_text()
	for e in Credits.entries():
		if e["style"] != Credits.STYLE_GAP:
			assert_contains(printed, String(e["text"]))
	var done: Array = []
	roll.finished.connect(func() -> void: done.append(true))
	roll.start()
	var steps := 0
	while not roll.is_finished() and steps < 100000:
		roll.advance(0.1)
		steps += 1
	assert_eq(done.size(), 1, "finished once")
	var thanks_y := roll.column.position.y + roll.thanks.position.y + roll.thanks.size.y * 0.5
	assert_approx(thanks_y, roll.size.y * 0.5, 2.0, "the last line stands at the centre")
	roll.free()


# --- the scene ----------------------------------------------------------------------------------

func test_sequence_reaches_the_summary_with_the_win() -> void:
	_won_run(0)
	var e := _ending()
	await await_frames(2)
	assert_false(e.variant)
	assert_false(e.skippable, "the first viewing")
	assert_null(e.corridor.descend_label, "no menu without the variant")
	assert_approx(e.white.color.a, 1.0, 0.001, "cut to white")
	assert_approx(e.player.coherence, 40.0, 0.5, "from the crossing's Coherence")
	assert_false(e.player.has_agency(), "held under the white")
	assert_false(e.skip(), "no skip on the first viewing")
	var phases: Array = []
	e.phase_changed.connect(func(p: StringName) -> void: phases.append(p))
	e.advance(Tuning.ENDING_WHITE_TIME + 0.01)
	assert_eq(e.phase, Ending.PHASE_FADE)
	assert_true(e.player.has_agency(), "the player can walk")
	assert_null(e.player.noclip_targeting, "no noclip in the corridor")
	e.advance(Tuning.ENDING_FADE_IN_TIME + 0.01)
	assert_eq(e.phase, Ending.PHASE_WALK)
	assert_approx(e.white.color.a, 0.0, 0.001)
	e.advance(Tuning.COHERENCE_ENDING_RESTORE_TIME)
	assert_approx(e.player.coherence, 100.0, 0.01, "01 §8: restored to 100")
	assert_approx(CoherenceRenderer.coherence01, 1.0, 0.01, "the renderer follows")
	# Walk to the window: DEPTH 0, then NOCLIP.
	e.player.global_position = e.corridor.to_global(Vector3(0.0, 0.05, e.corridor.far_z + 2.0))
	e.advance(0.01)
	assert_eq(e.phase, Ending.PHASE_CARD)
	assert_eq(e.depth_label.full_text, Strings.ENDING_DEPTH)
	e.advance(Tuning.ENDING_CARD_DELAY + 0.01)
	assert_true(e.card.visible)
	assert_eq(e.card_label.full_text, Strings.ENDING_TITLE_CARD)
	e.advance(Tuning.ENDING_CARD_HOLD)
	assert_eq(e.phase, Ending.PHASE_CREDITS)
	assert_true(e.credits.running)
	e.time_scale = 400.0
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary), "the Run Summary follows")
	assert_eq(phases, [Ending.PHASE_FADE, Ending.PHASE_WALK, Ending.PHASE_CARD, Ending.PHASE_CREDITS, Ending.PHASE_DONE])
	assert_eq(GameState.last_cause(), &"threshold")
	assert_contains(RunSummary.top_line(), "THRESHOLD CROSSED")
	assert_contains(RunSummary.unlock_lines(), "MODE UNLOCKED: ENDLESS AND CYCLE 2", "01 §8 step 4: the unlock list")


func test_card_prints_without_walking() -> void:
	_won_run(0)
	var e := _ending()
	await await_frames(1)
	e.advance(Tuning.ENDING_WHITE_TIME + 0.01)
	e.advance(Tuning.ENDING_FADE_IN_TIME + 0.01)
	e.advance(Tuning.ENDING_WALK_MAX_TIME + 0.01)
	assert_eq(e.phase, Ending.PHASE_CARD, "the sequence never waits forever")


func test_skip_after_the_first_viewing() -> void:
	_won_run(1)
	var e := _ending()
	await await_frames(1)
	assert_true(e.skippable)
	var ev := InputEventAction.new()
	ev.action = Ending.SKIP_ACTION
	ev.pressed = true
	e._unhandled_input(ev)
	assert_true(e.skip_label.visible, "the first press shows the skip line")
	assert_eq(e.skip_label.text, Strings.ENDING_SKIP.replace("{key}", UiKeys.key_name(Ending.SKIP_ACTION)))
	assert_ne(e.phase, Ending.PHASE_DONE, "one press does not skip")
	e._unhandled_input(ev)
	assert_eq(e.phase, Ending.PHASE_DONE, "the second press skips")
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary), "straight to the summary")


func test_skip_line_times_out() -> void:
	_won_run(3)
	var e := _ending()
	await await_frames(1)
	var ev := InputEventAction.new()
	ev.action = Ending.SKIP_ACTION
	ev.pressed = true
	e._unhandled_input(ev)
	e.advance(Tuning.ENDING_SKIP_CONFIRM_TIME + 0.1)
	assert_false(e.skip_label.visible)
	e._unhandled_input(ev)
	assert_ne(e.phase, Ending.PHASE_DONE, "a late second press only shows the line again")


func test_variant_menu_descends_into_the_next_run() -> void:
	_all_notes_but_u6(GameState.meta)
	GameState.meta.earn(&"note_u6")
	_won_run(0)
	var e := _ending()
	await await_frames(1)
	assert_true(e.variant)
	assert_not_null(e.corridor.descend_label, "01 §8: the title menu on the far wall")
	var texts: Array[String] = []
	for l in e.corridor.menu_labels:
		texts.append(l.text)
	assert_contains(texts, Strings.MENU_SELECTED_PREFIX + Strings.MENU_DESCEND)
	assert_contains(texts, Strings.MENU_ENDLESS, "the win has just unlocked Endless")
	assert_contains(texts, Strings.MENU_QUIT)
	assert_true(e.corridor.descend_interactable.can_interact(e.player))
	var seed_before := GameState.run.run_seed
	e.corridor.descend_interactable.interact(e.player)
	assert_true(GameState.is_run_active(), "the next Descent starts")
	assert_eq(GameState.run.mode, Tuning.MODE_DESCENT)
	assert_ne(GameState.run.run_seed, seed_before)
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is Run), "the run, not the title")
	var run := SceneRouter.current_scene() as Run
	if run != null:
		run.capture_mouse = false
		# Let depth 1 finish generating before the host is freed (the worker writes into the run).
		assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING, 60.0), "depth 1 arrives")
