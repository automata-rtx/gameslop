extends SceneTree
## Headless test runner (14 §8). Discovers test_*.gd under res://tests/, runs every
## test_* method, prints TAP, and quits with 0 (all pass) or 1.
## Usage: godot --headless --path game --script tests/run_tests.gd [-- --filter <substring>]

const ROOT := "res://tests"

var _filter: String = ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--filter")
	if i != -1 and i + 1 < args.size():
		_filter = args[i + 1]
	_run.call_deferred()

func _run() -> void:
	var files: PackedStringArray = []
	_collect(ROOT, files)
	files.sort()
	var total := 0
	var failed := 0
	var lines: PackedStringArray = []
	var started := Time.get_ticks_msec()
	for path in files:
		var script: Variant = load(path)
		if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
			total += 1
			failed += 1
			lines.append("not ok %d - %s (script failed to load or parse)" % [total, path])
			continue
		var tc: Variant = (script as GDScript).new()
		if not (tc is TestCase):
			if tc is Node:
				(tc as Node).free()
			continue
		var case := tc as TestCase
		# With a filter, a file with no matching test is skipped whole (before_all may be slow).
		var wanted: PackedStringArray = []
		for m in case.get_method_list():
			var name: String = m["name"]
			var label := "%s::%s" % [path.trim_prefix(ROOT + "/"), name]
			if name.begins_with("test_") and (_filter.is_empty() or label.contains(_filter)):
				wanted.append(name)
		if wanted.is_empty():
			case.free()
			continue
		root.add_child(case)
		if case.has_method("before_all"):
			await case.call("before_all")
		for m in case.get_method_list():
			var name: String = m["name"]
			if not wanted.has(name):
				continue
			var label := "%s::%s" % [path.trim_prefix(ROOT + "/"), name]
			total += 1
			case._failures = []
			case._current = name
			if case.has_method("before_each"):
				await case.call("before_each")
			var t0 := Time.get_ticks_usec()
			await case.call(name)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if case.has_method("after_each"):
				await case.call("after_each")
			if case._failures.is_empty():
				lines.append("ok %d - %s (%.1f ms)" % [total, label, ms])
			else:
				failed += 1
				lines.append("not ok %d - %s" % [total, label])
				for f in case._failures:
					lines.append("  # " + f)
			print(lines[lines.size() - 1])
			for f in case._failures:
				print("  # " + f)
		if case.has_method("after_all"):
			await case.call("after_all")
		case.queue_free()
		await process_frame
	print("1..%d" % total)
	print("# %d passed, %d failed, %.1f s" % [total - failed, failed, (Time.get_ticks_msec() - started) / 1000.0])
	if failed > 0:
		print("# FAILED:")
		for l in lines:
			if l.begins_with("not ok"):
				print("#   " + l)
	quit(1 if failed > 0 or total == 0 else 0)

func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path + "/" + sub, out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(dir_path + "/" + f)
