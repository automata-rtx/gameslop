extends TestCase
## M2.16: the title's small public text helpers (04 §7, 13 §3) and the rule that every way a
## run can end explains itself (00 §5: death explains itself on the summary screen).

var _saved_last_run: Dictionary = {}


func before_each() -> void:
	_saved_last_run = GameState.meta.last_run.duplicate(true)


func after_each() -> void:
	GameState.meta.last_run = _saved_last_run


func test_every_death_cause_has_a_summary_line_and_an_explanation() -> void:
	for cause in MetaSchema.DEATH_CAUSES:
		var id := StringName(cause)
		assert_true(Strings.CAUSE_LINES.has(id), "%s has a top line" % cause)
		assert_true(Strings.CAUSE_EXPLANATIONS.has(id), "%s has an explanation" % cause)
		assert_false(String(Strings.CAUSE_EXPLANATIONS.get(id, "")).is_empty())
	for id: StringName in [&"threshold", &"abandoned"]:
		assert_true(Strings.CAUSE_LINES.has(id), "the non-death ends too: %s" % id)


func test_last_cause_text_reads_the_last_run() -> void:
	GameState.meta.last_run = {}
	assert_eq(TitlePage.last_cause_text(), Strings.TITLE_VALUE_NONE, "no run yet")
	for id: StringName in Strings.CAUSE_LINES:
		GameState.meta.last_run = {"cause": String(id), "depth": 2}
		assert_eq(TitlePage.last_cause_text(), Strings.CAUSE_LINES[id])
	GameState.meta.last_run = {"cause": "mystery"}
	assert_eq(TitlePage.last_cause_text(), "MYSTERY", "an unknown cause is shown, not hidden")


func test_daily_result_and_version_lines() -> void:
	var t := TitlePage.daily_result_text({"score": 12345, "depth": 4})
	assert_eq(t, "SCORE 12,345 · DEPTH 4")
	assert_eq(TitlePage.daily_result_text({}), "SCORE 0 · DEPTH 1", "a malformed entry still prints")
	var v := Title.version_line()
	assert_true(v.contains("v" + Version.VERSION))
	assert_true(v.contains(GameState.today_key()))
	assert_true(v.contains("MADE BY AN AI"), "the store page and the title say who made it (00 §6)")


func test_score_formatting() -> void:
	assert_eq(RunSummary.format_score(0), "0")
	assert_eq(RunSummary.format_score(999), "999")
	assert_eq(RunSummary.format_score(1000), "1,000")
	assert_eq(RunSummary.format_score(1234567), "1,234,567")
	assert_eq(RunSummary.format_score(-4500), "-4,500")
