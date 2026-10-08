extends Node
## Settings and bindings (12 Interfaces, 14 §3). Loads user://settings.cfg at startup before
## the title (12 §8: so the window mode is right from the first frame), validates every value
## against its range (SettingsSchema), writes defaults for missing keys, backs a corrupt file
## up as settings.cfg.bad, migrates by `settings_version`, applies every option at once
## (SettingsApply) and persists each change debounced 0.5 s. Window mode and resolution from
## the menu go through try_display: applied now, kept on confirm, reverted after 10 s (12 §1).
## No game logic.

## Two routes, both kept: `changed` is the local signal for nodes that hold a reference
## to this autoload (HUD, player); EventBus.settings_changed is the cross-scene route for
## listeners that must not depend on the autoload (renderer, audio). set_value emits both.
signal changed(key: StringName, value: Variant)
## A binding changed (rebind, clear, reset). Local: the menus redraw their rows.
signal bindings_changed
## The pending window change was kept (true) or reverted (false).
signal display_resolved(kept: bool)

## Setting keys and their defaults (12 §2 to §7), from SettingsSchema.
const DEFAULTS: Dictionary = SettingsSchema.DEFAULTS
## 06 §2: every rebindable action, in menu order. The ui_* built-ins are not rebindable.
const REBINDABLE_ACTIONS: Array[StringName] = Tuning.INPUT_ACTIONS
const FILE_NAME := "settings.cfg"
const TEST_DIR := "user://tests"
const SECTION_META := "meta"
const SECTION_SETTINGS := "settings"
const SECTION_BINDINGS := "bindings"
const KEY_VERSION := "settings_version"
## Version 0 (synthetic, 12 §9 migration test): no settings_version and two older key names.
const V0_RENAMES: Dictionary = {"sensitivity": "mouse_sensitivity", "master_volume": "audio_master"}

## Folder of settings.cfg; empty means user:// (user://tests under the test runner).
var directory: String = ""
## Off for benches that must never write the player's file.
var persist: bool = true
## The millisecond source for the debounce and the revert countdown (tests swap it).
var now_msec: Callable = Time.get_ticks_msec
var bind: SettingsBindings = SettingsBindings.new(REBINDABLE_ACTIONS)

var _values: Dictionary = DEFAULTS.duplicate()
var _dirty: bool = false
var _save_at_msec: int = 0
var _pending_key: StringName = &""
var _pending_old: Variant = null
var _pending_deadline_msec: int = 0
var _focused: bool = true


func _ready() -> void:
	# Settings change from the pause menu, which holds the tree pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	bind.capture_defaults()
	load_settings()
	apply_all()
	EventBus.level_entered.connect(func(_d: int, _s: StringName, _a: StringName) -> void: _apply_graphics())
	get_tree().root.size_changed.connect(func() -> void: SettingsApply.ui_scale(get_tree().root, float(_values[&"ui_scale"])))


func _process(_delta: float) -> void:
	var now: int = now_msec.call()
	if _dirty and now >= _save_at_msec:
		save_settings()
	if _pending_key != &"" and now >= _pending_deadline_msec:
		revert_display()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			_apply_mute()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_apply_mute()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			flush()


# --- values ------------------------------------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return _values.get(key)


## Sets a value (validated against 12's range), applies it, announces it, and saves it
## (debounced). Editing a graphics option the preset sets switches the preset to Custom.
func set_value(key: StringName, v: Variant) -> void:
	if key == &"preset" and (v is String or v is StringName) and StringName(v) != SettingsSchema.PRESET_CUSTOM:
		apply_preset(StringName(v))
		return
	_store(key, v)
	if key in SettingsSchema.PRESET_KEYS and _values[&"preset"] != SettingsSchema.PRESET_CUSTOM \
			and SettingsSchema.preset_values(_values[&"preset"]).get(key) != _values[key]:
		_store(&"preset", SettingsSchema.PRESET_CUSTOM)


## 12 §3: Low, Medium or High sets every graphics option; Custom keeps them.
func apply_preset(preset_name: StringName) -> void:
	var vals := SettingsSchema.preset_values(preset_name)
	for key: StringName in vals:
		_store(key, vals[key])
	_store(&"preset", preset_name if SettingsSchema.PRESETS.has(preset_name) else SettingsSchema.PRESET_CUSTOM)


