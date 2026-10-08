extends TestCase
## The Feedback Contract bench's pure parts (11 §7): the row table, its coverage of the
## contract document, the spy's change detection and the bench's evaluation filter. The
## sequence itself runs in sim/test_feedback_bench.gd.

const CONTRACT := "res://../docs/design/11_feedback_contract.md"
## Contract table row (first column, trimmed) -> the FeedbackRows ids that cover it.
const COVERAGE: Dictionary = {
	"Walk step": [&"walk_step"],
	"Sprint start / stop": [&"sprint_start", &"sprint_stop"],
	"Stamina empty": [&"stamina_empty"],
	"Crouch / stand": [&"crouch", &"stand"],
	"Flashlight on / off": [&"flashlight_on", &"flashlight_off"],
	"Crank (hold)": [&"crank"],
	"Crank full": [&"crank_full"],
	"Interact press": [&"interact_press"],
	"Interact hold": [&"interact_hold"],
	"Item select": [&"item_select"],
	"Item use (each)": [&"item_polaroid", &"item_glowstick", &"item_flare", &"item_radio"],
	"Noclip charge": [&"noclip_charge"],
	"Noclip cancel": [&"noclip_cancel"],
	"Noclip commit (wall)": [&"noclip_commit_wall"],
	"Noclip commit (floor)": [&"noclip_commit_floor"],
	"Noclip invalid": [&"noclip_invalid"],
	"Chalk stamp": [&"chalk_stamp"],
	"Enter hide spot": [&"hide_enter"],
	"Leave hide spot": [&"hide_leave"],
	"Coherence loss (any)": [&"coherence_loss"],
	"Coherence gain": [&"coherence_gain"],
	"Error contact": [&"error_contact"],
	"Inside Static": [&"inside_static"],
	"Still within 8 m": [&"still_within_8m"],
	"Still observed ≥ 2 s": [&"still_observed"],
	"Flicker lunge": [&"flicker_lunge"],
	"Echo at 4 m": [&"echo_4m"],
	"Null radius": [&"null_radius"],
	"Null core": [&"null_core"],
	"Exit seen": [&"exit_seen"],
	"Exit unlocked": [&"exit_unlocked"],
	"Enter exit": [&"enter_exit"],
	"Landing": [&"landing"],
	"Arrival (proper)": [&"arrival_proper"],
	"Arrival (drop)": [&"arrival_drop"],
	"Note found": [&"note_found"],
	"Unlock earned": [&"unlock_earned"],
	"Breaker thrown by player": [&"breaker"],
	"Dissolve": [&"dissolve"],
	"Threshold crossed": [&"threshold"],
}


func test_ids_are_unique_and_every_listed_channel_is_valid() -> void:
	var seen: Dictionary = {}
	for r in FeedbackRows.all():
		assert_false(seen.has(r[&"id"]), "duplicate id %s" % r[&"id"])
		seen[r[&"id"]] = true
		for ch in String(r[&"listed"]):
			assert_contains("ISMR", ch, "%s lists %s" % [r[&"id"], ch])
		assert_eq(int(r[&"min"]), mini(3, String(r[&"listed"]).length()), String(r[&"id"]))
		assert_gt(int(r[&"window"]), 0)


func test_every_active_row_has_a_recipe_and_every_pending_row_a_reason() -> void:
	var recipes := FeedbackRecipes.new()
	for r in FeedbackRows.all():
		if r[&"status"] == FeedbackRows.PENDING:
			assert_false(String(r[&"reason"]).is_empty(), "%s pending without a reason" % r[&"id"])
		else:
			assert_true(recipes.has_method(r[&"id"]), "no recipe for %s" % r[&"id"])
		if r[&"status"] == FeedbackRows.GAP:
			assert_false(String(r[&"reason"]).is_empty(), "%s gap without a reason" % r[&"id"])
		for ch: StringName in r[&"expect"]:
			assert_contains(String(r[&"listed"]), String(ch), "%s expects an unlisted channel" % r[&"id"])


