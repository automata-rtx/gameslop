extends TestCase
## M3.3 audio mix pass (03 §3, §6; 04 §10; 11 Sound channel):
## - rule 2 by construction: a one-shot on Errors plays no louder than its manifest peak and
##   its distance allow under -6 dBFS; Echo's steps keep -3 dB beyond 1.3 m; the manifest's
##   peak_db matches the files; Errors loops fit rule 2 at the player's +3 dB max_db;
## - occlusion per 03 §3: the 0.2 s pass muffles Errors and Interact emitters behind a wall
##   (800 Hz, -6 dB over 100 ms) and opens them again; Static, Null-like through_walls sounds,
##   Ambience and Footsteps are never occluded;
## - caption coverage: every row of the 04 §10 table is a Strings constant and reaches
##   EventBus.audio_cue with its text when its sound plays; every Errors-bus sound and every
##   door and breaker sound is captioned or listed below with the reason it is not.

const TABLE_DOC := "res://../docs/design/04_ui_design_language.md"
const MANIFEST := "res://assets/audio/manifest.json"
## Errors-bus and door/breaker sounds without a caption of their own, and why (03 §6 rule 6
## asks for "the text in the table in 04 §10"; these have no row there).
const UNCAPTIONED: Dictionary = {
	&"static_band": "plays with static_hum, which carries [hum]",
	&"still_contact": "plays with error_contact_hit, which carries [contact]",
	&"echo_breath": "04 §10 gives Echo one row, its late footsteps",
	&"door_open": "the player's own action; 04 §10 rows are door slams only",
	&"door_close": "the player's own action; 04 §10 rows are door slams only",
}
## Rows not tied to a sample: emitted by AudioManager's feeds.
const FEED_ROWS: Array[String] = ["CAPTION_STILL_SILENCE", "CAPTION_NULL"]

var _cues: Array[String] = []
var _scratch: Array[Node] = []
var _listener: Node3D


func before_each() -> void:
	_cues.clear()
	EventBus.audio_cue.connect(_on_cue)
	_stop_pool()
	_listener = _node3d(Vector3.ZERO)
	AudioManager.set_listener(_listener)


func after_each() -> void:
	EventBus.audio_cue.disconnect(_on_cue)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	AudioManager.tick(0.1)
	for n in _scratch:
		if is_instance_valid(n):
			n.queue_free()
	_scratch.clear()
	AudioManager.set_listener(null)
	EventBus.level_left.emit(true)
	AudioManager.tick(2.0)
	_stop_pool()


func after_all() -> void:
	AudioManager.stop_all()
	await await_frames(3)


func _on_cue(text: String, _pos: Vector3) -> void:
	_cues.append(text)


func _stop_pool() -> void:
	for p in AudioManager.pool.players_3d:
		p.stop()
	for p in AudioManager.pool.players_2d:
		p.stop()


