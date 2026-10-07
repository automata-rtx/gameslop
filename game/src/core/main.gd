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
	if args.wants_direct_level():
		# TODO(M1.12): launch straight into a generated level from the flags (14 §9).
		push_warning("--seed/--depth/--stratum: direct level launch arrives with M1.12")
	# TODO(M1.9): SceneRouter.change_to("res://scenes/title.tscn") once the title exists;
	# until then %Content holds the placeholder title.


func _run_smoke() -> void:
	_smoke_generate_depth_1()
	# Process time, not wall time: the smoke test measures that frames keep flowing.
	await get_tree().create_timer(SMOKE_WAIT_S).timeout
	get_tree().quit(0)


## TODO(M1.9): generate and build depth 1 (Halls, the --seed or a fixed seed) and
## wait for LevelBuilder.built before the smoke timer starts.
func _smoke_generate_depth_1() -> void:
	pass
