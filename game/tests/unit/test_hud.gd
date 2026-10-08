extends TestCase
## M1.6: the HUD (04 §6, 11 R column). Every Player signal it reads moves the right part;
## the Coherence numeral ticks at 30 per second with the loss and gain segments; noclip,
## stamina, prompt, belt, depth, exit status, notifications, hiding and dissolve behave
## per 04 §6. Time is driven by hand (UiMotion.manual_clock).

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var hud: Hud
var fake: HudFakePlayer


func before_each() -> void:
	UiMotion.manual_clock = true
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	fake = HudFakePlayer.new()
	add_child(fake)
	hud.bind_player(fake)


func after_each() -> void:
	hud.free()
	fake.free()
	UiMotion.manual_clock = false


func _step(seconds: float, frame: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		var dt := minf(frame, seconds - t)
		UiMotion.step(hud, dt)
		t += dt


func test_instantiates_headless_and_runs_always() -> void:
	assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS, "11 §4: the HUD moves through hitstop and pause")
	for part: Node in [hud.coherence, hud.depth, hud.notifications, hud.prompt, hud.caption_line,
			hud.crank, hud.belt, hud.crosshair, hud.note_sheet, hud.frame, hud.dimmable,
			hud.coherence_shutter, hud.crank_shutter, hud.belt_shutter]:
		assert_not_null(part)
	assert_true(hud.coherence_shutter.is_shown(), "pillar 1: Coherence is on screen from the start")
	assert_eq(hud.coherence.numeral_text(), "100")


func test_binds_a_real_player_and_reads_its_signals() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world)
	hud.bind_player(p)
	assert_eq(hud.player, p)
	p.coherence_changed.emit(60.0, -40.0, &"still")
	assert_eq(hud.coherence.value, 60.0)
	p.stamina_changed.emit(40.0)
	assert_true(hud.crosshair.stamina_shutter.is_shown())
	p.charge_changed.emit(12.0)
	assert_eq(hud.crank.percent_text(), "12%")
	p.noclip_state.emit(0.4, &"wall", true, &"")
	assert_true(hud.crosshair.noclip_shutter.is_shown())
	p.prompt_changed.emit("OPEN DOOR", 0.0)
	assert_eq(hud.prompt.plain_text(), "[E] OPEN DOOR")
	p.stun_changed.emit(true)
	assert_eq(hud.crosshair.mark(), HudCrosshair.Mark.STUNNED)
	p.hidden_changed.emit(true)
	assert_eq(hud.crosshair.mark(), HudCrosshair.Mark.EYE)
	hud.unbind_player()
	p.coherence_changed.emit(10.0, -50.0, &"still")
	assert_eq(hud.coherence.value, 60.0, "unbound: no longer listening")
	world.free()


func test_coherence_numeral_ticks_at_30_per_second() -> void:
	fake.set_coherence(85.0, &"static")
	assert_eq(hud.coherence.value, 85.0, "the bar takes the value at once")
	assert_eq(hud.coherence.numeral_text(), "100", "the numeral does not jump")
	_step(0.25)
	assert_approx(hud.coherence.shown, 92.5, 0.01)
	_step(0.25)
	assert_eq(hud.coherence.numeral_text(), "085")
	fake.set_coherence(95.0, &"polaroid")
	_step(0.25)
	assert_approx(hud.coherence.shown, 92.5, 0.01, "ticks up at the same rate")


## 04 §6 (R11): a single change of 20 or more ticks at 60 per second, inside the 600 ms
## loss linger; the dissolve snaps the numeral to the target.
func test_big_changes_tick_fast_and_the_dissolve_snaps() -> void:
	fake.set_coherence(70.0, &"still")
	assert_eq(hud.coherence.tick_rate, Tuning.COHERENCE_TICK_RATE_FAST)
	_step(0.25)
	assert_approx(hud.coherence.shown, 85.0, 0.01, "60 per second")
	_step(0.25)
	assert_eq(hud.coherence.numeral_text(), "070", "landed within the loss linger")
	fake.set_coherence(60.0, &"static")
	assert_eq(hud.coherence.tick_rate, Tuning.COHERENCE_TICK_RATE, "a small change walks at 30")
	_step(0.4)
	fake.set_coherence(0.0, &"still")
	hud._on_dissolved(&"still")
	assert_eq(hud.coherence.numeral_text(), "000", "snapped at the dissolve")


