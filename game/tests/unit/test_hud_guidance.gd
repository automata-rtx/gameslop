extends TestCase
## M2.12: sound cue captions (04 §8, §10), first-run guidance (04 §9, 05 §10), and the HUD
## indicators (keycard glyph, burning flare and radio on, the Archive's unread notes).
## Time is driven by hand (UiMotion.manual_clock).

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var hud: Hud
var fake: HudFakePlayer
var _meta: MetaState
var _settings: Dictionary = {}
var _sense: Dictionary = {}


func before_each() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()
	for key: StringName in [&"captions", &"hints", &"text_size", &"hud_mode"]:
		_settings[key] = SettingsManager.get_value(key)
	SettingsManager.set_value(&"captions", true)
	SettingsManager.set_value(&"hints", true)
	UiMotion.manual_clock = true
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	fake = HudFakePlayer.new()
	add_child(fake)
	hud.bind_player(fake)
	_sense = {}
	hud.hints.world_sense = func() -> Dictionary: return _sense


func after_each() -> void:
	hud.free()
	fake.free()
	for key: StringName in _settings:
		SettingsManager.set_value(key, _settings[key])
	GameState.meta = _meta
	UiMotion.manual_clock = false


func _step(seconds: float, frame: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		var dt := minf(frame, seconds - t)
		UiMotion.step(hud, dt)
		t += dt


# --- captions ---------------------------------------------------------------------------------

func test_audio_cue_captions_follow_the_option() -> void:
	SettingsManager.set_value(&"captions", false)
	EventBus.audio_cue.emit("[hum, left]", Vector3.ZERO)
	assert_false(hud.captions.is_shown(), "12 §6: Off by default, no captions")
	SettingsManager.set_value(&"captions", true)
	EventBus.audio_cue.emit("[hum, left]", Vector3.ZERO)
	assert_eq(hud.captions.lines(), PackedStringArray(["[hum, left]"]))
	assert_eq(hud.captions.labels()[0].theme_type_variation, &"Caption")
	SettingsManager.set_value(&"captions", false)
	assert_true(hud.captions.lines().is_empty(), "turning captions off clears the stack")


func test_caption_stack_rules() -> void:
	for t in ["[door slams, behind, far]", "[tear]", "[contact]"]:
		hud.caption(t)
		_step(0.5)
	assert_eq(hud.captions.lines().size(), 3)
	assert_eq(hud.captions.plain_text(), "[contact]", "the newest line is the lowest")
	hud.caption("[tear]")
	assert_eq(hud.captions.lines().size(), 3, "a repeat restarts its hold instead of stacking")
	hud.caption("[silence]")
	assert_eq(hud.captions.lines(), PackedStringArray(["[tear]", "[contact]", "[silence]"]),
			"a fourth pushes the oldest out")
	_step(Tuning.CAPTION_TIME - 0.4)
	assert_eq(hud.captions.lines(), PackedStringArray(["[tear]", "[silence]"]), "[contact] timed out; [tear] was refreshed")
	_step(1.0)
	assert_true(hud.captions.lines().is_empty())
	_step(0.3)
	await await_frames(1)
	assert_eq(hud.captions.get_node("Stack").get_child_count(), 0, "closed lines are freed")


func test_captions_sit_above_the_prompt() -> void:
	hud.show_prompt("OPEN DOOR")
	for t in ["[hum, ahead left, near]", "[footsteps, behind, late]", "[silence]"]:
		hud.caption(t)
	_step(0.3)
	await await_frames(2)
	var stack := hud.captions.get_node("Stack") as Control
	var prompt_box := hud.prompt.shutter.get_global_rect()
	assert_lt(stack.get_global_rect().end.y, prompt_box.position.y, "11 §6: captions never overlap the prompt")


func test_captioned_sounds_reach_the_hud_end_to_end() -> void:
	# 08 Still within 8 m: AudioManager ducks the room and emits `[silence]` (03 §6 rule 6).
	EventBus.error_proximity.emit(&"still", 6.0)
	assert_contains(hud.captions.lines(), Strings.CAPTION_STILL_SILENCE)
	EventBus.error_proximity.emit(&"still", 40.0)
	# Echo's footsteps and the noclip tear arrive formatted from the listener.
	var l := Transform3D.IDENTITY
	EventBus.audio_cue.emit(AudioMix.format_caption(Strings.CAPTION_ECHO_FOOTSTEP, l, Vector3(0, 0, 4)), Vector3(0, 0, 4))
	EventBus.audio_cue.emit(Strings.CAPTION_NOCLIP_COMMIT, Vector3.ZERO)
	assert_contains(hud.captions.lines(), "[footsteps, behind, late]")
	assert_contains(hud.captions.lines(), "[tear]")
	# M2.14: Echo's contact emits `[contact]` twice; the stack shows it once.
	EventBus.audio_cue.emit(Strings.CAPTION_CONTACT, Vector3.ZERO)
	EventBus.audio_cue.emit(Strings.CAPTION_CONTACT, Vector3.ZERO)
	assert_eq(Array(hud.captions.lines()).count(Strings.CAPTION_CONTACT), 1)


func test_text_size_scales_captions_and_notes() -> void:
	SettingsManager.set_value(&"text_size", 1.4)
	hud.caption("[a line]")
	assert_eq(hud.captions.labels()[0].get_theme_font_size(&"font_size"), 28, "20 px x 1.4")
	hud.show_note(DataRegistry.note(&"H1"))
	assert_eq(hud.note_sheet.line_labels()[0].get_theme_font_size(&"font_size"), 28)
	assert_eq(hud.prompt.line.get_theme_font_size(&"font_size", &"Prompt"), UiTokens.FONT_PROMPT, "prompts do not scale (12 §6)")
	SettingsManager.set_value(&"text_size", 1.0)
	assert_eq(hud.captions.labels()[0].get_theme_font_size(&"font_size"), 20)


func test_captions_follow_hud_mode() -> void:
	SettingsManager.set_value(&"hud_mode", &"minimal")
	assert_true(hud.captions.visible, "12 §6 Minimal keeps captions")
	SettingsManager.set_value(&"hud_mode", &"off")
	assert_false(hud.captions.visible)


# --- first-run guidance -------------------------------------------------------------------------

func test_move_hint_on_spawn_until_three_metres() -> void:
	EventBus.level_entered.emit(1, &"halls", &"start")
	_step(0.2)
	assert_eq(hud.hints.current(), FirstRunHints.MOVE)
	var keys := "%s %s %s %s" % [UiKeys.key_name(&"move_forward"), UiKeys.key_name(&"move_left"),
			UiKeys.key_name(&"move_back"), UiKeys.key_name(&"move_right")]
	assert_eq(hud.hints.plain_text(), "[%s] MOVE · [MOUSE] LOOK" % keys.replace(" ", "] ["))
	_step(Tuning.HINT_SHOW_TIME + 1.0)
	assert_eq(hud.hints.current(), FirstRunHints.MOVE, "the move hint stays until 3 m walked")
	_sense = {&"walked": 3.2}
	_step(0.2)
	assert_eq(hud.hints.current(), FirstRunHints.NONE)
	assert_eq(GameState.meta.hints_shown, [FirstRunHints.MOVE] as Array[StringName], "kept in meta.json")


func test_flashlight_hint_at_15_s_and_performed_by_the_action() -> void:
	GameState.meta.hints_shown = [FirstRunHints.MOVE] as Array[StringName]
	hud.hints._load()
	EventBus.level_entered.emit(1, &"halls", &"start")
	_step(Tuning.HINT_FLASHLIGHT_DELAY - 0.5)
	assert_eq(hud.hints.current(), FirstRunHints.NONE)
	_step(1.0)
	assert_eq(hud.hints.current(), FirstRunHints.FLASHLIGHT)
	assert_eq(hud.hints.plain_text(), "[%s] FLASHLIGHT" % UiKeys.key_name(&"flashlight"))
	fake.flashlight_toggled.emit(true)
	assert_eq(hud.hints.current(), FirstRunHints.NONE, "until the action is performed")


func test_hints_time_out_queue_and_yield_to_prompts() -> void:
	GameState.meta.hints_shown = [FirstRunHints.MOVE, FirstRunHints.FLASHLIGHT] as Array[StringName]
	hud.hints._load()
	EventBus.level_entered.emit(1, &"halls", &"start")
	fake.charge_changed.emit(55.0)
	fake.set_coherence(40.0, &"still")
	_step(0.2)
	assert_eq(hud.hints.current(), FirstRunHints.CRANK)
	assert_eq(hud.hints.plain_text(), "HOLD [%s] CRANK" % UiKeys.key_name(&"crank"))
	hud.show_prompt("OPEN DOOR")
	_step(0.3)
	assert_false(hud.hints.is_shown(), "an interaction prompt owns the position")
	hud.hide_prompt()
	_step(0.3)
	assert_true(hud.hints.is_shown())
	_step(Tuning.HINT_SHOW_TIME)
	assert_eq(hud.hints.current(), FirstRunHints.COHERENCE, "one at a time, the next after 6 s")
	assert_eq(hud.hints.plain_text(), Strings.HINT_COHERENCE)


func test_noclip_drop_and_items_hints() -> void:
	GameState.meta.hints_shown = [FirstRunHints.MOVE, FirstRunHints.FLASHLIGHT] as Array[StringName]
	hud.hints._load()
	EventBus.level_entered.emit(2, &"pools", &"proper")
	_sense = {&"soft_aim": true}
	_step(0.2)
	assert_eq(hud.hints.current(), FirstRunHints.NOCLIP)
	fake.noclip_state.emit(0.2, &"soft", true, &"")
	assert_eq(hud.hints.current(), FirstRunHints.NONE)
	_sense = {&"floor_aim": true}
	_step(Tuning.HINT_FLOOR_AIM_TIME - 0.5)
	assert_eq(hud.hints.current(), FirstRunHints.NONE, "5 s with no soft wall first")
	_step(1.0)
	assert_eq(hud.hints.current(), FirstRunHints.DROP)
	assert_eq(hud.hints.plain_text(), "HOLD [%s] ON FLOOR DROP A LEVEL · COSTS COHERENCE" % UiKeys.key_name(&"noclip"))
	_step(Tuning.HINT_SHOW_TIME + 0.1)
	EventBus.item_picked.emit(&"keycard")
	assert_eq(hud.hints.current(), FirstRunHints.NONE, "the keycard is not a belt item")
	EventBus.item_picked.emit(&"chalk")
	assert_eq(hud.hints.current(), FirstRunHints.ITEMS)
	EventBus.item_used.emit(&"chalk")
	assert_eq(hud.hints.current(), FirstRunHints.NONE)


func test_drop_hint_waits_for_depth_two() -> void:
	var r := FirstRunHints.new()
	r.shown = [FirstRunHints.MOVE] as Array[StringName]
	r.level_started(1)
	r.tick(Tuning.HINT_FLOOR_AIM_TIME + 1.0, {&"floor_aim": true})
	assert_false(r.is_done(FirstRunHints.DROP))
	r.level_started(2)
	r.tick(Tuning.HINT_FLOOR_AIM_TIME + 1.0, {&"floor_aim": true})
	assert_eq(r.current, FirstRunHints.DROP)


func test_hint_keys_follow_rebinding() -> void:
	var before := SettingsManager.binding(&"flashlight", 0)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	SettingsManager.rebind(&"flashlight", ev, 0)
	assert_eq(HudHints.segments_for(FirstRunHints.FLASHLIGHT)[0][UiKeys.TEXT], "G", "04 §9: rendered from the current bindings")
	SettingsManager.reset_bindings()
	assert_eq(HudHints.segments_for(FirstRunHints.FLASHLIGHT)[0][UiKeys.TEXT], UiKeys.key_name(&"flashlight"))
	assert_ne(before, null)


func test_depth_three_retires_hints_and_the_option_resets_them() -> void:
	EventBus.level_entered.emit(1, &"halls", &"start")
	_step(0.2)
	assert_eq(hud.hints.current(), FirstRunHints.MOVE)
	EventBus.level_entered.emit(3, &"garage", &"proper")
	assert_false(bool(SettingsManager.get_value(&"hints")), "04 §9: suppressed after depth 3 once")
	assert_true(GameState.meta.hints_retired)
	assert_eq(hud.hints.current(), FirstRunHints.NONE)
	_step(0.3)
	assert_false(hud.hints.is_shown())
	SettingsManager.set_value(&"hints", true)
	assert_true(GameState.meta.hints_shown.is_empty(), "12 §6: turning hints back on resets them")
	EventBus.level_entered.emit(4, &"offices", &"proper")
	assert_true(bool(SettingsManager.get_value(&"hints")), "retired once; the player's choice stands")
	assert_eq(hud.hints.current(), FirstRunHints.MOVE)


func test_hints_never_take_input() -> void:
	EventBus.level_entered.emit(1, &"halls", &"start")
	_step(0.2)
	assert_eq(hud.hints.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.hints.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_false(get_tree().paused, "the world does not pause")


# --- HUD indicators -------------------------------------------------------------------------------

class FakeInventory extends Node:
	signal changed(slots: Array, selected: int)
	signal keycard_changed(has_card: bool)
	var slots: Array = []
	var selected: int = 0
	var keycard: bool = false


func test_keycard_glyph_beside_the_depth_label() -> void:
	var inv := FakeInventory.new()
	add_child(inv)
	hud.bind_inventory(inv)
	hud.set_depth(2, &"pools")
	assert_false(hud.depth.key_shutter.is_shown())
	inv.keycard_changed.emit(true)
	assert_true(hud.depth.key_shutter.is_shown())
	assert_not_null((hud.depth.key_shutter.get_child(0) as TextureRect).texture, "the 04 §5 key glyph")
	inv.keycard_changed.emit(false)
	assert_false(hud.depth.key_shutter.is_shown())
	hud.bind_inventory(null)
	inv.free()


func test_belt_shows_a_burning_flare_and_a_radio_on() -> void:
	var flare := ItemSlot.new(&"flare", 2, {FlareItem.BURN: 12.3})
	var radio := ItemSlot.new(&"radio", 1, {RadioItem.ON: true, RadioItem.CHARGE: 60.0})
	var glow := ItemSlot.new(&"glowstick", 1)
	hud.set_items([flare, radio, glow, null], 0)
	assert_eq(hud.belt.slot(0).status_label.text, "13S")
	assert_true(hud.belt.slot(0).status_label.visible)
	assert_eq(hud.belt.slot(1).status_label.text, "ON")
	assert_false(hud.belt.slot(2).status_label.visible)
	flare.state[FlareItem.BURN] = 4.5
	radio.state[RadioItem.ON] = false
	_step(0.05)
	assert_eq(hud.belt.slot(0).status_label.text, "5S", "the burn counts down without a signal")
	assert_false(hud.belt.slot(1).status_label.visible)


func test_archive_unread_notes_blink_once_and_become_read() -> void:
	GameState.meta.notes_found = [&"H1", &"H2"] as Array[StringName]
	GameState.meta.notes_read = [&"H1"] as Array[StringName]
	var a := ArchiveMenu.new()
	add_child(a)
	a.on_open()
	assert_eq(a.blinking, [&"H2"] as Array[StringName])
	assert_true(a.is_blink_lit(&"H2"))
	assert_false(a.is_blink_lit(&"H1"))
	var h2 := a.cells[ArchiveMenu.GRID.x]  # column 0, row 1
	assert_eq(h2.get_theme_color(&"font_color"), UiTokens.accent())
	assert_contains(GameState.meta.notes_read, &"H2", "13 §5: read from the first open")
	a.advance(Tuning.ARCHIVE_NEW_BLINK_S * 0.5 + 0.01)
	assert_eq(h2.get_theme_color(&"font_color"), UiTokens.UI_FG)
	a.advance(Tuning.ARCHIVE_NEW_BLINK_S)
	assert_true(a.blinking.is_empty())
	a.on_open()
	assert_true(a.blinking.is_empty(), "blinks once")
	a.free()


func test_meta_read_state_round_trips_and_validates() -> void:
	var m := MetaState.new()
	m.notes_found = [&"H1"] as Array[StringName]
	m.notes_read = [&"H1"] as Array[StringName]
	m.hints_shown = [&"move", &"crank"] as Array[StringName]
	m.hints_retired = true
	var back := MetaSchema.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	assert_eq(back.notes_read, [&"H1"] as Array[StringName])
	assert_eq(back.hints_shown, [&"move", &"crank"] as Array[StringName])
	assert_true(back.hints_retired)
	var bad := MetaSchema.from_dict({"version": 1, "notes_found": ["H1"], "notes_read": ["H1", "H9", 3, ""],
		"hints_shown": ["move", "fly", "move"], "hints_retired": "yes"})
	assert_eq(bad.notes_read, [&"H1"] as Array[StringName], "only found notes can be read")
	assert_eq(bad.hints_shown, [&"move"] as Array[StringName], "unknown and repeated ids dropped")
	assert_false(bad.hints_retired)
	var old := MetaSchema.from_dict({"version": 1})
	assert_true(old.notes_read.is_empty(), "missing keys take their defaults")
	assert_false(old.hints_retired)
