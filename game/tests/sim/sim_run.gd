extends SceneTree
## Headless simulated playtests (M1.8, R8): the scripted bot (SimBot) plays one level per
## seed, profile and depth with the Director and errors active, at time scale 1. Prints one
## JSON line per run (`sim-run {...}`) and a summary table.
## Usage (`--fixed-fps 60` steps 1/60 s per frame as fast as the CPU allows; without it
## the engine syncs to the wall clock and a 10-minute level takes 10 minutes):
##   godot --headless --fixed-fps 60 --path game --script tests/sim/sim_run.gd -- \
##         [--seeds 3] [--from 1] [--profiles direct,explorer,cautious] [--depths 1,2]
##         [--max-seconds 600] [--stop-after-relief] [--linger] [--no-linger] [--csv <dir>]
##         [--json <file>] [--no-audio-guard] [--descent]
## --descent (R18, review S6) plays one chained Descent per seed and profile instead of one
## level: depths 1 to 6 on one run, Coherence and the belt carried through the real exit,
## Landing and arrival (SimDescent). --max-seconds is then per level. It prints three tables
## (per run, per level, per profile) and --json writes the results.
## --linger makes every profile visit more rooms and dead ends before its objective; the
## explorer lingers by default (M2.7), --no-linger turns that off.
## With --csv, each run's Director telemetry is written as
## <dir>/<profile>_d<depth>_seed<n>.csv and the summary table as <dir>/summary.csv.
## With --json, every result is written as one JSON array (the gate test reads it).
## Depths beyond 1 start the run there (`RunState.depth`); strata without a grammar
## generate as Halls (M1.9).

const SUMMARY_HEADER := "profile,depth,seed,stratum,outcome,time_s,calm,build,peak,peak_chased,relief,max_intensity,contacts,unchased,relief_contacts,refused,chases,sent_away,violations,stuck_events,coherence,hunter,static,spawned,scares,scare_contacts,decisions,dpm,max_gap_s,hides,items_used,pickups,cause,null_woke_s,null_core_s,null_drained,null_wake_dist,soft_passes"

var _seeds: int = 3
var _from: int = 1
var _profiles: Array[StringName] = [&"direct", &"explorer", &"cautious"]
var _depths: Array[int] = [1]
var _max_s: float = 600.0
var _stop_after_relief: bool = false
var _linger: bool = false
var _no_linger: bool = false
var _csv_dir: String = ""
var _json_path: String = ""
var _descent: bool = false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		var next := a[i + 1] if i + 1 < a.size() else ""
		match a[i]:
			"--seeds":
				_seeds = maxi(next.to_int(), 1)
			"--from":
				_from = next.to_int()
			"--profiles":
				_profiles.clear()
				for p in next.split(",", false):
					_profiles.append(StringName(p.strip_edges()))
			"--depths":
				_depths.clear()
				for d in next.split(",", false):
					_depths.append(maxi(d.to_int(), 1))
			"--max-seconds":
				_max_s = maxf(next.to_float(), 10.0)
			"--stop-after-relief":
				_stop_after_relief = true
			"--linger":
				_linger = true
			"--no-linger":
				_no_linger = true
			"--csv":
				_csv_dir = next
			"--json":
				_json_path = next
			"--descent":
				_descent = true
			"--no-audio-guard":
				AudioMixGuard.enabled = false  # RCA1 A/B: reopens the engine audio race
	_main.call_deferred()


func _main() -> void:
	Engine.time_scale = 1.0
	var host := Node.new()
	host.name = "SimHost"
	root.add_child(host)
	# Autoloads are not compile-time identifiers in a --script SceneTree; reach them by path.
	var router: Node = root.get_node(^"SceneRouter")
	router.call(&"set_host", host)
	router.set(&"transition", null)
	var bot_script: GDScript = load("res://tests/sim/sim_bot.gd")
	var results: Array = []
	var wall0 := Time.get_ticks_msec()
	if _descent:
		await _descents(host, results, wall0, load("res://tests/sim/sim_descent.gd"))
		return
	for depth in _depths:
		for profile in _profiles:
			for s in range(_from, _from + _seeds):
				var bot: Variant = bot_script.new()
				bot.tree = self
				bot.host = host
				bot.profile = profile
				bot.depth = depth
				bot.max_seconds = _max_s
				bot.stop_after_relief = _stop_after_relief
				bot.linger = _linger or (profile == &"explorer" and not _no_linger)
				if not _csv_dir.is_empty():
					bot.csv_path = _csv_dir.path_join("%s_d%d_seed%d.csv" % [profile, depth, s])
				var r: Dictionary = await bot.call(&"play", s)
				results.append(r)
				print("sim-run %s" % JSON.stringify(r))
	var table := summary_rows(results)
	print("sim-run summary (%d runs, %.0f s wall):" % [results.size(), (Time.get_ticks_msec() - wall0) / 1000.0])
	print(format_table(table))
	if not _csv_dir.is_empty():
		var f := FileAccess.open(_csv_dir.path_join("summary.csv"), FileAccess.WRITE)
		if f != null:
			f.store_string(SUMMARY_HEADER + "\n" + "\n".join(PackedStringArray(table.map(func(row: Array) -> String:
				return ",".join(PackedStringArray(row.map(func(v: Variant) -> String: return str(v))))))) + "\n")
			f.close()
	if not _json_path.is_empty():
		var j := FileAccess.open(_json_path, FileAccess.WRITE)
		if j != null:
			j.store_string(JSON.stringify(results))
			j.close()
	quit(0)


