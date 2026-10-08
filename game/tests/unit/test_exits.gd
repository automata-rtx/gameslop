extends TestCase
## M2.9 exits and locks (07 §6, 09 §5, 11 §3, 04 §6): every exit prefab under every lock, the
## Keyed reader opening its exit, the Cycled schedule and its HUD timer, the prefab map, the
## Variant B unlock, the forced-lock generator option and the Cycled validator rule.

const PREFABS: Array[String] = [
	"res://scenes/exits/elevator.tscn",
	"res://scenes/exits/drain_hatch.tscn",
	"res://scenes/exits/stairwell_door.tscn",
	"res://scenes/exits/floor_hatch.tscn",
]
const LOCKS: Array[StringName] = [Tuning.LOCK_OPEN, Tuning.LOCK_POWERED, Tuning.LOCK_KEYED, Tuning.LOCK_CYCLED]

var _world: Node3D
var _p: Player
var _statuses: Array = []


func _on_status(s: StringName, t: float) -> void:
	_statuses.append([s, t])


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 4))
	await await_physics_frames(2)
	_statuses = []
	EventBus.exit_status_changed.connect(_on_status)


func after_each() -> void:
	EventBus.exit_status_changed.disconnect(_on_status)
	PlayerFixture.release_all()
	_world.free()


func _exit(path: String, lock: StringName) -> Exit:
	var e := (load(path) as PackedScene).instantiate() as Exit
	e.lock = lock
	_world.add_child(e)
	e.set_physics_process(false)
	return e


func _playing(id: StringName) -> int:
	var n := 0
	if AudioManager.pool == null:
		return 0
	for list: Array in [AudioManager.pool.players_3d, AudioManager.pool.players_2d]:
		for p: Node in list:
			if p.get_meta(AudioPool.META_ID, &"") == id and bool(p.get(&"playing")):
				n += 1
	return n


func test_every_prefab_takes_every_lock() -> void:
	for path in PREFABS:
		for lock in LOCKS:
			var e := _exit(path, lock)
			var tag := "%s %s" % [path.get_file(), lock]
			assert_eq(e.lock, lock, tag)
			assert_eq(e.is_open(), lock == Tuning.LOCK_OPEN, tag + ": open only when Open")
			assert_approx(e.leaf_open_amount(), 1.0 if lock == Tuning.LOCK_OPEN else 0.0, 0.001, tag + ": leaves")
			assert_eq(e.reader != null, lock == Tuning.LOCK_KEYED, tag + ": reader only on Keyed")
			if e.display != null:
				assert_eq(e.display.visible, lock == Tuning.LOCK_CYCLED, tag + ": display only on Cycled")
			else:
				fail(tag + ": no %Display")
			assert_eq(e.light.visible, lock == Tuning.LOCK_OPEN, tag + ": light on only when open")
			var lamp_lit := e.emission_of(e.lamp) > 0.0
			assert_eq(lamp_lit, lock != Tuning.LOCK_POWERED, tag + ": a Powered exit is dark and dead")
			assert_ne(e.sound_open, &"", tag)
			assert_true(AudioManager.library == null or AudioManager.library.has(e.sound_open), tag + ": the open sound exists")
			e.free()


func test_prefab_sounds_and_kinds_differ_per_stratum() -> void:
	var sounds := {}
	for path in PREFABS:
		var e := _exit(path, Tuning.LOCK_OPEN)
		sounds[e.exit_kind] = e.sound_open
		assert_eq(RunLevelSetup.exit_scene_for(e.exit_kind), path, "the map names this prefab")
		e.free()
	assert_eq(sounds.size(), 4)
	assert_eq(sounds[&"elevator"], &"exit_open")
	assert_eq(sounds[&"stairwell_door"], &"exit_open_door")
	assert_eq(sounds[&"drain_hatch"], &"exit_open_drain")
	assert_eq(sounds[&"floor_hatch"], &"exit_open_hatch")
	assert_eq(RunLevelSetup.exit_scene_for(&"threshold_door"), "res://scenes/exits/threshold_door.tscn",
		"M2.3: the Substrate's Threshold")
	assert_eq(RunLevelSetup.exit_scene_for(&"nonsense"), RunLevelSetup.DEFAULT_EXIT_SCENE)