## 11 §3 Unlock earned: the unlock chime plays with the notification.
func test_unlock_earned_plays_the_chime() -> void:
	var before := _chimes()
	EventBus.unlock_earned.emit(&"radio")
	assert_eq(_chimes(), before + 1, "ui_unlock played")


func _chimes() -> int:
	var n := 0
	if AudioManager.pool == null:
		return 0
	for p: Node in AudioManager.pool.players_2d:
		if p.get_meta(AudioPool.META_ID, &"") == &"ui_unlock" and bool(p.get(&"playing")):
			n += 1
	return n


func test_coherence_loss_segment_lingers_600_ms_then_shutters_out() -> void:
	fake.set_coherence(65.0, &"still")
	assert_eq(hud.coherence.segments.size(), 1)
	var seg: Dictionary = hud.coherence.segments[0]
	assert_eq(seg["kind"], HudCoherence.LOSS)
	assert_eq(seg["from"], 65.0)
	assert_eq(seg["to"], 100.0)
	_step(0.59)
	assert_eq(hud.coherence.segments.size(), 1, "lit in ui_danger for 600 ms")
	_step(0.12)
	assert_eq(hud.coherence.segments.size(), 1, "shuttering out")
	_step(0.02)
	assert_eq(hud.coherence.segments.size(), 0, "gone after 600 + 120 ms")


func test_coherence_gain_segment_flashes_200_ms() -> void:
	fake.set_coherence(50.0, &"still")
	_step(1.0)
	fake.set_coherence(75.0, &"polaroid")
	var gain: Array = hud.coherence.segments.filter(func(s: Dictionary) -> bool: return s["kind"] == HudCoherence.GAIN)
	assert_eq(gain.size(), 1)
	_step(0.19)
	assert_eq(hud.coherence.segments.filter(func(s: Dictionary) -> bool: return s["kind"] == HudCoherence.GAIN).size(), 1)
	_step(0.02)
	assert_eq(hud.coherence.segments.filter(func(s: Dictionary) -> bool: return s["kind"] == HudCoherence.GAIN).size(), 0)


func test_coherence_danger_below_25() -> void:
	fake.set_coherence(30.0, &"still")
	_step(3.0)
	assert_false(hud.coherence.is_danger())
	assert_eq(hud.coherence.numeral_color(), UiTokens.UI_FG)
	fake.set_coherence(20.0, &"still")
	_step(0.5)
	assert_true(hud.coherence.is_danger())
	assert_eq(hud.coherence.numeral_color(), UiTokens.UI_DANGER)
	assert_eq(hud.coherence.heartbeat_bpm(), Tuning.COHERENCE_HEARTBEAT_FLOOR_BPM, "06 §9: 90 bpm floor")
	EventBus.threat_changed.emit(1.0)
	assert_eq(hud.coherence.heartbeat_bpm(), Tuning.AUDIO_HEARTBEAT_MAX_BPM)
	EventBus.threat_changed.emit(0.0)


func test_reset_snaps_and_restores() -> void:
	fake.set_coherence(10.0, &"still")
	fake.dissolved.emit(&"still")
	_step(0.49)
	assert_true(hud.coherence_shutter.is_shown())
	_step(0.02)
	assert_eq(hud.coherence_shutter.phase, UiShutter.Phase.CLOSING, "11 §3: the HUD shutters out 0.5 s into the dissolve")
	assert_eq(hud.belt_shutter.phase, UiShutter.Phase.CLOSING)
	_step(0.2)
	assert_false(hud.coherence_shutter.visible)
	assert_false(hud.crosshair.visible)
	fake.reset()
	assert_true(hud.coherence_shutter.is_shown(), "a new Descent brings it back")
	assert_true(hud.crosshair.visible)
	assert_eq(hud.coherence.numeral_text(), "100", "reset snaps the numeral")
	assert_eq(hud.coherence.segments.size(), 0)


