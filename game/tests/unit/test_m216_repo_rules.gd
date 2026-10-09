extends TestCase
## M2.16 cross-cutting checks of the rules in CLAUDE.md and 14 that every M2 task had to
## keep: seeded randomness only, no imported meshes or image textures, every resource path
## and sound id the code names exists, every bench scene loads. A regression here is the
## kind no single system test notices.

const SCAN_DIRS: Array[String] = ["res://src", "res://scenes", "res://data", "res://shaders"]
const MODEL_NAMES := "(?i)\\b(sonnet|opus|haiku|gpt-?[0-9]|gemini|llama)\\b"
const BANNED_EXT: Array[String] = ["glb", "gltf", "obj", "fbx", "dae", "blend", "jpg", "jpeg", "webp",
		"tga", "bmp", "exr", "hdr", "dds", "psd"]
## The one raster image in the project: the window icon (an icon is not a surface texture).
const RASTER_ALLOWED: Array[String] = ["res://assets/icon.png"]
const MANIFEST := "res://assets/audio/manifest.json"

var _cache: Dictionary = {}


func _files(root: String, exts: Array[String]) -> PackedStringArray:
	var key := root + "|" + ",".join(exts)
	if _cache.has(key):
		return _cache[key]
	var out: PackedStringArray = []
	_walk(root, exts, out)
	out.sort()
	_cache[key] = out
	return out


func _walk(dir: String, exts: Array[String], out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if exts.is_empty() or exts.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d != ".godot":
			_walk(dir.path_join(d), exts, out)


func test_no_unseeded_randomness_in_the_game() -> void:
	# 14 §9: gameplay and generation use seeded RandomNumberGenerators only. The global
	# functions and the Array helpers that read the global generator are banned in src/.
	var re := RegEx.create_from_string("(^|[^._A-Za-z0-9])(randi|randf|randi_range|randf_range|randomize|rand_from_seed)\\(|\\.shuffle\\(\\)|\\.pick_random\\(\\)")
	for path in _files("res://src", ["gd"]):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i].split("#")[0]
			assert_null(re.search(code), "%s:%d uses the global generator: %s" % [path, i + 1, lines[i].strip_edges()])


func test_no_imported_meshes_or_image_textures() -> void:
	# 02 T8: primitives, procedural noise, SVG and synthesized audio only.
	for path in _files("res://", BANNED_EXT):
		if path.begins_with("res://tests/") or path.contains("/.godot/"):
			continue
		fail("imported art asset: " + path)
	for path in _files("res://", ["png"]):
		if not RASTER_ALLOWED.has(path):
			fail("raster image outside the icon: " + path)


func test_no_model_names_in_code_or_text() -> void:
	# CLAUDE.md: the credits say "an AI (Claude, Anthropic)" and nothing more specific.
	var re := RegEx.create_from_string(MODEL_NAMES)
	for dir in ["res://src", "res://data", "res://scenes"]:
		for path in _files(dir, ["gd", "tres", "tscn", "json", "cfg"]):
			var m := re.search(FileAccess.get_file_as_string(path))
			assert_null(m, "%s names a model: %s" % [path, m.get_string() if m != null else ""])


func test_every_literal_resource_path_exists() -> void:
	var re := RegEx.create_from_string("res://[A-Za-z0-9_./\\-]+")
	var checked := 0
	for dir in SCAN_DIRS:
		for path in _files(dir, ["gd", "tscn", "tres"]):
			var text := FileAccess.get_file_as_string(path)
			for m in re.search_all(text):
				var p := m.get_string()
				var after := text.substr(m.get_end(), 1)
				# Format templates ("res://x/%s.tscn"), directories and prefixes are not paths.
				if after == "%" or after == "{" or p.ends_with("/") or p.ends_with(".") or p.get_extension() == "":
					continue
				checked += 1
				assert_true(ResourceLoader.exists(p) or FileAccess.file_exists(p), "%s names a missing file: %s" % [path, p])
	assert_gt(checked, 100, "the scan found the paths")


func test_every_named_sound_is_in_the_manifest() -> void:
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary)["sounds"]
	var call_re := RegEx.create_from_string("AudioManager\\.(?:play_2d|play_3d|loop|start_loop)\\(\\s*&\"([a-z0-9_]+)\"")
	var const_re := RegEx.create_from_string("(?m)^\\s*const\\s+[A-Z_0-9]*(?:SOUND|SFX)[A-Z_0-9]*\\s*(?::\\s*StringName)?\\s*:?=\\s*&\"([a-z0-9_]+)\"")
	var used := 0
	for path in _files("res://src", ["gd"]):
		var text := FileAccess.get_file_as_string(path)
		for re in [call_re, const_re]:
			for m: RegExMatch in (re as RegEx).search_all(text):
				used += 1
				assert_true(manifest.has(m.get_string(1)), "%s plays an id that is not in the manifest: %s" % [path, m.get_string(1)])
	assert_gt(used, 40)


func test_every_scene_loads_and_every_bench_instantiates() -> void:
	# The bench and debug scenes are maintained (15 §1): a broken script or path in one
	# is found here without a GPU. Instancing does not enter the tree.
	var scenes := _files("res://scenes", ["tscn"])
	assert_gt(scenes.size(), 50)
	for path in scenes:
		var ps := load(path) as PackedScene
		assert_not_null(ps, path)
		if ps == null:
			continue
		var node := ps.instantiate()
		assert_not_null(node, path + " instantiates")
		if node != null:
			node.free()
	assert_gt(_files("res://scenes/debug", ["tscn"]).size(), 9, "the bench scenes are all here")


func test_every_script_in_src_parses() -> void:
	for path in _files("res://src", ["gd"]):
		assert_not_null(load(path) as GDScript, path + " parses")
