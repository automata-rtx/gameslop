extends TestCase
## R21: the cp-12 script-time pass changes no behaviour. Each rewritten per-frame path is
## run against its pre-R21 form (kept here) on seeded random input: the proximity-line
## crossing, the ducker's skipped apply and filter, Echo's cached trail target and resolve
## counter, the exit timer's repaint test, the pad voices' skipped volume writes, and the
## shutters and menu rows that process only while they have something to advance.

const STEPS := 600
const BUSES: Array[StringName] = Tuning.AUDIO_BUSES


# --- the pre-R21 forms --------------------------------------------------------------------

static func _crossed_old(from: float, to: float) -> bool:
	for line: float in [Tuning.STILL_SILENCE_RANGE, Tuning.AUDIO_ERRORS_DUCK_DIST]:
		if (from < line) != (to < line):
			return true
	return false


## AudioDucker before R21 (its level math only; apply wrote every changed bus each call).
class OldDucker:
	var room_tone_db: float = 0.0
	var _ducks: Array[Dictionary] = []
	var _clock: float = 0.0
	var _slider_db: Dictionary = {}

	func advance(delta: float) -> void:
		_clock += delta
		_ducks = _ducks.filter(func(d: Dictionary) -> bool: return float(d[&"until"]) > _clock)

	func duck(bus: StringName, db: float, seconds: float) -> void:
		_ducks.append({&"key": &"", &"bus": bus, &"db": db, &"until": _clock + seconds, &"mute": false})

	func hold(key: StringName, bus: StringName, db: float) -> void:
		release(key)
		_ducks.append({&"key": key, &"bus": bus, &"db": db, &"until": INF, &"mute": false})

	func hold_mute(key: StringName, bus: StringName) -> void:
		release(key)
		_ducks.append({&"key": key, &"bus": bus, &"db": Tuning.AUDIO_SLIDER_MUTE_DB, &"until": INF, &"mute": true})

	func release(key: StringName) -> void:
		_ducks = _ducks.filter(func(d: Dictionary) -> bool: return d[&"key"] != key)

	func has(key: StringName) -> bool:
		return _ducks.any(func(d: Dictionary) -> bool: return d[&"key"] == key)

	func silence(bus: StringName, seconds: float) -> void:
		_ducks.append({&"key": &"", &"bus": bus, &"db": Tuning.AUDIO_SLIDER_MUTE_DB, &"until": _clock + seconds, &"mute": true})

	func clear() -> void:
		_ducks.clear()

	func ambience_floor(still_key: StringName) -> AudioMix.Floor:
		for d in _ducks:
			if d[&"mute"] and d[&"bus"] in [&"Ambience", &"World", &"Master"]:
				return AudioMix.Floor.MUTE
		return AudioMix.Floor.STILL if still_key != &"" and has(still_key) else AudioMix.Floor.NORMAL

	func duck_db(bus: StringName, still_key: StringName = &"") -> float:
		var d := AudioMix.bus_duck_db(_ducks, bus, _clock)
		if bus != &"Ambience":
			return d
		var world := AudioMix.bus_duck_db(_ducks, &"World", _clock)
		return AudioMix.clamp_ambience(d + world, room_tone_db, ambience_floor(still_key)) - world

	func set_slider(buses: Array, v: float) -> void:
		for bus: StringName in buses:
			_slider_db[bus] = AudioMix.slider_db(v)

	func level_db(bus: StringName, still_key: StringName = &"") -> float:
		return maxf(float(_slider_db.get(bus, 0.0)) + duck_db(bus, still_key), Tuning.AUDIO_SLIDER_MUTE_DB)


## EchoTrail.target_index and resolve before R21 (full scans every call).
static func _target_old(t: EchoTrail, delay: float) -> int:
	if t.entries.is_empty():
		return -1
	var limit := t.newest_time() - delay + 1e-6
	var out := 0
	for i in t.entries.size():
		if float(t.entries[i][&"time"]) <= limit:
			out = i
		else:
			break
	return out


static func _resolve_old(t: EchoTrail, player_trail: RingBuffer, fallback_surface: StringName) -> void:
	for e in t.entries:
		if bool(e[&"resolved"]):
			continue
		var found: Variant = EchoTrail._match(player_trail, e[&"position"])
		if found is Dictionary:
			e[&"surface"] = StringName((found as Dictionary).get(&"surface", fallback_surface))
			e[&"speed_kind"] = StringName((found as Dictionary).get(&"speed_kind", NoiseModel.GAIT_WALK))
		else:
			e[&"surface"] = fallback_surface if e[&"surface"] == &"" else e[&"surface"]
			e[&"speed_kind"] = NoiseModel.GAIT_WALK if e[&"speed_kind"] == &"" else e[&"speed_kind"]
		e[&"resolved"] = true


