extends TestCase
## M1.5 rendering review fixes (R3): the renderer API additions (noclip target, invalid flag,
## Static, ripple and drop pulses, heartbeat phase, viewports, texture detail), the two
## accessibility defaults, the Null-only scene pass, and shader constants against Tuning.

const SHADER_FILES: Array[String] = [
	"res://shaders/include/coherence.gdshaderinc",
	"res://shaders/world_surface.gdshader",
	"res://shaders/coherence_post.gdshader",
	"res://shaders/coherence_screen.gdshader",
	"res://shaders/water.gdshader",
]
const NOISE_ALBEDO := "res://data/materials/noise_albedo.tres"

var _const_re := RegEx.create_from_string(
		"^\\s*const\\s+(float|int|vec3)\\s+(\\w+)\\s*=\\s*([^;]+);\\s*(//\\s*(.*))?$")


func after_each() -> void:
	CoherenceRenderer._on_run_started(&"test", 0)
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ---------------------------------------------------------------- shader constants

## Every `const` in the shaders names its Tuning constant in a trailing comment (or says
## `shader-local`), and the literal equals the Tuning value.
func test_shader_constants_match_tuning() -> void:
	var tuning: Dictionary = (load("res://src/core/tuning.gd") as GDScript).get_script_constant_map()
	var checked := 0
	for path in SHADER_FILES:
		var text := _source(path)
		assert_gt(text.length(), 0, path)
		for line in text.split("\n"):
			var m := _const_re.search(line)
			if m == null:
				continue
			var kind := m.get_string(1)
			var cname := m.get_string(2)
			var literal := m.get_string(3).strip_edges()
			var note := m.get_string(5).strip_edges()
			if note.begins_with("shader-local"):
				continue
			var tname := note.split(" ")[0] if note != "" else ""
			assert_true(tuning.has(tname), "%s %s names a Tuning constant (got '%s')" % [path, cname, tname])
			if not tuning.has(tname):
				continue
			var tv: Variant = tuning[tname]
			if kind == "vec3":
				var hexc := Color(String(tv))
				var expect := hexc.srgb_to_linear() if note.contains("linear") else hexc
				var nums := literal.trim_prefix("vec3(").trim_suffix(")").split(",")
				for i in 3:
					assert_approx(float(nums[i]), expect[i], 0.001, "%s %s[%d] vs %s" % [path, cname, i, tname])
			else:
				assert_approx(float(literal), float(tv), 0.00001, "%s %s vs %s" % [path, cname, tname])
			checked += 1
	assert_gt(checked, 25, "the shaders mirror their Tuning numbers")


func test_no_reversed_smoothstep_edges() -> void:
	# GLSL leaves smoothstep(e0, e1, x) undefined for e0 >= e1; a descending ramp is spelled
	# 1 - smoothstep(lo, hi, x) (coh_falloff).
	var re := RegEx.create_from_string("smoothstep\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,")
	var bad := RegEx.create_from_string("smoothstep\\(\\s*(g_null_radius|NOCLIP_RADIUS|COH_NOCLIP_RADIUS)\\s*,")
	for path in SHADER_FILES:
		var text := _source(path)
		for m in re.search_all(text):
			assert_lt(float(m.get_string(1)), float(m.get_string(2)), "%s: %s" % [path, m.get_string(0)])
		assert_null(bad.search(text), "%s: no descending smoothstep on a radius" % path)


func test_screen_door_is_world_anchored() -> void:
	var inc := _source("res://shaders/include/coherence.gdshaderinc")
	assert_true(inc.contains("floor(wp / cell)"), "hash of the world cell")
	assert_true(inc.contains("COH_SCREEN_DOOR_CELL * exp2("), "a 1 cm lattice by octaves")
	var world := _source("res://shaders/world_surface.gdshader")
	assert_false(world.contains("FRAGCOORD"), "no screen-space dither in the world shader")


func test_grade_lives_in_the_screen_pass() -> void:
	var post := _source("res://shaders/coherence_post.gdshader")
	for u in ["uniform float sat", "uniform float warmth", "uniform float vig"]:
		assert_false(post.contains(u), "scene pass no longer grades: %s" % u)
	var screen := _source("res://shaders/coherence_screen.gdshader")
	assert_false(screen.contains("uv + dir * ca"), "no CA read points outward past the edge")
	assert_true(screen.contains("inside(uv - dir * 2.0 * ca, px)"), "CA reads are kept inside the image")


