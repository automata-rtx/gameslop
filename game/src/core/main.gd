extends Node
## Boot scene script (14 §5): main.tscn hosts the routed scene under %Content and
## stays for the whole session. Main stays PROCESS_MODE_PAUSABLE so the routed
## level freezes with hitstop and pause; menus opt into ALWAYS themselves.

## 14 §9: --smoke waits this long after generating depth 1, then quits 0.
const SMOKE_WAIT_S := 2.0


func _ready() -> void:
	SceneRouter.set_host(%Content)
	var args := CliArgs.current()
	if args.smoke:
		_run_smoke()
		return
	if args.validate_levels > 0:
		_run_validate_levels(args.validate_levels)
		return
	if args.wants_direct_level():
		_show(DirectLevel.from_args(args))
		return
	# TODO(M1.9): SceneRouter.change_to("res://scenes/title.tscn") once the title exists;
	# until then %Content holds the placeholder title.


func _run_smoke() -> void:
	await _smoke_generate_depth_1()
	# Process time, not wall time: the smoke test measures that frames keep flowing.
	await get_tree().create_timer(SMOKE_WAIT_S).timeout
	print("smoke: ok")
	get_tree().quit(0)


## 14 §9 --validate-levels N: N levels per stratum with a grammar; prints one report line
## per stratum and quits 1 if any level shipped invalid.
func _run_validate_levels(n: int) -> void:
	var ok := true
	for stratum in CliArgs.STRATA:
		var report := LevelValidator.run_batch(stratum, n)
		var failures: Array = report["failures"]
		report.erase("failures")
		print("validate-levels %s" % JSON.stringify(report))
		for line in failures:
			print("  " + str(line))
		ok = ok and report["invalid"] == 0
	get_tree().quit(0 if ok else 1)


## 14 §9: generate and build depth 1 (Halls, the --seed or a fixed seed) and wait for
## LevelBuilder.built (bounded) before the smoke timer starts.
func _smoke_generate_depth_1() -> void:
	var args := CliArgs.current()
	var d := DirectLevel.from_args(args)
	d.stratum = Tuning.STRATUM_DEPTH1
	d.depth = 1
	d.shots_dir = ""
	d.capture_mouse = false
	_show(d)
	await d.built


## Replaces the routed content with a debug node (direct level launch, smoke).
func _show(node: Node) -> void:
	for child in %Content.get_children():
		child.queue_free()
	%Content.add_child(node)
