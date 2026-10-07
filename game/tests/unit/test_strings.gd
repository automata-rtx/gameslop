extends TestCase
## strings.gd rules (M0.3): no forbidden words (01 §2, GLOSSARY), no exclamation marks or
## ellipses (01 §6 writing rules), HUD text is UPPERCASE (04 §2), and the caption table (04 §10)
## is complete and exact.

const FORBIDDEN := "\\b(backrooms|liminal|level 0|almond water|entity|entities|smiler|bacteria|partygoer|monster|monsters|enemy|enemies)\\b"

var _map: Dictionary = {}

func before_all() -> void:
	var script: GDScript = load("res://src/core/strings.gd")
	_map = script.get_script_constant_map()

## Flattens every string reachable from the constants: [{name, value}].
func _all_strings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in _map:
		_collect(String(name), _map[name], out)
	return out

func _collect(label: String, value: Variant, out: Array[Dictionary]) -> void:
	if value is String or value is StringName:
		out.append({"name": label, "value": String(value)})
	elif value is Array:
		for i in (value as Array).size():
			_collect("%s[%d]" % [label, i], (value as Array)[i], out)
	elif value is Dictionary:
		for k in (value as Dictionary):
			_collect("%s[%s]" % [label, k], (value as Dictionary)[k], out)

func test_collects_a_large_string_set() -> void:
	assert_gt(_all_strings().size(), 300, "Strings should cover every UI string")

func test_no_forbidden_words() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("(?i)" + FORBIDDEN), OK)
	for entry in _all_strings():
		var m := re.search(entry["value"])
		if m != null:
			fail("Strings.%s contains forbidden word '%s'" % [entry["name"], m.get_string()])

func test_forbidden_regex_catches_and_spares() -> void:
	var re := RegEx.new()
	re.compile("(?i)" + FORBIDDEN)
	assert_not_null(re.search("An ENTITY in the Backrooms"))
	assert_not_null(re.search("almond water"))
	assert_null(re.search("IDENTITY"), "a word boundary keeps 'identity' legal")
	assert_null(re.search("DEPTH 03"))

func test_writing_rules() -> void:
	# Deliberate whitespace: the "mid distance" caption fragment is empty, the menu prefix has a trailing space.
	var spacing_exempt := ["CAPTION_DIST_MID", "MENU_SELECTED_PREFIX"]
	for entry in _all_strings():
		var s: String = entry["value"]
		var n: String = entry["name"]
		assert_false(s.contains("!"), "%s has an exclamation mark" % n)
		assert_false(s.contains("…"), "%s has an ellipsis" % n)
		assert_false(s.contains("..."), "%s has an ellipsis" % n)
		if n in spacing_exempt:
			continue
		assert_false(s.is_empty(), "%s is empty" % n)
		assert_eq(s, s.strip_edges(), "%s has stray edge spacing" % n)
		assert_false(s.contains("  "), "%s has a double space" % n)

func test_braces_are_balanced() -> void:
	for entry in _all_strings():
		var s: String = entry["value"]
		assert_eq(s.count("{"), s.count("}"), "%s has unbalanced braces" % entry["name"])

func test_hud_text_is_uppercase() -> void:
	var braces := RegEx.new()
	braces.compile("\\{[a-z_0-9]+\\}")
	for name in _map:
		var n := String(name)
		if not (n.begins_with("HUD_") or n.begins_with("MENU_") or n.begins_with("PROMPT_") or n.begins_with("HINT_") or n.begins_with("SUMMARY_") or n.begins_with("MSG_")):
			continue
		if not (_map[name] is String):
			continue
		var s: String = braces.sub(_map[name], "", true)
		assert_eq(s, s.to_upper(), "%s should be UPPERCASE" % n)

