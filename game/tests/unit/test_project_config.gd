extends TestCase
## project.godot carries what 14 §1, §3, §7, §11 and 06 §2 require.

## 14 §3, in order.
const AUTOLOADS: Array[String] = [
	"EventBus", "GameState", "SettingsManager", "SaveManager",
	"AudioManager", "CoherenceRenderer", "Clock", "SceneRouter",
]

## 14 §7.
const LAYERS: Array[String] = ["world", "player", "errors", "interactable", "items", "hide_spots", "water", "thrown"]

## 14 §11: name -> [type, default].
const GLOBALS := {
	"g_coherence": ["float", 1.0],
	"g_noclip_charge": ["float", 0.0],
	"g_noclip_commit": ["float", 0.0],
	"g_null_pos": ["vec3", Vector3(0, -1000, 0)],
	"g_null_radius": ["float", 0.0],
	"g_time": ["float", 0.0],
}

## 06 §2 defaults: action -> physical keycode (int) or "mouse:<button index>".
const BINDINGS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"sprint": KEY_SHIFT, "crouch": KEY_CTRL, "interact": KEY_E, "flashlight": KEY_F, "crank": KEY_R,
	"noclip": "mouse:1", "use_item": "mouse:2",
	"item_1": KEY_1, "item_2": KEY_2, "item_3": KEY_3, "item_4": KEY_4,
	"item_next": "mouse:5", "item_prev": "mouse:4",
	"status": KEY_TAB, "pause": KEY_ESCAPE,
}


func test_autoloads_exist_in_order() -> void:
	var root := get_tree().root
	var last := -1
	for name in AUTOLOADS:
		var node := root.get_node_or_null(NodePath(name))
		assert_not_null(node, "/root/%s" % name)
		assert_true(ProjectSettings.has_setting("autoload/" + name), "autoload/%s" % name)
		if node != null:
			assert_gt(node.get_index(), last, "%s after the previous autoload" % name)
			last = node.get_index()


func test_exactly_eight_autoloads() -> void:
	var n := 0
	for p: Dictionary in ProjectSettings.get_property_list():
		if String(p["name"]).begins_with("autoload/"):
			n += 1
	assert_eq(n, 8, "14 §3: exactly these eight")


func test_renderer_physics_main_scene() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "forward_plus")
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/main.tscn")
	assert_true(ResourceLoader.exists("res://scenes/main.tscn"), "main scene exists")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "disabled", "no stretch for 3D")


func test_physics_layer_names() -> void:
	for i in LAYERS.size():
		assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % (i + 1)), LAYERS[i], "layer %d" % (i + 1))


func test_shader_globals() -> void:
	for name: String in GLOBALS:
		var key := "shader_globals/" + name
		assert_true(ProjectSettings.has_setting(key), key)
		var v: Variant = ProjectSettings.get_setting(key)
		if not (v is Dictionary):
			fail("%s is not a Dictionary" % key)
			continue
		assert_eq((v as Dictionary).get("type"), GLOBALS[name][0], "%s type" % name)
		assert_eq((v as Dictionary).get("value"), GLOBALS[name][1], "%s default" % name)


func test_input_actions_and_defaults() -> void:
	for action: String in BINDINGS:
		assert_true(InputMap.has_action(action), "action %s" % action)
		if not InputMap.has_action(action):
			continue
		var events := InputMap.action_get_events(action)
		assert_eq(events.size(), 1, "%s has one default binding" % action)
		if events.is_empty():
			continue
		var want: Variant = BINDINGS[action]
		var ev := events[0]
		if want is String:
			assert_true(ev is InputEventMouseButton, "%s is a mouse button" % action)
			if ev is InputEventMouseButton:
				assert_eq("mouse:%d" % (ev as InputEventMouseButton).button_index, want, action)
		else:
			assert_true(ev is InputEventKey, "%s is a key" % action)
			if ev is InputEventKey:
				# 12 §5: physical keycodes are stored so layouts map by position.
				assert_eq((ev as InputEventKey).physical_keycode, want, action)


func test_left_modifiers_are_left() -> void:
	for action in ["sprint", "crouch"]:
		var ev := InputMap.action_get_events(action)[0] as InputEventKey
		assert_eq(ev.location, KEY_LOCATION_LEFT, "%s is the left-hand key (06 §2)" % action)


func test_rebindable_list_matches_input_map() -> void:
	var listed: Array[StringName] = SettingsManager.REBINDABLE_ACTIONS
	assert_eq(listed.size(), BINDINGS.size())
	for action: String in BINDINGS:
		assert_contains(listed, StringName(action))
	var b: Dictionary = SettingsManager.bindings()
	assert_eq(b.size(), BINDINGS.size())


func test_main_scene_boots_to_title_placeholder() -> void:
	var prev_host := SceneRouter.get_host()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var content := main.get_node(^"%Content")
	assert_eq(SceneRouter.get_host(), content, "main registers %Content as the router host")
	var label := content.find_child("Wordmark", true, false) as Label
	assert_not_null(label)
	if label != null:
		assert_eq(label.text, "NOCLIP")
	assert_eq(main.process_mode, Node.PROCESS_MODE_INHERIT, "main stays pausable")
	main.free()
	SceneRouter.set_host(prev_host)
