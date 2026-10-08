class_name FeedbackBench
extends Node
## The Feedback Contract bench (11 §7). Hosts a real Descent (Run: player, HUD, level, exit,
## breaker, Landing, dissolve) and fires each row of 11 §2 and §3 through the code path the
## game uses, while FeedbackSpy watches the four channels. Per row it logs which channels
## reacted and how many physics ticks after the trigger (the contract: within 3 ticks, 50 ms
## at 60 fps). Rows for features that do not exist yet are listed as pending.
##
## Interactive (the editor or a GPU build):
##   godot --path game res://scenes/debug/feedback_bench.tscn
## Up/Down (or P/N) choose a row, Enter fires it, A runs the whole sequence, Esc/Q quits.
## Automatic, headless, JSON out and a table on stdout (exit 1 if a row fails):
##   godot --headless --path game res://scenes/debug/feedback_bench.tscn -- --auto build/feedback.json
##
## The Image channel reads the state the renderer and the held objects are fed (a GPU is
## not needed): what looks right on screen is a human check (docs/qa/human_check_cp-06.md).

signal row_finished(result: Dictionary)
signal finished(results: Array)

## Seed of the Descent the bench runs in, and the loadout.
const RUN_SEED := 4
const LOADOUT := &"faller"
## Starting Coherence for the rows (room for losses and a gain).
const START_COHERENCE := 70.0
const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right",
	&"sprint", &"crouch", &"interact", &"flashlight", &"crank", &"noclip", &"use_item"]
const QUIET_FRAMES := 6
const QUIET_MAX_FRAMES := 120
const ROW_TIMEOUT_USEC := 20_000_000

## Tests set this false before adding the bench to the tree and call start() themselves.
var autostart: bool = true
var run: Run
var spy := FeedbackSpy.new()
var results: Array[Dictionary] = []
## When set, `--auto` writes the JSON here.
var out_path: String = ""
var current: Dictionary = {}

var _recipes := FeedbackRecipes.new()
var _anchor_index: int = -1
var _anchor_tick: int = 0
var _anchor_frame: int = 0
var _anchor_usec: int = 0
var _host: Node
var _prev_host: Node
var _prev_meta: MetaState
var _prev_transition: Object
var _label: RichTextLabel
var _selected: int = 0
var _busy: bool = false
var _rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_rows = FeedbackRows.all()
	var args := OS.get_cmdline_user_args()
	var auto := args.has("--auto")
	var i := args.find("--auto")
	if i != -1 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		out_path = args[i + 1]
	if not auto:
		_build_ui()
	if autostart:
		_boot.call_deferred(auto)


func _exit_tree() -> void:
	_teardown()


func _boot(auto: bool) -> void:
	await start()
	if auto:
		var only: Array = []
		var args := OS.get_cmdline_user_args()
		var ri := args.find("--rows")
		if ri != -1 and ri + 1 < args.size():
			only = Array(args[ri + 1].split(","))
		await run_all(only)
		_print_table()
		if not out_path.is_empty():
			write_json(out_path)
		var args2 := OS.get_cmdline_user_args()
		var mi := args2.find("--md")
		if mi != -1 and mi + 1 < args2.size():
			write_text(args2[mi + 1], markdown(results))
		var bad := results.filter(func(r: Dictionary) -> bool: return r[&"status"] == FeedbackRows.IMPLEMENTED and not r[&"ok"])
		get_tree().quit(1 if not bad.is_empty() else 0)
	else:
		_refresh_ui()


# --- sampling -------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	spy.sample(get_tree())


# --- boot and teardown ------------------------------------------------------------------------

## Starts the Descent and waits for depth 1 to stand under the player.
func start() -> void:
	_prev_meta = GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = false
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_prev_host = SceneRouter.get_host()
	_host = Node.new()
	_host.name = "FeedbackHost"
	add_child(_host)
	SceneRouter.set_host(_host)
	GameState.start_run(Tuning.MODE_DESCENT, LOADOUT, RUN_SEED)
	run = (load("res://scenes/run.tscn") as PackedScene).instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 1.5
	run.drop_fall_time = 0.2
	run.dissolve_time = 0.6
	_host.add_child(run)
	spy.run = run
	await until(func() -> bool: return run.phase == Run.PHASE_PLAYING and run.level != null and run.level.is_ready(), 1800)
	run.player.inventory.reset({&"polaroid": 3, &"chalk": 4, &"glowstick": 4})
	run.player.flashlight.set_on(false, true)
	set_coherence(START_COHERENCE)
	await ticks(10)


func _teardown() -> void:
	release_all()
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	if _prev_meta != null:
		GameState.meta = _prev_meta
		_prev_meta = null
	if SceneRouter.get_host() == _host:
		SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition


# --- running rows -----------------------------------------------------------------------------