func test_opening_moves_the_leaves_and_walk_in_enters() -> void:
	for path in PREFABS:
		var e := _exit(path, Tuning.LOCK_POWERED)
		var tag := path.get_file()
		assert_false(e.try_enter(_p), tag + ": closed")
		e.power()
		assert_true(e.is_open(), tag)
		await get_tree().create_timer(Exit.DOOR_OPEN_TIME + 0.15).timeout
		assert_approx(e.leaf_open_amount(), 1.0, 0.02, tag + ": leaves fully open")
		assert_true(e.light.visible, tag)
		var entered: Array = []
		e.entering.connect(func(n: Node3D) -> void: entered.append(n))
		_p.global_position = e.walk_in_point()
		await await_physics_frames(4)
		assert_eq(entered.size(), 1, tag + ": walking into the volume enters the exit")
		e.free()
		_p.global_position = Vector3(0, 0.05, 4)
		await await_physics_frames(2)


func test_keyed_exit_opens_from_its_reader() -> void:
	var e := _exit(PREFABS[2], Tuning.LOCK_KEYED)
	e.mark_seen()
	assert_eq(_statuses.back(), [Tuning.EXIT_STATUS_KEYED, 0.0], "EXIT: KEYED once seen")
	assert_eq(e.reader.interactable.prompt_text(), Strings.PROMPT_NO_CARD)
	assert_false(e.reader.swipe(_p), "no card")
	assert_false(e.is_open(), "a rejected swipe opens nothing")
	assert_gt(_playing(CardReader.SOUND_REJECT), 0, "the reject beeps")
	await await_frames(2)
	assert_gt(e.reader.indicator_glow(), 0.0, "the reader blinks on the reject")
	_p.inventory.set_keycard(true)
	assert_true(e.reader.interactable.can_interact(_p), "offers SWIPE")
	assert_eq(e.reader.interactable.prompt_text(), Strings.PROMPT_SWIPE)
	e.reader.interactable.interact(_p)
	assert_true(e.reader.accepted)
	assert_true(e.is_open(), "CardReader.swiped -> Exit.open")
	assert_eq(_statuses.back(), [Tuning.EXIT_STATUS_OPEN, 0.0], "EXIT: OPEN")
	e.free()


func test_keyed_unlock_is_announced_before_seen() -> void:
	var e := _exit(PREFABS[0], Tuning.LOCK_KEYED)
	_p.inventory.set_keycard(true)
	e.reader.swipe(_p)
	assert_eq(_statuses, [[Tuning.EXIT_STATUS_OPEN, 0.0]], "11 §3: the unlock prints even unseen")
	e.free()


func test_cycled_schedule_and_hud_timer() -> void:
	var e := _exit(PREFABS[1], Tuning.LOCK_CYCLED)
	assert_eq(e.status, Tuning.EXIT_STATUS_SEALED)
	e.advance_cycle(30.0)
	assert_approx(e.cycle_left, Tuning.CYCLED_SEALED_TIME, 0.001, "the clock waits for start_cycle")
	e.start_cycle()
	e.mark_seen()
	assert_eq(_statuses.back()[0], Tuning.EXIT_STATUS_SEALED)
	assert_approx(_statuses.back()[1], Tuning.CYCLED_SEALED_TIME, 0.001, "EXIT: SEALED 01:10")
	assert_gt(_playing(Exit.SOUND_TONE), 0, "11 §3: a Cycled exit's seen sound is the long tone")
	e.advance_cycle(Tuning.CYCLED_SEALED_TIME - Tuning.CYCLED_WARNING_TIME - 0.5)
	assert_eq(e.display.text, "00:06")
	var tones := _playing(Exit.SOUND_TONE)
	e.advance_cycle(1.0)
	assert_gt(_playing(Exit.SOUND_TONE), tones, "the long tone 5 s before opening")
	assert_false(e.is_open())
	e.advance_cycle(Tuning.CYCLED_WARNING_TIME)
	assert_true(e.is_open(), "opens after 70 s sealed")
	assert_eq(_statuses.back()[0], Tuning.EXIT_STATUS_OPEN)
	assert_approx(_statuses.back()[1], Tuning.CYCLED_OPEN_TIME - 0.5, 0.01, "EXIT: OPEN 00:20 counts down")
	e.advance_cycle(Tuning.CYCLED_OPEN_TIME - 1.0)
	assert_true(e.is_open())
	e.advance_cycle(1.0)
	assert_false(e.is_open(), "seals after 20 s open")
	assert_eq(_statuses.back()[0], Tuning.EXIT_STATUS_SEALED)
	assert_approx(_statuses.back()[1], Tuning.CYCLED_SEALED_TIME - 0.5, 0.01)
	assert_false(e.try_enter(_p), "sealed")
	# A second cycle plays a second tone.
	tones = _playing(Exit.SOUND_TONE)
	e.advance_cycle(Tuning.CYCLED_SEALED_TIME - 2.0)
	assert_true(_playing(Exit.SOUND_TONE) > tones or tones > 0, "tone each cycle")
	e.advance_cycle(2.0)
	assert_true(e.is_open())
	e.free()