## 04 §7 RESET TAB TO DEFAULTS; the Controls tab also restores the default key map (12 §5).
func reset_tab(tab: StringName) -> void:
	for key in SettingsSchema.keys_for(tab):
		if key != &"preset":
			_store(key, DEFAULTS[key])
	if tab == SettingsSchema.TAB_GRAPHICS:
		apply_preset(DEFAULTS[&"preset"])
	if tab == SettingsSchema.TAB_CONTROLS:
		reset_bindings()


func _store(key: StringName, v: Variant) -> void:
	var valid: Variant = SettingsSchema.validate(key, v)
	if _values.has(key) and typeof(_values[key]) == typeof(valid) and _values[key] == valid:
		return
	_values[key] = valid
	_apply(key)
	if SettingsSchema.has_key(key):
		_mark_dirty()
	changed.emit(key, valid)
	EventBus.settings_changed.emit(key, valid)


# --- window changes with the revert countdown (12 §1) ---------------------------------------

## Applies a window mode or resolution now; it is kept by keep_display() and reverted by
## revert_display() or after Tuning.SETTINGS_REVERT_COUNTDOWN seconds.
func try_display(key: StringName, v: Variant) -> void:
	if not key in SettingsSchema.REVERT_KEYS:
		set_value(key, v)
		return
	if _pending_key != &"" and _pending_key != key:
		keep_display()
	if _pending_key == &"":
		_pending_old = _values[key]
	_pending_key = key
	_pending_deadline_msec = int(now_msec.call()) + int(Tuning.SETTINGS_REVERT_COUNTDOWN * 1000.0)
	_store(key, v)
	if _values[key] == _pending_old:
		_pending_key = &""


func keep_display() -> void:
	if _pending_key == &"":
		return
	_pending_key = &""
	display_resolved.emit(true)


func revert_display() -> void:
	if _pending_key == &"":
		return
	var key := _pending_key
	_pending_key = &""
	_store(key, _pending_old)
	display_resolved.emit(false)


func is_display_pending() -> bool:
	return _pending_key != &""


func display_seconds_left() -> int:
	if _pending_key == &"":
		return 0
	return maxi(0, ceili(float(_pending_deadline_msec - int(now_msec.call())) / 1000.0))


# --- bindings (12 §5) ----------------------------------------------------------------------------

## action -> Array[InputEvent] in slot order (primary, secondary), filled slots only.
func bindings() -> Dictionary:
	return bind.as_events()


func binding(action: StringName, slot: int) -> InputEvent:
	return bind.get_event(action, slot)


## Binds `event` to `action` at `slot` (0 primary, 1 secondary). On a conflict the two
## slots swap; the partner action is returned (&"" when none) so the menu can flash both rows.
func rebind(action: StringName, event: InputEvent, slot: int = 0) -> StringName:
	var partner := bind.rebind(action, event, slot)
	_bindings_changed()
	return partner


func clear_binding(action: StringName, slot: int) -> void:
	bind.clear(action, slot)
	_bindings_changed()


func reset_bindings() -> void:
	bind.reset()
	_bindings_changed()


func _bindings_changed() -> void:
	_mark_dirty()
	bindings_changed.emit()


# --- persistence (12 §8, 13 §1) ----------------------------------------------------------------

func settings_path() -> String:
	return _dir().path_join(FILE_NAME)


func bad_path() -> String:
	return settings_path() + Tuning.SETTINGS_BACKUP_SUFFIX


## Reads settings.cfg: validates, migrates, fills defaults; a corrupt file becomes .bad.
func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	bind.reset()
	var path := settings_path()
	if not FileAccess.file_exists(path):
		_mark_dirty()
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("SettingsManager: %s is corrupt; backed up as %s" % [path, bad_path()])
		_backup_corrupt(path)
		_mark_dirty()
		return
	var version := int(cfg.get_value(SECTION_META, KEY_VERSION, 0)) if cfg.get_value(SECTION_META, KEY_VERSION, 0) is int else 0
	var raw := migrate(_section(cfg, SECTION_SETTINGS), version)
	var complete := version == Tuning.SETTINGS_VERSION
	for key: StringName in DEFAULTS:
		if raw.has(String(key)):
			var valid: Variant = SettingsSchema.validate(key, raw[String(key)])
			complete = complete and _same(valid, raw[String(key)])
			_values[key] = valid
		else:
			complete = false
	bind.from_texts(_section(cfg, SECTION_BINDINGS))
	if not complete:
		_mark_dirty()