# ---------------------------------------------------------------- settings

func test_accessibility_defaults_exist_and_are_read() -> void:
	assert_eq(SettingsManager.DEFAULTS.get(&"reduce_visual_noise"), false)
	assert_eq(SettingsManager.DEFAULTS.get(&"reduce_flashing"), false)
	assert_eq(SettingsManager.get_value(&"reduce_visual_noise"), false, "never null before settings.cfg")
	assert_eq(CoherenceRenderer.reduce_noise, bool(SettingsManager.get_value(&"reduce_visual_noise")))
	assert_eq(CoherenceRenderer.reduce_flashing, bool(SettingsManager.get_value(&"reduce_flashing")))
	SettingsManager.set_value(&"reduce_flashing", true)
	assert_true(CoherenceRenderer.reduce_flashing, "on change")
	SettingsManager.set_value(&"reduce_flashing", false)
	assert_false(CoherenceRenderer.reduce_flashing)


func test_texture_detail_sets_noise_resolution() -> void:
	var tex := load(NOISE_ALBEDO) as NoiseTexture2D
	CoherenceRenderer.apply_texture_detail(&"low")
	assert_eq(tex.width, Tuning.QUALITY_TEXTURE_SIZE_LOW)
	CoherenceRenderer.apply_texture_detail(&"high")
	assert_eq(tex.width, Tuning.QUALITY_TEXTURE_SIZE_HIGH)
	assert_eq(tex.height, Tuning.QUALITY_TEXTURE_SIZE_HIGH)


# ---------------------------------------------------------------- API

func test_noclip_target_and_invalid_reach_the_globals() -> void:
	# Declared in project.godot (14 §11); the headless dummy renderer does not echo values
	# back, so the test checks the declarations and the values the renderer writes.
	for g in ["g_noclip_target", "g_noclip_target_normal", "g_noclip_invalid"]:
		assert_true(ProjectSettings.has_setting("shader_globals/" + g), "%s declared" % g)
	CoherenceRenderer.set_noclip_target(Vector3(1.0, 1.5, -8.0), Vector3(-2.0, 0.0, 0.0))
	CoherenceRenderer.set_noclip_invalid(true)
	assert_eq(CoherenceRenderer.noclip_target, Vector3(1.0, 1.5, -8.0))
	assert_eq(CoherenceRenderer.noclip_target_normal, Vector3(-1.0, 0.0, 0.0), "normalised")
	assert_true(CoherenceRenderer.noclip_invalid)
	await await_frames(1)
	CoherenceRenderer.set_noclip_invalid(false)
	CoherenceRenderer.set_noclip_target(Vector3.ZERO, Vector3.ZERO)
	assert_false(CoherenceRenderer.noclip_invalid)
	assert_eq(CoherenceRenderer.noclip_target_normal, Vector3.ZERO, "zero normal: sphere fallback")


func test_run_start_clears_the_new_state() -> void:
	CoherenceRenderer.set_noclip_target(Vector3.ONE, Vector3.UP)
	CoherenceRenderer.set_noclip_invalid(true)
	CoherenceRenderer.set_static(1.0)
	CoherenceRenderer.pulse(&"drop")
	CoherenceRenderer._on_run_started(&"test", 0)
	assert_false(CoherenceRenderer.noclip_invalid)
	assert_approx(CoherenceRenderer.static_amount, 0.0)
	assert_eq(CoherenceRenderer.noclip_target_normal, Vector3.ZERO)
	assert_eq(CoherenceRenderer.pulse_age(&"drop"), INF)


func test_set_static_reaches_the_screen_pass() -> void:
	CoherenceRenderer.set_static(2.0)
	assert_approx(CoherenceRenderer.static_amount, 1.0, 0.0, "clamped")
	await await_frames(1)
	assert_approx(CoherenceRenderer.post_params[&"grain"], Tuning.POST_STATIC_GRAIN, 0.0001)
	assert_approx(CoherenceRenderer.post_params[&"ca"], Tuning.POST_STATIC_CA, 0.0001)