func _node3d(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	_scratch.append(n)
	return n


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	_scratch.append(wall)
	wall.global_position = pos
	return wall


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return (parsed as Dictionary).get("sounds", {}) if parsed is Dictionary else {}


# --------------------------------------------------------------------------- rule 2

func test_errors_headroom_math() -> void:
	assert_approx(AudioMix.errors_headroom_db(-1.0, 1.0, 3.0), -5.0, 0.001, "1 m: no attenuation")
	assert_approx(AudioMix.errors_headroom_db(-1.0, 0.25, 3.0), -8.0, 0.001, "closer: capped at max_db +3")
	assert_approx(AudioMix.errors_headroom_db(-1.0, 4.0, 3.0), -5.0 + 12.041, 0.01, "4 m: -12 dB of distance")
	assert_approx(AudioMix.errors_headroom_db(-14.0, 1.0, 3.0), 8.0, 0.001, "a quiet tick has room")


func test_errors_one_shots_stay_under_minus_6_dbfs() -> void:
	var lib := AudioManager.library
	var far := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 4), &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)
	assert_eq(far.get_meta(AudioPool.META_ID), &"echo_foot_carpet")
	assert_approx(far.volume_db, Tuning.ECHO_STEP_PLAYBACK_DB, 0.001, "Echo's -3 dB, untouched at 4 m")
	var near := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 0.5), &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)
	var peak := lib.peak_db(&"echo_foot_carpet")
	assert_lt(peak, -0.5, "the manifest knows the echo step's peak")
	assert_approx(near.volume_db, Tuning.AUDIO_ERRORS_BUS_MAX_DB - peak - 3.0, 0.01, "0.5 m: turned down to -6 dBFS")
	var hit := AudioManager.play_3d(&"error_contact_hit", Vector3(0, 1, 0), &"Errors")
	assert_approx(hit.volume_db, Tuning.AUDIO_ERRORS_BUS_MAX_DB - lib.peak_db(&"error_contact_hit"), 0.01,
		"the contact hit Echo plays on Errors at 1 m")
	var own := AudioManager.play_3d(&"foot_carpet", Vector3(0, 0, 0.5))
	assert_approx(own.volume_db, 0.0, 0.001, "the player's own step (Footsteps) is never clamped")
	var tick := AudioManager.play_3d(&"still_tick", Vector3(0, 0, 0.3))
	assert_approx(tick.volume_db, 0.0, 0.001, "a quiet Errors sound keeps its level")
	# Worst case for every Errors one-shot the game plays: at the listener (+3 dB max_db).
	for id: StringName in lib.ids():
		if lib.bus(id) != &"Errors" or lib.is_loop(id):
			continue
		var p := AudioManager.play_3d(id, Vector3(0, 0, 0.1))
		assert_lt(lib.peak_db(id) + p.volume_db + p.max_db, Tuning.AUDIO_ERRORS_BUS_MAX_DB + 0.01, "%s at 0.1 m" % id)


func test_errors_loops_fit_rule_2_at_the_listener() -> void:
	var lib := AudioManager.library
	for id: StringName in lib.ids():
		if lib.bus(id) == &"Errors" and lib.is_loop(id):
			assert_lt(lib.peak_db(id) + 3.0, Tuning.AUDIO_ERRORS_BUS_MAX_DB, "%s loops are not clamped at play" % id)


func test_manifest_peaks_match_the_files() -> void:
	var sounds := _manifest()
	assert_false(sounds.is_empty(), "manifest")
	var checked := 0
	for id: String in sounds:
		var e: Dictionary = sounds[id]
		var errors_bound: bool = e.get("bus", "") == "Errors" or id.begins_with("foot_") or id == "error_contact_hit"
		assert_true(e.has("peak_db"), "%s has peak_db (re-run tools/audio/synth.py)" % id)
		if not errors_bound or bool(e.get("loop", false)):
			continue
		var peak := -INF
		for f: Variant in e.get("files", []):
			peak = maxf(peak, _wav_peak_db(String(f)))
		assert_approx(peak, float(e.get("peak_db", 0.0)), 0.06, "%s peak" % id)
		checked += 1
	assert_gt(checked, 15)


## Peak of a 16-bit PCM WAV as written by synth.py (the source file, not the import).
static func _wav_peak_db(res_path: String) -> float:
	var b := FileAccess.get_file_as_bytes(res_path)
	var pos := 12
	var peak := 0
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		if id == "data":
			for i in range(pos + 8, pos + 8 + size, 2):
				peak = maxi(peak, absi(b.decode_s16(i)))
			break
		pos += 8 + size + (size & 1)
	return linear_to_db(maxf(float(peak), 1.0) / 32767.0)


# --------------------------------------------------------------------------- occlusion

