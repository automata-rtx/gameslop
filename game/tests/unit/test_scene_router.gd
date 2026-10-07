extends TestCase
## SceneRouter (14 §3, §5): threaded load, swap under the host, transition hook.

const TARGET := "res://tests/fixtures/router_target.tscn"

var _prev_host: Node
var _host: Node


func before_each() -> void:
	_prev_host = SceneRouter.get_host()
	_host = Node.new()
	add_child(_host)


func after_each() -> void:
	SceneRouter.transition = null
	SceneRouter.set_host(_prev_host)
	_host.free()


func test_api_exists() -> void:
	for m in [&"change_to", &"set_host", &"get_host", &"is_loading", &"current_path", &"current_scene"]:
		assert_true(SceneRouter.has_method(m), "SceneRouter.%s" % m)
	assert_true(SceneRouter.has_signal(&"scene_changed"))
	assert_true(SceneRouter.has_signal(&"scene_failed"))
	assert_true("transition" in SceneRouter, "glitch transition hook")


func test_change_to_swaps_host_child() -> void:
	var old := Node.new()
	_host.add_child(old)
	SceneRouter.set_host(_host)
	assert_eq(SceneRouter.current_scene(), old)
	var changed: Array = []
	var cb := func(p: String) -> void: changed.append(p)
	SceneRouter.scene_changed.connect(cb)
	await SceneRouter.change_to(TARGET)
	SceneRouter.scene_changed.disconnect(cb)
	assert_eq(changed, [TARGET])
	assert_false(SceneRouter.is_loading())
	assert_eq(SceneRouter.current_path(), TARGET)
	var cur := SceneRouter.current_scene()
	assert_not_null(cur)
	if cur != null:
		assert_eq(String(cur.name), "RouterTarget")
		assert_eq(cur.get_parent(), _host)
	await get_tree().process_frame
	assert_false(is_instance_valid(old), "previous scene freed")
	assert_eq(_host.get_child_count(), 1)


func test_transition_hook_plays_out_then_in() -> void:
	SceneRouter.set_host(_host)
	var hook := _Hook.new()
	SceneRouter.transition = hook
	await SceneRouter.change_to(TARGET)
	assert_eq(hook.phases, [&"out", &"in"])


func test_missing_scene_fails_and_keeps_current() -> void:
	var old := Node.new()
	_host.add_child(old)
	SceneRouter.set_host(_host)
	var failed: Array = []
	var cb := func(p: String) -> void: failed.append(p)
	SceneRouter.scene_failed.connect(cb)
	await SceneRouter.change_to("res://tests/fixtures/does_not_exist.tscn")
	SceneRouter.scene_failed.disconnect(cb)
	assert_eq(failed.size(), 1)
	assert_eq(SceneRouter.current_scene(), old)
	assert_false(SceneRouter.is_loading())


func test_change_completes_while_paused() -> void:
	SceneRouter.set_host(_host)
	get_tree().paused = true
	await SceneRouter.change_to(TARGET)
	get_tree().paused = false
	assert_eq(SceneRouter.current_path(), TARGET)


class _Hook extends RefCounted:
	var phases: Array = []

	func play(phase: StringName) -> void:
		phases.append(phase)
		await Engine.get_main_loop().process_frame