## `only` (row ids) limits the sequence, in table order; empty runs everything.
func run_all(only: Array = []) -> Array:
	for row in _rows:
		if only.is_empty() or only.has(String(row[&"id"])):
			await run_row(row[&"id"])
	finished.emit(results)
	return results


## Fires one row and returns its result: {id, label, ref, status, listed, min, ok, fired,
## channels: {I: {ticks, ms, key, keys} or {}}, missing, late, reason}.
func run_row(id: StringName) -> Dictionary:
	var row := FeedbackRows.find(id)
	if row.is_empty():
		return {}
	if row[&"status"] == FeedbackRows.PENDING:
		var skipped := _result_for(row, {})
		_store(skipped)
		return skipped
	_busy = true
	current = row
	spy.extra.clear()
	_anchor_index = -1
	var t0 := Time.get_ticks_usec()
	if not row[&"chained"]:
		release_all()
		run.player.flashlight.set_on(false, true)
		await arm()
	await _recipes.call(String(id), self)
	if _anchor_index < 0:
		push_warning("FeedbackBench: row %s never anchored" % id)
	else:
		var end_tick := _anchor_tick + int(row[&"window"])
		await until(func() -> bool:
			return Engine.get_physics_frames() >= end_tick or Time.get_ticks_usec() - t0 > ROW_TIMEOUT_USEC, 1200)
	release_all()
	var result := _evaluate(row)
	result[&"wall_ms"] = int((Time.get_ticks_usec() - t0) / 1000)
	spy.extra.clear()
	_store(result)
	_busy = false
	return result


func _store(result: Dictionary) -> void:
	results.append(result)
	row_finished.emit(result)
	print(format_line(result))
	if _label != null:
		_refresh_ui()


## What a row's channels did after the anchor.
func _evaluate(row: Dictionary) -> Dictionary:
	var channels: Dictionary = {}
	if _anchor_index >= 0:
		var end_tick := _anchor_tick + int(row[&"window"])
		for ch: StringName in FeedbackSpy.CHANNELS:
			var lookback := int((row[&"lookback"] as Dictionary).get(ch, 0))
			var noisy: Dictionary = {} if lookback > 0 else spy.noisy_keys(_anchor_index, ch)
			var expect: Array = (row[&"expect"] as Dictionary).get(ch, [])
			var first := -1
			var keys: Dictionary = {}
			var start := _anchor_index
			while start > 0 and spy.entries[start - 1][&"tick"] >= _anchor_tick - lookback:
				start -= 1
			for i in range(start, spy.entries.size()):
				var e: Dictionary = spy.entries[i]
				if int(e[&"tick"]) > end_tick:
					break
				for k: String in _accepted(e[&"changed"][ch], noisy, expect):
					keys[k] = true
					if first < 0:
						first = i
			if first >= 0:
				var fe: Dictionary = spy.entries[first]
				var key_list := _accepted(fe[&"changed"][ch], noisy, expect)
				channels[ch] = {
					&"ticks": maxi(int(fe[&"tick"]) - _anchor_tick, 0),
					&"frames": maxi(int(fe[&"frame"]) - _anchor_frame, 0),
					&"ms": maxf(float(int(fe[&"usec"]) - _anchor_usec) / 1000.0, 0.0),
					&"key": key_list[0],
					&"first_keys": Array(key_list.slice(0, 5)),
					&"keys": keys.size(),
				}
	return _result_for(row, channels)