func test_all_captions_from_04_exist() -> void:
	var expected: Dictionary = {
		"CAPTION_STATIC": "[hum, {dir}{dist}]",
		"CAPTION_STILL_SILENCE": "[silence]",
		"CAPTION_STILL_TICK": "[a line]",
		"CAPTION_FLICKER_PRESENT": "[lights stutter, {dir}{dist}]",
		"CAPTION_FLICKER_JUMP": "[sparks, {dir}]",
		"CAPTION_FLICKER_LUNGE": "[flash]",
		"CAPTION_ECHO_FOOTSTEP": "[footsteps, {dir}, late]",
		"CAPTION_NULL": "[grid tone, {dir}{dist}]",
		"CAPTION_DOOR_SLAM": "[door slams, {dir}{dist}]",
		"CAPTION_PAYPHONE": "[phone rings, {dir}{dist}]",
		"CAPTION_BREAKER": "[breaker thrown]",
		"CAPTION_POWER_WAVE": "[lights waking]",
		"CAPTION_NOCLIP_COMMIT": "[tear]",
		"CAPTION_CONTACT": "[contact]",
	}
	assert_eq(expected.size(), 14, "04 §10 lists 14 captions")
	for key in expected:
		assert_contains(_map, key)
		if _map.has(key):
			assert_eq(_map[key], expected[key], key)
	assert_eq((_map["CAPTION_DIRECTIONS"] as Array).size(), 8, "8 sectors")

func test_hud_strings() -> void:
	assert_eq(_map["HUD_COHERENCE"], "COHERENCE")
	assert_eq(_map["HUD_DEPTH_LINE"], "DEPTH {depth} · {stratum}")
	assert_eq(_map["HUD_EXIT_UNKNOWN"], "EXIT: UNKNOWN")
	assert_eq(_map["HUD_EXIT_POWERED"], "EXIT: POWERED")
	assert_eq(_map["HUD_EXIT_KEYED"], "EXIT: KEYED")
	assert_eq(_map["HUD_EXIT_SEALED"], "EXIT: SEALED {time}")
	assert_eq(_map["MSG_DESCENDING"], "DESCENDING")
	assert_eq(_map["MSG_DROPPED"], "DROPPED · THEY ARE AWAKE")
	assert_eq(_map["MSG_COHERENCE_GAIN"], "COHERENCE +{amount}")
	assert_eq(_map["MSG_ARCHIVE_NOTE"], "ARCHIVE: NOTE {id}")
	assert_eq(_map["MSG_ITEM_UNLOCKED"], "ITEM UNLOCKED: {name}")
	assert_eq(_map["MSG_LOADOUT_UNLOCKED"], "LOADOUT UNLOCKED: {name}")
	var reasons: Dictionary = _map["NOCLIP_REASONS"]
	for r in ["SOLID", "NO SPACE", "TOO FAR", "TOO THIN"]:
		assert_contains(reasons, StringName(r))

func test_menu_strings() -> void:
	assert_eq(_map["MENU_DESCEND"], "DESCEND")
	assert_eq(_map["MENU_DAILY"], "DAILY DESCENT")
	assert_eq(_map["MENU_ENDLESS"], "ENDLESS")
	assert_eq(_map["MENU_ARCHIVE"], "ARCHIVE")
	assert_eq(_map["MENU_SETTINGS"], "SETTINGS")
	assert_eq(_map["MENU_QUIT"], "QUIT")
	assert_eq(_map["PAUSE_ABANDON"], "ABANDON DESCENT")
	assert_eq(_map["PAUSE_QUIT_TITLE"], "QUIT TO TITLE")
	assert_eq(_map["PAUSE_ABANDON_CONFIRM"], "This ends the run. Depth and notes found are kept.")
	assert_eq(_map["SETTINGS_TABS"], ["DISPLAY", "GRAPHICS", "AUDIO", "CONTROLS", "ACCESSIBILITY", "GAMEPLAY"])
	assert_eq(_map["TITLE_VERSION_LINE"].replace("{version}", "1.0.0").replace("{seed}", "20261007"), "v1.0.0 · MADE BY AN AI · SEED OF THE DAY 20261007")

