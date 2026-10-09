extends TestCase
## R15 (M2.17 review): S4 the Cycle 2 Substrate drain (06 §9), S8 DISTANCE WALKED (13 §2),
## S10 auto-sprint after the stamina lockout (12 §7). Run-level checks (B1, S1, S4's cause on
## run_ended) are in tests/sim/test_r15_run_fixes.gd.

const DT := 1.0 / 60.0

var _world: Node3D
var _p: Player
var _meta: MetaState
var _auto: Variant


func before_all() -> void:
	_meta = GameState.meta
	_auto = SettingsManager.get_value(PlayerLocomotion.SETTING_AUTO_SPRINT)


func after_all() -> void:
	GameState.meta = _meta
	SettingsManager.set_value(PlayerLocomotion.SETTING_AUTO_SPRINT, _auto if _auto is bool else false)


func before_each() -> void:
	GameState.meta = MetaState.new()
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	if GameState.is_run_active():
		GameState.end_run(&"abandoned")
	_world.free()


# --- S4 -------------------------------------------------------------------------------------

func test_substrate_drains_only_from_cycle_2() -> void:
	var c := _p.coherence
	assert_approx(RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 6, 1.0), 0.0, 0.0001, "Cycle 1: none")
	assert_approx(RunLevelSetup.substrate_drain(_p, &"halls", 7, 1.0), 0.0, 0.0001, "Cycle 2 Halls: none")
	assert_approx(_p.coherence, c, 0.0001)
	for i in 60:
		RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 12, DT)
	assert_approx(_p.coherence, c - Tuning.COHERENCE_LOSS_CYCLE2_SUBSTRATE_PER_S, 0.001, "0.2 per second")
	RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 18, 1.0)
	assert_approx(_p.coherence, c - 2.0 * Tuning.COHERENCE_LOSS_CYCLE2_SUBSTRATE_PER_S, 0.001, "Cycle 3 too")


func test_substrate_drain_respects_no_loss_states_and_names_its_cause() -> void:
	_p.state_machine.transition_to(PlayerStateMachine.LANDING)
	var c := _p.coherence
	RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 12, 1.0)
	assert_approx(_p.coherence, c, 0.0001, "no loss in the Landing")
	_p.state_machine.reset()
	_p.apply_coherence(-(_p.coherence - 0.1), &"test")
	var causes := []
	_p.dissolved.connect(func(cause: StringName) -> void: causes.append(cause))
	RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 12, 1.0)
	assert_eq(causes, [Player.CAUSE_SUBSTRATE], "DISSOLVED BY THE SUBSTRATE")


## Float residue: 0.3 drained in 1/60 s steps must reach 0 and dissolve, not hang at 1e-6.
func test_slow_drain_reaches_zero() -> void:
	_p.apply_coherence(-(_p.coherence - 0.3), &"test")
	var causes := []
	_p.dissolved.connect(func(cause: StringName) -> void: causes.append(cause))
	for i in 120:
		RunLevelSetup.substrate_drain(_p, Tuning.STRATUM_SUBSTRATE, 12, DT)
	assert_eq(_p.coherence, 0.0)
	assert_eq(causes, [Player.CAUSE_SUBSTRATE])


# --- S8 -------------------------------------------------------------------------------------

func test_walking_counts_distance() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 15)
	assert_approx(GameState.run.distance_m, 0.0)
	var from := _p.global_position
	Input.action_press(&"move_forward")
	await await_physics_frames(60)
	Input.action_release(&"move_forward")
	await await_physics_frames(20)
	var walked := Vector2(_p.global_position.x - from.x, _p.global_position.z - from.z).length()
	assert_gt(walked, 1.0, "the player walked")
	assert_approx(GameState.run.distance_m, walked, 0.05, "the straight walk is the distance")
	var before := GameState.run.distance_m
	_p.state_machine.transition_to(PlayerStateMachine.LANDING)
	_p.global_position += Vector3(5, 0, 0)
	await await_physics_frames(5)
	assert_approx(GameState.run.distance_m, before, 0.0001, "a move without agency is not walked")
	_p.state_machine.reset()
	GameState.end_run(&"abandoned")
	assert_approx(float(GameState.meta.stats.get("distance_walked_m", 0.0)), before, 0.01, "the statistic is saved")


func test_no_run_no_distance() -> void:
	Input.action_press(&"move_forward")
	await await_physics_frames(20)
	Input.action_release(&"move_forward")
	assert_false(GameState.is_run_active())


# --- S10 ------------------------------------------------------------------------------------

func _exhaust_and_wait_lockout() -> void:
	_p.locomotion.stamina.value = 0.5
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(10)
	assert_true(_p.locomotion.stamina.is_locked_out(), "exhausted")
	var frames := int(ceil(Tuning.STAMINA_LOCKOUT_TIME / DT)) + 10
	await await_physics_frames(frames)
	assert_false(_p.locomotion.stamina.is_locked_out(), "lockout over")


func test_auto_sprint_off_needs_a_new_press() -> void:
	SettingsManager.set_value(PlayerLocomotion.SETTING_AUTO_SPRINT, false)
	await _exhaust_and_wait_lockout()
	assert_true(_p.locomotion.stamina.can_sprint())
	assert_false(_p.locomotion.sprinting, "off: the held key does not resume the sprint")
	Input.action_release(&"sprint")
	await await_physics_frames(2)
	Input.action_press(&"sprint")
	await await_physics_frames(5)
	assert_true(_p.locomotion.sprinting, "a new press sprints")


func test_auto_sprint_on_resumes_a_held_sprint() -> void:
	SettingsManager.set_value(PlayerLocomotion.SETTING_AUTO_SPRINT, true)
	await _exhaust_and_wait_lockout()
	assert_true(_p.locomotion.sprinting, "on: the held key resumes the sprint")
	assert_eq(_p.state_machine.state, PlayerStateMachine.SPRINT)