## The changed keys that count: not noisy, and (when the row names what it expects) matching.
static func _accepted(changed: PackedStringArray, noisy: Dictionary, expect: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for k in changed:
		if noisy.has(k):
			continue
		if not expect.is_empty() and not expect.any(func(sub: String) -> bool: return k.contains(sub)):
			continue
		out.append(k)
	return out


func _result_for(row: Dictionary, channels: Dictionary) -> Dictionary:
	var fired := 0
	var late: Array[String] = []
	var missing: Array[String] = []
	for ch: StringName in FeedbackSpy.CHANNELS:
		var listed: bool = String(row[&"listed"]).contains(String(ch))
		if channels.has(ch):
			if within(channels[ch]):
				fired += 1
			else:
				late.append(String(ch))
		elif listed:
			missing.append(String(ch))
	var pending: bool = row[&"status"] == FeedbackRows.PENDING
	return {
		&"id": row[&"id"], &"label": row[&"label"], &"ref": row[&"ref"], &"status": row[&"status"],
		&"listed": row[&"listed"], &"min": row[&"min"], &"fired": fired,
		&"ok": pending or fired >= int(row[&"min"]),
		&"channels": channels, &"missing": missing, &"late": late, &"reason": row[&"reason"],
	}


## 11 §1: within 50 ms of the triggering frame, i.e. 3 frames at 60 fps. The bench runs at
## whatever rate the machine gives it (headless is not locked to 60 fps and physics ticks
## bunch up after a stall), so a reaction is on time when ANY of the three measures is inside
## the budget: physics ticks, process frames, or wall milliseconds. It is late only when it
## is late by all three.
static func within(c: Dictionary) -> bool:
	return int(c[&"ticks"]) <= Tuning.FEEDBACK_MAX_LATENCY_FRAMES \
			or int(c.get(&"frames", 0)) <= Tuning.FEEDBACK_MAX_LATENCY_FRAMES \
			or float(c[&"ms"]) <= float(Tuning.FEEDBACK_MAX_LATENCY_MS)


static func format_line(r: Dictionary) -> String:
	if r[&"status"] == FeedbackRows.PENDING:
		return "feedback %-22s PENDING  %s" % [r[&"id"], r[&"reason"]]
	var parts: PackedStringArray = []
	for ch: StringName in FeedbackSpy.CHANNELS:
		var c: Dictionary = (r[&"channels"] as Dictionary).get(ch, {})
		if c.is_empty():
			parts.append("%s -" % ch)
		else:
			parts.append("%s %dt/%.0fms %s" % [ch, c[&"ticks"], c[&"ms"], c[&"key"]])
	var mark := "ok  " if r[&"ok"] else ("GAP " if r[&"status"] == FeedbackRows.GAP else "FAIL")
	return "feedback %-22s %s  %d/%d  %5dms  %s" % [r[&"id"], mark, r[&"fired"], r[&"min"], int(r.get(&"wall_ms", 0)), " | ".join(parts)]


func _print_table() -> void:
	var good := 0
	var bad := 0
	var pending := 0
	var gaps := 0
	for r in results:
		if r[&"status"] == FeedbackRows.PENDING:
			pending += 1
		elif r[&"status"] == FeedbackRows.GAP:
			gaps += 1
		elif r[&"ok"]:
			good += 1
		else:
			bad += 1
	print("feedback: %d ok, %d failed, %d gaps, %d pending" % [good, bad, gaps, pending])


func write_json(path: String) -> void:
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("FeedbackBench: cannot write %s" % abs_path)
		return
	f.store_string(JSON.stringify({"seed": RUN_SEED, "max_latency_ticks": Tuning.FEEDBACK_MAX_LATENCY_FRAMES, "rows": results}, "  "))
	f.close()
	print("feedback: wrote ", abs_path)


## The checklist table (docs/qa/feedback_checklist.md): x = reacted within 3 ticks (50 ms at
## 60 fps), `x*` = reacted though the table lists a dash, `+N` = reacted N ticks late, `no` =
## listed but did not react, `-` = not listed. Written by `--auto out.json --md out.md`.
static func markdown(rows: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("| Action / event | Ref | I | S | M | R | Result | What reacted |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for r in rows:
		var cells: PackedStringArray = []
		var evidence: PackedStringArray = []
		for ch: StringName in FeedbackSpy.CHANNELS:
			var listed: bool = String(r[&"listed"]).contains(String(ch))
			var c: Dictionary = (r[&"channels"] as Dictionary).get(ch, {})
			if r[&"status"] == FeedbackRows.PENDING:
				cells.append("pending" if listed else "-")
			elif c.is_empty():
				cells.append("no" if listed else "-")
			else:
				var on_time := within(c)
				var mark := "x" if listed else "x*"
				cells.append(mark if on_time else "+%d" % int(c[&"ticks"]))
				if on_time:
					evidence.append("%s %s" % [ch, _short(String(c[&"key"]))])
		var result := "pending: " + String(r[&"reason"]) if r[&"status"] == FeedbackRows.PENDING \
				else ("ok %d/%d" % [r[&"fired"], r[&"min"]] if r[&"ok"] else "GAP: " + String(r[&"reason"]) \
				if r[&"status"] == FeedbackRows.GAP else "FAIL %d/%d" % [r[&"fired"], r[&"min"]])
		lines.append("| %s | %s | %s | %s | %s |" % [r[&"label"], r[&"ref"], " | ".join(cells), result, "; ".join(evidence)])
	return "\n".join(lines) + "\n"


static func _short(key: String) -> String:
	var parts := key.split("/")
	return parts[parts.size() - 1] if parts.size() > 1 else key


func write_text(path: String, text: String) -> void:
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
		print("feedback: wrote ", abs_path)


# --- the recipe API -----------------------------------------------------------------------------

## Waits until the spy sees a steady state: the same set of changing keys for a few checks
## in a row (nothing at all, or a perpetual animation such as a heartbeat pulse). Bounded.
## Call before the trigger.
func arm() -> void:
	var steady := 0
	var frames_left := QUIET_MAX_FRAMES
	var seen := spy.entries.size()
	var last := ""
	while steady < QUIET_FRAMES and frames_left > 0:
		await get_tree().process_frame
		await get_tree().process_frame
		frames_left -= 1
		var keys: Array = []
		for i in range(seen, spy.entries.size()):
			for ch: StringName in FeedbackSpy.CHANNELS:
				for k in spy.entries[i][&"changed"][ch]:
					if not keys.has(k):
						keys.append(k)
		seen = spy.entries.size()
		keys.sort()
		var sig := ",".join(PackedStringArray(keys))
		steady = steady + 1 if sig == last else 0
		last = sig


## Marks the trigger: the next sampled frame is the first one that can show the reaction.
func anchor() -> void:
	if _anchor_index >= 0:
		return
	_anchor_index = spy.entries.size()
	_anchor_tick = Engine.get_physics_frames()
	_anchor_frame = Engine.get_process_frames()
	_anchor_usec = Time.get_ticks_usec()


## Anchors when `sig` next emits (and `accept` returns true for its arguments).
func anchor_on(sig: Signal, accept: Callable = Callable()) -> void:
	var cb := func(a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null) -> void:
		if accept.is_valid() and not bool(accept.callv([a, b, c, d].slice(0, accept.get_argument_count()))):
			return
		anchor()
	sig.connect(cb, CONNECT_ONE_SHOT)


func is_anchored() -> bool:
	return _anchor_index >= 0


## Polls `cond` every process frame, at most `frames` frames. True if it became true.
func until(cond: Callable, frames: int = 600) -> bool:
	var n := 0
	while not bool(cond.call()) and n < frames:
		await get_tree().process_frame
		n += 1
	return bool(cond.call())


## Waits `n` physics ticks (process frames while the tree is paused by a hitstop).
func ticks(n: int) -> void:
	var end := Engine.get_physics_frames() + n
	var guard := 0
	while Engine.get_physics_frames() < end and guard < 5000:
		await get_tree().process_frame
		guard += 1


func press(action: StringName) -> void:
	Input.action_press(action)


func release(action: StringName) -> void:
	Input.action_release(action)


func release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func player() -> Player:
	return run.player


func set_coherence(v: float) -> void:
	var p := run.player
	p.coherence = clampf(v, 0.0, Tuning.COHERENCE_MAX)
	p.call(&"_feed_coherence")
	p.coherence_changed.emit(p.coherence, 0.0, &"reset")


## Puts the player at `pos` (feet) facing `yaw` (rad) with `pitch` (rad), standing, still.
func place(pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
	var p := run.player
	p.global_position = pos
	p.rotation = Vector3(0.0, yaw, 0.0)
	p.velocity = Vector3.ZERO
	p.rig.reset_pitch()
	p.rig.add_pitch(pitch)


## Yaw that faces `target` from `from` on the floor plane.
static func yaw_to(from: Vector3, target: Vector3) -> float:
	var d := target - from
	return atan2(-d.x, -d.z)


## Stands the player at the start of the longest straight sightline (LevelShots pose 0).
func pose_sightline() -> void:
	var pose := LevelShots.poses(run.data)[0]
	var from: Vector3 = pose[&"from"]
	place(from - Vector3(0.0, LevelShots.EYE, 0.0), yaw_to(from, pose[&"to"]), 0.0)
	run.level.light_pool.reevaluate()
	await ticks(8)


# --- interactive UI ---------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_label.size = Vector2(900, 700)
	_label.position = Vector2(12, 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)


func _refresh_ui() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = ["[b]FEEDBACK BENCH[/b]  Up/Down choose, Enter fire, A all, Esc quit"]
	var by_id: Dictionary = {}
	for r in results:
		by_id[r[&"id"]] = r
	var from := maxi(_selected - 8, 0)
	for i in range(from, mini(from + 20, _rows.size())):
		var row := _rows[i]
		var mark := ">" if i == _selected else " "
		var r: Dictionary = by_id.get(row[&"id"], {})
		var text := "%s %-22s %s" % [mark, row[&"label"], row[&"listed"]]
		if row[&"status"] == FeedbackRows.PENDING:
			text += "  pending"
		elif not r.is_empty():
			text += "  " + ("ok " if r[&"ok"] else "FAIL ") + str(r[&"fired"]) + "/" + str(r[&"min"])
		lines.append(text)
	_label.text = "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _busy:
		return
	match k.physical_keycode:
		KEY_DOWN, KEY_N:
			_selected = mini(_selected + 1, _rows.size() - 1)
		KEY_UP, KEY_P:
			_selected = maxi(_selected - 1, 0)
		KEY_ENTER, KEY_KP_ENTER:
			run_row(_rows[_selected][&"id"])
		KEY_A:
			run_all()
		KEY_ESCAPE, KEY_Q:
			get_tree().quit(0)
	_refresh_ui()