## R18: the chained Descents, then the three tables.
func _descents(host: Node, results: Array, wall0: int, script: GDScript) -> void:
	for profile in _profiles:
		for s in range(_from, _from + _seeds):
			var d: Variant = script.new()
			d.tree = self
			d.host = host
			d.profile = profile
			d.max_seconds = _max_s
			d.linger = _linger
			var r: Dictionary = await d.call(&"play", s)
			results.append(r)
			print("sim-descent %s" % JSON.stringify(r))
	print("sim-descent (%d runs, %.0f s wall)" % [results.size(), (Time.get_ticks_msec() - wall0) / 1000.0])
	print("per run:\n" + script.call(&"format_table", script.get(&"RUN_HEADER"), script.call(&"run_rows", results)))
	print("per level:\n" + script.call(&"format_table", script.get(&"LEVEL_HEADER"), script.call(&"level_rows", results)))
	print("per profile:\n" + script.call(&"format_table", script.get(&"SUMMARY_HEADER"), script.call(&"summary_rows", results)))
	if not _json_path.is_empty():
		var j := FileAccess.open(_json_path, FileAccess.WRITE)
		if j != null:
			j.store_string(JSON.stringify(results))
			j.close()
	quit(0)


## One row per run, columns as SUMMARY_HEADER.
static func summary_rows(results: Array) -> Array:
	var out: Array = []
	for r: Dictionary in results:
		var pc: Dictionary = r.get(&"phase_counts", {})
		out.append([r.get(&"profile", ""), r.get(&"depth", 0), r.get(&"seed", 0), r.get(&"stratum", ""),
			r.get(&"outcome", ""), r.get(&"time_s", 0.0), pc.get(&"calm", 0), pc.get(&"build", 0),
			pc.get(&"peak", 0), r.get(&"peaks_with_chase", 0), pc.get(&"relief", 0), r.get(&"max_intensity", 0.0), r.get(&"contacts", 0),
			r.get(&"contacts_unchased", 0), r.get(&"contacts_in_relief", 0),
			r.get(&"refused", 0), r.get(&"encounters", 0), r.get(&"retreated_chases", 0),
			(r.get(&"contact_violations", []) as Array).size(), r.get(&"stuck_events", 0),
			r.get(&"coherence", 0.0), r.get(&"has_hunter", false), r.get(&"has_static", false),
			"+".join(PackedStringArray((r.get(&"spawned", []) as Array).map(
				func(v: Variant) -> String: return str(v)))),
			r.get(&"scares", 0), r.get(&"scare_contacts", 0), r.get(&"decisions", 0), r.get(&"dpm", 0.0),
			r.get(&"max_decision_gap_s", 0.0), r.get(&"hides", 0),
			_sum((r.get(&"items_used", {}) as Dictionary).values()), r.get(&"pickups", 0),
			r.get(&"cause", ""), r.get(&"null_woke_s", -1.0), r.get(&"null_core_s", 0.0), r.get(&"null_drained", 0.0),
			r.get(&"null_wake_dist", -1.0), r.get(&"soft_passes", 0)])
	return out


static func _sum(a: Array) -> int:
	var n := 0
	for v in a:
		n += int(v)
	return n


static func format_table(rows: Array) -> String:
	var head := SUMMARY_HEADER.split(",")
	var all: Array = [Array(head)]
	all.append_array(rows)
	var widths: Array[int] = []
	for c in head.size():
		var w := 0
		for row: Array in all:
			w = maxi(w, str(row[c]).length())
		widths.append(w)
	var lines := PackedStringArray()
	for row: Array in all:
		var cells := PackedStringArray()
		for c in head.size():
			cells.append(str(row[c]).rpad(widths[c]))
		lines.append("| " + " | ".join(cells) + " |")
	return "\n".join(lines)
