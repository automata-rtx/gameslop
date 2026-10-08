extends Node
## Noclip verification frames (M1.4) in a built Halls level, with the HUD: charging at a
## passable wall, aiming at a refused wall (dashed preview, reason), and the commit frame
## mid-pass (world lines within 3 m). Run on the CPU renderer:
##   tools/ci/render.sh --path game --resolution 960x540 res://scenes/debug/noclip_shots.tscn -- --noclip-shots build/noclip
## The CPU renderer runs at a few fps, so each pose freezes the player's physics before the
## capture, and the commit pulse is re-fired every frame so its envelope stays at the peak.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const SETTLE := 12

var _direct: DirectLevel
var _dir: String = "build/noclip"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--noclip-shots")
	if i != -1 and i + 1 < args.size():
		_dir = args[i + 1]
	_direct = DirectLevel.new()
	_direct.capture_mouse = false
	add_child(_direct)
	_run.call_deferred()


func _run() -> void:
	await _direct.built
	var abs_dir := _dir if _dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var p := _direct.player
	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	hud.call(&"bind_player", p)
	var g := _direct.data.grid
	var space := p.get_world_3d().direct_space_state
	var good: Array = []
	var bad: Array = []
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c):
				continue
			for d in 4:
				var o := c + LevelGrid.DIRS[d]
				var a := _eval(space, g, c, d)
				if good.is_empty() and a[&"valid"] and g.in_bounds(o) and g.is_walkable(o) and g.wall(c, d) == LevelGrid.WALL:
					good = [c, d]
				if bad.is_empty() and not a[&"valid"] and a[&"distance"] < Tuning.NOCLIP_RANGE \
						and a[&"reason"] == Tuning.NOCLIP_REASON_NO_SPACE:
					bad = [c, d]
	print("noclip_shots: wall ", good, " refused ", bad)
	# 1. charging at a wall, about 60%.
	await _pose(p, good)
	Input.action_press(&"noclip")
	await _until(func() -> bool: return (p.noclip_targeting as NoclipTargeting).charge_fraction() >= 0.6)
	p.set_physics_process(false)
	await _frames(SETTLE)
	_save(abs_dir, "noclip_charge")
	Input.action_release(&"noclip")
	p.set_physics_process(true)
	await _frames(4)
	# 2. invalid: a wall onto a non-walkable cell.
	if not bad.is_empty():
		await _pose(p, bad)
		Input.action_press(&"noclip")
		await _until(func() -> bool: return CoherenceRenderer.noclip_invalid)
		p.set_physics_process(false)
		await _frames(SETTLE)
		_save(abs_dir, "noclip_invalid")
		Input.action_release(&"noclip")
		p.set_physics_process(true)
		await _frames(4)
	# 3. the commit frame, mid-pass.
	await _pose(p, good)
	Input.action_press(&"noclip")
	var nt := p.noclip_targeting as NoclipTargeting
	# Mid-pass: the sine in-out pass crosses the wall at half its time (NoclipMotion).
	await _until(func() -> bool: return nt.phase == NoclipTargeting.Phase.PASSING and nt.pass_time() >= NoclipMotion.PASS_TIME * 0.5)
	p.set_physics_process(false)
	nt.set_physics_process(false)
	for f in SETTLE:
		CoherenceRenderer.pulse(&"noclip_commit")
		await get_tree().process_frame
	_save(abs_dir, "noclip_commit")
	# The same frame with Reduce visual noise (grain and CA capped, no scanline), to tell
	# the post pulse's share of the lost lines from the world shader's.
	SettingsManager.set_value(CoherenceRenderer.SETTING_REDUCE_NOISE, true)
	for f in SETTLE:
		CoherenceRenderer.pulse(&"noclip_commit")
		await get_tree().process_frame
	_save(abs_dir, "noclip_commit_reduced_noise")
	SettingsManager.set_value(CoherenceRenderer.SETTING_REDUCE_NOISE, false)
	Input.action_release(&"noclip")
	get_tree().quit(0)


func _eval(space: PhysicsDirectSpaceState3D, g: LevelGrid, c: Vector2i, d: int) -> Dictionary:
	var base := g.world_of(c)
	var dv := LevelGrid.DIRS[d]
	return NoclipQuery.evaluate(space, base + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT, Vector3(dv.x, 0, dv.y),
			base, _direct.player.collision.shape, 100.0, false, [_direct.player.get_rid()])


## Stands the player 0.4 m back from the centre of `e[0]`, facing edge `e[1]`, slightly down.
func _pose(p: Player, e: Array) -> void:
	var g := _direct.data.grid
	var dv := LevelGrid.DIRS[int(e[1])]
	var fwd := Vector3(dv.x, 0, dv.y)
	p.global_position = g.world_of(e[0]) - fwd * 0.4 + Vector3.UP * 0.02
	p.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	p.rig.reset_pitch()
	p.rig.add_pitch(deg_to_rad(-6.0))
	p.flashlight.set_on(true, true)
	_direct.level.light_pool.reevaluate()
	await _frames(SETTLE)


func _until(cond: Callable) -> void:
	var guard := 0
	while not bool(cond.call()) and guard < 2000:
		guard += 1
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame


func _save(dir: String, name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	print("noclip_shots: %s (%s)" % [path, error_string(img.save_png(path))])
