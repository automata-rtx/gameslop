extends Node
## meta.json I/O with atomic writes (13 Interfaces, 14 §3). Never interprets data.
## TODO(M2.10): schema v1 round trip, migrations, atomic tmp+rename, corrupt backup.

const META_PATH := "user://meta.json"

var _warned: Dictionary = {}


func load_meta() -> MetaState:
	_todo("load_meta (M2.10)")
	return MetaState.new()


func save_meta() -> void:
	_todo("save_meta (M2.10)")


func reset_meta() -> void:
	_todo("reset_meta (M2.10)")


func backup_corrupt(path: String) -> void:
	_todo("backup_corrupt(%s) (M2.10)" % path)


func _todo(what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("not implemented: SaveManager.%s" % what)