func test_stamina_arc_appears_and_leaves_1_s_after_refill() -> void:
	var cross := hud.crosshair
	assert_false(cross.stamina_shutter.visible, "hidden at 100")
	fake.stamina_changed.emit(80.0)
	assert_true(cross.stamina_shutter.is_shown())
	fake.stamina_exhausted.emit()
	assert_true(cross.stamina_arc.exhausted)
	assert_eq(cross.stamina_arc.stamina_color(), UiTokens.UI_DANGER)
	assert_true(cross.stamina_arc.blink_off(), "11 §2: blinks twice")
	_step(0.15)
	assert_false(cross.stamina_arc.blink_off())
	_step(Tuning.STAMINA_LOCKOUT_TIME)
	assert_false(cross.stamina_arc.exhausted, "danger lasts the lockout")
	fake.stamina_changed.emit(100.0)
	_step(0.95)
	assert_true(cross.stamina_shutter.is_shown(), "stays 1 s after refill")
	_step(0.1)
	assert_eq(cross.stamina_shutter.phase, UiShutter.Phase.CLOSING)
	fake.sprint_changed.emit(true)
	assert_true(cross.stamina_shutter.is_shown(), "11 §2: sprint start brings the arc")


func test_noclip_arc_readiness_ring_and_invalid_reason() -> void:
	var cross := hud.crosshair
	fake.noclip_state.emit(0.3, &"wall", true, &"")
	assert_true(cross.noclip_shutter.is_shown())
	assert_eq(cross.noclip_arc.charge, 0.3)
	assert_eq(cross.reason_text(), "")
	# 04 §6: the echo ring completes 100 ms before commit.
	var wall_ready := 1.0 - 0.1 / Tuning.NOCLIP_WALL_TIME
	assert_approx(HudArc.echo_fraction(wall_ready, &"wall"), 1.0, 0.0001)
	assert_lt(HudArc.echo_fraction(wall_ready - 0.05, &"wall"), 1.0)
	var floor_ready := 1.0 - 0.1 / Tuning.NOCLIP_FLOOR_TIME
	assert_approx(HudArc.echo_fraction(floor_ready, &"floor"), 1.0, 0.0001)
	assert_lt(HudArc.echo_fraction(floor_ready - 0.01, &"floor"), 1.0)
	assert_eq(HudArc.target_glyph_name(&"floor"), &"arrow_d")
	assert_eq(HudArc.target_glyph_name(&"wall"), &"noclip")
	fake.noclip_state.emit(0.0, &"wall", false, Tuning.NOCLIP_REASON_SOLID)
	assert_true(cross.noclip_shutter.is_shown(), "invalid shows the dashed arc")
	assert_eq(cross.reason_text(), "SOLID")
	fake.noclip_state.emit(0.0, &"", true, &"")
	_step(0.13)
	assert_false(cross.noclip_shutter.visible, "cancel: the arc shutters out")
	assert_eq(cross.reason_text(), "")


func test_prompt_press_and_hold_with_underline() -> void:
	fake.prompt_changed.emit("OPEN DOOR", 0.0)
	assert_eq(hud.prompt.plain_text(), "[E] OPEN DOOR")
	assert_false(hud.prompt.underline_visible())
	assert_eq(hud.crosshair.mark(), HudCrosshair.Mark.RING, "an interactable within reach rings the dot")
	fake.prompt_changed.emit(Strings.PROMPT_FLIP_BREAKER, 0.6)
	assert_eq(hud.prompt.plain_text(), "HOLD [E] FLIP BREAKER")
	assert_true(hud.prompt.underline_visible())
	fake.prompt_progress.emit(0.5)
	assert_eq(hud.prompt.progress, 0.5)
	fake.prompt_changed.emit("", 0.0)
	assert_eq(hud.prompt.shutter.phase, UiShutter.Phase.CLOSING, "11 §2: the prompt shutters out")
	assert_eq(hud.crosshair.mark(), HudCrosshair.Mark.DOT)
	assert_eq(hud.prompt.line.key_labels().size(), 1, "one boxed key")


