class_name Ending
extends Node3D
## The ending (01 §8, 14 §5 `ending.tscn`, GLOSSARY Threshold). The run has already ended
## with cause `threshold` (the win, Endless and Cycle 2 earned and saved) and cut to white
## with the single low tone (cut_to_white). Here:
## 1. the white holds until ENDING_WHITE_TIME after the cut (Reduce flashing: it faded in);
## 2. it fades to the sunlit corridor (EndingCorridor). No HUD. Coherence restores from the
##    crossing's value to 100 over 6 s and the renderer's desaturation and grain fall away
##    with it. The player walks (no noclip here). MusicDirector plays the ending chord.
## 3. near the far wall (or after ENDING_WALK_MAX_TIME) `DEPTH 0` prints small in the HUD's
##    depth position, then the console-style title card NOCLIP;
## 4. the credits roll over the corridor (CreditsRoll), then the Run Summary (the WIN line and
##    the unlock list).
## The variant (all 36 notes: unlock #14 earned before this win) prints the title menu on
## the far wall; pressing DESCEND there starts the next Descent without the title.
## Skippable after the first viewing (the first win plays whole): one press of `pause`
## shows `[ESC] SKIP`, a second within ENDING_SKIP_CONFIRM_TIME goes to the summary.

signal phase_changed(phase: StringName)

const PHASE_WHITE := &"white"
const PHASE_FADE := &"fade"
const PHASE_WALK := &"walk"
const PHASE_CARD := &"card"
const PHASE_CREDITS := &"credits"
const PHASE_DONE := &"done"
const SUMMARY_SCENE := "res://scenes/summary.tscn"
const RUN_SCENE := "res://scenes/run.tscn"
const SCENE_PATH := "res://scenes/ending.tscn"
## 01 §8 step 1, 11 §3 "Threshold crossed": the single low tone (03 §4).
const SOUND_TONE := &"threshold_tone"
## AudioManager.set_stratum(&"ending") plays `room_tone_ending` (03 §4).
const ROOM := &"ending"
const SKIP_ACTION := &"pause"
## Above the glitch transition (100), so the white is never sliced.
const WHITE_LAYER := 110
const UI_LAYER := 20
const NOTE_U6 := &"note_u6"

## Ticks (ms) of the Threshold's cut to white; set by cut_to_white, read once by the next ending.
static var cut_at_ms: int = -1

@onready var player: Player = %Player
@onready var corridor: EndingCorridor = %Corridor
@onready var world: WorldEnvironment = %World
@onready var white: ColorRect = %WhiteRect
@onready var ui: Control = %UiRoot

var phase: StringName = PHASE_WHITE
var variant: bool = false
var skippable: bool = false
var capture_mouse: bool = true
## Tests and benches only: multiplies the sequence clock (never the player's movement).
var time_scale: float = 1.0
## Seconds since the fade began (the Coherence restore clock).
var restore_t: float = 0.0
var start_coherence: float = Tuning.COHERENCE_MAX
var depth_label: UiTypedLabel
var depth_box: Control
var card: Control
var card_label: UiTypedLabel
var credits: CreditsRoll
var skip_label: Label
var reduce_flashing: bool = false

var _phase_t: float = 0.0
var _white_hold: float = Tuning.ENDING_WHITE_TIME
var _since_cut: float = 0.0
var _skip_left: float = 0.0
var _leaving: bool = false


# --- rules (static, tested) ------------------------------------------------------------------

## 01 §8 variant: all 36 notes found before this win, i.e. unlock #14 (the builder's note,
## found by finding the 35 others) is earned.
static func variant_for(meta: MetaState) -> bool:
	if meta == null:
		return false
	return meta.is_unlocked(NOTE_U6) or meta.notes_count_except(GameState.NOTE_U6) >= Tuning.UNLOCK_NOTE_U6_NOTES


## 01 §8: skippable after the first viewing. The win is recorded before the ending plays, so
## the first win's ending is the first viewing.
static func is_skippable(meta: MetaState) -> bool:
	return meta != null and int(meta.stats.get("wins", 0)) >= 2


## 01 §8 step 2: Coherence from the crossing's value to 100 over 6 s.
static func coherence_at(t: float, from: float) -> float:
	var k := clampf(t / Tuning.COHERENCE_ENDING_RESTORE_TIME, 0.0, 1.0)
	return lerpf(clampf(from, 0.0, Tuning.COHERENCE_MAX), Tuning.COHERENCE_ENDING_RESTORE_TO, k)


## The white's opacity `t` seconds after the cut: a hard cut, or (Reduce flashing, 12 §6)
## a fade over ENDING_WHITE_SOFT_FADE.
static func white_alpha(t: float, soft: bool) -> float:
	if not soft:
		return 1.0
	return clampf(t / Tuning.ENDING_WHITE_SOFT_FADE, 0.0, 1.0)


