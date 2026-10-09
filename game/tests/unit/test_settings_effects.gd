extends TestCase
## M3.6 accessibility verification: every 12 option has an effect. test_accessibility.gd
## covers §6 end to end, test_settings.gd and test_player_camera.gd the display, graphics
## and FOV math; this file adds a test for each option that had none: the five audio sliders
## and Mute when unfocused (§4), Sprint and Crouch Hold/Toggle (§5), Particles and Indirect
## lighting (§3), Show depth, Exit status line and Debug overlay (§7). Window mode,
## resolution, VSync and the output device call DisplayServer / AudioServer, which do nothing
## headless (SettingsApply returns early): the human check script covers them (A4).

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const KEYS: Array[StringName] = [
	&"audio_master", &"audio_effects", &"audio_ambience", &"audio_music", &"audio_ui",
	&"mute_unfocused", &"sprint_mode", &"crouch_mode", &"particles", &"indirect_lighting",
	&"show_depth", &"show_exit_status", &"debug_overlay",
]

var _saved: Dictionary = {}


func before_each() -> void:
	for k in KEYS:
		_saved[k] = SettingsManager.get_value(k)


func after_each() -> void:
	for k: StringName in _saved:
		SettingsManager.set_value(k, _saved[k])
	for a: StringName in [&"sprint", &"crouch"]:
		Input.action_release(a)


## 12 §4: each slider sets its buses through linear_to_db(v / 100), -80 dB at 0.
func test_audio_sliders_set_their_buses() -> void:
	var map := {
		&"audio_master": [&"Master"], &"audio_effects": [&"World", &"Player"],
		&"audio_ambience": [&"Ambience"], &"audio_music": [&"Music"], &"audio_ui": [&"UI"],
	}
	for key: StringName in map:
		SettingsManager.set_value(key, 50)
		for bus: StringName in map[key]:
			assert_approx(AudioManager.ducker.slider_db(bus), AudioMix.slider_db(50.0), 0.01, "%s -> %s" % [key, bus])
		SettingsManager.set_value(key, 0)
		for bus: StringName in map[key]:
			assert_approx(AudioManager.ducker.slider_db(bus), Tuning.AUDIO_SLIDER_MUTE_DB, 0.01, "%s at 0 is -80 dB" % key)
			var i := AudioServer.get_bus_index(bus)
			assert_lt(AudioServer.get_bus_volume_db(i), -60.0, "%s bus follows" % bus)
		SettingsManager.set_value(key, 100)
		for bus: StringName in map[key]:
			assert_approx(AudioManager.ducker.slider_db(bus), 0.0, 0.01)


## 12 §4 Mute when unfocused: Master mutes on focus out only while the option is on.
func test_mute_when_unfocused() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	SettingsManager.set_value(&"mute_unfocused", true)
	SettingsManager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(AudioServer.is_bus_mute(master), "unfocused: muted")
	SettingsManager.set_value(&"mute_unfocused", false)
	assert_false(AudioServer.is_bus_mute(master), "the option off: heard")
	SettingsManager.set_value(&"mute_unfocused", true)
	SettingsManager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_false(AudioServer.is_bus_mute(master), "focused again: heard")


## 12 §5 Sprint / Crouch: Hold follows the key; Toggle latches on a press.
func test_sprint_and_crouch_hold_or_toggle() -> void:
	for pair: Array in [[&"sprint_mode", &"sprint"], [&"crouch_mode", &"crouch"]]:
		var key: StringName = pair[0]
		var action: StringName = pair[1]
		SettingsManager.set_value(key, &"hold")
		var p := PlayerInput.new()
		Input.action_press(action)
		p.poll()
		assert_true(p.get(action), "%s held" % action)
		Input.action_release(action)
		p.poll()
		assert_false(p.get(action), "%s released (hold)" % action)
		SettingsManager.set_value(key, &"toggle")
		p = PlayerInput.new()
		Input.action_press(action)
		p.poll()
		Input.action_release(action)
		p.poll()
		assert_true(p.get(action), "%s latched after a press (toggle)" % action)
		Input.action_press(action)
		p.poll()
		Input.action_release(action)
		p.poll()
		assert_false(p.get(action), "%s unlatched by a second press" % action)


## 12 §3 Particles (Low, Full) and Indirect lighting (SSIL) reach the scene.
func test_particles_and_indirect_lighting() -> void:
	var holder := Node.new()
	add_child(holder)
	var parts := GPUParticles3D.new()
	holder.add_child(parts)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	holder.add_child(we)
	var vals := SettingsSchema.DEFAULTS.duplicate()
	vals[&"particles"] = &"low"
	vals[&"indirect_lighting"] = true
	SettingsApply.graphics(holder, vals)
	var low := parts.amount_ratio
	assert_lt(low, 1.0, "Low thins the particles")
	assert_true(we.environment.ssil_enabled, "SSIL on")
	vals[&"particles"] = &"full"
	vals[&"indirect_lighting"] = false
	SettingsApply.graphics(holder, vals)
	assert_approx(parts.amount_ratio, 1.0, 0.0001, "Full")
	assert_false(we.environment.ssil_enabled, "SSIL off")
	holder.free()


## 12 §7 Show depth and stratum, Exit status line.
func test_show_depth_and_exit_status_line() -> void:
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.set_depth(2, &"halls")
	hud.set_exit_status(&"powered", 0.0)
	SettingsManager.set_value(&"show_depth", false)
	assert_false(hud.depth.visible, "depth line hidden")
	SettingsManager.set_value(&"show_depth", true)
	assert_true(hud.depth.visible)
	SettingsManager.set_value(&"show_exit_status", false)
	var exit_label := hud.depth.get_node("ExitShutter").get_child(0) as Label
	assert_false(exit_label.visible, "exit status line hidden")
	SettingsManager.set_value(&"show_exit_status", true)
	assert_true(exit_label.visible)
	hud.free()


## 12 §7 Debug overlay (debug builds only): the option shows and hides the F3 overlay.
func test_debug_overlay_option() -> void:
	var overlay := DebugOverlay.new()
	add_child(overlay)
	SettingsManager.set_value(&"debug_overlay", true)
	assert_eq(overlay.visible, OS.is_debug_build(), "shown in a debug build")
	SettingsManager.set_value(&"debug_overlay", false)
	assert_false(overlay.visible)
	overlay.free()