func test_hidden_state_dims_to_40_percent_except_crosshair() -> void:
	fake.hidden_changed.emit(true)
	fake.prompt_changed.emit(Strings.PROMPT_LEAVE, 0.6)
	_step(0.2)
	assert_approx(hud.dimmable.modulate.a, Tuning.HIDE_HUD_DIM, 0.001)
	assert_eq(hud.crosshair.mark(), HudCrosshair.Mark.EYE)
	assert_false(hud.dimmable.is_ancestor_of(hud.crosshair), "the crosshair is not dimmed")
	assert_eq(hud.prompt.plain_text(), "HOLD [E] LEAVE", "04 §6 hidden prompt")
	fake.hidden_changed.emit(false)
	_step(0.2)
	assert_approx(hud.dimmable.modulate.a, 1.0, 0.001)


func test_crank_gauge() -> void:
	assert_eq(hud.crank.percent_text(), "100%")
	assert_eq(hud.crank.glyph_color(), UiTokens.UI_DIM, "ui_dim at 100%")
	fake.flashlight_toggled.emit(true)
	fake.charge_changed.emit(62.0)
	assert_eq(hud.crank.percent_text(), "62%")
	assert_eq(hud.crank.glyph_color(), UiTokens.UI_FG, "brightens with the light on")
	fake.flashlight_toggled.emit(false)
	assert_eq(hud.crank.glyph_color(), UiTokens.UI_DIM, "dims with it off")
	fake.charge_changed.emit(12.0)
	assert_eq(hud.crank.percent_color(), UiTokens.UI_DANGER, "below 15%")
	fake.crank_changed.emit(true)
	_step(0.25)
	assert_gt(hud.crank.glyph_rotation(), 0.0, "the handle turns while cranking")
	fake.crank_changed.emit(false)
	assert_eq(hud.crank.glyph_rotation(), 0.0)


func test_item_belt() -> void:
	for i in HudBelt.SLOT_COUNT:
		assert_true(hud.belt.slot(i).is_empty(), "works with an empty inventory")
		assert_eq(hud.belt.slot(i).count_label.text, "—")
	hud.set_items([{"kind": &"polaroid", "count": 2}, {"kind": &"glowstick", "count": 1}, null], 0)
	var s0 := hud.belt.slot(0)
	assert_eq(s0.number.text, "1")
	assert_eq(s0.count_label.text, "×2")
	assert_not_null(s0.glyph.texture, "polaroid glyph")
	assert_true(s0.selected)
	assert_approx(s0.glyph.scale.x, UiMotion.PULSE_SCALE, 0.001, "select pulses 1.15x")
	_step(0.12)
	assert_approx(s0.glyph.scale.x, 1.0, 0.001)
	assert_true(hud.belt.slot(2).is_empty())
	hud.set_items([{"kind": &"polaroid", "count": 1}, {"kind": &"glowstick", "count": 1}], 1)
	assert_eq(s0.count_label.get_theme_color(&"font_color"), UiTokens.UI_ACCENT, "count decrement blinks ui_accent")
	assert_true(hud.belt.slot(1).selected)
	assert_false(s0.selected)
	_step(0.12)
	assert_eq(s0.count_label.get_theme_color(&"font_color"), UiTokens.UI_FG)


func test_bind_inventory_minimal_api() -> void:
	var inv := Node.new()
	inv.add_user_signal("changed", [{"name": "slots", "type": TYPE_ARRAY}, {"name": "selected", "type": TYPE_INT}])
	add_child(inv)
	hud.bind_inventory(inv)
	inv.emit_signal(&"changed", [{"kind": &"chalk", "count": 8}], 0)
	assert_eq(hud.belt.slot(0).count_label.text, "×8")
	hud.bind_inventory(null)
	assert_true(hud.belt.slot(0).is_empty())
	inv.free()