## Every string the ending can print (01 §2 forbidden words; tests).
static func printed_texts() -> Array[String]:
	var out: Array[String] = [Strings.ENDING_DEPTH, Strings.ENDING_TITLE_CARD,
			Strings.ENDING_SKIP.replace("{key}", UiKeys.key_name(SKIP_ACTION))]
	for item in EndingCorridor.menu_items():
		out.append(String(item["text"]))
	out.append(Credits.text())
	return out


## 01 §8 step 1, from the run: a white layer over everything (above the glitch), at once or,
## with Reduce flashing, fading in; the single low tone. The ending picks the white up.
static func cut_to_white(parent: Node) -> CanvasLayer:
	cut_at_ms = Time.get_ticks_msec()
	var layer := make_white_layer()
	parent.add_child(layer)
	var rect := layer.get_child(0) as ColorRect
	if CoherenceRenderer.reduce_flashing:
		rect.color.a = 0.0
		layer.create_tween().tween_property(rect, ^"color:a", 1.0, Tuning.ENDING_WHITE_SOFT_FADE)
	AudioManager.play_2d(SOUND_TONE)
	return layer


static func make_white_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "WhiteCut"
	layer.layer = WHITE_LAYER
	var rect := ColorRect.new()
	rect.name = "WhiteRect"
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	return layer


# --- lifecycle --------------------------------------------------------------------------------

func _ready() -> void:
	variant = variant_for(GameState.meta)
	skippable = is_skippable(GameState.meta)
	reduce_flashing = CoherenceRenderer.reduce_flashing
	if GameState.run != null:
		start_coherence = GameState.run.coherence
	corridor.build(variant)
	corridor.descend_chosen.connect(descend)
	world.environment = EndingEnvironment.build()
	EndingEnvironment.apply_settings(self)
	_take_the_cut()
	_setup_player()
	_setup_presentation()
	_build_ui()
	white.color.a = white_alpha(_since_cut, reduce_flashing)


func _exit_tree() -> void:
	# The corridor's room tone stays here; the summary and the title have none.
	AudioManager.set_stratum(&"")
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The white holds until ENDING_WHITE_TIME after the run's cut; opened on its own (benches),
## the ending makes the cut itself.
func _take_the_cut() -> void:
	if cut_at_ms < 0:
		cut_at_ms = Time.get_ticks_msec()
		AudioManager.play_2d(SOUND_TONE)
	_since_cut = maxf(0.0, (Time.get_ticks_msec() - cut_at_ms) / 1000.0)
	_white_hold = maxf(0.0, Tuning.ENDING_WHITE_TIME - _since_cut)
	cut_at_ms = -1


func _setup_player() -> void:
	player.reset_for_run(start_coherence)
	# No noclip in the corridor: nothing here needs passing through (and no HUD to aim it).
	var nt := player.noclip_targeting
	player.noclip_targeting = null
	if nt != null:
		nt.set_physics_process(false)
	player.global_transform = corridor.spawn_transform()
	player.velocity = Vector3.ZERO
	# Daylight needs no torch: the hand is empty here (the flashlight stays off and unseen).
	player.flashlight.set_on(false, true)
	player.flashlight.visible = false
	# Held still under the white (look only), like the Landing.
	player.state_machine.transition_to(PlayerStateMachine.LANDING)
	player.rig.camera.make_current()
	if variant:
		player.prompt_changed.connect(_on_prompt_changed)


func _setup_presentation() -> void:
	AudioManager.set_listener(player.rig.camera)
	AudioManager.set_stratum(ROOM)
	CoherenceRenderer.set_threat(0.0)
	CoherenceRenderer.set_static(0.0)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	CoherenceRenderer.set_noclip_charge(0.0)
	_apply_coherence(start_coherence)


func _build_ui() -> void:
	# DEPTH 0 where the HUD's depth line stood (04 §6, top-right), small, on the readout's backing.
	depth_label = UiTypedLabel.new()
	depth_label.theme_type_variation = &"HudLabel"
	depth_box = _backing(depth_label)
	depth_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, UiTokens.SAFE_MARGIN)
	depth_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	depth_box.visible = false
	# The console-style title card: the title's wordmark and grid (04 §7), typed with the cursor.
	var grid := TitlePage.WordmarkGrid.new()
	var stock := grid.label
	grid.remove_child(stock)
	stock.free()
	card_label = UiTypedLabel.new()
	card_label.theme_type_variation = &"Wordmark"
	grid.add_child(card_label)
	grid.label = card_label
	card = _backing(grid)
	card.position = Vector2(UiTokens.SAFE_MARGIN * 4, UiTokens.GRID * 40)
	card.visible = false
	credits = CreditsRoll.new()
	credits.finished.connect(_finish)
	ui.add_child(credits)
	skip_label = Label.new()
	skip_label.theme_type_variation = &"HudLabel"
	skip_label.text = Strings.ENDING_SKIP.replace("{key}", UiKeys.key_name(SKIP_ACTION))
	var skip_box := _backing(skip_label)
	skip_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, UiTokens.SAFE_MARGIN)
	skip_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skip_label.visibility_changed.connect(func() -> void: skip_box.visible = skip_label.visible)
	skip_label.visible = false
	skip_box.visible = false


