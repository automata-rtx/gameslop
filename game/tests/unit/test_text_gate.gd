extends TestCase
## M3.7: the text gate. One scan of every player-facing string for 01 §2's forbidden words, the
## punctuation rules of 01 §6 / 04, and model names (16 §6). The gate is proved by a planted
## fixture (tests/fixtures/text_gate_planted*.txt), never by the shipped files.

const Gate := preload("res://tests/text_gate.gd")
const PLANTED := "res://tests/fixtures/text_gate_planted.txt"
const PLANTED_CODE := "res://tests/fixtures/text_gate_planted_code.txt"
const PLANTED_STORE := "res://tests/fixtures/text_gate_planted_store.txt"

var _ui: Array[Dictionary] = []
var _map: Dictionary = {}


func before_all() -> void:
	_ui = Gate.ui_corpus()
	_map = (load("res://src/core/strings.gd") as GDScript).get_script_constant_map()


func _planted(tag: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for line in FileAccess.get_file_as_string(PLANTED).split("\n"):
		if line.begins_with("[%s] " % tag):
			out.append(line.substr(tag.length() + 3))
	return out


func _le(actual: int, bound: int, msg: String) -> void:
	assert_true(actual <= bound, "%s (%d > %d)" % [msg, actual, bound])


# ------------------------------------------------------------------- the gate fires

func test_fixture_exists() -> void:
	assert_gt(FileAccess.get_file_as_string(PLANTED).length(), 100, "fixture present")
	assert_gt(FileAccess.get_file_as_string(PLANTED_CODE).length(), 50, "code fixture present")


func test_forbidden_words_fire_on_the_planted_lines() -> void:
	var seen: Array[String] = []
	for line in _planted("forbidden"):
		for w in Gate.forbidden_hits(line):
			seen.append(w)
	for w in ["entity", "backrooms", "almond water", "smiler", "partygoer", "bacteria", "monster", "enemy",
			"level 0", "entities", "enemies"]:
		assert_contains(seen, w, "the gate catches '%s'" % w)


func test_forbidden_words_spare_legal_neighbours() -> void:
	for line in _planted("clean"):
		assert_eq(Gate.forbidden_hits(line).size(), 0, line)
	assert_eq(Gate.forbidden_hits("IDENTITY, LEVEL 03, a monstrous idea").size(), 0, "word boundaries")


func test_store_page_may_say_liminal_only() -> void:
	assert_eq(Gate.forbidden_hits("Descend through generated liminal floors", true).size(), 0)
	assert_eq(Gate.forbidden_hits("Descend through generated liminal floors", false).size(), 1)
	assert_eq(Gate.forbidden_hits("The Backrooms, liminal", true).size(), 1, "other words stay banned")


func test_style_rules_fire_on_the_planted_lines() -> void:
	var kinds: Array[String] = []
	for line in _planted("style"):
		var hits := Gate.style_hits(line)
		assert_gt(hits.size(), 0, "caught: " + line)
		for h in hits:
			kinds.append(h)
	for k in ["exclamation mark", "ellipsis", "double space"]:
		assert_contains(kinds, k)
	assert_eq(Gate.style_hits("!").size(), 0, "the single-glyph danger mark (12 §6) is not a sentence")
	assert_eq(Gate.style_hits("COHERENCE 087 · DEPTH 03").size(), 0)


func test_model_names_fire() -> void:
	for line in _planted("model"):
		assert_gt(Gate.model_hits(line).size(), 0, "caught: " + line)
	for line in _planted("clean"):
		assert_eq(Gate.model_hits(line).size(), 0, line)
	assert_eq(Gate.model_hits("designed and built by an AI (Claude, Anthropic) using the Godot Engine").size(), 0)
	assert_gt(Gate.model_hits("built by Claude").size(), 0, "Claude outside the one phrase")


func test_code_literal_scanner_reads_literals_not_comments() -> void:
	var lits := Gate.code_literals(FileAccess.get_file_as_string(PLANTED_CODE))
	var texts: Array[String] = []
	for l in lits:
		texts.append(l["text"])
	assert_eq(texts.size(), 4, "four literals, no comment text: %s" % [texts])
	assert_contains(texts, "An entity waits!")
	assert_contains(texts, "Wait... here")
	assert_contains(texts, "!")
	var hits := 0
	for t in texts:
		hits += Gate.forbidden_hits(t).size() + Gate.style_hits(t).size()
	assert_eq(hits, 3, "entity, the exclamation mark, the ellipsis (the lone '!' mark and the comments pass)")


func test_store_scope_extraction() -> void:
	var doc := "## 4. Other\nx\n## 5. Store page facts (for the human)\nTitle: NOCLIP\n## 6. Credits\ny"
	var s := Gate.store_page_facts(doc)
	assert_contains(s, "NOCLIP")
	assert_false(s.contains("Credits"))
	assert_eq(Gate.store_page_facts("nothing"), "")


func test_store_page_rules_fire_on_the_planted_page() -> void:
	var lines := FileAccess.get_file_as_string(PLANTED_STORE).split("\n")
	var pages := 0
	var cleans := 0
	for line in lines:
		if line.begins_with("[page] "):
			pages += 1
			assert_gt(Gate.store_hits(line.substr(7)).size(), 0, "caught: " + line)
		elif line.begins_with("[clean] "):
			cleans += 1
			assert_eq(Gate.store_hits(line.substr(8)).size(), 0, line)
	assert_eq(pages, 5, "five planted store lines")
	assert_eq(cleans, 2, "two clean store lines (liminal and the AI phrase pass)")
	var all := "\n".join(lines)
	var hits := ",".join(Gate.store_hits(all))
	for expect in ["entity", "backrooms", "ellipsis", "exclamation mark", "Claude outside the AI phrase"]:
		assert_true(hits.contains(expect), "the planted page trips '%s': %s" % [expect, hits])


func test_store_page_is_in_the_scanned_corpus_and_clean() -> void:
	var found := false
	for f in Gate.file_corpus():
		if f["src"] == "store_page.md":
			found = true
			assert_eq(f["kind"], "store")
			var hits := Gate.store_hits(f["text"])
			assert_eq(hits.size(), 0, "store_page.md: %s" % [hits])
	assert_true(found, "docs/release/store_page.md is scanned by the gate")


# ------------------------------------------------------------------- the shipped text is clean

func test_corpus_is_complete() -> void:
	var by_src: Dictionary = {}
	for e in _ui:
		by_src[String(e["src"]).get_slice(" ", 0).get_slice(".", 0).get_slice("[", 0)] = true
	for key in ["Strings", "note", "error", "item", "loadout", "stratum", "credits", "ending"]:
		assert_contains(by_src, key)
	var notes := 0
	for e in _ui:
		if String(e["src"]).begins_with("note "):
			notes += 1
	assert_eq(notes, 36, "all 36 notes")
	assert_gt(_ui.size(), 500)
	for f in Gate.file_corpus():
		assert_ne(f["kind"], "missing", "%s is readable" % f["src"])
		assert_gt(String(f["text"]).length(), 200, f["src"])


func test_no_forbidden_words_in_player_facing_text() -> void:
	for e in _ui:
		for w in Gate.forbidden_hits(e["text"]):
			fail("%s contains forbidden word '%s'" % [e["src"], w])
	for f in Gate.file_corpus():
		for w in Gate.forbidden_hits(f["text"], f["kind"] == "store"):
			fail("%s contains forbidden word '%s'" % [f["src"], w])


func test_no_forbidden_words_in_code_scenes_and_data() -> void:
	# Text built in code, scene labels, resource fields: every string literal, comments excluded.
	var scanned := 0
	for path in Gate.shipped_files(["gd", "tscn", "tres"]):
		for l in Gate.code_literals(FileAccess.get_file_as_string(path)):
			scanned += 1
			for w in Gate.forbidden_hits(l["text"]):
				fail("%s:%d literal contains forbidden word '%s'" % [path, l["line"], w])
	assert_gt(scanned, 1000, "the scanner reached the literals")


func test_punctuation_rules_in_player_facing_text() -> void:
	# CAPTION_DIST_MID and MENU_SELECTED_PREFIX are deliberate whitespace.
	var spacing_exempt := ["Strings.CAPTION_DIST_MID", "Strings.MENU_SELECTED_PREFIX"]
	for e in _ui:
		var spacing: bool = not (e["src"] in spacing_exempt)
		for h in Gate.style_hits(e["text"], spacing):
			fail("%s has an %s: %s" % [e["src"], h, String(e["text"]).left(60)])
	for f in Gate.file_corpus():
		for h in Gate.style_hits(f["text"], false):
			fail("%s has an %s" % [f["src"], h])


func test_punctuation_rules_in_code_literals() -> void:
	# A literal built in code that reads as a sentence must obey 01 §6 (debug benches excluded).
	for path in Gate.shipped_files(["gd"]):
		if path.contains("/debug/") or path.ends_with("/strings.gd"):
			continue
		for l in Gate.code_literals(FileAccess.get_file_as_string(path)):
			for h in Gate.style_hits(l["text"], false):
				fail("%s:%d literal has an %s: %s" % [path, l["line"], h, l["text"]])


func test_scene_text_properties_obey_the_rules() -> void:
	var re := RegEx.create_from_string("(?m)^(text|title|tooltip_text|placeholder_text) = \"((?:[^\"\\\\]|\\\\.)*)\"")
	for path in Gate.shipped_files(["tscn", "tres"]):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var t := m.get_string(2)
			assert_eq(Gate.forbidden_hits(t).size(), 0, "%s: %s" % [path, t])
			assert_eq(Gate.style_hits(t, false).size(), 0, "%s: %s" % [path, t])


# ------------------------------------------------------------------- model names and the credits

func test_no_model_identifier_in_anything_that_ships() -> void:
	for e in _ui:
		for h in Gate.model_hits(e["text"]):
			fail("%s: %s" % [e["src"], h])
	for f in Gate.file_corpus():
		for h in Gate.model_hits(f["text"]):
			fail("%s: %s" % [f["src"], h])
	for path in Gate.shipped_files(["gd", "tscn", "tres"]):
		for l in Gate.code_literals(FileAccess.get_file_as_string(path)):
			for h in Gate.model_hits(l["text"]):
				fail("%s:%d literal: %s" % [path, l["line"], h])
	# Project metadata and the export presets ship too.
	for path in ["res://project.godot", "res://export_presets.cfg"]:
		for h in Gate.model_hits(FileAccess.get_file_as_string(path)):
			fail("%s: %s" % [path, h])


func test_credits_match_16_section_6() -> void:
	var lines := PackedStringArray()
	for e in Credits.entries():
		if String(e["text"]) != "":
			lines.append(String(e["text"]))
	assert_eq(lines[0], "NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine.", "the AI line, verbatim, first")
	assert_eq(lines[lines.size() - 1], "Thank you for looking.", "the last line")
	var roll := Credits.roll_text()
	assert_contains(roll, "Godot Engine. MIT license.")
	assert_contains(roll, "SIL Open Font License 1.1")
	assert_contains(roll, "Copyright 2020 The JetBrains Mono Project Authors")
	var all := Credits.text()
	assert_eq(all.count("Claude"), 1, "Claude is named once")
	assert_eq(all.count("Anthropic"), 1, "Anthropic is named once")
	assert_eq(Gate.model_hits(all).size(), 0)
	assert_eq(Gate.model_hits(roll).size(), 0)
	assert_eq(Gate.forbidden_hits(all).size(), 0)


func test_readme_discloses_the_ai_with_the_same_phrase() -> void:
	var readme := ""
	for f in Gate.file_corpus():
		if f["src"] == "README.txt.in":
			readme = f["text"]
	assert_contains(readme, Gate.AI_PHRASE)
	assert_contains(readme, "That is the experiment.")


# ------------------------------------------------------------------- strings review rules

func test_descriptions_are_sentence_case_and_end_with_a_period() -> void:
	var tables := ["SETTING_DESCRIPTIONS", "LOADOUT_DESCRIPTIONS", "LOADOUT_UNLOCK_CONDITIONS",
			"UNLOCK_DESCRIPTIONS", "CAUSE_EXPLANATIONS", "ERROR_CODEX"]
	var singles := ["TITLE_DAILY_RULES", "TITLE_DAILY_PLAYED", "TITLE_ENDLESS_RULES", "TITLE_ARCHIVE_DESC",
			"TITLE_SETTINGS_DESC", "PAUSE_ABANDON_CONFIRM", "PAUSE_QUIT_CONFIRM", "ARCHIVE_NOTES_HELP",
			"ARCHIVE_CREDITS_DESC", "SETTINGS_BRIGHTNESS_TEST", "LICENSES_DESCRIPTION", "CAUSE_EXPLANATION_DEFAULT",
			"CREDITS_AI", "CREDITS_GODOT", "CREDITS_FONT", "CREDITS_SOUND", "CREDITS_LICENSES_NOTE", "CREDITS_THANKS"]
	var texts: Array[Array] = []
	for t in tables:
		for k in _map[t]:
			texts.append(["%s[%s]" % [t, k], _map[t][k]])
	for s in singles:
		texts.append([s, _map[s]])
	for pair in texts:
		var s: String = pair[1]
		var first := s.substr(0, 1)
		assert_eq(first, first.to_upper(), "%s starts with a capital" % pair[0])
		assert_true(s.ends_with("."), "%s ends with a period" % pair[0])


func test_notes_follow_the_writing_rules() -> void:
	var first_person := RegEx.create_from_string("\\bI\\b|\\bI'(m|ll|ve|d)\\b|\\bmy\\b|\\bme\\b")
	for n in DataRegistry.notes():
		var words := n.text.split(" ", false).size()
		_le(words, 70 if n.voice != &"builder_final" else 110, "%s word count" % n.id)
		var first := n.text.substr(0, 1)
		assert_eq(first, first.to_upper(), "%s starts with a capital" % n.id)
		if n.voice == &"builder":
			assert_null(first_person.search(n.text), "%s: builder memos never use I (01 §6 rule 2)" % n.id)


func test_single_line_fields_fit() -> void:
	# HUD notifications, prompts, one-word reasons, captions and cause lines are single-line fields
	# in a 1080p HUD at 18 to 22 px with +0.08 em tracking (04 §2); 34 characters is the widest the
	# top-right and lower-third fields take. Hints use the wide line.
	var narrow := ["HUD_", "MSG_", "PROMPT_", "NOCLIP_REASON", "CAPTION_", "MENU_", "PAUSE_RESUME", "PAUSE_SETTINGS", "PAUSE_TITLE", "PAUSE_ABANDON_YES", "PAUSE_ABANDON_NO", "PAUSE_QUIT_YES",
			"PAUSE_QUIT_TITLE", "SUMMARY_LINE_", "SUMMARY_DESCEND", "STAT_", "ARCHIVE_LOCKED"]
	for name in _map:
		var n := String(name)
		var v: Variant = _map[name]
		if not (v is String):
			continue
		for p in narrow:
			if n.begins_with(p):
				_le((v as String).length(), 34, "%s" % n)
	for k in _map["CAUSE_LINES"]:
		_le((_map["CAUSE_LINES"][k] as String).length(), 34, "cause %s" % k)
	for k in _map["CAUSE_EXPLANATIONS"]:
		_le((_map["CAUSE_EXPLANATIONS"][k] as String).length(), 60, "explanation %s" % k)
	for h in _map["HINTS_IN_ORDER"]:
		_le((h as String).length(), 80, h)
	for table in ["ERROR_NAMES", "STRATUM_NAMES", "ITEM_NAMES", "LOADOUT_NAMES", "UNLOCK_NAMES", "SETTING_LABELS", "ACTION_LABELS"]:
		for k in _map[table]:
			_le((_map[table][k] as String).length(), 36, "%s[%s]" % [table, k])


func test_names_in_text_are_canonical() -> void:
	# GLOSSARY: Coherence (never "health"), errors (never "creature"), the dissolve (never "you died").
	# Faller notes are in-world voices and are exempt.
	var banned := RegEx.create_from_string("(?i)\\b(health|hp|creatures?|ghosts?|zombies?|bosses|boss|game over|you died|killed|slain|death screen)\\b")
	for e in _ui:
		if String(e["src"]).begins_with("note "):
			continue
		var m := banned.search(e["text"])
		assert_null(m, "%s uses a non-canonical word: %s" % [e["src"], m.get_string() if m != null else ""])
