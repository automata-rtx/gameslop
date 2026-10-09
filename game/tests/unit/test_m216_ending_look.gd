extends TestCase
## M2.16: the ending's pieces that test_ending does not build directly: the corridor (01 §8
## step 2), its in-world title menu for the variant, the warm Environment, and the Dissolve
## grid (11 §3). Geometry and numbers only; how it looks is the human check list's.


func _corridor(menu: bool) -> EndingCorridor:
	var c := EndingCorridor.new()
	add_child(c)
	c.build(menu)
	return c


func test_corridor_dimensions_and_the_window() -> void:
	var c := _corridor(false)
	assert_approx(c.far_z, -(Tuning.ENDING_CORRIDOR_LENGTH + Tuning.ENDING_BAY_SIZE.y), 0.0001)
	assert_approx(c.distance_to_far_wall(Vector3.ZERO), Tuning.ENDING_CORRIDOR_LENGTH + Tuning.ENDING_BAY_SIZE.y, 0.0001)
	assert_approx(c.distance_to_far_wall(Vector3(0, 0, c.far_z + 4.0)), 4.0, 0.0001, "the card prints 4 m from the wall")
	var w := c.window_point()
	assert_approx(w.z, c.far_z, 0.0001)
	assert_approx(w.y, Tuning.ENDING_WINDOW_SILL + Tuning.ENDING_WINDOW_SIZE.y * 0.5, 0.0001)
	assert_approx(c.spawn_transform().origin.length(), 0.0, 0.0001, "the player starts at the near end")
	c.free()


func test_corridor_has_a_real_sun_and_no_menu_without_the_variant() -> void:
	var c := _corridor(false)
	assert_not_null(c.sun)
	assert_true(c.sun.shadow_enabled, "a real sun with real shadows (the mullion cross)")
	assert_eq(c.sun.light_color, Tuning.ENDING_SUN_COLOR)
	assert_approx(c.sun.light_energy, Tuning.ENDING_SUN_ENERGY, 0.0001)
	assert_gt(-c.sun.global_transform.basis.z.z, 0.0, "the light travels down the corridor toward the player")
	assert_false(c.variant)
	assert_null(c.descend_label)
	assert_null(c.descend_interactable)
	assert_true(c.menu_labels.is_empty())
	c.build(true)
	assert_true(c.menu_labels.is_empty(), "building twice changes nothing")
	c.free()


func test_the_variant_prints_the_title_menu_and_only_descend_can_be_chosen() -> void:
	var c := _corridor(true)
	var items := EndingCorridor.menu_items()
	assert_eq(items[0]["id"], TitlePage.ITEM_DESCEND, "DESCEND first and selected")
	assert_true(String(items[0]["text"]).begins_with(Strings.MENU_SELECTED_PREFIX))
	assert_eq(c.menu_labels.size(), items.size(), "one label per title line")
	assert_not_null(c.descend_interactable)
	assert_eq(c.descend_interactable.prompt_text().to_upper(), Strings.MENU_DESCEND.to_upper())
	var chosen := [0]
	c.descend_chosen.connect(func() -> void: chosen[0] += 1)
	c.descend_interactable.interact(null)
	assert_eq(chosen[0], 1, "pressing DESCEND goes up to the Ending")
	var ids: Array = []
	for it in items:
		ids.append(it["id"])
	assert_true(ids.has(TitlePage.ITEM_QUIT) and ids.has(TitlePage.ITEM_SETTINGS) and ids.has(TitlePage.ITEM_ARCHIVE))
	c.free()


func test_menu_lists_endless_only_once_it_is_unlocked() -> void:
	var ids_now: Array = []
	for it in EndingCorridor.menu_items():
		ids_now.append(it["id"])
	assert_eq(ids_now.has(TitlePage.ITEM_ENDLESS), GameState.is_mode_available(Tuning.MODE_ENDLESS))


func test_ending_environment_is_warm_daylight_through_the_halls_pipeline() -> void:
	var env := EndingEnvironment.build()
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_eq(env.ambient_light_color, EndingEnvironment.AMBIENT_COLOR)
	assert_approx(env.ambient_light_energy, EndingEnvironment.AMBIENT_ENERGY, 0.0001)
	assert_false(env.sdfgi_enabled, "no GI in v1.0")
	assert_eq(env.background_color, EndingEnvironment.FOG_COLOR)
	# Warm, and brighter than the Halls' mustard haze ambient.
	assert_gt(env.ambient_light_color.r, env.ambient_light_color.b)
	assert_eq(EndingEnvironment.data().id, EndingEnvironment.ID)


func test_dissolve_grid_scatters_over_its_duration_and_finishes_once() -> void:
	var g := DissolveGrid.new()
	add_child(g)
	assert_eq(g.grid, Vector2i(48, 27), "11 §3: a 48 x 27 grid")
	assert_false(g.visible)
	assert_approx(g.duration, Tuning.COHERENCE_DISSOLVE_TIME, 0.0001)
	var done := [0]
	g.finished.connect(func() -> void: done[0] += 1)
	g.play()
	assert_true(g.visible and g.running)
	for i in 1296:
		assert_approx(g.quad_progress(i), 0.0, 0.0001, "nothing has moved at t=0")
	var steps := 0
	while g.running and steps < 400:
		var before := g.quad_progress(7)
		g._process(0.05)
		assert_true(g.quad_progress(7) >= before, "a quad never comes back")
		steps += 1
	assert_eq(done[0], 1, "finished exactly once")
	assert_false(g.running)
	assert_approx(g.t, g.duration, 0.06)
	# Quads are staggered (hash delays), so a mid-way frame has some done and some not.
	g.t = g.duration * 0.6
	var lo := 1.0
	var hi := 0.0
	for i in 1296:
		var p := g.quad_progress(i)
		lo = minf(lo, p)
		hi = maxf(hi, p)
	assert_lt(lo, hi, "the image breaks up, it does not fade")
	g.free()
