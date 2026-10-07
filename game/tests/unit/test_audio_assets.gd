extends TestCase
## M0.6, M1.11a: every sound tools/audio/synth.py lists in the manifest imports as an
## AudioStreamWAV with the format, variant count, and loop setup 03 §2 asks for.
## Regenerate with: python3 tools/audio/synth.py --out game/assets/audio

const MANIFEST := "res://assets/audio/manifest.json"
const RATE := 48000
const BUSES: Array[String] = ["Footsteps", "Player", "UI", "Interact", "Errors", "Ambience", "Music", "World"]

## 03 §4 Player and UI tables, plus the player and UI sounds 11's sound column needs
## (noclip cancel and fall, drop arrival, interact hold tick) and 04 §4's motion sounds
## (shutter, typing). The Coherence static bed is a runtime generator, not a file.
const REQUIRED: Array[StringName] = [
	&"foot_carpet", &"foot_tile", &"foot_water", &"foot_concrete", &"foot_raised_floor", &"foot_substrate",
	&"sprint_breath_loop", &"stamina_empty_gasp", &"crouch", &"flashlight_toggle",
	&"crank_loop", &"crank_whine", &"crank_full",
	&"noclip_charge", &"noclip_commit", &"noclip_fall", &"noclip_fail", &"noclip_cancel", &"drop_arrival",
	&"coherence_loss_tick", &"coherence_gain", &"heartbeat", &"error_contact_hit", &"dissolve",
	&"ui_move", &"ui_confirm", &"ui_back", &"ui_slider_step", &"ui_glitch_transition",
	&"ui_title_boot", &"ui_unlock", &"ui_summary_stamp", &"ui_shutter", &"ui_type", &"ui_hold_tick",
	# M1.11a: Halls, doors, breaker, power wave, exit, noclip passes, Static, Still.
	&"noclip_pass_wall", &"noclip_pass_soft",
	&"room_tone_halls", &"fixture_hum_halls", &"fixture_buzz_halls", &"power_wave_ignite",
	&"door_open", &"door_close", &"door_slam", &"breaker_lever",
	&"exit_open", &"exit_latch", &"exit_tone",
	&"static_hum", &"static_band", &"still_tick", &"still_contact",
]

var _sounds: Dictionary = {}


func before_all() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		_sounds = (parsed as Dictionary).get("sounds", {})


func test_manifest_exists() -> void:
	assert_true(FileAccess.file_exists(MANIFEST), "run tools/audio/synth.py --out game/assets/audio")
	assert_false(_sounds.is_empty(), "manifest has no sounds")


func test_required_sounds_present() -> void:
	for id in REQUIRED:
		assert_contains(_sounds, String(id), "03/11 sound missing from the manifest")


func test_variant_counts_and_file_names() -> void:
	for id: String in _sounds:
		var entry: Dictionary = _sounds[id]
		var files: Array = entry.get("files", [])
		var lengths: Array = entry.get("length_s", [])
		assert_eq(files.size(), lengths.size(), id)
		if entry.get("loop", false):
			assert_true(files.size() >= 1 and files.size() <= 3, "%s: loops have 1 to 3 variations" % id)
		else:
			assert_true(files.size() >= 3 and files.size() <= 5, "%s: one-shots have 3 to 5 variations (03 §2)" % id)
		for i in files.size():
			var expected := "%s_v%02d.wav" % [id, i + 1]
			assert_eq(String(files[i]).get_file(), expected, "03 §2 file naming")
		assert_contains(BUSES, String(entry.get("bus", "")), "%s: unknown bus" % id)


func test_every_file_loads_as_audio_stream_wav() -> void:
	for id: String in _sounds:
		var entry: Dictionary = _sounds[id]
		var files: Array = entry.get("files", [])
		var lengths: Array = entry.get("length_s", [])
		var loop: bool = entry.get("loop", false)
		var stereo: bool = int(entry.get("channels", 1)) == 2
		var loop_frames: Array = entry.get("loop_frames", [])
		for i in files.size():
			var path := String(files[i])
			assert_true(ResourceLoader.exists(path), "%s does not import" % path)
			var stream := load(path) as AudioStreamWAV
			assert_not_null(stream, "%s is not an AudioStreamWAV" % path)
			if stream == null:
				continue
			assert_eq(stream.mix_rate, RATE, path)
			assert_eq(stream.stereo, stereo, path)
			assert_approx(stream.get_length(), float(lengths[i]), 0.002, path)
			if loop:
				assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s should loop" % path)
				assert_eq(stream.loop_begin, 0, path)
				assert_eq(stream.loop_end, int(loop_frames[i]), "%s loop end" % path)
			else:
				assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s should not loop" % path)


## 03 §6 rule 6: every caption a sound names is a Strings constant.
func test_runtime_captions_are_strings() -> void:
	var consts := (load("res://src/core/strings.gd") as GDScript).get_script_constant_map()
	for id: String in _sounds:
		var rt: Dictionary = (_sounds[id] as Dictionary).get("runtime", {})
		if rt.has("caption"):
			assert_contains(consts, String(rt["caption"]), "%s caption" % id)