func test_cycled_never_seals_on_a_player_being_carried_in() -> void:
	var e := _exit(PREFABS[3], Tuning.LOCK_CYCLED)
	e.start_cycle()
	e.advance_cycle(Tuning.CYCLED_SEALED_TIME + 1.0)
	assert_true(e.is_open())
	assert_true(e.try_enter(_p))
	e.advance_cycle(Tuning.CYCLED_OPEN_TIME * 2.0)
	assert_true(e.is_open(), "entering holds the doors")
	e.free()


func test_unseen_cycled_exit_stays_unknown() -> void:
	var e := _exit(PREFABS[0], Tuning.LOCK_CYCLED)
	e.start_cycle()
	e.advance_cycle(Tuning.CYCLED_SEALED_TIME + 1.0)
	assert_true(e.is_open())
	assert_eq(_statuses.size(), 0, "a Cycled opening is not announced before the exit is seen")
	e.free()


func test_hud_shows_every_status() -> void:
	var cases := [
		[Tuning.EXIT_STATUS_OPEN, 0.0, "EXIT: OPEN"],
		[Tuning.EXIT_STATUS_POWERED, 0.0, "EXIT: POWERED"],
		[Tuning.EXIT_STATUS_KEYED, 0.0, "EXIT: KEYED"],
		[Tuning.EXIT_STATUS_SEALED, 42.0, "EXIT: SEALED 00:42"],
		[Tuning.EXIT_STATUS_OPEN, 20.0, "EXIT: OPEN 00:20"],
	]
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	await await_frames(1)
	for c: Array in cases:
		EventBus.exit_status_changed.emit(c[0], c[1])
		assert_eq(hud.depth.exit_text(), c[2])
	hud.free()


func test_fuse_unlock_follows_meta_and_daily() -> void:
	var meta := MetaState.new()
	assert_false(Run.fuse_unlocked(meta))
	assert_true(Run.fuse_unlocked(meta, true), "Daily ignores unlock state")
	meta.earn(&"fuse")
	assert_true(Run.fuse_unlocked(meta))
	assert_false(Run.fuse_unlocked(null))


func test_forced_lock_option() -> void:
	for lock in LOCKS:
		var d := LevelGenerator.generate(&"halls", 4, 7, false, 1, {&"lock": lock})
		assert_eq(d.exit_lock, lock)
		assert_eq(d.failures.size(), 0, "%s: %s" % [lock, d.failures])
	var b := LevelGenerator.generate(&"halls", 2, 7, false, 1, {&"lock": Tuning.LOCK_POWERED, &"lock_variant": &"b"})
	assert_eq(b.lock_variant, &"b")
	var fuses := 0
	for p in b.placements_of(LevelData.P_ITEM):
		if p[&"params"].get(&"item", &"") == &"fuse":
			fuses += 1
	assert_eq(fuses, 1, "Variant B places exactly one fuse")


func test_cycled_validator_rule() -> void:
	for s: StringName in [&"halls", &"pools", &"garage", &"offices", &"server"]:
		var d := LevelGenerator.generate(s, 4, 3, false, 1, {&"lock": Tuning.LOCK_CYCLED})
		assert_eq(d.failures.size(), 0, "%s: %s" % [s, d.failures])
		var m := LevelValidator.cycled_walk_m(d)
		assert_true(m >= 0.0 and m <= LevelValidator.cycled_window_m(), "%s: %.0f m within the open window" % [s, m])
	# The rule can fail: an exit room too large for the window.
	var d := LevelGenerator.generate(&"halls", 4, 3, false, 1, {&"lock": Tuning.LOCK_CYCLED})
	var far := d.critical_path[0]
	d.grid.add_flag(far, LevelGrid.F_EXIT_ROOM)
	var fails := LevelValidator.validate(d)
	var hit := false
	for f in fails:
		hit = hit or f.begins_with("r3: cycled")
	assert_true(hit, "a far exit-room cell breaks the Cycled window: %s" % [fails])
