extends Node
## Boot scene script (14 §5): main.tscn hosts the routed scene under %Content and
## stays for the whole session. Main stays PROCESS_MODE_PAUSABLE so the routed
## level freezes with hitstop and pause; menus opt into ALWAYS themselves.

## 14 §9: --smoke waits this long after generating depth 1, then quits 0.
const SMOKE_WAIT_S := 2.0
const TITLE_SCENE := "res://scenes/title.tscn"


func _ready() -> void:
	SceneRouter.set_host(%Content)
	# 04 §4: the 120 ms glitch between screens (SceneRouter's transition hook).
	var glitch := GlitchTransition.new()
	glitch.name = "GlitchTransition"
	add_child(glitch)
	SceneRouter.transition = glitch
	if OS.is_debug_build():
		var overlay := DebugOverlay.new()
		overlay.name = "DebugOverlay"
		add_child(overlay)
	var args := CliArgs.current()
	if args.smoke:
		_run_smoke()
		return
	if args.tour:
		_run_tour(args.tour_dir)
		return
	if args.validate_levels > 0:
		_run_validate_levels(args.validate_levels, args.stratum)
		return
	if args.wants_direct_level():
		_show(DirectLevel.from_args(args))
		return
	SceneRouter.change_to(TITLE_SCENE)


func _run_smoke() -> void:
	await _smoke_generate_depth_1()
	# Process time, not wall time: the smoke test measures that frames keep flowing.
	await get_tree().create_timer(SMOKE_WAIT_S).timeout
	print("smoke: ok")
	get_tree().quit(0)


## 14 §9 --tour [out_dir]: the screenshot tour (02 §13). Needs a renderer; quits when done.
func _run_tour(out_dir: String) -> void:
	var tour := ScreenshotTour.new()
	tour.name = "ScreenshotTour"
	%Content.add_child(tour)
	tour.run(out_dir)


## 14 §9 --validate-levels N: N levels per stratum with a grammar; prints one report line
## per stratum and quits 1 if any level shipped invalid. With --stratum S, only that stratum.
func _run_validate_levels(n: int, only: StringName = &"") -> void:
	var ok := true
	for stratum in CliArgs.STRATA:
		if only != &"" and stratum != only:
			continue
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


func _exit_tree() -> void:
	if SceneRouter.transition is GlitchTransition and (SceneRouter.transition as Node).get_parent() == self:
		SceneRouter.transition = null
