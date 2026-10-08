class_name Run
extends Node3D
## One Descent on screen (14 §5 run.tscn): owns the persistent Player and the HUD, and per
## depth generates the level on a worker thread (Seeds.for_depth inside LevelGenerator),
## builds level.tscn, prepares it (RunLevelSetup: exit, breaker, pickups), re-parents the
## player at the arrival point, binds the HUD and announces EventBus.level_entered.
## Transitions (05 §4): the proper exit (entering tween, the Landing cabin while the next
## level builds), the drop (the noclip floor commit, black and grain, a random valid cell),
## and the dissolve (11 §3 grid scatter, then GameState.end_run and the summary).
## The Director (M1.8) is per level: _begin_director() calls it when the level has one.
## The floor drop arrives as `floor_drop_committed()` on the Player or its NoclipTargeting
## (M1.4, built in parallel); the run connects to whichever has it, by name.

signal phase_changed(phase: StringName)
## After arrival, once level_entered has been emitted.
signal level_ready(depth: int)

const PHASE_LOADING := &"loading"
const PHASE_PLAYING := &"playing"
const PHASE_ENTERING := &"entering"
const PHASE_LANDING := &"landing"
const PHASE_DROPPING := &"dropping"
const PHASE_DISSOLVING := &"dissolving"
const PHASE_ENDED := &"ended"

const LEVEL_SCENE := "res://scenes/level.tscn"
const LANDING_SCENE := "res://scenes/landing.tscn"
const SUMMARY_SCENE := "res://scenes/summary.tscn"
const DROP_SIGNAL := &"floor_drop_committed"
const LANDING_SOURCE := &"landing"
const EXIT_FOV_KEY := &"exit"
## The cabin hangs far below the level origin so the level can build while it is shown.
const LANDING_OFFSET := Vector3(0.0, -400.0, 0.0)

@onready var player: Player = %Player
@onready var hud: Hud = %Hud
@onready var levels: Node3D = %Levels
@onready var dissolve_grid: DissolveGrid = %DissolveGrid

var phase: StringName = PHASE_LOADING
var level: Level
var data: LevelData
var exit: Exit
var breaker: Breaker
var landing: Landing
## The stratum the run's order names for this depth (05 §2); `data.stratum` is the one built.
var stratum: StringName = &""
## Tests shorten these; gameplay never changes them.
var landing_time: float = Tuning.LANDING_TIME
var drop_fall_time: float = Tuning.DROP_FALL_TIME
var dissolve_time: float = Tuning.COHERENCE_DISSOLVE_TIME
var capture_mouse: bool = true
## Last arrival kind (&"start", &"proper", &"drop").
var arrival: StringName = &""
## Tests and benches only: extra LevelGenerator options merged over the run's (e.g. `lock`).
var generation_overrides: Dictionary = {}

var _task: int = -1
var _generated: LevelData
var _prepared: bool = false
var _loading: bool = false


static func new_seed() -> int:
	# The run seed itself is the one value not derived from another seed (05 §8 Descent).
	return absi(hash("%d:%d" % [Time.get_unix_time_from_system() * 1000.0, Time.get_ticks_usec()]))


func _ready() -> void:
	if GameState.run == null or not GameState.is_run_active():
		GameState.start_run(Tuning.MODE_DESCENT, &"faller", new_seed())
	var kit := DataRegistry.loadout(GameState.run.loadout)
	player.reset_for_run(GameState.run.coherence)
	player.inventory.reset(kit.start_items if kit != null else {})
	# No body until the first level stands under it (and no contact, 06 readings).
	player.state_machine.transition_to(PlayerStateMachine.LANDING)
	hud.bind_player(player)
	hud.bind_inventory(player.inventory)
	player.dissolved.connect(_on_dissolved)
	EventBus.breaker_thrown.connect(_on_breaker_thrown)
	# M2.11: the pause menu (04 §7) opens on the `pause` action through Clock.set_menu_pause.
	add_child(PauseMenu.create(self))
	_connect_drop_signal.call_deferred()
	_start.call_deferred()


func _exit_tree() -> void:
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_phase(p: StringName) -> void:
	phase = p
	phase_changed.emit(p)