func test_pulse_kinds_include_ripple_and_drop() -> void:
	assert_contains(Tuning.POST_PULSE_KINDS, &"ripple")
	assert_contains(Tuning.POST_PULSE_KINDS, &"drop")
	CoherenceRenderer.pulse(&"ripple")
	await await_frames(1)
	assert_true(CoherenceRenderer.post_params[&"ripple"] >= 0.0, "ripple running")


func test_drop_pulse_pairs_fall_and_arrival() -> void:
	CoherenceRenderer.pulse(&"drop")
	var fall_age := CoherenceRenderer.pulse_age(&"drop")
	assert_lt(fall_age, 1.0)
	assert_eq(CoherenceRenderer._drop_arrive_usec, -1, "first drop pulse is the fall")
	CoherenceRenderer.pulse(&"drop")
	assert_true(CoherenceRenderer._drop_arrive_usec >= 0, "second drop pulse is the arrival")
	assert_lt(CoherenceRenderer.pulse_age(&"drop"), fall_age + 1.0, "the fall time is kept")
	CoherenceRenderer.pulse(&"drop")
	assert_eq(CoherenceRenderer._drop_arrive_usec, -1, "a third pulse starts a new fall")
	await await_frames(1)
	assert_gt(CoherenceRenderer.post_params[&"black"], -0.0001)


func test_heartbeat_phase_accumulates_at_the_rate() -> void:
	CoherenceRenderer.set_threat(0.0)
	CoherenceRenderer.set_coherence(100.0)
	assert_approx(CoherenceRenderer.heartbeat_bpm(), Tuning.AUDIO_HEARTBEAT_MIN_BPM)
	var p0 := CoherenceRenderer.heartbeat_phase()
	CoherenceRenderer.advance_heartbeat(0.25)
	assert_approx(fposmod(CoherenceRenderer.heartbeat_phase() - p0, 1.0), 0.25, 0.0001, "60 bpm: a beat per second")
	# 06 §7: under 25 Coherence the heartbeat never drops below 90 bpm.
	CoherenceRenderer.set_coherence(10.0)
	assert_approx(CoherenceRenderer.heartbeat_bpm(), Tuning.COHERENCE_HEARTBEAT_FLOOR_BPM)
	p0 = CoherenceRenderer.heartbeat_phase()
	CoherenceRenderer.advance_heartbeat(0.2)
	assert_approx(fposmod(CoherenceRenderer.heartbeat_phase() - p0, 1.0), 0.3, 0.0001)
	CoherenceRenderer.set_threat(1.0)
	assert_approx(CoherenceRenderer.heartbeat_bpm(), Tuning.AUDIO_HEARTBEAT_MAX_BPM)
	assert_true(CoherenceRenderer.heartbeat_phase() >= 0.0 and CoherenceRenderer.heartbeat_phase() < 1.0)
	CoherenceRenderer.set_threat(0.0)


func test_scene_pass_only_while_null_is_present() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	await await_frames(1)
	assert_false(CoherenceRenderer.post_quad().visible, "no Null: no scene pass")
	assert_true(CoherenceRenderer.screen_layer().visible, "the grade always runs with a camera")
	CoherenceRenderer.set_null(Vector3(0.0, 0.0, -8.0), Tuning.NULL_UNRENDER_RADIUS)
	await await_frames(1)
	assert_true(CoherenceRenderer.post_quad().visible)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	await await_frames(1)
	assert_false(CoherenceRenderer.post_quad().visible)
	cam.queue_free()
	await await_frames(1)


func test_register_viewport() -> void:
	var vp := SubViewport.new()
	add_child(vp)
	CoherenceRenderer.register_viewport(vp)
	CoherenceRenderer.register_viewport(vp)
	var before := CoherenceRenderer.registered_viewports().size()
	assert_eq(CoherenceRenderer.registered_viewports().count(vp), 1)
	vp.queue_free()
	await await_frames(1)
	assert_eq(CoherenceRenderer.registered_viewports().size(), before - 1, "dropped when it leaves the tree")