func test_occlusion_pass_muffles_errors_and_interact_behind_a_wall() -> void:
	_wall(Vector3(0, 0, -5), Vector3(8, 6, 0.4))
	await await_physics_frames(2)
	var emitters := {}
	for id: StringName in [&"flicker_stutter", &"radio_static", &"static_hum", &"fan_loop"]:
		var h := AudioManager.loop(id, _node3d(Vector3(0, 0, -10)))
		h.start()
		emitters[id] = h
	var step := AudioManager.play_3d(&"foot_concrete", Vector3(0.5, 0, -10))
	assert_eq(step.bus, &"Footsteps")
	AudioManager.tick(Tuning.AUDIO_OCCLUSION_INTERVAL + 0.01)  # at least one 0.2 s pass
	var occ := func(id: StringName) -> bool:
		return bool((emitters[id] as AudioLoop).player.get_meta(AudioOcclusion.META_OCCLUDED, false))
	assert_true(occ.call(&"flicker_stutter"), "Errors loop behind the wall")
	assert_true(occ.call(&"radio_static"), "Interact loop behind the wall")
	assert_false(occ.call(&"static_hum"), "Static is heard through walls")
	assert_false(occ.call(&"fan_loop"), "Ambience is not occluded")
	assert_false(bool(step.get_meta(AudioOcclusion.META_OCCLUDED, false)), "Footsteps are not occluded")
	await Clock.wall_timer(Tuning.AUDIO_OCCLUSION_TWEEN_MS / 1000.0 + 0.05).timeout
	var fl := (emitters[&"flicker_stutter"] as AudioLoop).player as AudioStreamPlayer3D
	assert_approx(fl.attenuation_filter_cutoff_hz, Tuning.AUDIO_OCCLUSION_LOWPASS_HZ, 1.0, "800 Hz")
	assert_approx(float(fl.get_meta(AudioLoop.META_OCCLUSION, 0.0)), Tuning.AUDIO_OCCLUSION_DB, 0.01, "-6 dB")
	# The listener walks round the wall: the next pass opens the emitters again.
	_listener.global_position = Vector3(6, 0, -10)
	AudioManager.tick(Tuning.AUDIO_OCCLUSION_INTERVAL + 0.01)
	assert_false(occ.call(&"flicker_stutter"), "clear line again")
	await Clock.wall_timer(Tuning.AUDIO_OCCLUSION_TWEEN_MS / 1000.0 + 0.05).timeout
	assert_approx(fl.attenuation_filter_cutoff_hz, AudioOcclusion.OPEN_CUTOFF_HZ, 1.0, "filter open")
	assert_approx(float(fl.get_meta(AudioLoop.META_OCCLUSION, 0.0)), 0.0, 0.01, "level back")
	for h: AudioLoop in emitters.values():
		h.release()


func test_occlusion_pass_runs_every_0_2_s() -> void:
	_wall(Vector3(0, 0, -5), Vector3(8, 6, 0.4))
	await await_physics_frames(2)
	AudioManager.tick(Tuning.AUDIO_OCCLUSION_INTERVAL + 0.01)  # align: a pass just ran
	var h := AudioManager.loop(&"radio_static", _node3d(Vector3(0, 0, -10)))
	h.start()
	AudioManager.tick(Tuning.AUDIO_OCCLUSION_INTERVAL * 0.5)
	assert_false(bool(h.player.get_meta(AudioOcclusion.META_OCCLUDED, false)), "not before the next pass")
	AudioManager.tick(Tuning.AUDIO_OCCLUSION_INTERVAL * 0.5 + 0.01)
	assert_true(bool(h.player.get_meta(AudioOcclusion.META_OCCLUDED, false)), "within 0.2 s")
	h.release()


# --------------------------------------------------------------------------- captions