func test_depth_and_exit_status() -> void:
	EventBus.level_entered.emit(3, &"garage", &"proper")
	assert_eq(hud.depth.depth_text(), "DEPTH 03 · GARAGE")
	assert_eq(hud.depth.numeral_color(), UiTokens.UI_ACCENT)
	assert_eq(hud.depth.depth_shutter.phase, UiShutter.Phase.OPENING, "11 §3 arrival: shutters in")
	assert_eq(hud.depth.exit_text(), "EXIT: UNKNOWN")
	assert_eq(hud.depth.exit_color(), UiTokens.UI_DIM)
	EventBus.exit_status_changed.emit(&"powered", 0.0)
	assert_eq(hud.depth.exit_text(), "EXIT: POWERED")
	assert_eq(hud.depth.exit_shutter.phase, UiShutter.Phase.OPENING, "exit seen: the status shutters in")
	EventBus.exit_status_changed.emit(&"open", 0.0)
	assert_eq(hud.depth.exit_text(), "EXIT: OPEN")
	assert_eq(hud.depth.exit_color(), UiTokens.UI_FG, "ui_fg once cleared")
	assert_contains(hud.notifications.lines(), Strings.MSG_EXIT_UNLOCKED)
	hud.set_exit_status(&"sealed", 134.0)
	assert_eq(hud.depth.exit_text(), "EXIT: SEALED 02:14")
	_step(1.0)
	assert_eq(hud.depth.exit_text(), "EXIT: SEALED 02:13", "counts down between events")
	EventBus.level_entered.emit(6, &"substrate", &"drop")
	assert_eq(hud.depth.numeral_color(), UiTokens.UI_COLD, "Substrate depth in ui_cold")
	assert_contains(hud.notifications.lines(), Strings.MSG_DROPPED)


func test_notifications_type_and_stack_two() -> void:
	hud.notify("ARCHIVE: NOTE G2")
	var label: UiTypedLabel = hud.notifications.labels()[0]
	assert_true(label.is_typing())
	_step(0.1)
	assert_eq(label.typed_count(), 6, "60 characters per second")
	assert_eq(label.get_theme_color(&"font_color"), UiTokens.UI_DIM)
	hud.notify("EXIT UNLOCKED")
	hud.notify("DESCENDING")
	assert_eq(hud.notifications.lines(), PackedStringArray(["EXIT UNLOCKED", "DESCENDING"]), "max two stacked")
	_step(Tuning.HUD_NOTIFY_TIME + 0.2)
	assert_eq(hud.notifications.lines().size(), 0, "each held 4 s")


func test_note_found_and_unlock_from_the_bus() -> void:
	EventBus.note_found.emit(&"H3")
	assert_true(hud.note_sheet.is_shown())
	assert_eq(hud.note_sheet.header_text, "NOTE H3 · HANDWRITTEN")
	assert_contains(hud.notifications.lines(), "ARCHIVE: NOTE H3")
	EventBus.unlock_earned.emit(&"radio")
	assert_contains(hud.notifications.lines(), "ITEM UNLOCKED: RADIO")
	assert_eq(hud.notifications.labels()[-1].get_theme_color(&"font_color"), UiTokens.UI_ACCENT, "11 §3 unlock in ui_accent")
	assert_eq(Hud.unlock_message(&"diver"), "LOADOUT UNLOCKED: DIVER")
	assert_eq(Hud.unlock_message(&"daily"), "MODE UNLOCKED: DAILY DESCENT")
	assert_eq(Hud.unlock_message(&"codex_still"), "ARCHIVE: STILL CODEX")


func test_caption_slot() -> void:
	hud.caption("[tear]")
	assert_eq(hud.caption_line.plain_text(), "[tear]")
	hud.caption("")
	assert_eq(hud.caption_line.shutter.phase, UiShutter.Phase.CLOSING)


func test_hud_mode_setting() -> void:
	SettingsManager.set_value(&"hud_mode", &"minimal")
	assert_false(hud.depth.visible)
	assert_false(hud.belt_shutter.visible)
	assert_true(hud.prompt.visible)
	assert_true(hud.coherence.visible, "pillar 1: Coherence never hides")
	SettingsManager.set_value(&"hud_mode", &"off")
	assert_false(hud.prompt.visible)
	assert_true(hud.coherence.visible)
	SettingsManager.set_value(&"hud_mode", &"full")
	assert_true(hud.depth.visible)