func test_prompts_and_hints() -> void:
	assert_eq(_map["PROMPT_PRESS"].replace("{key}", "E").replace("{text}", _map["PROMPT_OPEN_DOOR"]), "[E] OPEN DOOR")
	assert_eq(_map["PROMPT_HOLD"].replace("{key}", "E").replace("{text}", _map["PROMPT_LEAVE_HIDING"]), "[HOLD E] LEAVE HIDING")
	assert_eq(_map["PROMPT_PICK_UP"].replace("{item}", "POLAROID"), "PICK UP POLAROID")
	assert_eq((_map["HINTS_IN_ORDER"] as Array).size(), 7, "04 §9 lists 7 hints")
	assert_eq(_map["HINT_COHERENCE"], "COHERENCE IS HOW REAL YOU ARE")
	var moved: String = _map["HINT_MOVE"]
	for a in ["move_forward", "move_left", "move_back", "move_right"]:
		moved = moved.replace("{%s}" % a, "X")
	assert_false(moved.contains("{"), "hint 1 names only the four move actions")

func test_summary_and_causes() -> void:
	var causes: Dictionary = _map["CAUSE_LINES"]
	for id in [&"static", &"still", &"flicker", &"echo", &"null", &"substrate"]:
		assert_contains(causes, id)
	assert_eq(causes[&"still"], "DISSOLVED BY STILL")
	assert_eq(causes[&"substrate"], "DISSOLVED BY THE SUBSTRATE")
	assert_eq(_map["SUMMARY_WIN_LINE"].replace("{depth}", "06"), "THRESHOLD CROSSED · DEPTH 06")
	assert_eq(_map["SUMMARY_TOP_LINE"].replace("{cause}", causes[&"still"]).replace("{depth}", "03").replace("{stratum}", "GARAGE"), "DISSOLVED BY STILL · DEPTH 03 · GARAGE")
	assert_eq(_map["SUMMARY_DESCEND_AGAIN"], "DESCEND AGAIN")
	for key in ["SUMMARY_LINE_DEPTH", "SUMMARY_LINE_TIME", "SUMMARY_LINE_COHERENCE_SPENT", "SUMMARY_LINE_WALLS_PASSED",
			"SUMMARY_LINE_FLOORS_DROPPED", "SUMMARY_LINE_NOTES_FOUND", "SUMMARY_LINE_ERRORS_EVADED", "SUMMARY_LINE_SCORE", "SUMMARY_LINE_BEST"]:
		assert_contains(_map, key)

func test_errors_strata_items_loadouts_unlocks() -> void:
	var errors: Dictionary = _map["ERROR_NAMES"]
	var codex: Dictionary = _map["ERROR_CODEX"]
	for id in [&"static", &"still", &"flicker", &"echo", &"null"]:
		assert_contains(errors, id)
		assert_contains(codex, id)
		assert_true((codex[id] as String).begins_with("RENDER NOTE."), "%s codex is a builder memo" % id)
	assert_eq((_map["STRATUM_NAMES"] as Dictionary).size(), 6)
	for kind in [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse"]:
		assert_contains(_map["ITEM_NAMES"], kind)
	assert_eq((_map["LOADOUT_NAMES"] as Dictionary).size(), 4)
	assert_eq((_map["LOADOUT_DESCRIPTIONS"] as Dictionary).size(), 4)
	var ids: Array = load("res://src/core/tuning.gd").get_script_constant_map()["UNLOCK_IDS"]
	assert_eq(ids.size(), 14)
	for id in ids:
		assert_contains(_map["UNLOCK_NAMES"], id)
		assert_contains(_map["UNLOCK_DESCRIPTIONS"], id)
	assert_eq((_map["UNLOCK_NAMES"] as Dictionary).size(), 14)

func test_settings_labels_cover_every_tab() -> void:
	var labels: Dictionary = _map["SETTING_LABELS"]
	var descriptions: Dictionary = _map["SETTING_DESCRIPTIONS"]
	assert_gt(labels.size(), 40)
	for key in labels:
		assert_contains(descriptions, key)
	for key in descriptions:
		assert_contains(labels, key)
	# Every action in 06 §2 has a rebind row label.
	var actions: Array = load("res://src/core/tuning.gd").get_script_constant_map()["INPUT_ACTIONS"]
	for a in actions:
		assert_contains(_map["ACTION_LABELS"], a)

func test_credits() -> void:
	assert_eq(_map["CREDITS_AI"], "NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine.")
	assert_eq(_map["CREDITS_THANKS"], "Thank you for looking.")
	assert_eq(_map["ENDING_DEPTH"], "DEPTH 0")