# --- tests ----------------------------------------------------------------------------------

func test_proximity_crossing_matches_the_array_loop() -> void:
	var rng := make_rng(2101)
	var values: Array[float] = [0.0, 7.999, 8.0, 8.001, 9.0, 9.999, 10.0, 10.001, 50.0, INF]
	for i in 200:
		values.append(rng.randf_range(0.0, 14.0))
	var mismatches := 0
	for a in values:
		for b in values:
			if ErrorBase._crossed_proximity_line(a, b) != _crossed_old(a, b):
				mismatches += 1
	assert_eq(mismatches, 0, "every pair of distances, on and around the 8 m and 10 m lines")


func test_ducker_levels_and_writes_match_the_old_ducker() -> void:
	var saved: Dictionary = {}
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			saved[i] = AudioServer.get_bus_volume_db(i)
	var rng := make_rng(2102)
	var now := AudioDucker.new()
	var old := OldDucker.new()
	var keys: Array[StringName] = [&"errors_near", &"still_silence", &"null_core_World", &"x"]
	var level_mismatch := 0
	var stale_writes := 0
	for step in STEPS:
		var op := rng.randi_range(0, 9)
		var bus: StringName = BUSES[rng.randi_range(0, BUSES.size() - 1)]
		var key: StringName = keys[rng.randi_range(0, keys.size() - 1)]
		match op:
			0:
				var db := rng.randf_range(-12.0, 0.0)
				var s := rng.randf_range(0.0, 0.5)
				now.duck(bus, db, s)
				old.duck(bus, db, s)
			1:
				var db := rng.randf_range(-8.0, -2.0)
				now.hold(key, bus, db)
				old.hold(key, bus, db)
			2:
				now.hold_mute(key, bus)
				old.hold_mute(key, bus)
			3, 4:
				now.release(key)
				old.release(key)
			5:
				var s := rng.randf_range(0.0, 2.0)
				now.silence(bus, s)
				old.silence(bus, s)
			6:
				var v := rng.randf_range(0.0, 100.0)
				now.set_slider([bus], v)
				old.set_slider([bus], v)
			7:
				var t := rng.randf_range(-40.0, 0.0) if rng.randf() < 0.7 else now.room_tone_db
				now.room_tone_db = t
				old.room_tone_db = t
			8:
				if rng.randf() < 0.05:
					now.clear()
					old.clear()
		# AudioManager's frame: advance, then apply (some frames twice, as AudioFeeds does).
		var dt := rng.randf_range(0.0, 0.05)
		now.advance(dt)
		old.advance(dt)
		var still := &"still_silence" if rng.randf() < 0.8 else &""
		now.apply(still)
		if rng.randf() < 0.2:
			now.apply(still)
		assert_eq(now.has(key), old.has(key))
		for b in BUSES:
			if not is_equal_approx(now.level_db(b, still), old.level_db(b, still)):
				level_mismatch += 1
			var i := AudioServer.get_bus_index(b)
			if i >= 0 and not is_equal_approx(AudioServer.get_bus_volume_db(i), old.level_db(b, still)):
				stale_writes += 1
	for i: int in saved:
		AudioServer.set_bus_volume_db(i, saved[i])
	AudioManager.ducker._applied_db.clear()
	AudioManager.ducker._applied_version = -1
	assert_eq(level_mismatch, 0, "%d steps: every bus level the old ducker gives" % STEPS)
	assert_eq(stale_writes, 0, "a skipped apply never leaves a bus at a stale level")


