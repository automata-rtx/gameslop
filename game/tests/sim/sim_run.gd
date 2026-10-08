extends SceneTree
## Headless simulated run (M1.8): the scripted bot plays depth 1 with the Director and
## errors active, for N seeds, and prints one JSON line per seed plus a summary.
## Usage:
##   godot --headless --path game --script tests/sim/sim_run.gd -- --seeds 5 [--from 1]
##         [--time-scale 4] [--max-seconds 600] [--csv <dir>]
## With --csv, each seed's Director telemetry is written as <dir>/seed_<n>.csv.

var _seeds: int = 5
var _from: int = 1
var _scale: float = 4.0
var _max_s: float = 600.0
var _csv_dir: String = ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size() - 1:
		match a[i]:
			"--seeds":
				_seeds = maxi(a[i + 1].to_int(), 1)
			"--from":
				_from = a[i + 1].to_int()
			"--time-scale":
				_scale = maxf(a[i + 1].to_float(), 1.0)
			"--max-seconds":
				_max_s = maxf(a[i + 1].to_float(), 10.0)
			"--csv":
				_csv_dir = a[i + 1]
	_main.call_deferred()


func _main() -> void:
	Engine.time_scale = _scale
	Engine.max_physics_steps_per_frame = maxi(8, ceili(_scale * 2.0))
	var host := Node.new()
	host.name = "SimHost"
	root.add_child(host)
	# Autoloads are not compile-time identifiers in a --script SceneTree; reach them by path.
	var router: Node = root.get_node(^"SceneRouter")
	router.call(&"set_host", host)
	router.set(&"transition", null)
	var bot_script: GDScript = load("res://tests/sim/sim_bot.gd")
	var reached := 0
	var total_t := 0.0
	var contacts := 0
	for s in range(_from, _from + _seeds):
		var bot: Variant = bot_script.new()
		bot.tree = self
		bot.host = host
		bot.max_seconds = _max_s
		if not _csv_dir.is_empty():
			bot.csv_path = _csv_dir.path_join("seed_%d.csv" % s)
		var r: Dictionary = await bot.call(&"play", s)
		print("sim-run %s" % JSON.stringify(r))
		reached += 1 if r.get(&"reached", false) else 0
		total_t += float(r.get(&"time_s", 0.0))
		contacts += int(r.get(&"contacts", 0))
	print("sim-run summary: %d/%d reached the exit, mean %.1f s, %d contacts" % [reached, _seeds, total_t / _seeds, contacts])
	Engine.time_scale = 1.0
	quit(0)
