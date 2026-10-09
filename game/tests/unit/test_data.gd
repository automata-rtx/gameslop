extends TestCase
## Data resources (M0.4): notes, strata, items, errors, loadouts authored from the design
## documents, and the DataRegistry that loads them.

const STRATA_IDS: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]
const NOTE_PREFIX := {&"halls": "H", &"pools": "P", &"garage": "G", &"offices": "O", &"server": "S", &"substrate": "U"}
## 01 §2 plus the GLOSSARY ban on "monster", "enemy", "entity" in text.
const FORBIDDEN: Array[String] = [
	"backrooms", "liminal", "level 0", "almond water", "entity", "entities", "smiler", "bacteria",
	"partygoer", "monster", "enemy",
]

# ---------------------------------------------------------------- loading

func test_every_data_file_loads_with_the_right_class() -> void:
	var expect := {
		"notes": "NoteData", "items": "ItemData", "strata": "StratumData",
		"errors": "ErrorData", "loadouts": "LoadoutData",
	}
	var total := 0
	for folder in expect:
		for path in _tres_files("res://data/" + folder):
			total += 1
			var res := ResourceLoader.load(path)
			assert_not_null(res, "loads: " + path)
			if res == null:
				continue
			var script: Script = res.get_script()
			assert_not_null(script, "has script: " + path)
			if script != null:
				assert_eq(script.get_global_name(), StringName(expect[folder]), "class of " + path)
	assert_eq(total, 36 + 7 + 6 + 5 + 4)

func test_registry_counts_match_files_on_disk() -> void:
	DataRegistry.reload()
	assert_eq(DataRegistry.notes().size(), _tres_files("res://data/notes").size())
	assert_eq(DataRegistry.items().size(), _tres_files("res://data/items").size())
	assert_eq(DataRegistry.strata().size(), _tres_files("res://data/strata").size())
	assert_eq(DataRegistry.errors().size(), _tres_files("res://data/errors").size())
	assert_eq(DataRegistry.loadouts().size(), _tres_files("res://data/loadouts").size())

func test_registry_lookup_and_unknown_ids() -> void:
	assert_eq(DataRegistry.note(&"G1").stratum, &"garage")
	assert_null(DataRegistry.note(&"Z9"))
	assert_eq(DataRegistry.stratum(&"pools").id, &"pools")
	assert_null(DataRegistry.stratum(&"nowhere"))
	assert_eq(DataRegistry.item(&"flare").cap, 2)
	assert_null(DataRegistry.item(&"sword"))
	assert_eq(DataRegistry.error(&"echo").contact_cost, 25.0)
	assert_null(DataRegistry.error(&"smiler"))
	assert_eq(DataRegistry.loadout(&"diver").start_depth, 3)
	assert_null(DataRegistry.loadout(&"nobody"))

# ---------------------------------------------------------------- notes

func test_thirty_six_notes_unique_ids() -> void:
	var notes := DataRegistry.notes()
	assert_eq(notes.size(), 36)
	var seen := {}
	for n in notes:
		assert_false(seen.has(n.id), "duplicate id " + String(n.id))
		seen[n.id] = true
	for p in ["H", "P", "G", "O", "S", "U"]:
		for i in range(1, 7):
			assert_true(seen.has(StringName("%s%d" % [p, i])), "missing %s%d" % [p, i])

func test_six_notes_per_stratum_with_matching_prefix() -> void:
	for s in STRATA_IDS:
		var group := DataRegistry.notes_for(s)
		assert_eq(group.size(), 6, "notes in " + String(s))
		for n in group:
			assert_true(String(n.id).begins_with(NOTE_PREFIX[s]), "%s prefix in %s" % [n.id, s])

func test_notes_are_in_canonical_order() -> void:
	var ids: PackedStringArray = []
	for n in DataRegistry.notes():
		ids.append(String(n.id))
	var expect: PackedStringArray = []
	for p in ["H", "P", "G", "O", "S", "U"]:
		for i in range(1, 7):
			expect.append("%s%d" % [p, i])
	assert_eq(ids, expect)