func test_echo_trail_target_and_resolve_match_the_full_scans() -> void:
	var rng := make_rng(2103)
	var now := EchoTrail.new()
	var old := EchoTrail.new()
	now.capacity = 16
	old.capacity = 16
	var player_trail := RingBuffer.new(Tuning.ECHO_TRAIL_CAPACITY)
	var clock := 0.0
	var target_mismatch := 0
	var resolve_mismatch := 0
	for step in STEPS:
		clock += rng.randf_range(0.0, 0.4)
		var op := rng.randf()
		if op < 0.35:
			var pos := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0))
			if rng.randf() < 0.7:
				player_trail.push({&"position": pos, &"surface": &"concrete", &"speed_kind": NoiseModel.GAIT_SPRINT})
			var surface := &"tile" if rng.randf() < 0.2 else &""
			now.add(pos, clock, surface, NoiseModel.GAIT_WALK if surface != &"" else &"")
			old.add(pos, clock, surface, NoiseModel.GAIT_WALK if surface != &"" else &"")
		elif op < 0.42:
			var t := clock - rng.randf_range(0.0, 3.0)
			now.drop_before(t)
			old.drop_before(t)
		elif op < 0.44:
			now.clear()
			old.clear()
		if rng.randf() < 0.8:
			now.resolve(player_trail, &"carpet")
			_resolve_old(old, player_trail, &"carpet")
		for delay: float in [Tuning.ECHO_TRAIL_DELAY, 0.0, 1.5]:
			if now.target_index(delay) != _target_old(old, delay):
				target_mismatch += 1
		if str(now.entries) != str(old.entries):
			resolve_mismatch += 1
	assert_eq(target_mismatch, 0, "the cached target is the scanned one, for any delay")
	assert_eq(resolve_mismatch, 0, "the resolved surfaces and speed kinds are the old ones")


func test_exit_timer_repaints_on_the_same_seconds() -> void:
	var rng := make_rng(2104)
	var mismatches := 0
	for i in 4000:
		var a := rng.randf_range(-1.0, 200.0)
		var b := maxf(0.0, a - rng.randf_range(0.0, 0.05))
		if (HudDepth.format_time(a) != HudDepth.format_time(b)) != (HudDepth.shown_seconds(a) != HudDepth.shown_seconds(b)):
			mismatches += 1
	assert_eq(mismatches, 0, "a repaint exactly when the shown text changes")


func test_pad_voice_volume_is_the_last_level_written() -> void:
	var v := MusicVoice.new()
	for k in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		v.players.append(p)
	var rng := make_rng(2105)
	var want: Array[float] = [0.0, 0.0]
	for step in 300:
		var i := rng.randi_range(0, 1)
		var db := want[i] if rng.randf() < 0.5 else rng.randf_range(-80.0, 0.0)
		v._set_db(i, db)
		want[i] = db
		assert_approx(v.players[i].volume_db, db, 0.0001)
	for p in v.players:
		p.queue_free()


func test_shutters_and_rows_process_only_while_they_move() -> void:
	var sh := UiShutter.new()
	add_child(sh)
	await await_frames(1)
	assert_false(sh.is_processing(), "closed: idle")
	sh.shutter_in()
	assert_true(sh.is_processing(), "opening: processing")
	var frames := 0
	while sh.phase != UiShutter.Phase.OPEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_eq(sh.phase, UiShutter.Phase.OPEN, "it still opens on its own")
	assert_false(sh.is_processing(), "open: idle")
	sh.shutter_out()
	frames = 0
	while sh.phase != UiShutter.Phase.CLOSED and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_eq(sh.phase, UiShutter.Phase.CLOSED)
	assert_false(sh.visible)
	assert_false(sh.is_processing())
	sh.show_now(true)
	assert_false(sh.is_processing(), "snapped open: idle")
	sh.queue_free()
	var sheet := (load("res://scenes/ui/note_sheet.tscn") as PackedScene).instantiate() as NoteSheet
	sheet.movement_held = func() -> bool: return false
	add_child(sheet)
	await await_frames(1)
	assert_false(sheet.is_processing(), "a closed note sheet is idle")
	sheet.show_note(DataRegistry.note(&"H3"))
	frames = 0
	while sheet.phase != UiShutter.Phase.OPEN and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_true(sheet.is_processing(), "an open note sheet keeps typing and counting its life")
	await await_frames(5)
	assert_gt(sheet.typed_count(), 0, "it types")
	sheet.dismiss()
	frames = 0
	while sheet.phase != UiShutter.Phase.CLOSED and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_false(sheet.is_processing())
	sheet.queue_free()
	var row := MenuRow.new(&"r", "ROW")
	add_child(row)
	await await_frames(1)
	assert_false(row.is_processing(), "a row without a flash is idle")
	row.flash_accent(0.05)
	assert_true(row.is_processing())
	assert_eq(row.label_color(), UiTokens.accent())
	frames = 0
	while row.flash > 0.0 and frames < 60:
		await get_tree().process_frame
		frames += 1
	assert_eq(row.flash, 0.0, "the flash still runs out")
	assert_false(row.is_processing())
	assert_eq(row.label_color(), UiTokens.UI_FG)
	row.queue_free()
