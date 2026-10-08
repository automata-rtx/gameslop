extends TestCase
## M1.8 simulated playtest in the gate: one seed of depth 1 with the Director and its
## errors active; the bot reaches the exit, the Director left Calm, nobody dissolved, and
## the contact rules held (05 §9 rules 4 and 5: at most one contact per 3 s, so no more
## contacts than the time allows).

const SEED := 1
const TIME_SCALE := 4.0

var _host: Node
var _prev_host: Node
var _prev_transition: Object


func before_each() -> void:
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "SimTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	Engine.time_scale = 1.0
	await await_frames(3)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()


func test_bot_reaches_the_exit_of_depth_1() -> void:
	Engine.time_scale = TIME_SCALE
	var bot := SimBot.new()
	bot.tree = get_tree()
	bot.host = _host
	bot.max_seconds = 400.0
	var r: Dictionary = await bot.play(SEED)
	Engine.time_scale = 1.0
	print("  # sim-run %s" % JSON.stringify(r))
	assert_false(r.has(&"error"), str(r.get(&"error", "")))
	assert_true(bool(r.get(&"reached", false)), "the bot walked into the exit")
	assert_false(bool(r.get(&"dissolved", true)), "nobody dissolved")
	var phases: Array = r.get(&"phases", [])
	assert_true(phases.size() > 0 and phases[0] == DirectorPacing.CALM, "Calm first")
	assert_true(int(r.get(&"telemetry_rows", 0)) > 10, "telemetry rows")
	var t := float(r.get(&"time_s", 0.0))
	assert_true(int(r.get(&"contacts", 0)) <= int(t / Tuning.CONTACT_EXCLUSIVITY_TIME) + 1, "contact exclusivity")
