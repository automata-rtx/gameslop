extends Node
## Settings and bindings (12 Interfaces, 14 §3). No game logic.
## M0.2: an in-memory value store that announces changes, and bindings read from
## the InputMap. TODO(M2.11): load/validate/persist user://settings.cfg (12 §8),
## presets, tab reset, rebinding with conflict swap (12 §5).

## Two routes, both kept: `changed` is the local signal for nodes that hold a reference
## to this autoload (HUD, player); EventBus.settings_changed is the cross-scene route for
## listeners that must not depend on the autoload (renderer, audio). set_value emits both.
signal changed(key: StringName, value: Variant)

## Setting keys and their defaults (12 §3 to §6), from Tuning. Seeded into `_values` so
## get_value never returns null for a known key before M2.11 loads settings.cfg.
const DEFAULTS: Dictionary = {
	&"mouse_sensitivity": Tuning.PLAYER_MOUSE_SENS_DEFAULT,
	&"fov": Tuning.SETTINGS_FOV_DEFAULT,
	&"head_bob": Tuning.SETTINGS_HEAD_BOB_DEFAULT,
	&"screen_shake": Tuning.SETTINGS_SHAKE_DEFAULT,
	&"invert_y": false,
	&"sprint_mode": &"hold",   # &"hold" or &"toggle" (12 §5)
	&"crouch_mode": &"hold",
	&"hold_to_press": false,   # 12 §6 accessibility
	&"render_scale": Tuning.SETTINGS_RENDER_SCALE_DEFAULT,
	&"ui_scale": Tuning.SETTINGS_UI_SCALE_DEFAULT,
	&"text_size": Tuning.SETTINGS_TEXT_SIZE_DEFAULT,
	&"brightness": Tuning.SETTINGS_BRIGHTNESS_DEFAULT,
	&"flicker_intensity": Tuning.SETTINGS_FLICKER_INTENSITY_DEFAULT,
	&"audio_master": Tuning.SETTINGS_AUDIO_MASTER_DEFAULT,
	&"audio_effects": Tuning.SETTINGS_AUDIO_EFFECTS_DEFAULT,
	&"audio_ambience": Tuning.SETTINGS_AUDIO_AMBIENCE_DEFAULT,
	&"audio_music": Tuning.SETTINGS_AUDIO_MUSIC_DEFAULT,
	&"audio_ui": Tuning.SETTINGS_AUDIO_UI_DEFAULT,
	&"mute_unfocused": Tuning.SETTINGS_MUTE_UNFOCUSED_DEFAULT,
	&"preset": Tuning.SETTINGS_PRESET_DEFAULT,
}

## 06 §2: every rebindable action, in menu order. The ui_* built-ins are not rebindable.
const REBINDABLE_ACTIONS: Array[StringName] = Tuning.INPUT_ACTIONS

var _values: Dictionary = DEFAULTS.duplicate()
var _warned: Dictionary = {}


func _ready() -> void:
	# Settings change from the pause menu, which holds the tree pause.
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_value(key: StringName) -> Variant:
	return _values.get(key)


func set_value(key: StringName, v: Variant) -> void:
	if _values.has(key) and _values[key] == v:
		return
	_values[key] = v
	changed.emit(key, v)
	EventBus.settings_changed.emit(key, v)


func apply_preset(preset_name: StringName) -> void:
	_todo("apply_preset(%s) (12 §3, M2.11)" % preset_name)


func reset_tab(tab: StringName) -> void:
	_todo("reset_tab(%s) (12 §5, M2.11)" % tab)


## action -> Array[InputEvent] in slot order (primary, secondary), from the live InputMap.
func bindings() -> Dictionary:
	var out: Dictionary = {}
	for action in REBINDABLE_ACTIONS:
		out[action] = InputMap.action_get_events(action) if InputMap.has_action(action) else []
	return out


func rebind(action: StringName, event: InputEvent, slot: int) -> void:
	_todo("rebind(%s, %s, %d) (12 §5, M2.11)" % [action, event, slot])


func _todo(what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("not implemented: SettingsManager.%s" % what)