## The 04 §10 table: [event, caption text] rows.
func _caption_rows() -> Array:
	var rows: Array = []
	var text := FileAccess.get_file_as_string(TABLE_DOC)
	var start := text.find("## 10. Caption text table")
	var section := text.substr(start, text.find("\n## ", start + 4) - start)
	for line in section.split("\n"):
		var cells := line.split("|", false)
		if cells.size() == 2 and cells[1].strip_edges().begins_with("`"):
			rows.append([cells[0].strip_edges(), cells[1].strip_edges().trim_prefix("`").trim_suffix("`")])
	return rows


func _strings_key(caption: String) -> String:
	var consts := (load("res://src/core/strings.gd") as GDScript).get_script_constant_map()
	for k: String in consts:
		if k.begins_with("CAPTION_") and consts[k] is String and consts[k] == caption:
			return k
	return ""


func test_caption_table_is_the_strings() -> void:
	var rows := _caption_rows()
	assert_eq(rows.size(), 14, "04 §10 has 14 rows")
	for r: Array in rows:
		assert_ne(_strings_key(r[1]), "", "%s: %s is a Strings constant" % r)


func test_every_caption_row_reaches_the_caption_stack() -> void:
	var lib := AudioManager.library
	var by_key := {}   # Strings key -> sound ids that carry it
	for id: StringName in lib.ids():
		var key := String(lib.runtime(id).get("caption", ""))
		if key != "":
			by_key[key] = by_key.get(key, []) + [id]
	var at := Vector3(7, 0, -7)   # ahead right, 9.9 m: no distance word
	var l := _listener.global_transform
	for r: Array in _caption_rows():
		var key := _strings_key(r[1])
		if key in FEED_ROWS:
			continue
		assert_true(by_key.has(key), "%s (%s) is carried by a sound" % [r[0], key])
		for id: StringName in by_key.get(key, []):
			_cues.clear()
			_stop_pool()
			var h: AudioLoop = null
			var pos := at
			if lib.is_loop(id):
				h = AudioManager.loop(id, _node3d(at)).start()
			elif lib.bus(id) in [&"Player", &"UI"]:
				AudioManager.play_2d(id)  # non-spatial: captioned at the listener
				pos = l.origin
			else:
				AudioManager.play_3d(id, at)
			assert_contains(_cues, AudioMix.format_caption(r[1], l, pos), "%s: %s plays its caption" % [r[0], id])
			if h != null:
				h.release()
	# Echo's footsteps: the player's step sent to Errors.
	_cues.clear()
	AudioManager.play_3d(&"foot_tile", at, &"Errors", Tuning.ECHO_STEP_PLAYBACK_DB)
	assert_contains(_cues, AudioMix.format_caption(Strings.CAPTION_ECHO_FOOTSTEP, l, at), "Echo footstep")
	# The feed rows: Still within 8 m, Null audible.
	_cues.clear()
	EventBus.error_proximity.emit(&"still", 5.0)
	assert_contains(_cues, Strings.CAPTION_STILL_SILENCE, "Still within 8 m")
	_cues.clear()
	CoherenceRenderer.set_null(Vector3(0, 0, -30), Tuning.NULL_UNRENDER_RADIUS)
	AudioManager.tick(0.05)
	assert_contains(_cues, "[grid tone, ahead, far]", "Null audible")


func test_every_errors_door_and_breaker_sound_is_captioned_or_exempt() -> void:
	var lib := AudioManager.library
	for id: StringName in lib.ids():
		var s := String(id)
		var watched := lib.bus(id) == &"Errors" or s.begins_with("door_") or s.begins_with("breaker")
		if not watched or s.begins_with("echo_foot_"):
			continue
		var captioned := String(lib.runtime(id).get("caption", "")) != ""
		assert_true(captioned or UNCAPTIONED.has(id), "%s (%s) needs a 04 §10 caption or a reason here" % [id, lib.bus(id)])
		assert_false(captioned and UNCAPTIONED.has(id), "%s is captioned; drop it from UNCAPTIONED" % id)
	for id: StringName in UNCAPTIONED:
		assert_true(lib.has(id), "%s still exists" % id)
