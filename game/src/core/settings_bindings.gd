class_name SettingsBindings
extends RefCounted
## The key bindings of 12 §5: every rebindable action (06 §2) has a primary and a secondary
## slot; each slot holds a key (stored by physical keycode, so a layout maps by position), a
## mouse button (wheel included), or nothing. The InputMap is rebuilt from the slots after
## every change. Conflicts swap: binding an input another slot holds moves this slot's old
## input to that slot (04 §7). Serialised as text for settings.cfg: `key:<physical>:<location>`,
## `mouse:<button>`, or an empty string.

const SLOTS := Tuning.SETTINGS_BINDING_SLOTS
const PREFIX_KEY := "key"
const PREFIX_MOUSE := "mouse"

var actions: Array[StringName] = []
## action -> Array of SLOTS entries (InputEvent or null).
var slots: Dictionary = {}
## action -> Array of SLOTS texts, the project's InputMap at boot (06 §2 defaults).
var defaults: Dictionary = {}


func _init(action_list: Array[StringName] = []) -> void:
	actions = action_list


## Reads the project's InputMap as the default map (call once, before any rebind).
func capture_defaults() -> void:
	for action in actions:
		var texts: Array = []
		var events: Array[InputEvent] = InputMap.action_get_events(action) if InputMap.has_action(action) else []
		for i in SLOTS:
			texts.append(event_to_text(events[i]) if i < events.size() else "")
		defaults[action] = texts
	reset()


func reset() -> void:
	for action in actions:
		var row: Array = []
		for t in defaults.get(action, []):
			row.append(text_to_event(String(t)))
		while row.size() < SLOTS:
			row.append(null)
		slots[action] = row
	apply_all()


func get_event(action: StringName, slot: int) -> InputEvent:
	var row: Array = slots.get(action, [])
	return row[slot] if slot >= 0 and slot < row.size() else null


## Binds `event` to `action` at `slot`. Returns the action whose slot gave the input up
## (the swap partner, possibly `action` itself for a slot swap), or &"" when nothing swapped.
func rebind(action: StringName, event: InputEvent, slot: int) -> StringName:
	if not slots.has(action) or slot < 0 or slot >= SLOTS:
		return &""
	var clean := normalized(event)
	if clean == null:
		return &""
	var old: InputEvent = get_event(action, slot)
	var partner := &""
	for other: StringName in actions:
		for j in SLOTS:
			if other == action and j == slot:
				continue
			if same_input(get_event(other, j), clean):
				slots[other][j] = old
				partner = other
				if other != action:
					_apply(other)
	slots[action][slot] = clean
	_apply(action)
	return partner


func clear(action: StringName, slot: int) -> void:
	if slots.has(action) and slot >= 0 and slot < SLOTS:
		slots[action][slot] = null
		_apply(action)


## action -> Array[InputEvent] of the filled slots in slot order (SettingsManager.bindings()).
func as_events() -> Dictionary:
	var out: Dictionary = {}
	for action in actions:
		var list: Array[InputEvent] = []
		for ev: Variant in slots.get(action, []):
			if ev != null:
				list.append(ev as InputEvent)
		out[action] = list
	return out


## action -> Array of SLOTS texts (settings.cfg [bindings]).
func to_texts() -> Dictionary:
	var out: Dictionary = {}
	for action in actions:
		var texts: Array = []
		for ev: Variant in slots.get(action, []):
			texts.append(event_to_text(ev as InputEvent) if ev != null else "")
		out[action] = texts
	return out


## Loads texts for the actions present; malformed entries keep the default slot.
func from_texts(d: Dictionary) -> void:
	for action in actions:
		var v: Variant = d.get(String(action), d.get(action, null))
		if not (v is Array):
			continue
		var row: Array = []
		for i in SLOTS:
			var t := String((v as Array)[i]) if i < (v as Array).size() and (v as Array)[i] is String else ""
			row.append(text_to_event(t))
		slots[action] = row
	apply_all()


func apply_all() -> void:
	for action in actions:
		_apply(action)


func _apply(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for ev: Variant in slots.get(action, []):
		if ev != null:
			InputMap.action_add_event(action, ev as InputEvent)


## A clean copy of a captured event: keys by physical keycode (and left/right location),
## mouse buttons by index. Anything else is refused (null).
static func normalized(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code == KEY_NONE:
			return null
		var out := InputEventKey.new()
		out.physical_keycode = code
		out.location = k.location
		return out
	if event is InputEventMouseButton:
		var b := InputEventMouseButton.new()
		b.button_index = (event as InputEventMouseButton).button_index
		return b
	return null


static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca := ka.physical_keycode if ka.physical_keycode != KEY_NONE else ka.keycode
		var cb := kb.physical_keycode if kb.physical_keycode != KEY_NONE else kb.keycode
		return ca == cb and (ka.location == kb.location or ka.location == KEY_LOCATION_UNSPECIFIED \
				or kb.location == KEY_LOCATION_UNSPECIFIED)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func event_to_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "%s:%d:%d" % [PREFIX_KEY, code, k.location]
	if ev is InputEventMouseButton:
		return "%s:%d" % [PREFIX_MOUSE, (ev as InputEventMouseButton).button_index]
	return ""


static func text_to_event(t: String) -> InputEvent:
	var parts := t.split(":")
	if parts.size() >= 2 and parts[0] == PREFIX_KEY and parts[1].is_valid_int() and int(parts[1]) > 0:
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		if parts.size() >= 3 and parts[2].is_valid_int():
			k.location = clampi(int(parts[2]), 0, 2) as KeyLocation
		return k
	if parts.size() == 2 and parts[0] == PREFIX_MOUSE and parts[1].is_valid_int() and int(parts[1]) > 0:
		var b := InputEventMouseButton.new()
		b.button_index = int(parts[1]) as MouseButton
		return b
	return null
