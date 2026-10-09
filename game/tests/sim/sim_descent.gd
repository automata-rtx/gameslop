class_name SimDescent
extends RefCounted
## The chained simulated Descent (R18, review S6): one run, depths 1 to 6, played by a SimBot
## profile through the real run flow. A fresh `SimBot` plays each level of the same `Run`
## scene (`chain = true`); between levels the real exit, Landing (item choice through the
## panel's own keys) and arrival run, so Coherence (+20 per proper exit), the belt and the
## RunState counters carry exactly as they do in play. The run ends in a dissolve, a stuck or
## timed-out bot, or the Threshold. Used by `sim_run.gd --descent` (CLI) and
## `test_sim_descent.gd` (the gate).
##
## Result keys: seed, profile, outcome (`threshold`, `dissolved`, `stuck`, `timeout`, `limit`,
## `error`), depth_reached, death_depth (0 when the run was not lost), cause, time_s (all
## levels), spent (Coherence spent on noclip), levels: one entry per level played with depth,
## stratum, arrive_coh (after the Landing's +20), arrive_items (kind -> count), exit_coh,
## time_s, outcome, cause, contacts, picked (the Landing item taken after this level).

const LANDING_WAIT_S := 30.0
## M3.4: the bot's per-level keys kept in each `levels` entry for the tuning tables.
const TELEMETRY_KEYS: Array[StringName] = [&"contact_log", &"losses", &"contact_light", &"breaker_s",
	&"phase_intensity", &"phase_counts", &"max_intensity", &"spawned", &"encounters", &"retreated_chases",
	&"notices", &"scares", &"hides", &"stuck_at", &"null_woke_s", &"null_core_s", &"null_drained",
	&"null_wake_dist", &"null_min_dist", &"null_replaced", &"null_wake_flat", &"path_m", &"player_path_f",
	&"null_path_f", &"winding_player", &"winding_null", &"soft_passes", &"soft_fails", &"stuck_events", &"evasions", &"last_losses"]
const PICK_PREFERENCE: Array[StringName] = [&"glowstick", &"flare", &"polaroid"]
const LOW_COHERENCE := 75.0

var tree: SceneTree
var host: Node
var profile: StringName = SimBot.PROFILE_DIRECT
var max_seconds: float = 600.0
var linger: bool = false
## M3.4: when set, each level's Director telemetry CSV goes to
## <csv_dir>/<profile>_seed<n>_d<depth>.csv.
var csv_dir: String = ""
## Stop after this many levels (a gate test that only proves the chain works).
var max_levels: int = 99

var _run: Run


## Plays one Descent with `run_seed`.
func play(run_seed: int) -> Dictionary:
	var result := {&"seed": run_seed, &"profile": profile, &"outcome": &"error", &"depth_reached": 1,
		&"death_depth": 0, &"cause": "", &"time_s": 0.0, &"spent": 0.0, &"levels": []}
	var meta := GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	_run = (load(SimBot.RUN_SCENE) as PackedScene).instantiate() as Run
	_run.capture_mouse = false
	_run.landing_time = 0.5
	host.add_child(_run)
	var t0 := Time.get_ticks_msec()
	while _run.phase != Run.PHASE_PLAYING and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	var levels: Array = result[&"levels"]
	var played := 0
	while is_instance_valid(_run) and _run.phase == Run.PHASE_PLAYING and played < max_levels:
		var depth := GameState.run.depth
		var entry := {&"depth": depth, &"stratum": _run.data.stratum, &"arrive_coh": snappedf(_run.player.coherence, 0.1),
			&"arrive_items": belt(_run.player.inventory)}
		var bot := SimBot.new()
		bot.tree = tree
		bot.host = host
		bot.profile = profile
		bot.depth = depth
		bot.max_seconds = max_seconds
		bot.linger = linger or profile == SimBot.PROFILE_EXPLORER
		bot.chain = true
		bot.run = _run
		if not csv_dir.is_empty():
			bot.csv_path = csv_dir.path_join("%s_seed%d_d%d.csv" % [profile, run_seed, depth])
		var r: Dictionary = await bot.play(run_seed)
		played += 1
		entry[&"outcome"] = r.get(&"outcome", &"error")
		entry[&"cause"] = r.get(&"cause", "")
		entry[&"time_s"] = r.get(&"time_s", 0.0)
		entry[&"contacts"] = r.get(&"contacts", 0)
		entry[&"exit_coh"] = r.get(&"coherence", 0.0)
		entry[&"items_used"] = r.get(&"items_used", {})
		for k: StringName in TELEMETRY_KEYS:
			if r.has(k):
				entry[k] = r[k]
		levels.append(entry)
		print("sim-descent %s seed %d depth %d %s: arrived %.0f, left %.0f, %.0f s, %s %s" % [profile, run_seed, depth,
			entry[&"stratum"], entry[&"arrive_coh"], entry[&"exit_coh"], entry[&"time_s"], entry[&"outcome"], entry[&"cause"]])
		result[&"time_s"] = snappedf(float(result[&"time_s"]) + float(entry[&"time_s"]), 0.1)
		result[&"depth_reached"] = GameState.run.max_depth
		if r.has(&"error"):
			result[&"error"] = r[&"error"]
		var out: StringName = entry[&"outcome"]
		if out == &"exit" and depth >= Tuning.RUN_FINAL_DEPTH:
			# The Threshold: the door has taken the player; the run ends once the entering tween is done.
			var w0 := Time.get_ticks_msec()
			while GameState.is_run_active() and Time.get_ticks_msec() - w0 < 10000:
				await tree.process_frame
			if GameState.last_cause() == GameState.WIN_CAUSE:
				out = &"threshold"
				entry[&"outcome"] = out
		if out != &"exit":
			result[&"outcome"] = out
			if out == &"dissolved":
				result[&"death_depth"] = depth
				result[&"cause"] = entry[&"cause"]
			break
		# A proper exit: through the Landing to the next level.
		if not await _through_landing(entry, depth):
			result[&"outcome"] = &"error"
			result[&"error"] = "no arrival after the Landing at depth %d" % depth
			break
	if is_instance_valid(_run) and _run.phase == Run.PHASE_PLAYING and played >= max_levels:
		result[&"outcome"] = &"limit"
	result[&"spent"] = snappedf(GameState.run.coherence_spent, 0.1)
	result[&"proper_exits"] = GameState.run.proper_exits
	result[&"drops_total"] = GameState.run.drops_total
	await _teardown(meta)
	return result