func test_note_fields_are_valid() -> void:
	for n in DataRegistry.notes():
		var tag := String(n.id)
		assert_false(n.text.strip_edges().is_empty(), "text of " + tag)
		assert_true(n.voice in NoteData.VOICES, "voice of " + tag)
		assert_true(n.tier in [1, 2, NoteData.TIER_ARCHIVE_ONLY], "tier of " + tag)
		assert_eq(n.text, n.text.strip_edges(), "no stray whitespace in " + tag)
		assert_eq(n.resource_path.get_file().get_basename(), tag, "file name matches id")

func test_only_u6_is_the_builder_final_voice() -> void:
	for n in DataRegistry.notes():
		if n.id == &"U6":
			assert_eq(n.voice, &"builder_final")
			assert_eq(n.tier, NoteData.TIER_ARCHIVE_ONLY)
		else:
			assert_ne(n.voice, &"builder_final", String(n.id))
			assert_true(n.tier == 1 or n.tier == 2, String(n.id))

func test_note_voices_follow_the_tables() -> void:
	# 01 §6: F/B/S/X column per note id.
	var letter := {&"faller": "F", &"builder": "B", &"stray": "S", &"builder_final": "X"}
	var want := {"H": "FBFBFS", "P": "FBFBFS", "G": "FBFBFS", "O": "FBFBFS", "S": "FBFBFS", "U": "BFBFSX"}
	for prefix in want:
		for i in 6:
			var id := StringName("%s%d" % [prefix, i + 1])
			assert_eq(letter[DataRegistry.note(id).voice], want[prefix][i], String(id))

func test_notes_obey_the_writing_rules() -> void:
	for n in DataRegistry.notes():
		var tag := String(n.id)
		assert_false("!" in n.text, "no exclamation marks in " + tag)
		assert_false("..." in n.text or "…" in n.text, "no ellipses in " + tag)
		if n.voice != &"builder_final":
			assert_lt(_word_count(n.text), 71, "70 word limit in " + tag)
		if n.voice == &"builder":
			assert_false(RegEx.create_from_string("\\bI\\b").search(n.text) != null, "builder memos never say I: " + tag)
			if n.id != &"U6":
				assert_true(n.text.begins_with("RENDER NOTE "), "memo header in " + tag)

func test_notes_match_the_design_document_verbatim() -> void:
	var doc := _read_doc("01_fiction_and_tone.md")
	if doc.is_empty():
		return # docs/ is not shipped with an export; the check only runs in the repo
	var re := RegEx.create_from_string("(?m)^\\| ([HPGOSU]\\d) \\| (\\w) \\| ([^|]+?) \\| (.+) \\|$")
	var voices := {"F": &"faller", "B": &"builder", "S": &"stray", "X": &"builder_final"}
	var found := 0
	for m in re.search_all(doc):
		var id := StringName(m.get_string(1))
		var n := DataRegistry.note(id)
		assert_not_null(n, "note exists for " + String(id))
		if n != null:
			assert_eq(n.text, _apply_known_substitutions(m.get_string(4)), "verbatim " + String(id))
			assert_eq(n.voice, voices[m.get_string(2)], "voice of " + String(id))
			var tier_text := m.get_string(3)
			assert_eq(n.tier, NoteData.TIER_ARCHIVE_ONLY if tier_text.begins_with("Archive") else int(tier_text), "tier of " + String(id))
		found += 1
	assert_eq(found, 36)

func test_error_codex_matches_the_design_document_verbatim() -> void:
	var doc := _read_doc("08_entities.md")
	if doc.is_empty():
		return
	var re := RegEx.create_from_string("(?m)^- \\*\\*Codex[^*]*\\*\\* `(.+)`$")
	var found := 0
	var ordered := ["static", "still", "flicker", "echo", "null"]
	for m in re.search_all(doc):
		var e := DataRegistry.error(StringName(ordered[found]))
		assert_eq(e.codex_text, _apply_known_substitutions(m.get_string(1)), "codex " + ordered[found])
		found += 1
	assert_eq(found, 5)

