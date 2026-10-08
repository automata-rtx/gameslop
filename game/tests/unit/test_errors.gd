extends TestCase
## M1.7 error architecture, pure logic and contracts: the 08 §8 aggression mapping, the
## 08 §2 suspicion table, the error scenes (layers, sizes, no shadows), the two error
## shaders (compile, constants mirror Tuning, the coherence include), and no unseeded
## randomness in the error code.

const ERROR_SCRIPTS := "res://src/errors"
## Screen and depth samplers and instance uniforms are not listed by
## get_shader_uniform_list, so the check is on the source; compilation is verified by the
## error_arena render (tools/ci/render.sh).
const SHADERS: Dictionary = {
	"res://shaders/static_field.gdshader": ["hint_screen_texture", "hint_depth_texture", "instance uniform float radius"],
	"res://shaders/still_column.gdshader": ["instance uniform float line_on", "instance uniform float line_height"],
}

var _const_re := RegEx.create_from_string(
		"^\\s*const\\s+(float|int)\\s+(\\w+)\\s*=\\s*([^;]+);\\s*(//\\s*(.*))?$")


func test_aggression_mapping_clamps_outside_the_columns() -> void:
	assert_approx(ErrorBase.aggr_t(0.0), 0.0)
	assert_approx(ErrorBase.aggr_t(0.25), 0.0)
	assert_approx(ErrorBase.aggr_t(0.5), 0.5)
	assert_approx(ErrorBase.aggr_t(0.75), 1.0)
	assert_approx(ErrorBase.aggr_t(1.0), 1.0, 0.0, "1.0 uses the 0.75 column")
	assert_approx(ErrorBase.aggr_lerp(0.3, 0.6, 0.5), 0.45, 0.0001)


func test_suspicion_table() -> void:
	assert_approx(Senses.suspicion_for(&"step"), 0.6)
	assert_approx(Senses.suspicion_for(&"tear"), 1.0)
	assert_approx(Senses.suspicion_for(&"door"), 1.0)
	assert_approx(Senses.suspicion_for(&"mech"), 1.0)
	assert_approx(Senses.suspicion_for(&"impact"), 0.0)


func test_suspicion_decays_and_grows() -> void:
	var s := Senses.new()
	add_child(s)
	s.register_noise(Vector3.ZERO, 5.0, &"step")
	assert_approx(s.suspicion, 0.6)
	assert_true(s.has_last_known())
	s.tick(1.0, null)
	assert_approx(s.suspicion, 0.1, 0.0001, "0.5 per second")
	s.tick(1.0, null)
	assert_approx(s.suspicion, 0.0)
	s.free()


func test_scenes_exist_for_static_and_still() -> void:
	for id: StringName in [&"static", &"still"]:
		var e := ErrorBase.create(id)
		assert_not_null(e, String(id))
		add_child(e)
		assert_eq(e.error_id, id)
		assert_true(e.is_in_group(ErrorBase.GROUP), "registers in group errors")
		assert_eq(e.state, Tuning.ERROR_STATE_DORMANT, "spawns Dormant")
		assert_not_null(e.data)
		e.free()
	assert_null(ErrorBase.create(&"nothing"))


func test_still_scene_contract() -> void:
	var s := ErrorBase.create(&"still") as ErrorStill
	add_child(s)
	assert_eq(s.body.collision_layer, 1 << (Tuning.LAYER_ERRORS - 1), "layer 3")
	var shape := (s.body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	assert_approx(shape.radius, Tuning.STILL_CAPSULE_RADIUS)
	assert_approx(shape.height, Tuning.STILL_CAPSULE_HEIGHT)
	var mesh := s.column.mesh as CapsuleMesh
	assert_approx(mesh.radius, Tuning.STILL_CAPSULE_RADIUS)
	assert_approx(mesh.height, Tuning.STILL_CAPSULE_HEIGHT)
	assert_eq(s.column.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "never casts a shadow")
	assert_true(s.agent.avoidance_enabled, "avoidance on movers")
	assert_approx(s.senses.sight_range, Tuning.STILL_SIGHT_RANGE)
	assert_eq(s.observe_points().size(), 2, "centre and top")
	s.free()


func test_static_scene_contract() -> void:
	var s := ErrorBase.create(&"static") as ErrorStatic
	add_child(s)
	assert_eq(s.mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_approx(s.senses.sight_range, 0.0, 0.0, "Static is blind")
	assert_approx(s.centre().y - s.global_position.y, Tuning.STATIC_CENTRE_HEIGHT, 0.0001)
	assert_false(s.field.monitoring, "the drain is computed, not overlap-driven")
	s.free()


func test_error_shaders_compile_and_mirror_tuning() -> void:
	var tuning: Dictionary = (load("res://src/core/tuning.gd") as GDScript).get_script_constant_map()
	for path: String in SHADERS:
		var shader := load(path) as Shader
		assert_not_null(shader, path)
		var text := FileAccess.get_file_as_string(path)
		for u: String in SHADERS[path]:
			assert_contains(text, u, path)
		for line in text.split("\n"):
			var m := _const_re.search(line)
			if m == null:
				continue
			var note := m.get_string(5).strip_edges()
			if note.begins_with("shader-local"):
				continue
			var tname := note.split(" ")[0]
			assert_true(tuning.has(tname), "%s %s names a Tuning constant" % [path, m.get_string(2)])
			if tuning.has(tname):
				assert_approx(float(m.get_string(3)), float(tuning[tname]), 0.00001, "%s %s" % [path, tname])
	assert_contains(FileAccess.get_file_as_string("res://shaders/static_field.gdshader"),
			"#include \"res://shaders/include/coherence.gdshaderinc\"")
	var still := FileAccess.get_file_as_string("res://shaders/still_column.gdshader")
	assert_contains(still, "unshaded")
	assert_contains(still, "shadows_disabled")


## CLAUDE.md: seeded RandomNumberGenerator only in gameplay code.
func test_no_unseeded_randomness() -> void:
	var re := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randomize)\\s*\\(")
	var dir := DirAccess.open(ERROR_SCRIPTS)
	assert_not_null(dir)
	var checked := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(ERROR_SCRIPTS.path_join(f))
		assert_null(re.search(text), "%s uses unseeded randomness" % f)
		checked += 1
	assert_gt(checked, 3)