func _start() -> void:
	_begin_generation()
	await _load_level()
	_arrive(Tuning.RUN_ARRIVE_START)


## Connects the noclip floor commit by name: the Player's or the NoclipTargeting's signal.
func _connect_drop_signal() -> void:
	for src: Object in [player, player.noclip_targeting]:
		if src != null and src.has_signal(DROP_SIGNAL) and not src.is_connected(DROP_SIGNAL, commit_drop):
			src.connect(DROP_SIGNAL, commit_drop)


# --- level lifecycle --------------------------------------------------------------------------

## Starts generating the current depth on a worker thread (07 §1: data only).
func _begin_generation() -> void:
	var depth := GameState.run.depth
	stratum = GameState.stratum_for(depth)
	var build := stratum
	if not LevelGenerator.supports(build):
		# M1: only the Halls grammar exists; later strata generate as Halls until theirs land.
		push_warning("Run: no grammar for %s yet; depth %d generates as %s" % [stratum, depth, Tuning.STRATUM_DEPTH1])
		build = Tuning.STRATUM_DEPTH1
	var run_seed := GameState.run.run_seed
	var first := not GameState.meta.first_descent_done
	var cycle := 1 + (depth - 1) / Tuning.RUN_CYCLE_LENGTH
	var options := {
		&"item_pool": RunLevelSetup.item_pool(GameState.meta, GameState.run.mode == Tuning.MODE_DAILY),
		# M2.9: Variant B once unlock #4 (Fuse) is earned (05 §6); Daily ignores unlocks (05 §8).
		&"fuse_unlocked": fuse_unlocked(GameState.meta, GameState.run.mode == Tuning.MODE_DAILY),
		&"endless": GameState.run.mode == Tuning.MODE_ENDLESS,
	}
	options.merge(generation_overrides, true)
	_generated = null
	_prepared = false
	_task = WorkerThreadPool.add_task(func() -> void:
		_generated = LevelGenerator.generate(build, depth, run_seed, first, cycle, options), false, "LevelGenerator")


## 07 §6 Variant B: Powered exits may need a fuse once the Fuse unlock is earned (or always in
## Daily Descent, which ignores unlock state like the item pool does).
static func fuse_unlocked(meta: MetaState, daily: bool = false) -> bool:
	return daily or (meta != null and meta.is_unlocked(&"fuse"))


## Waits for the generation, builds the level, prepares it once walkable. Sets _prepared.
func _load_level() -> void:
	_loading = true
	while _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
		await get_tree().process_frame
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	data = _generated
	if data == null:
		push_error("Run: level generation failed at depth %d" % GameState.run.depth)
		_loading = false
		return
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	level.name = "Level%d" % GameState.run.depth
	levels.add_child(level)
	level.begin(data)
	if not level.is_walkable_now():
		await level.geometry_ready
	var setup := RunLevelSetup.prepare(level, data)
	exit = setup[&"exit"]
	breaker = setup[&"breaker"]
	if exit != null:
		exit.entering.connect(_on_exit_entering)
	_prepared = true
	_loading = false


## Frees the current level; the player moves to `holder` (the run or the cabin) first.
func _free_level(holder: Node3D) -> void:
	if level == null:
		return
	level.detach_player(player)
	if player.get_parent() != holder:
		player.reparent(holder, true)
	level.queue_free()
	level = null
	exit = null
	breaker = null


## 14 §5: the player at the arrival point, HUD bound, level_entered, the Director.
func _arrive(kind: StringName) -> void:
	if level == null:
		return
	arrival = kind
	if player.get_parent() != level:
		player.reparent(level, false)
	level.attach_player(player, player.rig.camera)
	if kind == Tuning.RUN_ARRIVE_DROP:
		player.global_transform = drop_transform()
	player.velocity = Vector3.ZERO
	player.rig.camera.make_current()
	AudioManager.set_listener(player.rig.camera)
	if not player.state_machine.transition_to(PlayerStateMachine.IDLE):
		player.state_machine.reset()
	if kind == Tuning.RUN_ARRIVE_PROPER:
		# 05 §4: COHERENCE +20, applied on arrival with the gain pulse (the Player's).
		player.apply_coherence(Tuning.COHERENCE_GAIN_PROPER_EXIT, LANDING_SOURCE)
	elif kind == Tuning.RUN_ARRIVE_DROP:
		# 11 §3 Arrival (drop): black and grain to the world, sub settle, 0.3 trauma.
		CoherenceRenderer.pulse(&"drop")
		AudioManager.play_2d(&"drop_arrival")
		player.rig.add_trauma(Tuning.FEEDBACK_ARRIVAL_DROP_TRAUMA)
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_phase(PHASE_PLAYING)
	if exit != null:
		# 07 §6 Cycled: the schedule runs from the player's arrival, not from the build.
		exit.start_cycle()
	GameState.run.stratum = data.stratum
	EventBus.level_entered.emit(GameState.run.depth, data.stratum, kind)
	_begin_director(level, kind)
	level_ready.emit(GameState.run.depth)