func test_gallery_hud_states_build_headless() -> void:
	for state in HudGalleryStates.STATES:
		var root := Control.new()
		add_child(root)
		var h := HudGalleryStates.build(root, state)
		assert_not_null(h, String(state))
		assert_true(h.coherence_shutter.is_shown(), "%s keeps Coherence on screen" % state)
		root.free()
	UiMotion.manual_clock = true


func test_notice_prompt_is_dim_and_keyless() -> void:
	fake.prompt_changed.emit(Strings.PROMPT_FUSE_MISSING, 0.0)
	assert_eq(hud.prompt.plain_text(), "FUSE MISSING", "no key cap, no HOLD")
	assert_false(hud.prompt.underline_visible())
	assert_true(hud.prompt.is_shown())
	hud.show_notice_prompt("NO CARD")
	assert_eq(hud.prompt.plain_text(), "NO CARD")
	fake.prompt_changed.emit("OPEN DOOR", 0.0)
	assert_eq(hud.prompt.plain_text(), "[E] OPEN DOOR", "ordinary prompts keep the key")


func test_breaker_variant_b_shows_fuse_missing_without_a_fuse() -> void:
	var b := (load("res://scenes/interactables/breaker.tscn") as PackedScene).instantiate() as Breaker
	b.variant = Breaker.VARIANT_B
	add_child(b)
	var carrier := Node.new()
	var inv := Inventory.new()
	inv.name = "Inventory"
	carrier.add_child(inv)
	add_child(carrier)
	assert_true(b.interactable.can_interact(carrier), "the notice is still offered")
	assert_eq(b.interactable.prompt_text(), Strings.PROMPT_FUSE_MISSING)
	assert_approx(b.interactable.hold_time, 0.0)
	fake.prompt_changed.emit(b.interactable.prompt_text(), b.interactable.hold_time)
	assert_eq(hud.prompt.plain_text(), "FUSE MISSING")
	b.interactable.interact(carrier)
	assert_false(b.fuse_in, "interacting without a fuse does nothing")
	inv.add(Breaker.FUSE)
	assert_true(b.interactable.can_interact(carrier))
	assert_eq(b.interactable.prompt_text(), Strings.PROMPT_INSERT_FUSE)
	assert_approx(b.interactable.hold_time, Tuning.FUSE_INSERT_TIME)
	b.queue_free()
	carrier.queue_free()


func test_exit_status_clears_in_the_cabin_and_returns_on_entry() -> void:
	EventBus.level_entered.emit(3, &"garage", &"proper")
	_step(1.0)
	assert_true(hud.depth.exit_shutter.is_shown())
	EventBus.level_left.emit(true)
	_step(1.0)
	assert_false(hud.depth.exit_shutter.is_shown(), "the Landing cabin has no exit status")
	EventBus.level_entered.emit(4, &"garage", &"proper")
	assert_eq(hud.depth.exit_text(), "EXIT: UNKNOWN")
	assert_true(hud.depth.exit_shutter.is_shown(), "restored on the next level")


func test_numeral_never_reads_000_while_coherence_is_left() -> void:
	hud.coherence.set_value(0.00004, 0.0)
	assert_eq(hud.coherence.numeral_text(), "001", "any Coherence above 0 reads at least 001")
	hud.coherence.set_value(0.4, 0.0)
	assert_eq(hud.coherence.numeral_text(), "001")
	hud.coherence.set_value(0.0, 0.0)
	assert_eq(hud.coherence.numeral_text(), "000", "only 0 is 000")


func test_noclip_refund_snaps_without_a_gain_segment() -> void:
	fake.set_coherence(90.0, &"noclip")
	fake.set_coherence(100.0, &"noclip_refund")
	assert_eq(hud.coherence.numeral_text(), "100", "the numeral snaps back")
	assert_false(hud.coherence.segments.any(func(s: Dictionary) -> bool: return int(s["kind"]) == HudCoherence.GAIN),
			"a refund is not a gain")
