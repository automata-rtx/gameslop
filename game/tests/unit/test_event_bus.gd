extends TestCase
## 14 §4: EventBus declares exactly the eighteen canonical signals with typed params.

const VARIANT := -1

## name -> argument types, in order. VARIANT marks an untyped Variant parameter.
const CANON := {
	"run_started": [TYPE_STRING_NAME, TYPE_INT],
	"level_entered": [TYPE_INT, TYPE_STRING_NAME, TYPE_STRING_NAME],
	"level_left": [TYPE_BOOL],
	"run_ended": [TYPE_STRING_NAME, TYPE_INT],
	"unlock_earned": [TYPE_STRING_NAME],
	"settings_changed": [TYPE_STRING_NAME, VARIANT],
	"noise_emitted": [TYPE_VECTOR3, TYPE_FLOAT, TYPE_STRING_NAME],
	"note_found": [TYPE_STRING_NAME],
	"item_picked": [TYPE_STRING_NAME],
	"item_used": [TYPE_STRING_NAME],
	"breaker_thrown": [TYPE_VECTOR3],
	"exit_status_changed": [TYPE_STRING_NAME, TYPE_FLOAT],
	"hide_state": [TYPE_BOOL],
	"error_proximity": [TYPE_STRING_NAME, TYPE_FLOAT],
	"error_state": [TYPE_STRING_NAME, TYPE_STRING_NAME, TYPE_STRING_NAME],
	"director_phase": [TYPE_STRING_NAME],
	"threat_changed": [TYPE_FLOAT],
	"audio_cue": [TYPE_STRING, TYPE_VECTOR3],
}


func _script_signals() -> Dictionary:
	var out := {}
	var bus := get_tree().root.get_node(^"EventBus")
	for s: Dictionary in (bus.get_script() as Script).get_script_signal_list():
		out[String(s["name"])] = s["args"]
	return out


func test_exactly_eighteen_signals() -> void:
	var sigs := _script_signals()
	assert_eq(CANON.size(), 18, "the canon itself")
	assert_eq(sigs.size(), 18, "EventBus signal count")
	for name: String in sigs:
		assert_true(CANON.has(name), "unexpected signal %s" % name)


func test_signal_arguments_match_canon() -> void:
	var sigs := _script_signals()
	for name: String in CANON:
		if not sigs.has(name):
			fail("missing signal %s" % name)
			continue
		var args: Array = sigs[name]
		var want: Array = CANON[name]
		assert_eq(args.size(), want.size(), "%s argument count" % name)
		for i in mini(args.size(), want.size()):
			var arg: Dictionary = args[i]
			if want[i] == VARIANT:
				assert_eq(arg["type"], TYPE_NIL, "%s arg %d is Variant" % [name, i])
				assert_true(int(arg["usage"]) & PROPERTY_USAGE_NIL_IS_VARIANT != 0, "%s arg %d is Variant" % [name, i])
			else:
				assert_eq(arg["type"], want[i], "%s arg %d type" % [name, i])


func test_bus_holds_no_state() -> void:
	var bus := get_tree().root.get_node(^"EventBus")
	var vars := 0
	for p: Dictionary in (bus.get_script() as Script).get_script_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			vars += 1
	assert_eq(vars, 0, "EventBus declares no variables (14 §3)")


func test_emit_reaches_listener() -> void:
	var got: Array = []
	var cb := func(pos: Vector3, radius: float, kind: StringName) -> void: got.append([pos, radius, kind])
	EventBus.noise_emitted.connect(cb)
	EventBus.noise_emitted.emit(Vector3(1, 2, 3), 7.0, &"step")
	EventBus.noise_emitted.disconnect(cb)
	assert_eq(got.size(), 1)
	assert_eq(got[0][1], 7.0)
	assert_eq(got[0][2], &"step")
