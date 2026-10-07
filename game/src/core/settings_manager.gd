extends Node
## Settings and bindings (12 Interfaces, 14 §3). No game logic.
## M0.2: an in-memory value store that announces changes, and bindings read from
## the InputMap. TODO(M2.11): load/validate/persist user://settings.cfg (12 §8),
## presets, tab reset, rebinding with conflict swap (12 §5).

signal changed(key: StringName, value: Variant)

## 06 §2: every rebindable action, in menu order. The ui_* built-ins are not rebindable.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"sprint", &"crouch", &"interact", &"flashlight", &"crank",
	&"noclip", &"use_item",
	&"item_1", &"item_2", &"item_3", &"item_4", &"item_next", &"item_prev",
	&"status", &"pause",
]

var _values: Dictionary = {}
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
