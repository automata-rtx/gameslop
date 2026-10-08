extends TestCase
## The screenshot tour's planning (14 §9, 02 §13) on generated levels, headless: which strata
## it visits, the poses and the noclip wall it frames, the T1 limits; and tour_check.py's
## PNG decoder and T4 ordering through its self test. The frames themselves need a renderer
## (tools/ci/render.sh -- --tour).

const CHECK_SCRIPT := "res://../tools/ci/tour_check.py"


func test_the_tour_visits_every_stratum_with_a_grammar() -> void:
	var expected: Array[StringName] = []
	for s in CliArgs.STRATA:
		if LevelGenerator.supports(s):
			expected.append(s)
	assert_eq(ScreenshotTour.strata(), expected)
	assert_contains(ScreenshotTour.strata(), &"halls")


func test_t1_limit_is_shorter_in_the_dark_strata() -> void:
	assert_approx(ScreenshotTour.t1_limit(&"halls"), 12.0)
	assert_approx(ScreenshotTour.t1_limit(&"server"), 6.0)
	assert_approx(ScreenshotTour.t1_limit(&"substrate"), 6.0)


func test_plan_has_the_three_poses_the_t1_pose_and_a_noclip_wall() -> void:
	for s in ScreenshotTour.strata():
		var data := LevelGenerator.generate(s, ScreenshotTour.tour_depth(s), ScreenshotTour.SEED)
		var plan := ScreenshotTour.plan(data)
		var names: Array = []
		for p in plan[&"poses"]:
			if not ScreenshotTour.EXTRA_POSES.has(StringName(p[&"name"])):
				names.append(p[&"name"])
		assert_eq(names, ["spawn", "corridor", "exit_room", "corridor_long"], String(s))
		var view: Dictionary = plan[&"noclip"]
		assert_false(view.is_empty(), "%s has a wall between two walkable cells" % s)
		if view.is_empty():
			continue
		var ahead: Vector3 = (view[&"point"] as Vector3) - (view[&"from"] as Vector3)
		ahead.y = 0.0
		assert_approx(ahead.length(), 1.4, 0.05, "the wall is 1.4 m from the camera")
		assert_approx((view[&"normal"] as Vector3).dot(ahead.normalized()), -1.0, 0.001, "facing the camera")


## R11 #9: the tour frames a soft wall (02 §5) when the level has one, from inside the 2 m
## preview range, facing it.
## M2.3: the Substrate tours at depth 6 with its pocket, studio light and checker poses, and
## the dark strata are photographed with the flashlight on (02 §2 ruling).
func test_substrate_tour_poses_and_flashlight() -> void:
	assert_eq(ScreenshotTour.tour_depth(&"substrate"), 6)
	assert_eq(ScreenshotTour.tour_depth(&"halls"), 1)
	var data := LevelGenerator.generate(&"substrate", 6, ScreenshotTour.SEED)
	var names: Array = []
	for p in ScreenshotTour.plan(data)[&"poses"]:
		names.append(p[&"name"])
	for n in ["pocket", "studio", "checker"]:
		assert_contains(names, n)
	var torch := ScreenshotTour.make_flashlight()
	var spot := torch.get_child(0) as SpotLight3D
	assert_approx(spot.spot_angle, Tuning.FLASH_SPOT_ANGLE)
	assert_approx(spot.light_energy, Tuning.FLASH_ENERGY_MAX)
	assert_approx(spot.spot_range, Tuning.FLASH_RANGE)
	torch.free()


func test_plan_frames_a_soft_wall() -> void:
	var data := LevelGenerator.generate(&"halls", 1, ScreenshotTour.SEED)
	var soft: Dictionary = ScreenshotTour.plan(data)[&"soft"]
	if data.soft_walls.is_empty():
		assert_true(soft.is_empty())
		return
	assert_eq(soft[&"name"], "soft_wall")
	var e := data.soft_walls[0]
	var dv := LevelGrid.DIRS[e.z]
	var wall := data.grid.world_of(Vector2i(e.x, e.y)) + Vector3(dv.x, 0.0, dv.y) * (Tuning.GRID_CELL_SIZE * 0.5)
	var from: Vector3 = soft[&"from"]
	var flat := Vector2(wall.x - from.x, wall.z - from.z)
	assert_lt(flat.length(), Tuning.WORLD_SOFT_PREVIEW_DIST, "inside the preview range")
	var look: Vector3 = (soft[&"to"] as Vector3) - from
	assert_gt(Vector2(look.x, look.z).normalized().dot(flat.normalized()), 0.99, "facing the wall")


func test_plan_is_deterministic() -> void:
	var a := ScreenshotTour.plan(LevelGenerator.generate(&"halls", 1, ScreenshotTour.SEED))
	var b := ScreenshotTour.plan(LevelGenerator.generate(&"halls", 1, ScreenshotTour.SEED))
	assert_eq(str(a), str(b))


func test_tour_check_self_test_passes_with_and_without_pillow() -> void:
	var script := ProjectSettings.globalize_path(CHECK_SCRIPT).simplify_path()
	if not FileAccess.file_exists(script):
		return
	for no_pil in ["", "1"]:
		var out: Array = []
		var code := OS.execute("env", ["TOUR_CHECK_NO_PIL=%s" % no_pil, "python3", script, "--selftest"], out)
		if code == -1:
			return  # no python3 here
		assert_eq(code, 0, "selftest (TOUR_CHECK_NO_PIL=%s): %s" % [no_pil, out])