func test_no_forbidden_words_in_any_game_text() -> void:
	var re := RegEx.create_from_string("(?i)\\b(" + "|".join(FORBIDDEN) + ")\\b")
	for text in _all_game_text():
		var m := re.search(text[1])
		assert_null(m, "forbidden word in %s: %s" % [text[0], m.get_string() if m != null else ""])

# ---------------------------------------------------------------- strata

func test_six_strata_with_ids_and_depth_ranges() -> void:
	var strata := DataRegistry.strata()
	assert_eq(strata.size(), 6)
	var ids: Array[StringName] = []
	for s in strata:
		ids.append(s.id)
	assert_eq(ids, STRATA_IDS)
	# 01 §4 and 05 §2: Halls 1, Pools/Garage 2-5, Offices 3-5, Server 4-5, Substrate 6.
	var ranges := {
		&"halls": Vector2i(1, 1), &"pools": Vector2i(2, 5), &"garage": Vector2i(2, 5),
		&"offices": Vector2i(3, 5), &"server": Vector2i(4, 5), &"substrate": Vector2i(6, 6),
	}
	for s in strata:
		assert_eq(Vector2i(s.depth_min, s.depth_max), ranges[s.id], String(s.id))
	for depth in range(1, 7):
		var any := false
		for s in strata:
			any = any or s.contains_depth(depth)
		assert_true(any, "some stratum covers depth %d" % depth)

func test_strata_walkable_cells_and_grid_sizes_per_depth() -> void:
	# 05 §2 / 07 §2.
	var cells := {1: 300, 2: 380, 3: 460, 4: 520, 5: 580, 6: 360}
	var grids := {1: 24, 2: 28, 3: 32, 4: 34, 5: 36, 6: 28}
	for s in DataRegistry.strata():
		var span: int = s.depth_max - s.depth_min + 1
		assert_eq(s.walkable_cells.size(), span, "walkable entries of " + String(s.id))
		assert_eq(s.grid_sizes.size(), span, "grid entries of " + String(s.id))
		for depth in range(s.depth_min, s.depth_max + 1):
			assert_eq(s.walkable_target(depth), cells[depth], "%s walkable at %d" % [s.id, depth])
			assert_eq(s.grid_size(depth), grids[depth], "%s grid at %d" % [s.id, depth])
		assert_eq(s.walkable_target(s.depth_max + 1), 0)
		assert_eq(s.grid_size(0), 0)

func test_strata_heights_decks_and_water() -> void:
	var heights := {&"halls": 3.0, &"pools": 6.0, &"garage": 3.2, &"offices": 3.0, &"server": 3.5, &"substrate": 3.0}
	for s in DataRegistry.strata():
		assert_approx(s.height, heights[s.id], 0.0001, String(s.id))
		assert_eq(s.decks, 2 if s.id == &"garage" else 1, String(s.id))
		assert_eq(s.has_water, s.id == &"pools", String(s.id))

