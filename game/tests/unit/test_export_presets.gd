extends TestCase
## game/export_presets.cfg carries what 16 §1 and §2 require, and the version has one
## source (16 §1). tools/ci/export.sh and tools/ci/smoke.sh prove the presets actually export
## and boot; this test keeps the options from drifting between those runs.

const PRESETS_FILE := "res://export_presets.cfg"
const WINDOWS := "Windows x86_64"
const LINUX := "Linux x86_64"


## Preset name -> [section, options section], or {} when the file does not parse.
func _presets(cfg: ConfigFile) -> Dictionary:
	var out := {}
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			out[cfg.get_value(section, "name", "")] = [section, section + ".options"]
	return out


func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS_FILE)
	assert_eq(err, OK, "export_presets.cfg parses")
	return cfg


func test_both_presets_exist_on_their_platforms() -> void:
	var cfg := _load()
	var p := _presets(cfg)
	assert_eq(p.size(), 2, "exactly the two desktop presets (16 §1)")
	assert_true(p.has(WINDOWS), WINDOWS)
	assert_true(p.has(LINUX), LINUX)
	if p.has(WINDOWS):
		assert_eq(cfg.get_value(p[WINDOWS][0], "platform", ""), "Windows Desktop")
	if p.has(LINUX):
		assert_eq(cfg.get_value(p[LINUX][0], "platform", ""), "Linux")


func test_common_options() -> void:
	var cfg := _load()
	var p := _presets(cfg)
	for name: String in [WINDOWS, LINUX]:
		if not p.has(name):
			fail("missing preset %s" % name)
			continue
		var sec: String = p[name][0]
		var opt: String = p[name][1]
		assert_eq(cfg.get_value(sec, "export_filter", ""), "all_resources", name)
		assert_false(bool(cfg.get_value(sec, "dedicated_server", true)), "%s: client build" % name)
		assert_false(bool(cfg.get_value(sec, "encrypt_pck", true)), "%s: no encryption" % name)
		var exclude := _filters(str(cfg.get_value(sec, "exclude_filter", "")))
		assert_contains(exclude, "tests/*", "%s: tests excluded (16 §2)" % name)
		assert_contains(exclude, "scenes/debug/*", "%s: debug benches excluded (16 §2)" % name)
		assert_contains(exclude, "scenes/ui/menu_gallery.tscn", "%s: the menu gallery bench is excluded" % name)
		# FileAccess-read files that are not resources must be named explicitly.
		var include := _filters(str(cfg.get_value(sec, "include_filter", "")))
		assert_contains(include, "*.json", "%s: the audio manifest ships" % name)
		assert_eq(cfg.get_value(opt, "binary_format/embed_pck", true), false, "%s: separate .pck (16 §1)" % name)
		assert_eq(cfg.get_value(opt, "binary_format/architecture", ""), "x86_64", name)
		assert_eq(cfg.get_value(opt, "texture_format/s3tc_bptc", false), true, "%s: bptc (16 §2)" % name)
		assert_eq(cfg.get_value(opt, "texture_format/etc2_astc", true), false, "%s: no etc2/astc (16 §2)" % name)
		assert_eq(cfg.get_value(opt, "shader_baker/enabled", false), true, "%s: shader baker (16 §2)" % name)
		assert_eq(cfg.get_value(opt, "debug/export_console_wrapper", -1), 0, "%s: no console wrapper" % name)
		assert_eq(str(cfg.get_value(opt, "custom_template/release", "x")), "", "%s: official templates" % name)


func test_windows_options() -> void:
	var cfg := _load()
	var p := _presets(cfg)
	if not p.has(WINDOWS):
		fail("missing preset %s" % WINDOWS)
		return
	var opt: String = p[WINDOWS][1]
	assert_eq(cfg.get_value(opt, "application/product_name", ""), "NOCLIP")
	assert_ne(str(cfg.get_value(opt, "application/file_description", "")), "", "file description")
	var copyright := str(cfg.get_value(opt, "application/copyright", ""))
	assert_true(copyright.contains("20"), "copyright line with the year: %s" % copyright)
	assert_eq(cfg.get_value(opt, "application/modify_resources", false), true, "icon and version written into the exe")
	var icon := str(cfg.get_value(opt, "application/icon", ""))
	assert_eq(icon, "res://assets/icon.ico")
	assert_true(FileAccess.file_exists(icon), "icon.ico exists (tools/ci/icons.gd)")
	# Empty file and product versions make the exporter use application/config/version.
	assert_eq(str(cfg.get_value(opt, "application/file_version", "x")), "", "file version from project.godot")
	assert_eq(str(cfg.get_value(opt, "application/product_version", "x")), "", "product version from project.godot")


func test_version_has_one_source() -> void:
	assert_true(Version.VERSION.split(".").size() == 3, "semver: %s" % Version.VERSION)
	assert_eq(ProjectSettings.get_setting("application/config/version", ""), Version.VERSION,
			"project.godot config/version mirrors version.gd (16 §1)")
	assert_eq(Title.VERSION, Version.VERSION, "the title shows version.gd's version")


func test_icons() -> void:
	var png := str(ProjectSettings.get_setting("application/config/icon", ""))
	assert_eq(png, "res://assets/icon.png", "16 §2 Linux icon")
	assert_true(ResourceLoader.exists(png), "icon.png imports")
	var tex := load(png) as Texture2D
	assert_not_null(tex, "icon.png loads")
	if tex != null:
		assert_eq(tex.get_size(), Vector2(256, 256))
	assert_eq(ProjectSettings.get_setting("application/config/windows_native_icon", ""), "res://assets/icon.ico")
	var ico := FileAccess.get_file_as_bytes("res://assets/icon.ico")
	assert_gt(ico.size(), 6, "icon.ico has data")
	if ico.size() > 6:
		assert_eq(ico.decode_u16(2), 1, "ICO type")
		assert_eq(ico.decode_u16(4), 7, "16, 24, 32, 48, 64, 128, 256 px (16 §2)")


func _filters(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in s.split(","):
		if not f.strip_edges().is_empty():
			out.append(f.strip_edges())
	return out


func test_credits_md_lists_the_font_license() -> void:
	# 04 §2 / 16 §6: the repo root CREDITS.md (the project folder is game/, so one level up).
	var path := ProjectSettings.globalize_path("res://").path_join("../CREDITS.md").simplify_path()
	var text := FileAccess.get_file_as_string(path)
	assert_false(text.is_empty(), "CREDITS.md exists at the repo root")
	assert_true(text.contains("an AI (Claude, Anthropic)"), "the AI line, exactly")
	assert_true(text.contains("SIL Open Font License"), "the font license")
	assert_true(text.contains("JetBrains Mono"), "the font name")
	assert_true(text.contains("Thank you for looking."), "the closing line")
