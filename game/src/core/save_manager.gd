extends Node
## meta.json I/O with atomic writes (13 Interfaces, 14 §3). Never interprets data: the schema,
## validation and migrations are MetaSchema's; GameState decides when to save (13 §3).
## Writes go to meta.json.tmp and are renamed over meta.json, so a crash leaves either the
## old file or the new one (13 §1). A file that cannot be read is renamed meta.json.bad and a
## fresh Archive starts; the title shows ARCHIVE RESET once (13 §2, 14 §12).
## Under the headless test runner (or any SceneTree script) the files live in user://tests/,
## wiped at start, so tests never read or write the player's Archive.

const DEFAULT_DIR := "user://"
const TEST_DIR := "user://tests"
const META_NAME := "meta.json"
const TMP_SUFFIX := ".tmp"
const BAD_SUFFIX := ".bad"
const JSON_INDENT := "\t"

## Where meta.json lives. Empty until first use, then DEFAULT_DIR or TEST_DIR. Tests may set it.
var directory: String = ""
## Test hook: when true, save_meta writes the tmp file and stops before the rename (a crash).
var crash_before_rename: bool = false

var _reset_notice: bool = false


func meta_path() -> String:
	return _dir().path_join(META_NAME)


func tmp_path() -> String:
	return meta_path() + TMP_SUFFIX


func bad_path() -> String:
	return meta_path() + BAD_SUFFIX


## Reads meta.json. Missing: a fresh MetaState (nothing is written until the first save).
## Unreadable: backed up as meta.json.bad, a fresh file is written, and the reset notice is set.
## A leftover meta.json.tmp is used only when meta.json itself is missing (crash mid-rename).
func load_meta() -> MetaState:
	var path := meta_path()
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(tmp_path()):
			var rescued := _read(tmp_path())
			if not rescued.is_empty():
				var m := MetaSchema.from_dict(rescued)
				save_meta(m)
				return m
		return MetaState.new()
	var d := _read(path)
	if d.is_empty():
		push_warning("SaveManager: %s is unreadable; the Archive is reset (13 §2)" % path)
		backup_corrupt(path)
		_reset_notice = true
		var fresh := MetaState.new()
		save_meta(fresh)
		return fresh
	_remove(tmp_path())  # stale tmp from a crash after a good rename (13 §7)
	return MetaSchema.from_dict(d)


## Writes `meta` (GameState.meta when null) atomically. Returns false on an I/O failure.
func save_meta(meta: MetaState = null) -> bool:
	var m: MetaState = meta if meta != null else GameState.meta
	if m == null:
		return false
	var text := JSON.stringify(m.to_dict(), JSON_INDENT)
	DirAccess.make_dir_recursive_absolute(_dir())
	var tmp := tmp_path()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	var err := f.get_error()
	f.close()
	if err != OK:
		push_error("SaveManager: write failed for %s (%s)" % [tmp, error_string(err)])
		return false
	if crash_before_rename:
		return false
	return _replace(tmp, meta_path())


## Starts a fresh Archive: writes it and hands it to GameState.
func reset_meta() -> MetaState:
	var fresh := MetaState.new()
	save_meta(fresh)
	GameState.meta = fresh
	return fresh


## Moves an unreadable file aside as <path>.bad (one backup; an older one is replaced).
func backup_corrupt(path: String) -> void:
	var bad := path + BAD_SUFFIX
	_remove(bad)
	var err := DirAccess.rename_absolute(path, bad)
	if err != OK:
		push_error("SaveManager: cannot back up %s (%s)" % [path, error_string(err)])
		_remove(path)


func has_reset_notice() -> bool:
	return _reset_notice


## 13 §2: the title shows `ARCHIVE RESET` once. Returns it the first time, then "".
func consume_reset_notice() -> String:
	if not _reset_notice:
		return ""
	_reset_notice = false
	return Strings.TITLE_ARCHIVE_RESET


## The parsed top-level object, or {} when the file is missing, empty, not JSON, not an
## object, or of a version that cannot be migrated.
func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if text.strip_edges().is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return MetaSchema.migrate(json.data)


## Renames `from` over `to`. Some platforms refuse to rename onto an existing file; then
## the old file is removed first (the tmp file still holds the data if that step dies).
func _replace(from: String, to: String) -> bool:
	if DirAccess.rename_absolute(from, to) == OK:
		return true
	_remove(to)
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		push_error("SaveManager: cannot rename %s (%s)" % [from, error_string(err)])
		return false
	return true


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _dir() -> String:
	if directory.is_empty():
		directory = DEFAULT_DIR
		if _under_test_runner():
			directory = TEST_DIR
			for name in [META_NAME, META_NAME + TMP_SUFFIX, META_NAME + BAD_SUFFIX]:
				_remove(TEST_DIR.path_join(name))
	return directory


## The game's main loop is a plain SceneTree; the test runner and CI tools are scripts.
static func _under_test_runner() -> bool:
	var ml := Engine.get_main_loop()
	if ml != null and ml.get_script() != null:
		return true
	var args := OS.get_cmdline_args()
	return args.has("--script") or args.has("-s")