func test_strata_atmosphere_matches_look_sheets() -> void:
	# 02 §6 fog density and §7 colours.
	var fog := {&"halls": 0.02, &"pools": 0.035, &"garage": 0.015, &"offices": 0.02, &"server": 0.03, &"substrate": 0.0}
	var fog_color := {
		&"halls": "b49a3c", &"pools": "5fa8a3", &"garage": "4a3a22", &"offices": "8e96a0",
		&"server": "0d1b2a", &"substrate": "000000",
	}
	var ambient := {
		&"halls": "6e5a1e", &"pools": "1f4a47", &"garage": "6a5032", &"offices": "3a4048",
		&"server": "0c1220", &"substrate": "101010",
	}
	var exposure := {&"halls": 1.0, &"pools": 1.05, &"garage": 0.95, &"offices": 1.0, &"server": 1.1, &"substrate": 1.0}
	for s in DataRegistry.strata():
		var tag := String(s.id)
		assert_approx(s.fog_density, fog[s.id], 0.00001, tag)
		assert_eq(s.fog_color.to_html(false), fog_color[s.id], "fog colour " + tag)
		assert_eq(s.ambient_color.to_html(false), ambient[s.id], "ambient colour " + tag)
		assert_approx(s.exposure, exposure[s.id], 0.00001, tag)
	var sub := DataRegistry.stratum(&"substrate")
	assert_approx(sub.distance_fog_begin, 25.0)
	assert_approx(sub.distance_fog_end, 45.0)
	assert_approx(sub.ambient_energy, 0.05)
	assert_eq(DataRegistry.stratum(&"halls").wall_color.to_html(false), "c9a227")
	assert_eq(DataRegistry.stratum(&"pools").wall_color.to_html(false), "9fd5cf")
	assert_eq(DataRegistry.stratum(&"garage").floor_color.to_html(false), "5e5e5a")
	assert_eq(DataRegistry.stratum(&"offices").partition_color.to_html(false), "8a8f96")
	assert_eq(DataRegistry.stratum(&"pools").water_color.to_html(true), "2e8b8bbf")

func test_strata_fixtures() -> void:
	var kind := {
		&"halls": &"tube", &"pools": &"panel", &"garage": &"sodium_lamp", &"offices": &"troffer",
		&"server": &"emergency_box", &"substrate": &"none",
	}
	var spacing := {&"halls": 4.0, &"pools": 6.0, &"garage": 8.0, &"offices": 4.0, &"server": 12.0}
	for s in DataRegistry.strata():
		assert_eq(s.fixture_kind, kind[s.id], String(s.id))
		if s.id == &"substrate":
			assert_true(s.fixture_prefab_path.is_empty())
			assert_approx(s.studio_light_energy, 0.6)
			assert_approx(s.studio_light_range, 15.0)
		else:
			assert_false(s.fixture_prefab_path.is_empty(), String(s.id))
			assert_approx(s.fixture_spacing_m, spacing[s.id], 0.0001, String(s.id))
			assert_gt(s.fixture_light_energy, 0.0)
			assert_gt(s.fixture_light_range, 0.0)

func test_strata_reverb_matches_audio_direction() -> void:
	# 03 §4: room, damping, wet, predelay ms, highpass Hz.
	var want := {
		&"halls": [0.5, 0.6, 0.2, 0.0, 0.0], &"pools": [0.9, 0.2, 0.45, 40.0, 0.0],
		&"garage": [0.8, 0.4, 0.3, 0.0, 0.0], &"offices": [0.4, 0.7, 0.15, 0.0, 0.0],
		&"server": [0.3, 0.8, 0.1, 0.0, 0.0], &"substrate": [1.0, 0.0, 0.5, 0.0, 300.0],
	}
	for s in DataRegistry.strata():
		var w: Array = want[s.id]
		assert_approx(s.reverb_room_size, w[0], 0.00001, String(s.id))
		assert_approx(s.reverb_damping, w[1], 0.00001, String(s.id))
		assert_approx(s.reverb_wet, w[2], 0.00001, String(s.id))
		assert_approx(s.reverb_predelay_ms, w[3], 0.00001, String(s.id))
		assert_approx(s.reverb_highpass_hz, w[4], 0.00001, String(s.id))