## 04 §2: text over the world sits on the ui_bg 60% backing.
func _backing(content: Control) -> PanelContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = &"Backing"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(content)
	ui.add_child(box)
	return box


# --- the sequence ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta * time_scale)


## Steps the sequence by `dt` seconds (public so tests can drive it).
func advance(dt: float) -> void:
	if _leaving:
		return
	_phase_t += dt
	_since_cut += dt
	if _skip_left > 0.0:
		_skip_left -= dt
		skip_label.visible = _skip_left > 0.0
	if phase != PHASE_WHITE:
		restore_t += dt
		_apply_coherence(coherence_at(restore_t, start_coherence))
	match phase:
		PHASE_WHITE:
			white.color.a = white_alpha(_since_cut, reduce_flashing)
			if _phase_t >= _white_hold:
				_set_phase(PHASE_FADE)
				_begin_fade()
		PHASE_FADE:
			white.color.a = 1.0 - clampf(_phase_t / Tuning.ENDING_FADE_IN_TIME, 0.0, 1.0)
			if _phase_t >= Tuning.ENDING_FADE_IN_TIME:
				_set_phase(PHASE_WALK)
		PHASE_WALK:
			if _near_the_window() or restore_t >= Tuning.ENDING_WALK_MAX_TIME:
				_set_phase(PHASE_CARD)
				depth_box.visible = true
				depth_label.type_text(Strings.ENDING_DEPTH)
		PHASE_CARD:
			_advance_card()
		PHASE_CREDITS:
			credits.advance(dt)


func _advance_card() -> void:
	if not card.visible and _phase_t >= Tuning.ENDING_CARD_DELAY:
		card.visible = true
		card_label.type_text(Strings.ENDING_TITLE_CARD)
	if _phase_t >= Tuning.ENDING_CARD_DELAY + Tuning.ENDING_CARD_HOLD:
		_set_phase(PHASE_CREDITS)
		# The card and DEPTH 0 make way for the roll.
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, ^"modulate:a", 0.0, Tuning.ENDING_FADE_IN_TIME)
		tw.tween_property(depth_box, ^"modulate:a", 0.0, Tuning.ENDING_FADE_IN_TIME)
		credits.start()


func _set_phase(p: StringName) -> void:
	phase = p
	_phase_t = 0.0
	phase_changed.emit(p)


func _begin_fade() -> void:
	if not player.state_machine.transition_to(PlayerStateMachine.IDLE):
		player.state_machine.reset()
	# 03 §5: the A major triad. MusicDirector also starts it on the routed scene change; only
	# start it when nothing has (benches, tests).
	var music := AudioManager.music
	if music != null and music.mode != MusicDirector.MODE_ENDING:
		music.play_ending()
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _near_the_window() -> bool:
	return corridor.distance_to_far_wall(player.global_position) <= Tuning.ENDING_CARD_DISTANCE


func _apply_coherence(c: float) -> void:
	player.coherence = c
	CoherenceRenderer.set_coherence(c)
	AudioManager.set_coherence(c)


# --- leaving ---------------------------------------------------------------------------------

## The credits have rolled (or the sequence was skipped): the Run Summary (04 §7, the win).
func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	_set_phase(PHASE_DONE)
	SceneRouter.change_to(SUMMARY_SCENE)


## Skips to the summary. Refused on the first viewing.
func skip() -> bool:
	if not skippable or _leaving:
		return false
	_finish()
	return true


## The variant's DESCEND (01 §8): the next Descent, with the last run's loadout when it is
## still available, without the title.
func descend() -> void:
	if _leaving:
		return
	_leaving = true
	_set_phase(PHASE_DONE)
	var loadout: StringName = GameState.run.loadout if GameState.run != null else &"faller"
	if not GameState.is_loadout_available(loadout):
		loadout = &"faller"
	GameState.start_run(Tuning.MODE_DESCENT, loadout, Run.new_seed())
	SceneRouter.change_to(RUN_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not skippable or _leaving or not event.is_action_pressed(SKIP_ACTION):
		return
	get_viewport().set_input_as_handled()
	if _skip_left > 0.0:
		skip()
	else:
		_skip_left = Tuning.ENDING_SKIP_CONFIRM_TIME
		skip_label.visible = true


## The variant's DESCEND line answers the player's aim: the cursor shows while it is targeted.
func _on_prompt_changed(text: String, _hold: float) -> void:
	var l := corridor.descend_label
	if l == null:
		return
	var aimed := text == Strings.MENU_DESCEND
	l.text = Strings.MENU_SELECTED_PREFIX + Strings.MENU_DESCEND + (Strings.MENU_CURSOR if aimed else "")