## Writes settings.cfg now. False when the file cannot be written.
func save_settings() -> bool:
	_dirty = false
	if not persist:
		return true
	DirAccess.make_dir_recursive_absolute(_dir())
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_META, KEY_VERSION, Tuning.SETTINGS_VERSION)
	for key: StringName in DEFAULTS:
		var v: Variant = _values[key]
		cfg.set_value(SECTION_SETTINGS, String(key), String(v) if v is StringName else v)
	var texts := bind.to_texts()
	for action: StringName in texts:
		cfg.set_value(SECTION_BINDINGS, String(action), texts[action])
	var err := cfg.save(settings_path())
	if err != OK:
		push_error("SettingsManager: cannot write %s (%s)" % [settings_path(), error_string(err)])
		return false
	return true


## Writes now if a change is waiting for its debounce.
func flush() -> void:
	if _dirty:
		save_settings()


func is_dirty() -> bool:
	return _dirty


## settings.cfg migrations by settings_version (12 §8). Version 0 had two older key names.
static func migrate(raw: Dictionary, version: int) -> Dictionary:
	var out := raw.duplicate()
	if version < 1:
		for old: String in V0_RENAMES:
			if out.has(old) and not out.has(V0_RENAMES[old]):
				out[V0_RENAMES[old]] = out[old]
			out.erase(old)
	return out


func _section(cfg: ConfigFile, section: String) -> Dictionary:
	var out: Dictionary = {}
	if cfg.has_section(section):
		for k in cfg.get_section_keys(section):
			out[k] = cfg.get_value(section, k)
	return out


func _mark_dirty() -> void:
	_dirty = true
	_save_at_msec = int(now_msec.call()) + int(Tuning.SETTINGS_SAVE_DEBOUNCE * 1000.0)


func _backup_corrupt(path: String) -> void:
	if FileAccess.file_exists(bad_path()):
		DirAccess.remove_absolute(bad_path())
	DirAccess.rename_absolute(path, bad_path())


func _dir() -> String:
	if directory.is_empty():
		directory = "user://"
		if SaveManager._under_test_runner():
			# Tests never touch the player's settings (as SaveManager does for meta.json).
			directory = TEST_DIR
			DirAccess.make_dir_recursive_absolute(TEST_DIR)
			for name in [FILE_NAME, FILE_NAME + Tuning.SETTINGS_BACKUP_SUFFIX]:
				if FileAccess.file_exists(TEST_DIR.path_join(name)):
					DirAccess.remove_absolute(TEST_DIR.path_join(name))
	return directory


static func _same(a: Variant, b: Variant) -> bool:
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


# --- application (12 §1) -------------------------------------------------------------------------

## Applies every option (boot, after a load).
func apply_all() -> void:
	if _window_allowed():
		SettingsApply.window(_values)
	SettingsApply.vsync(_values[&"vsync"])
	SettingsApply.max_fps(int(_values[&"max_fps"]))
	SettingsApply.ui_scale(get_tree().root, float(_values[&"ui_scale"]))
	SettingsApply.raw_mouse(bool(_values[&"raw_mouse"]))
	SettingsApply.output_device(String(_values[&"audio_output_device"]))
	SettingsApply.colorblind(bool(_values[&"colorblind_accent"]))
	SettingsApply.text_size(float(_values[&"text_size"]))
	_apply_graphics()
	_apply_mute()


func _apply(key: StringName) -> void:
	if not is_inside_tree():
		return
	match key:
		&"window_mode", &"resolution":
			if _window_allowed():
				SettingsApply.window(_values)
			SettingsApply.ui_scale(get_tree().root, float(_values[&"ui_scale"]))
		&"vsync":
			SettingsApply.vsync(_values[key])
		&"max_fps":
			SettingsApply.max_fps(int(_values[key]))
		&"ui_scale":
			SettingsApply.ui_scale(get_tree().root, float(_values[key]))
		&"raw_mouse":
			SettingsApply.raw_mouse(bool(_values[key]))
		&"audio_output_device":
			SettingsApply.output_device(String(_values[key]))
		&"mute_unfocused":
			_apply_mute()
		&"colorblind_accent":
			SettingsApply.colorblind(bool(_values[key]))
		&"text_size":
			SettingsApply.text_size(float(_values[key]))
		_:
			if key in SettingsApply.GRAPHICS_KEYS:
				_apply_graphics()


func _apply_graphics() -> void:
	if is_inside_tree():
		SettingsApply.graphics(get_tree().root, _values)


func _apply_mute() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, bool(_values[&"mute_unfocused"]) and not _focused)


## The command line wins over the saved window (benches, `--resolution`, `--windowed`).
static func _window_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_args():
		if a in ["--resolution", "--windowed", "-w", "--fullscreen", "-f", "--position", "--maximized", "-m"]:
			return false
	return true