## Picks the Landing item while the cabin stands, then waits for the next level's arrival.
func _through_landing(entry: Dictionary, depth: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while _run.phase != Run.PHASE_LANDING and Time.get_ticks_msec() - t0 < LANDING_WAIT_S * 1000.0:
		await tree.process_frame
	if _run.phase == Run.PHASE_LANDING and _run.landing != null:
		var landing := _run.landing
		var kinds: Array = landing.panel.kinds
		var choice := pick_index(kinds, _run.player.coherence)
		if choice >= 0:
			entry[&"picked"] = kinds[choice]
			var key := StringName("item_%d" % (choice + 1))
			Input.parse_input_event(_press(key, true))
			await tree.process_frame
			Input.parse_input_event(_press(key, false))
			if landing.panel.chosen_index < 0:
				landing.call(&"_choose", choice)  # the key path did not reach the cabin (headless input)
	while Time.get_ticks_msec() - t0 < LANDING_WAIT_S * 1000.0:
		if _run.phase == Run.PHASE_PLAYING and GameState.run.depth == depth + 1 and _run.arrival == Tuning.RUN_ARRIVE_PROPER:
			return true
		if _run.phase == Run.PHASE_DISSOLVING or _run.phase == Run.PHASE_ENDED:
			return true  # the caller's loop ends and the run is scored as it stands
		await tree.process_frame
	return false


static func _press(action: StringName, pressed: bool) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	return e


## The Landing row the bots take: the first of glowstick, flare, polaroid offered (the
## counters SimBotItems plays), Polaroid first while Coherence is below 75; else row 0.
static func pick_index(kinds: Array, coherence: float) -> int:
	if kinds.is_empty():
		return -1
	var order: Array[StringName] = PICK_PREFERENCE.duplicate()
	if coherence < LOW_COHERENCE:
		order.erase(&"polaroid")
		order.push_front(&"polaroid")
	for k in order:
		var i := kinds.find(k)
		if i >= 0:
			return i
	return 0


## kind -> count over the belt.
static func belt(inv: Inventory) -> Dictionary:
	var out := {}
	for s: Variant in inv.slots:
		if s != null:
			var k := String((s as ItemSlot).kind)
			out[k] = int(out.get(k, 0)) + (s as ItemSlot).count
	return out


func _teardown(meta: MetaState) -> void:
	PlayerFixture.release_all()
	for c in host.get_children():
		c.queue_free()  # the run, or the ending scene a win loaded
	for i in 3:
		await tree.process_frame
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = meta


# --- tables -------------------------------------------------------------------------------

## "100 90 74" style Coherence at each arrival of a result.
static func arrivals(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for e: Dictionary in r.get(&"levels", []):
		parts.append("%d" % roundi(float(e.get(&"arrive_coh", 0.0))))
	return " ".join(parts)


static func belt_text(items: Dictionary) -> String:
	var parts := PackedStringArray()
	var kinds: Array = items.keys()
	kinds.sort()
	for k in kinds:
		parts.append("%s%d" % [String(k).left(3), int(items[k])])
	return "+".join(parts) if not parts.is_empty() else "-"


const RUN_HEADER := ["profile", "seed", "outcome", "death_depth", "cause", "reached", "time_s", "spent", "coherence_at_arrival", "items_at_arrival"]


static func run_rows(results: Array) -> Array:
	var out: Array = []
	for r: Dictionary in results:
		var items := PackedStringArray()
		for e: Dictionary in r.get(&"levels", []):
			items.append(belt_text(e.get(&"arrive_items", {})))
		out.append([r.get(&"profile", ""), r.get(&"seed", 0), r.get(&"outcome", ""), r.get(&"death_depth", 0),
			r.get(&"cause", ""), r.get(&"depth_reached", 0), r.get(&"time_s", 0.0), r.get(&"spent", 0.0),
			arrivals(r), " | ".join(items)])
	return out


const LEVEL_HEADER := ["profile", "seed", "depth", "stratum", "arrive_coh", "arrive_items", "picked_after", "exit_coh", "time_s", "contacts", "outcome", "cause"]


static func level_rows(results: Array) -> Array:
	var out: Array = []
	for r: Dictionary in results:
		for e: Dictionary in r.get(&"levels", []):
			out.append([r.get(&"profile", ""), r.get(&"seed", 0), e.get(&"depth", 0), e.get(&"stratum", ""),
				e.get(&"arrive_coh", 0.0), belt_text(e.get(&"arrive_items", {})), e.get(&"picked", "-"),
				e.get(&"exit_coh", 0.0), e.get(&"time_s", 0.0), e.get(&"contacts", 0), e.get(&"outcome", ""), e.get(&"cause", "")])
	return out


const SUMMARY_HEADER := ["profile", "runs", "threshold", "died", "other", "deaths_by_depth(1..6)", "mean_arrival_coh(1..6)", "n_arrivals(1..6)", "mean_time_s", "death_causes"]


## Per profile: how many runs reached the Threshold, where the rest died, mean Coherence at
## each depth's arrival.
static func summary_rows(results: Array, depths: int = Tuning.RUN_FINAL_DEPTH) -> Array:
	var profiles: Array = []
	for r: Dictionary in results:
		if not profiles.has(r.get(&"profile", "")):
			profiles.append(r.get(&"profile", ""))
	var out: Array = []
	for p in profiles:
		var runs := results.filter(func(r: Dictionary) -> bool: return r.get(&"profile", "") == p)
		var win := runs.filter(func(r: Dictionary) -> bool: return r.get(&"outcome", "") == &"threshold").size()
		var died := runs.filter(func(r: Dictionary) -> bool: return r.get(&"outcome", "") == &"dissolved").size()
		var by_depth := PackedStringArray()
		var mean_coh := PackedStringArray()
		var counts := PackedStringArray()
		for d in range(1, depths + 1):
			by_depth.append(str(runs.filter(func(r: Dictionary) -> bool: return int(r.get(&"death_depth", 0)) == d).size()))
			var sum := 0.0
			var n := 0
			for r: Dictionary in runs:
				for e: Dictionary in r.get(&"levels", []):
					if int(e.get(&"depth", 0)) == d:
						sum += float(e.get(&"arrive_coh", 0.0))
						n += 1
			mean_coh.append("%.0f" % (sum / n) if n > 0 else "-")
			counts.append(str(n))
		var causes := {}
		var total_t := 0.0
		for r: Dictionary in runs:
			total_t += float(r.get(&"time_s", 0.0))
			if r.get(&"outcome", "") == &"dissolved":
				var c := String(r.get(&"cause", ""))
				causes[c] = int(causes.get(c, 0)) + 1
		var cause_parts := PackedStringArray()
		for c in causes:
			cause_parts.append("%s:%d" % [c, causes[c]])
		out.append([p, runs.size(), win, died, runs.size() - win - died, "/".join(by_depth), "/".join(mean_coh),
			"/".join(counts), "%.0f" % (total_t / maxf(runs.size(), 1)), " ".join(cause_parts) if not cause_parts.is_empty() else "-"])
	return out


static func format_table(header: Array, rows: Array) -> String:
	var all: Array = [header]
	all.append_array(rows)
	var widths: Array[int] = []
	for c in header.size():
		var w := 0
		for row: Array in all:
			w = maxi(w, str(row[c]).length())
		widths.append(w)
	var lines := PackedStringArray()
	for row: Array in all:
		var cells := PackedStringArray()
		for c in header.size():
			cells.append(str(row[c]).rpad(widths[c]))
		lines.append("| " + " | ".join(cells) + " |")
	return "\n".join(lines)