## M1.8 hook: the per-level Director, when the level carries one (a node named Director or
## in group `director`), gets begin(level, player, arrival) with as many arguments as it takes.
func _begin_director(lvl: Level, kind: StringName) -> void:
	var d: Node = lvl.find_child("Director", true, false)
	if d == null:
		for n in get_tree().get_nodes_in_group(&"director"):
			if lvl.is_ancestor_of(n):
				d = n
				break
	if d == null:
		# M1.8: the Director is per level (14 §3); the run gives each level its own.
		d = Director.new()
		lvl.add_child(d)
	if not d.has_method(&"begin"):
		return
	var args: Array = [lvl, player, kind]
	d.callv(&"begin", args.slice(0, d.get_method_argument_count(&"begin")))


## 05 §4: a random valid cell of the new level, facing open floor.
func drop_transform() -> Transform3D:
	var errs: Array[Vector3] = []
	for e in get_tree().get_nodes_in_group(&"errors"):
		if e is Node3D and level.is_ancestor_of(e):
			errs.append((e as Node3D).global_position)
	var rng := Seeds.rng(Seeds.derive(data.level_seed, Tuning.SEED_LABEL_DROP))
	var c := RunLevelSetup.pick_drop_cell(data, rng, errs)
	if c == LevelData.NO_CELL:
		return level.spawn_transform()
	var d := RunLevelSetup.open_dir(data.grid, c)
	return Transform3D(Basis(Vector3.UP, LevelData.yaw_facing(maxi(d, 0))), data.grid.world_of(c))


func _process(_delta: float) -> void:
	if landing != null and is_instance_valid(landing):
		landing.level_walkable = _prepared
		landing.level_built = _prepared and level != null and level.is_ready()


# --- proper exit and the Landing (05 §4) --------------------------------------------------

func _on_exit_entering(p: Node3D) -> void:
	if phase != PHASE_PLAYING or p != player:
		return
	_set_phase(PHASE_ENTERING)
	exit.accepting = false
	if not player.state_machine.transition_to(PlayerStateMachine.LANDING):
		player.state_machine.reset()
		player.state_machine.transition_to(PlayerStateMachine.LANDING)
	# 11 §3 Enter exit: 0.6 s entering tween into the car, FOV −3°.
	player.rig.fov_hold(Tuning.FEEDBACK_ENTER_EXIT_FOV_DEG, Tuning.FEEDBACK_FOV_TWEEN_MIN_MS, EXIT_FOV_KEY)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(player, ^"global_position", exit.entry_transform().origin, Tuning.EXIT_ENTER_TWEEN_TIME)
	await tw.finished
	GameState.run.coherence = player.coherence
	if RunLevelSetup.ends_descent(exit.exit_kind, GameState.run.mode):
		_cross_threshold()
		return
	GameState.descend(true)
	_begin_generation()
	await _transition(&"out")
	_open_landing()
	await _transition(&"in")
	await landing.finished
	player.rig.add_trauma(Tuning.FEEDBACK_LANDING_TRAUMA)
	await _transition(&"out")
	_arrive(Tuning.RUN_ARRIVE_PROPER)
	landing.queue_free()
	landing = null
	await _transition(&"in")


