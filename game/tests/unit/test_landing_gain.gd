extends TestCase
## 05 §4, 11 §3 (R20, M3 review S1): the Landing panel prints the Coherence the arrival will
## actually add, min(20, 100 - Coherence), and no gain line at full Coherence. The +20 itself
## is unchanged (pinned in test_tuning).


func _fake_player(coherence: float) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar coherence: float = %.3f\n" % coherence
	s.reload()
	var n := Node3D.new()
	n.set_script(s)
	return n


func test_gain_is_what_the_arrival_applies() -> void:
	assert_approx(Landing.gain_for(100.0), 0.0, 0.0001, "nothing at full")
	assert_approx(Landing.gain_for(93.0), 7.0, 0.0001, "up to full")
	assert_approx(Landing.gain_for(80.0), Tuning.COHERENCE_GAIN_PROPER_EXIT, 0.0001, "the whole +20 at 80")
	assert_approx(Landing.gain_for(15.0), Tuning.COHERENCE_GAIN_PROPER_EXIT, 0.0001, "never more than +20")
	assert_approx(Landing.gain_for(0.0), Tuning.COHERENCE_GAIN_PROPER_EXIT, 0.0001)


func test_gain_text_rounds_and_omits_zero() -> void:
	assert_eq(LandingPanel.gain_text(20.0), "COHERENCE +20")
	assert_eq(LandingPanel.gain_text(7.0), "COHERENCE +7")
	assert_eq(LandingPanel.gain_text(0.3), "COHERENCE +1", "a gain that applies is printed")
	assert_eq(LandingPanel.gain_text(0.0), "", "no line at full Coherence")


func test_panel_omits_the_line_at_zero_and_prints_the_real_gain() -> void:
	var panel := LandingPanel.new()
	add_child(panel)
	panel.setup([&"glowstick", &"chalk"] as Array[StringName], 0.0, false)
	assert_eq(panel.gain_line(), "", "omitted at 0")
	panel.setup([&"glowstick", &"chalk"] as Array[StringName], 7.0, false)
	assert_eq(panel.gain_line(), "COHERENCE +7")
	panel.setup([&"glowstick"] as Array[StringName], 0.0, false)
	assert_eq(panel.gain_line(), "", "and removed again on a later setup")
	panel.free()


func test_landing_reads_the_player_coherence() -> void:
	for c: float in [100.0, 93.0, 40.0]:
		var l := (load("res://scenes/landing.tscn") as PackedScene).instantiate() as Landing
		l.apply_theme(&"halls")
		add_child(l)
		var p := _fake_player(c)
		add_child(p)
		l.begin(p, [&"glowstick", &"chalk"] as Array[StringName], false)
		assert_eq(l.panel.gain_line(), LandingPanel.gain_text(Landing.gain_for(c)), "at %.0f Coherence" % c)
		l.free()
		p.free()
