extends TestCase

class Provider extends Node:
	func debug_info() -> Dictionary:
		return {"seed": 42}

func test_overlay_lists_counters_and_providers() -> void:
	var overlay := DebugOverlay.new()
	add_child(overlay)
	var p := Provider.new()
	p.add_to_group(DebugOverlay.GROUP)
	add_child(p)
	var t := overlay.text()
	assert_contains(t, "FPS")
	assert_contains(t, "DRAW CALLS")
	assert_contains(t, "SEED 42")
	assert_false(overlay.visible, "hidden until F3")
	p.free()
	overlay.free()