func _open_landing() -> void:
	landing = (load(LANDING_SCENE) as PackedScene).instantiate() as Landing
	landing.landing_time = landing_time
	add_child(landing)
	landing.position = LANDING_OFFSET
	_free_level(landing)
	player.global_transform = landing.player_transform()
	player.rig.fov_hold(0.0, 0.0, EXIT_FOV_KEY)
	var depth := GameState.run.depth
	var rng := Seeds.rng(Seeds.derive(GameState.run.run_seed, "%s:%d" % [Tuning.SEED_LABEL_LANDING, depth]))
	var pool := RunLevelSetup.item_pool(GameState.meta, GameState.run.mode == Tuning.MODE_DAILY)
	var choices := RunLevelSetup.landing_choices(pool, player.inventory.can_accept, player.inventory.count_of, rng)
	# 05 §10: CHOOSE ONE the first time a player reaches depth 2 (this run's count is 1).
	var counts: Dictionary = GameState.meta.stats.get("depth_reached_counts", {})
	var hint := depth == 2 and int(counts.get("2", 0)) <= 1
	landing.choice_made.connect(_on_landing_choice)
	landing.begin(player, choices, hint)
	player.rig.add_trauma(Tuning.FEEDBACK_LANDING_TRAUMA)
	_set_phase(PHASE_LANDING)
	_load_level()


func _on_landing_choice(kind: StringName) -> void:
	var d := DataRegistry.item(kind)
	player.inventory.add(kind, d.pickup_count if d != null else 1)


## The glitch cut (04 §4) when main.tscn provides one; nothing otherwise.
func _transition(p: StringName) -> void:
	var t: Object = SceneRouter.transition
	if t != null and t.has_method(&"play"):
		await t.call(&"play", p)


# --- drop (05 §4) ------------------------------------------------------------------------------

## The noclip floor commit (06 §8): Player.floor_drop_committed() (no args); the player is
## already falling in Dropping for 1.2 s. Public so tests and benches can drive it.
func commit_drop() -> void:
	if phase != PHASE_PLAYING:
		return
	_set_phase(PHASE_DROPPING)
	if exit != null:
		exit.accepting = false
	if not player.state_machine.is_in(PlayerStateMachine.DROPPING):
		player.state_machine.transition_to(PlayerStateMachine.DROPPING)
	GameState.run.coherence = player.coherence
	# The noclip commit already counted the drop (GameState.record_drop); the run descends.
	GameState.descend(false)
	_begin_generation()
	await get_tree().process_frame
	# The commit fires the first `drop` pulse (M1.4); fire it here if it did not.
	if CoherenceRenderer.pulse_age(&"drop") > drop_fall_time:
		CoherenceRenderer.pulse(&"drop")
	await get_tree().create_timer(drop_fall_time).timeout
	_free_level(self)
	_load_level()
	var waited := 0.0
	while not _prepared or (not level.is_ready() and waited < Tuning.LANDING_MAX_EXTRA_WAIT):
		await get_tree().process_frame
		if _prepared:
			waited += get_process_delta_time()
	_arrive(Tuning.RUN_ARRIVE_DROP)


# --- breaker -----------------------------------------------------------------------------------

func _on_breaker_thrown(pos: Vector3) -> void:
	if level == null or breaker == null or phase != PHASE_PLAYING:
		return
	RunLevelSetup.run_power_wave(level, data, exit, pos)
	# 11 §3 Breaker thrown by player: 0.3 trauma.
	player.rig.add_trauma(Tuning.FEEDBACK_BREAKER_TRAUMA)


## 01 §8 the win (M2.3 path; M2.15 replaces the summary jump with the ending scene): the run
## ends with cause `threshold`.
func _cross_threshold() -> void:
	_set_phase(PHASE_ENDED)
	GameState.end_run(GameState.WIN_CAUSE)
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneRouter.change_to(SUMMARY_SCENE)


# --- dissolve (06 §9, 11 §3) ---------------------------------------------------------------------

func _on_dissolved(cause: StringName) -> void:
	if phase == PHASE_DISSOLVING or phase == PHASE_ENDED:
		return
	_set_phase(PHASE_DISSOLVING)
	if exit != null:
		exit.accepting = false
	dissolve_grid.duration = dissolve_time
	dissolve_grid.play()
	await Clock.wall_timer(dissolve_time).timeout
	GameState.run.coherence = player.coherence
	GameState.end_run(cause)
	_set_phase(PHASE_ENDED)
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneRouter.change_to(SUMMARY_SCENE)
