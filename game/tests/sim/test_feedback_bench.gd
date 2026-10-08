extends TestCase
## 11 §7: the Feedback Contract bench fires every implemented row of 11 §2 and §3 in a real
## Descent (Run, HUD, level, exit, breaker, Landing, dissolve) and asserts each reacts on at
## least min(3, listed) channels within three physics ticks (50 ms at 60 fps). Rows for
## features that do not exist yet are listed as pending; rows with a known missing channel
## are `gap` rows: reported and pinned (when the game closes one this test says so).
## About two minutes: the rows run in real time and three levels are built.

var _bench: FeedbackBench
var _results: Array = []


func before_all() -> void:
	_bench = FeedbackBench.new()
	_bench.name = "FeedbackBench"
	_bench.autostart = false
	add_child(_bench)
	await _bench.start()
	_results = await _bench.run_all()


func after_all() -> void:
	_bench.queue_free()
	await await_frames(3)


func _row(id: StringName) -> Dictionary:
	for r in _results:
		if r[&"id"] == id:
			return r
	return {}


func test_every_row_of_the_table_ran_or_is_pending() -> void:
	assert_eq(_results.size(), FeedbackRows.all().size())
	for row in FeedbackRows.all():
		assert_false(_row(row[&"id"]).is_empty(), "no result for %s" % row[&"id"])


func test_every_implemented_row_reacts_on_enough_channels_within_50_ms() -> void:
	var bad: PackedStringArray = []
	for r in _results:
		if r[&"status"] == FeedbackRows.IMPLEMENTED and not r[&"ok"]:
			bad.append(FeedbackBench.format_line(r))
	assert_eq(bad.size(), 0, "rows below their channel count:\n" + "\n".join(bad))


func test_gap_rows_still_have_their_gap() -> void:
	for r in _results:
		if r[&"status"] == FeedbackRows.GAP:
			assert_false(r[&"ok"], "%s now passes: promote it to IMPLEMENTED in feedback_rows.gd" % r[&"id"])


func test_pending_rows_are_the_unbuilt_features_only() -> void:
	var ids: Array = []
	for r in _results:
		if r[&"status"] == FeedbackRows.PENDING:
			ids.append(r[&"id"])
	for id in [&"flicker_lunge", &"null_radius", &"null_core", &"item_flare", &"item_radio", &"threshold"]:
		assert_contains(ids, id)
	assert_eq(ids.size(), 6)


## The sparse rows stay as sparse as the table: they are held to their own count, not lowered.
func test_sparse_rows_keep_their_own_minimum() -> void:
	for id in [&"still_observed", &"unlock_earned", &"still_within_8m"]:
		assert_eq(int(_row(id)[&"min"]), 2, String(id))
	assert_eq(int(_row(&"walk_step")[&"min"]), 3)
	assert_eq(int(_row(&"crouch")[&"min"]), 3, "R11: crouch / stand gained the held-light dip")


## Feedback that lies is forbidden (11 §6): a row that fires the sound it names, not just
## something nearby. Spot-check the sound of the noisiest rows.
func test_rows_fire_their_own_sound() -> void:
	for id in [&"noclip_commit_wall", &"coherence_gain", &"error_contact", &"arrival_drop", &"dissolve"]:
		var r := _row(id)
		var s: Dictionary = (r[&"channels"] as Dictionary).get(&"S", {})
		assert_false(s.is_empty(), "%s has a sound" % id)
		if not s.is_empty():
			assert_true(String(s[&"key"]).begins_with("play."), "%s: %s" % [id, s[&"key"]])


## R11 #5/#11 determinism: only listed channels are credited, and a gap or sparse row never
## even reports an unlisted one, so a coincidence cannot change a row's result.
func test_only_listed_channels_are_credited() -> void:
	for r in _results:
		if r[&"status"] == FeedbackRows.PENDING:
			continue
		assert_true(int(r[&"fired"]) <= String(r[&"listed"]).length(), "%s fired beyond its listed channels" % r[&"id"])
		for ch: StringName in (r[&"channels"] as Dictionary):
			if not String(r[&"listed"]).contains(String(ch)):
				assert_false(FeedbackBench.is_strict(FeedbackRows.find(r[&"id"])),
						"%s (gap or sparse) reported unlisted %s" % [r[&"id"], ch])
