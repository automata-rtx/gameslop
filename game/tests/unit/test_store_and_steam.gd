extends TestCase
## M4.2: the store page file matches 16 section 5, and the Steam tooling (templates, VDF parser,
## upload script) refuses placeholders and keeps secrets out of its output. Nothing here talks to
## Steam; tools/steam/selftest.sh drives upload.sh against a fake steamcmd.

const Gate := preload("res://tests/text_gate.gd")
const DESIGN := "../docs/design/16_release_and_steam.md"
const PAGE := "../docs/release/store_page.md"

var _root: String = ""
var _page: String = ""
var _design: String = ""


func before_all() -> void:
	_root = ProjectSettings.globalize_path("res://")
	_page = FileAccess.get_file_as_string(_root.path_join(PAGE))
	_design = FileAccess.get_file_as_string(_root.path_join(DESIGN))


## The text under a `## N. Heading` in the page, up to the next `## `.
func _section(prefix: String) -> String:
	var a := _page.find("\n## " + prefix)
	assert_gt(a, -1, "section '%s' exists" % prefix)
	var b := _page.find("\n## ", a + 4)
	return _page.substr(a, b - a if b > 0 else -1)


func test_sections_follow_the_order_of_16() -> void:
	var order := ["1. Name", "2. Short description", "3. Long description", "4. Tags", "5. Features",
			"6. System requirements", "7. AI disclosure", "8. Content descriptors", "9. Languages", "10. Price"]
	var last := -1
	for h in order:
		var at := _page.find("\n## " + h)
		assert_gt(at, last, "'%s' comes after the one before it" % h)
		last = at


func test_short_description_is_16s_and_fits() -> void:
	var line := ""
	for l in _design.split("\n"):
		if l.begins_with("- **Short description"):
			line = l.get_slice("**", 2).strip_edges()
	assert_gt(line.length(), 100, "found 16's short description")
	assert_true(line.length() <= 300, "16 allows 300 characters")
	assert_contains(_section("2. Short description"), line)
	assert_contains(_section("3. Long description"), "Every system, line of code, shader, sound, and word in NOCLIP was designed and built by an AI. A human chose the project, published it, and did nothing else. That is the experiment.")


func test_long_description_is_three_paragraphs_of_prose_then_the_honesty_line() -> void:
	var body := _section("3. Long description").split("\n", false)
	body.remove_at(0)
	assert_eq(body.size(), 4, "premise, what hunts you, the loop, the honesty line")


func test_tags_features_and_requirements_match_16() -> void:
	for tag in ["Horror", "Roguelite", "First-Person", "Procedural Generation", "Psychological Horror",
			"Atmospheric", "Singleplayer", "Exploration", "Liminal (if available)", "Indie"]:
		assert_contains(_section("4. Tags"), tag)
	var features := _section("5. Features")
	for f in ["6 generated strata", "5 errors", "36 notes", "14 unlocks and 4 loadouts", "Daily Descent",
			"Endless", "FOV 70 to 110", "sound captions"]:
		assert_contains(features, f)
	var req := _section("6. System requirements")
	for r in ["Windows 10 64-bit", "Linux x86_64", "4-core CPU", "8 GB RAM", "Vulkan 1.2", "2 GB VRAM",
			"GTX 960 / RX 470", "500 MB", "GTX 1060 / RX 580", "16 GB RAM", "keyboard and mouse only"]:
		assert_contains(req, r)
	assert_contains(_section("10. Price"), "USD 2.99")


func test_the_page_discloses_the_ai_with_the_credits_phrase() -> void:
	assert_contains(_section("7. AI disclosure"), Gate.AI_PHRASE)
	assert_eq(_page.count("Claude"), 1, "Claude is named once, inside the one allowed phrase")
	assert_eq(_page.count("Anthropic"), 1)


func test_figures_in_the_page_match_the_game() -> void:
	assert_eq(DataRegistry.notes().size(), 36)
	assert_eq(DataRegistry.loadouts().size(), 4)
	assert_eq(DataRegistry.errors().size(), 5)
	assert_eq(DataRegistry.strata().size(), 6)
	var s := _section("2. Short description") + _section("5. Features")
	assert_contains(s, "6 generated strata")


func test_screenshot_list_is_eight_frames_the_tour_can_make() -> void:
	var shots := _section("13. Screenshots")
	var rows := 0
	var re := RegEx.create_from_string("(?m)^\\| (\\d) \\| .*`build/store/([a-z]+)/([a-z_0-9]+)\\.png`")
	var tour_poses := ["spawn", "corridor", "corridor_long", "exit_room", "pocket", "studio", "checker", "basin"]
	for m in re.search_all(shots):
		rows += 1
		var stratum := m.get_string(2)
		var frame := m.get_string(3)
		assert_contains(Tuning.STRATA_ALL.map(func(x: StringName) -> String: return String(x)) + ["garage", "offices"], stratum, "a real stratum folder")
		if frame.begins_with("still_") or frame.begins_with("flicker_"):
			assert_contains(["garage", "offices"], stratum, "arena frames come from the arena folders")
		elif frame == "noclip_commit":
			continue
		else:
			var pose := frame.rsplit("_c", true, 1)[0]
			assert_contains(tour_poses, pose, "%s is a pose the tour photographs" % frame)
	assert_eq(rows, 8, "eight screenshots, as 16 asks")
	assert_contains(shots, "--tour build/store")
	assert_contains(shots, "1920x1080")


func test_the_page_obeys_the_text_gate() -> void:
	assert_eq(Gate.store_hits(_page).size(), 0, "%s" % [Gate.store_hits(_page)])


# ------------------------------------------------------------------- Steam tooling

func test_steam_templates_carry_the_placeholders_of_16() -> void:
	var dir := _root.path_join("../tools/steam")
	var app := FileAccess.get_file_as_string(dir.path_join("app_build.vdf.template"))
	for p in ["{APP_ID}", "{DEPOT_WIN}", "{DEPOT_LINUX}", "{BUILD_DIR}", "{DESCRIPTION}"]:
		assert_contains(app, p)
	assert_contains(app, "\"setlive\" \"\"", "an upload never goes live by itself")
	assert_contains(FileAccess.get_file_as_string(dir.path_join("depot_build_windows.vdf.template")), "{DEPOT_WIN}")
	assert_contains(FileAccess.get_file_as_string(dir.path_join("depot_build_linux.vdf.template")), "{DEPOT_LINUX}")
	# Nothing secret or real in the repository: no digits after appid / DepotID, no password key.
	var all := app + FileAccess.get_file_as_string(dir.path_join("upload.sh"))
	assert_null(RegEx.create_from_string("\"(appid|DepotID)\" \"[0-9]").search(all), "no real ids committed")
	assert_false(FileAccess.get_file_as_string(dir.path_join("upload.sh")).contains("set -x"), "no command tracing, it would print the login")


func test_steam_selftest_passes() -> void:
	var out: Array = []
	var script := _root.path_join("../tools/steam/selftest.sh").simplify_path()
	var code := OS.execute("bash", [script], out, true)
	if code == -1:
		print("  (bash is not available; the Steam selftest was skipped)")
		return
	assert_eq(code, 0, "tools/steam/selftest.sh: %s" % ("\n".join(PackedStringArray(out))))