## A row added to or renamed in 11 §2/§3 has to be covered by the bench (or the map above).
func test_the_contract_document_is_covered() -> void:
	var path := ProjectSettings.globalize_path(CONTRACT).simplify_path()
	if not FileAccess.file_exists(path):
		return  # an exported build has no docs
	var ids: Dictionary = {}
	for r in FeedbackRows.all():
		ids[r[&"id"]] = true
	var names: Array[String] = []
	var in_tables := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("## 2.") or line.begins_with("## 3."):
			in_tables = true
		elif line.begins_with("## ") and in_tables and not (line.begins_with("## 2.") or line.begins_with("## 3.")):
			in_tables = false
		if not in_tables or not line.begins_with("| "):
			continue
		var cells := line.split("|", false)
		var first := cells[0].strip_edges()
		if first == "Action" or first == "Event" or first.begins_with("---"):
			continue
		names.append(first)
	assert_gt(names.size(), 35, "parsed the contract tables")
	for n in names:
		assert_true(COVERAGE.has(n), "contract row '%s' is not mapped to bench rows" % n)
		for id: StringName in COVERAGE.get(n, []):
			assert_true(ids.has(id), "'%s' maps to missing row %s" % [n, id])
	for n: String in COVERAGE:
		assert_contains(names, n, "COVERAGE names a row the contract no longer has")


func test_spy_change_detection() -> void:
	assert_false(FeedbackSpy.differs(1.0, 1.00001))
	assert_true(FeedbackSpy.differs(1.0, 1.01))
	assert_true(FeedbackSpy.differs(Vector3.ZERO, Vector3.RIGHT))
	assert_false(FeedbackSpy.differs(Vector3.ONE, Vector3.ONE))
	assert_true(FeedbackSpy.differs(1, 1.0), "a type change is a change")
	assert_true(FeedbackSpy.differs("a", "b"))
	assert_false(FeedbackSpy.differs(true, true))


func test_noisy_keys_need_repeated_changes() -> void:
	var spy := FeedbackSpy.new()
	for i in 6:
		var changed := {}
		for ch in FeedbackSpy.CHANNELS:
			changed[ch] = PackedStringArray(["steady", "tween"] if i < 4 else (["blip"] if i == 5 else []))
		spy.entries.append({&"frame": i, &"tick": i, &"usec": i, &"changed": changed})
	var noisy := spy.noisy_keys(6, &"I")
	assert_true(noisy.has("steady"), "changed in 4 frames")
	assert_false(noisy.has("blip"), "one change is a reaction, not noise")


func test_evaluation_filter_honours_expect_and_noise() -> void:
	var changed := PackedStringArray(["play.crouch", "Frame/Dimmable/CrankShutter/Crank/Percent.text", "loop.x.on"])
	var noisy := {"loop.x.on": true}
	assert_eq(FeedbackBench._accepted(changed, noisy, []).size(), 2, "noise dropped, anything else counts")
	var only := FeedbackBench._accepted(changed, noisy, ["play.crouch"])
	assert_eq(only.size(), 1)
	assert_eq(only[0], "play.crouch")
	assert_eq(FeedbackBench._accepted(changed, {}, ["Caption"]).size(), 0, "a coincidence never passes")


func test_a_result_counts_only_channels_inside_the_budget() -> void:
	var bench := FeedbackBench.new()
	var row := FeedbackRows.find(&"flashlight_on")
	var late := Tuning.FEEDBACK_MAX_LATENCY_FRAMES + 1
	var res := bench._result_for(row, {
		&"I": {&"ticks": 1, &"frames": 1, &"ms": 10.0, &"key": "a", &"keys": 1},
		&"S": {&"ticks": 3, &"frames": 3, &"ms": 40.0, &"key": "b", &"keys": 1},
		&"M": {&"ticks": late, &"frames": late, &"ms": 80.0, &"key": "c", &"keys": 1},
	})
	assert_eq(res[&"fired"], 2, "the channel at %d ticks, %d frames and 80 ms is late" % [late, late])
	assert_false(res[&"ok"], "two of the required three")
	assert_eq(res[&"late"], ["M"])
	assert_eq(res[&"missing"], ["R"])
	bench.free()


## Ticks bunch up after a stall and headless frames are not 60 fps: any one measure inside
## the budget is on time; all three outside is late.
func test_latency_is_late_only_by_all_three_measures() -> void:
	assert_true(FeedbackBench.within({&"ticks": 7, &"frames": 1, &"ms": 11.0}), "a catch-up of ticks in one frame")
	assert_true(FeedbackBench.within({&"ticks": 7, &"frames": 9, &"ms": 30.0}), "many fast frames, 30 ms")
	assert_true(FeedbackBench.within({&"ticks": 2, &"frames": 40, &"ms": 400.0}), "a stalled machine, 2 ticks")
	assert_false(FeedbackBench.within({&"ticks": 8, &"frames": 8, &"ms": 120.0}))
