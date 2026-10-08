extends TestCase
## R13: colliders the grid does not know about. For SEEDS seeds per stratum the level is
## built (geometry, props, hide spots, then the run's exit, breaker and pickups), and on
## the live physics space (PropClearance):
## - the player's capsule fits at every walkable cell's centre;
## - it travels centre to centre through every open edge between walkable cells;
## - no prop, hide spot, exit or interactable collider intrudes on a walkable cell's
##   cross (LEVEL_PROP_CLEARANCE);
## - every hide spot lets the player out on a walkable cell with room to stand.
## NOCLIP_CLEARANCE_SEEDS raises the seed count for an audit run.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const STRATA: Dictionary = {&"halls": 1, &"pools": 2, &"garage": 3, &"offices": 4, &"server": 5, &"substrate": 6}
const SEEDS := 2

var _problems: Dictionary = {}
var _cells: Dictionary = {}


func before_all() -> void:
	var n := int(OS.get_environment("NOCLIP_CLEARANCE_SEEDS")) if OS.has_environment("NOCLIP_CLEARANCE_SEEDS") else SEEDS
	for stratum: StringName in STRATA:
		var found := {&"centres": PackedStringArray(), &"lanes": PackedStringArray(), &"crosses": PackedStringArray(),
			&"hide_exits": PackedStringArray()}
		var cells := 0
		for k in n:
			var seed := 101 + k * 7
			var data := LevelGenerator.generate(stratum, STRATA[stratum], seed, false, 1, _options(stratum, k))
			var level := LEVEL_SCENE.instantiate() as Level
			add_child(level)
			level.begin(data)
			var frames := 0
			while not level.is_ready() and frames < MAX_FRAMES:
				await get_tree().process_frame
				frames += 1
			RunLevelSetup.prepare(level, data)
			await await_physics_frames(3)
			var space := level.get_world_3d().direct_space_state
			var tag := "seed %d %s: " % [seed, data.exit_lock]
			var doors := PropClearance.door_rids(level)
			for line in PropClearance.centres(space, data.grid, doors):
				found[&"centres"].append(tag + line)
			for line in PropClearance.lanes(space, data, doors):
				found[&"lanes"].append(tag + line)
			for line in PropClearance.crosses(level, data):
				found[&"crosses"].append(tag + line)
			for line in PropClearance.hide_exits(space, level, data.grid, doors):
				found[&"hide_exits"].append(tag + line)
			cells += data.grid.walkable_count()
			level.queue_free()
			await get_tree().process_frame
		_problems[stratum] = found
		_cells[stratum] = cells
		print("  # %s: %d walkable cells over %d seeds; %d centre, %d lane, %d cross, %d hide exit problems"
			% [stratum, cells, n, found[&"centres"].size(), found[&"lanes"].size(), found[&"crosses"].size(),
			found[&"hide_exits"].size()])
		for key: StringName in found:
			for i in mini(found[key].size(), 40):
				print("  #   %s" % found[key][i])


func after_all() -> void:
	PlayerFixture.release_all()


## Cycles the lock (Powered, Keyed, Open) so breakers and card readers get built; the
## Substrate has no lock.
func _options(stratum: StringName, k: int) -> Dictionary:
	if stratum == &"substrate":
		return {}
	var locks: Array[StringName] = [Tuning.LOCK_POWERED, Tuning.LOCK_KEYED, Tuning.LOCK_OPEN]
	return {&"lock": locks[k % locks.size()]}


func test_capsule_fits_every_walkable_centre() -> void:
	for stratum: StringName in _problems:
		assert_gt(_cells[stratum], 0, "%s built" % stratum)
		assert_eq(_problems[stratum][&"centres"].size(), 0, "%s: %s" % [stratum, _problems[stratum][&"centres"]])


func test_capsule_crosses_every_open_edge() -> void:
	for stratum: StringName in _problems:
		assert_eq(_problems[stratum][&"lanes"].size(), 0, "%s: %s" % [stratum, _problems[stratum][&"lanes"]])


func test_no_prop_collider_on_a_walkable_cross() -> void:
	for stratum: StringName in _problems:
		assert_eq(_problems[stratum][&"crosses"].size(), 0, "%s: %s" % [stratum, _problems[stratum][&"crosses"]])


func test_hide_spots_let_the_player_out_on_free_floor() -> void:
	for stratum: StringName in _problems:
		assert_eq(_problems[stratum][&"hide_exits"].size(), 0, "%s: %s" % [stratum, _problems[stratum][&"hide_exits"]])
