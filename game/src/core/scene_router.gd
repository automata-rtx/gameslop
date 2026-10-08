extends Node
## Scene changes with the glitch transition and threaded loads (14 §3, §5).
## main.tscn registers its content node as the host; the routed scene is the host's
## only child. Without a host (tests, --script runs) it falls back to the tree's
## current scene. Runs while paused so a change requested from a menu completes.

## Emitted after the new scene is in the tree and the transition-in has played.
signal scene_changed(path: String)
## Emitted when a requested scene cannot be loaded; the current scene stays.
signal scene_failed(path: String)

## The GlitchTransition (GLOSSARY; 04) plugs in here. Any object with
## `play(phase: StringName)` (phase &"out" or &"in"), which may be a coroutine.
## TODO(M2.11): GlitchTransition (120 ms sliced screen) assigns itself.
var transition: Object = null

var _host: Node = null
var _loading_path: String = ""
var _current_path: String = ""
var _current: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## The node whose single child is the routed scene (main.tscn's %Content).
func set_host(host: Node) -> void:
	_host = host
	_current = null
	if host != null and host.get_child_count() > 0:
		_current = host.get_child(host.get_child_count() - 1)


func get_host() -> Node:
	return _host


## Load `path` on a worker thread, play the transition out, swap, play it in.
## Returns when the change is complete (or failed). Requests while loading are refused.
## `with_transition` false swaps without the glitch (M2.15: the Threshold's cut to white is
## its own transition, 01 §8; the glitch and its sound would break the single low tone).
func change_to(path: String, with_transition: bool = true) -> void:
	if is_loading():
		push_warning("SceneRouter: change_to(%s) ignored while loading %s" % [path, _loading_path])
		return
	if not ResourceLoader.exists(path, "PackedScene"):
		push_warning("SceneRouter: no scene at %s" % path)
		scene_failed.emit(path)
		return
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		push_warning("SceneRouter: threaded load request failed for %s (%s)" % [path, error_string(err)])
		scene_failed.emit(path)
		return
	_loading_path = path
	if with_transition:
		await _play_transition(&"out")
	var packed := await _await_threaded(path)
	_loading_path = ""
	if packed == null:
		if with_transition:
			await _play_transition(&"in")
		scene_failed.emit(path)
		return
	_swap(packed.instantiate(), path)
	if with_transition:
		await _play_transition(&"in")
	scene_changed.emit(path)


func is_loading() -> bool:
	return not _loading_path.is_empty()


func current_path() -> String:
	return _current_path


func current_scene() -> Node:
	return _current if is_instance_valid(_current) else null


func _await_threaded(path: String) -> PackedScene:
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path) as PackedScene
			_:
				push_warning("SceneRouter: threaded load failed for %s" % path)
				return null
	return null


func _swap(scene: Node, path: String) -> void:
	var old := current_scene()
	if _host != null and is_instance_valid(_host):
		if old != null and old.get_parent() == _host:
			_host.remove_child(old)
			old.queue_free()
		_host.add_child(scene)
	else:
		var tree := get_tree()
		var tree_current := tree.current_scene
		tree.root.add_child(scene)
		tree.current_scene = scene
		if tree_current != null:
			tree_current.queue_free()
	_current = scene
	_current_path = path


## The glitch transition hook. A stub until the GlitchTransition exists: no wait.
func _play_transition(phase: StringName) -> void:
	if transition != null and transition.has_method(&"play"):
		await transition.call(&"play", phase)
