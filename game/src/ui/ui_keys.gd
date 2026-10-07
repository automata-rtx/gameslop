class_name UiKeys
extends RefCounted
## Key names from the current bindings (04 §6, §9: "rendered from the current bindings",
## SettingsManager.bindings()) and the segmentation of prompt templates into plain text
## and key caps. In a template a bracket group is a key cap frame: placeholders naming an
## action inside it become key caps (04 §6: "a 1 px box around the key name") and the
## other words stay plain (`[HOLD {interact}]` -> HOLD + [E]); a group with no action
## placeholder is a key cap as a whole (`[MOUSE]`). The brackets themselves are not drawn.

## A segment of a rendered line: {"text": String, "key": bool}.
const KEY := "key"
const TEXT := "text"


## The display name of the first binding of `action`, uppercase. Strings.BINDING_NONE
## when the action has no binding.
static func key_name(action: StringName) -> String:
	var b: Dictionary = SettingsManager.bindings()
	var events: Array = b.get(action, [])
	if events.is_empty() and InputMap.has_action(action):
		events = InputMap.action_get_events(action)
	for ev: Variant in events:
		var n := event_name(ev as InputEvent)
		if not n.is_empty():
			return n
	return Strings.BINDING_NONE


static func event_name(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
		if code == KEY_NONE:
			return ""
		return OS.get_keycode_string(code).to_upper()
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return Strings.BINDING_MOUSE_LEFT
			MOUSE_BUTTON_RIGHT:
				return Strings.BINDING_MOUSE_RIGHT
			MOUSE_BUTTON_MIDDLE:
				return Strings.BINDING_MOUSE_MIDDLE
			MOUSE_BUTTON_WHEEL_UP:
				return Strings.BINDING_WHEEL_UP
			MOUSE_BUTTON_WHEEL_DOWN:
				return Strings.BINDING_WHEEL_DOWN
	return ""


## Splits `template` into segments. `values` fills plain placeholders ({text}); every
## placeholder listed in `keys` (action name -> key name) becomes a key cap.
static func segments(template: String, values: Dictionary, keys: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group: Array[Dictionary] = []
	var in_group := false
	var i := 0
	while i < template.length():
		var ch := template[i]
		if ch == "[" and not in_group:
			in_group = true
			group = []
			i += 1
			continue
		if ch == "]" and in_group:
			in_group = false
			_close_group(group, out)
			i += 1
			continue
		var seg: Dictionary
		if ch == "{":
			var end := template.find("}", i)
			if end == -1:
				end = template.length() - 1
			var name := StringName(template.substr(i + 1, end - i - 1))
			if keys.has(name):
				seg = {TEXT: String(keys[name]), KEY: true}
			else:
				seg = {TEXT: String(values.get(name, "")), KEY: false}
			i = end + 1
		else:
			seg = {TEXT: ch, KEY: false}
			i += 1
		_append(group if in_group else out, seg)
	if in_group:
		_close_group(group, out)
	return out


## The plain reading of segments (tests, logs): key caps in brackets.
static func plain(segs: Array[Dictionary]) -> String:
	var s := ""
	for seg in segs:
		s += ("[%s]" % seg[TEXT]) if seg[KEY] else String(seg[TEXT])
	return s


static func _close_group(group: Array[Dictionary], out: Array[Dictionary]) -> void:
	var has_key := false
	for g in group:
		has_key = has_key or bool(g[KEY])
	if has_key:
		for g in group:
			_append(out, g)
		return
	var whole := ""
	for g in group:
		whole += String(g[TEXT])
	out.append({TEXT: whole, KEY: true})


static func _append(list: Array[Dictionary], seg: Dictionary) -> void:
	if not seg[KEY] and not list.is_empty() and not list[-1][KEY]:
		list[-1][TEXT] = String(list[-1][TEXT]) + String(seg[TEXT])
	else:
		list.append(seg)