func test_strata_content_lists() -> void:
	var native := {&"halls": &"", &"pools": &"echo", &"garage": &"still", &"offices": &"flicker", &"server": &"", &"substrate": &"null"}
	var soft := {&"halls": 4, &"pools": 3, &"garage": 3, &"offices": 4, &"server": 0, &"substrate": 6}
	for s in DataRegistry.strata():
		assert_eq(s.native_error, native[s.id], String(s.id))
		assert_eq(s.soft_wall_count, soft[s.id], String(s.id))
		assert_false(s.prop_ids.is_empty(), "props of " + String(s.id))
		assert_false(s.exit_kind == &"", "exit of " + String(s.id))
		assert_false(s.landing_kind == &"", "landing of " + String(s.id))
		if s.native_error != &"":
			assert_not_null(DataRegistry.error(s.native_error), "native error exists")
	assert_true(DataRegistry.stratum(&"substrate").hide_spot_kinds.is_empty(), "no hide spots in the Substrate")
	assert_eq(DataRegistry.stratum(&"substrate").exit_kind, &"threshold_door")

# ---------------------------------------------------------------- items

func test_six_items_plus_keycard() -> void:
	var items := DataRegistry.items()
	assert_eq(items.size(), 7)
	var kinds: Array[StringName] = []
	for i in items:
		kinds.append(i.kind)
	assert_eq(kinds, [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse", &"keycard"] as Array[StringName])

func test_item_numbers_match_the_item_table() -> void:
	# 09 §2: cap and weight; unlock gating 05 §6.
	var cap := {&"polaroid": 3, &"glowstick": 4, &"flare": 2, &"chalk": 20, &"radio": 1, &"fuse": 1, &"keycard": 1}
	var weight := {&"polaroid": 3, &"glowstick": 3, &"flare": 2, &"chalk": 2, &"radio": 1, &"fuse": 1, &"keycard": 0}
	var unlock := {
		&"polaroid": &"", &"glowstick": &"glowstick", &"flare": &"flare", &"chalk": &"",
		&"radio": &"radio", &"fuse": &"fuse", &"keycard": &"",
	}
	for i in DataRegistry.items():
		var tag := String(i.kind)
		assert_eq(i.cap, cap[i.kind], "cap " + tag)
		assert_eq(i.weight, weight[i.kind], "weight " + tag)
		assert_eq(i.unlock_id, unlock[i.kind], "unlock " + tag)
		assert_false(i.display_name.is_empty(), "name " + tag)
		assert_eq(i.display_name, i.display_name.to_upper(), "uppercase name " + tag)
		assert_true(i.use_time >= 0.0 and i.use_time <= 1.2, "use time within 1.2 s: " + tag)
		assert_eq(i.belt_item, i.kind != &"keycard", "belt flag " + tag)
	assert_eq(DataRegistry.item(&"chalk").pickup_count, 8)
	assert_approx(DataRegistry.item(&"polaroid").use_time, 1.2)
	assert_approx(DataRegistry.item(&"fuse").use_time, 0.8)
	assert_eq(DataRegistry.item(&"glowstick").world_light_color.to_html(false), "7cff4a")
	assert_eq(DataRegistry.item(&"flare").world_light_color.to_html(false), "ff4a2e")

# ---------------------------------------------------------------- errors

func test_five_errors_with_one_rule_each() -> void:
	var errors := DataRegistry.errors()
	assert_eq(errors.size(), 5)
	var ids: Array[StringName] = []
	for e in errors:
		ids.append(e.id)
		var tag := String(e.id)
		for field in [e.display_name, e.rule, e.counter, e.tell, e.cost, e.codex_text]:
			assert_false(String(field).strip_edges().is_empty(), "text field of " + tag)
		assert_true(e.codex_text.begins_with("RENDER NOTE."), "codex is a builder memo: " + tag)
		assert_eq(e.codex_encounters, 3)
	assert_eq(ids, [&"static", &"still", &"flicker", &"echo", &"null"] as Array[StringName])

func test_error_costs_match_the_law_of_errors() -> void:
	# 08 §1 cost column.
	var contact := {&"static": 0.0, &"still": 35.0, &"flicker": 30.0, &"echo": 25.0, &"null": 0.0}
	var drain := {&"static": 4.0, &"still": 0.0, &"flicker": 0.0, &"echo": 0.0, &"null": 10.0}
	for e in DataRegistry.errors():
		assert_approx(e.contact_cost, contact[e.id], 0.0001, String(e.id))
		assert_approx(e.drain_per_second, drain[e.id], 0.0001, String(e.id))
		# 05 §9 rule 5: no single damage event exceeds 35.
		assert_true(e.contact_cost <= 35.0)
	assert_eq(DataRegistry.error(&"still").native_stratum, &"garage")
	assert_eq(DataRegistry.error(&"static").native_stratum, &"")

# ---------------------------------------------------------------- loadouts

func test_four_loadouts_match_the_loadout_table() -> void:
	var loadouts := DataRegistry.loadouts()
	assert_eq(loadouts.size(), 4)
	var ids: Array[StringName] = []
	for l in loadouts:
		ids.append(l.id)
	assert_eq(ids, [&"faller", &"cartographer", &"lightbearer", &"diver"] as Array[StringName])
	var faller := DataRegistry.loadout(&"faller")
	assert_eq(faller.start_items, {&"polaroid": 1, &"chalk": 8})
	assert_approx(faller.start_coherence, 100.0)
	assert_eq(faller.unlock_id, &"")
	var carto := DataRegistry.loadout(&"cartographer")
	assert_eq(carto.start_items, {&"chalk": 20, &"radio": 1})
	assert_approx(carto.start_coherence, 90.0)
	var light := DataRegistry.loadout(&"lightbearer")
	assert_eq(light.start_items, {&"glowstick": 3, &"flare": 1})
	assert_approx(light.crank_rate_mult, 1.5)
	assert_approx(light.flicker_attract_mult, 1.5)
	assert_false(light.start_items.has(&"polaroid"), "Lightbearer has no Polaroid")
	var diver := DataRegistry.loadout(&"diver")
	assert_eq(diver.start_items, {&"polaroid": 2})
	assert_eq(diver.start_depth, 3)
	assert_approx(diver.start_coherence, 70.0)

func test_loadout_items_exist_and_fit_caps() -> void:
	for l in DataRegistry.loadouts():
		assert_false(l.description.is_empty(), "description of " + String(l.id))
		assert_true(l.start_items.size() <= 4, "fits the four-slot belt: " + String(l.id))
		for kind in l.start_items:
			var item := DataRegistry.item(kind)
			assert_not_null(item, "item exists: %s" % kind)
			if item != null:
				assert_true(l.start_items[kind] <= item.cap, "%s within cap in %s" % [kind, l.id])
				assert_true(item.belt_item)
	assert_eq(DataRegistry.loadout(&"cartographer").unlock_id, &"cartographer")

# ---------------------------------------------------------------- helpers

func _tres_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		fail("cannot open " + dir_path)
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(dir_path.path_join(f))
	return out

func _word_count(s: String) -> int:
	return s.split(" ", false).size()

func _read_doc(file_name: String) -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/design").path_join(file_name).simplify_path()
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

## The design documents contain the word "entity" in two lines (U1, Null's codex), which 01 §2
## forbids. The data uses "object"; this keeps the verbatim check honest about that one edit.
func _apply_known_substitutions(s: String) -> String:
	return s.replace("an entity", "an object")

## [label, text] for every player-facing string in the data.
func _all_game_text() -> Array:
	var out: Array = []
	for n in DataRegistry.notes():
		out.append([String(n.id), n.text])
	for e in DataRegistry.errors():
		for t in [e.display_name, e.rule, e.counter, e.tell, e.cost, e.codex_text]:
			out.append(["error " + String(e.id), t])
	for i in DataRegistry.items():
		out.append(["item " + String(i.kind), i.display_name])
	for l in DataRegistry.loadouts():
		out.append(["loadout " + String(l.id), l.display_name + " " + l.description])
	for s in DataRegistry.strata():
		out.append(["stratum " + String(s.id), s.display_name])
	return out
