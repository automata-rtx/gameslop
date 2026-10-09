class_name HudGalleryStates
extends RefCounted
## The HUD states of the debug gallery (04 §11: every HUD state for screenshot review).
## Each state drives a fresh HUD through a HudFakePlayer and the EventBus exactly as play
## would, then steps time by hand to the moment worth looking at. Debug-only text.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

const STATES: Array[StringName] = [
	&"full", &"low_coherence", &"coherence_gain", &"noclip_charging", &"noclip_floor_ready",
	&"invalid", &"stunned", &"prompt_hold", &"notification_typing", &"hidden", &"cranking_low",
	&"substrate_sealed", &"note_faller", &"note_builder", &"note_stray",
	&"colorblind", &"captions_stack", &"first_run_hint", &"belt_live", &"note_captions",
]


## A stand-in world behind the HUD: a dim Halls-like corridor with one bright fixture, so
## contrast can be judged against both dark and lit areas.
class Backdrop extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color("#2a2618"))
		var c := Vector2(w * 0.5, h * 0.48)
		var far := Vector2(w * 0.09, h * 0.12)
		# Ceiling, floor and the two walls converging on a far doorway.
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), c + Vector2(far.x, -far.y), c + Vector2(-far.x, -far.y)]), Color("#4a4430"))
		draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(w, h), c + Vector2(far.x, far.y), c + Vector2(-far.x, far.y)]), Color("#3b3423"))
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), c + Vector2(-far.x, -far.y), c + Vector2(-far.x, far.y), Vector2(0, h)]), Color("#6b6142"))
		draw_colored_polygon(PackedVector2Array([Vector2(w, 0), c + Vector2(far.x, -far.y), c + Vector2(far.x, far.y), Vector2(w, h)]), Color("#5c5338"))
		draw_rect(Rect2(c - far, far * 2.0), Color("#151309"))
		# A lit fixture overhead (the brightest thing behind the top readouts).
		draw_rect(Rect2(w * 0.38, h * 0.06, w * 0.24, h * 0.03), Color("#fff2c4"))
		draw_rect(Rect2(w * 0.7, h * 0.16, w * 0.12, h * 0.02), Color("#e8d9a8"))


## Builds backdrop + HUD + fake player under `parent` and applies `state`.
static func build(parent: Control, state: StringName) -> Hud:
	UiMotion.manual_clock = true
	parent.add_child(Backdrop.new())
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	# The gallery never touches the player's meta.json or settings; hints only in their state.
	parent.add_child(hud)
	hud.hints.persist = false
	hud.hints.world_sense = func() -> Dictionary: return {}
	hud.hints.logic.shown.clear()
	hud.hints.logic.set_enabled(state == &"first_run_hint")
	UiAccessibility.apply_colorblind(state == &"colorblind" or bool(SettingsManager.get_value(&"colorblind_accent")))
	var fake := HudFakePlayer.new()
	hud.add_child(fake)
	hud.bind_player(fake)
	_baseline(hud, fake)
	apply(state, hud, fake)
	return hud


static func _baseline(hud: Hud, fake: HudFakePlayer) -> void:
	fake.reset()
	hud.set_depth(3, &"garage")
	hud.set_exit_status(&"unknown", 0.0)
	fake.charge_changed.emit(62.0)
	fake.flashlight_toggled.emit(true)
	hud.set_items([{"kind": &"polaroid", "count": 2}, {"kind": &"glowstick", "count": 1}, {"kind": &"chalk", "count": 8}, null], 0)
	_step(hud, 0.5)


static func apply(state: StringName, hud: Hud, fake: HudFakePlayer) -> void:
	match state:
		&"full":
			fake.flashlight_toggled.emit(false)
			fake.charge_changed.emit(100.0)
			hud.set_items([], -1)
		&"low_coherence":
			fake.set_coherence(52.0, &"still")
			_step(hud, 2.0)
			hud.set_exit_status(&"powered", 0.0)
			fake.set_coherence(17.0, &"still")
			fake.stamina_changed.emit(35.0)
			_step(hud, 0.35)
		&"coherence_gain":
			fake.set_coherence(48.0, &"still")
			_step(hud, 2.0)
			fake.set_coherence(73.0, &"polaroid")
			_step(hud, 0.1)
		&"noclip_charging":
			fake.noclip_state.emit(0.55, &"wall", true, &"")
			_step(hud, 0.2)
		&"noclip_floor_ready":
			fake.set_coherence(64.0, &"still")
			_step(hud, 2.0)
			fake.noclip_state.emit(0.97, &"floor", true, &"")
			_step(hud, 0.2)
		&"invalid":
			fake.noclip_state.emit(0.0, &"wall", false, Tuning.NOCLIP_REASON_SOLID)
			_step(hud, 0.2)
		&"stunned":
			fake.set_coherence(65.0, &"still")
			fake.stun_changed.emit(true)
			_step(hud, 0.3)
		&"prompt_hold":
			fake.prompt_changed.emit(Strings.PROMPT_FLIP_BREAKER, 0.6)
			fake.prompt_progress.emit(0.55)
			_step(hud, 0.2)
		&"notification_typing":
			fake.prompt_changed.emit(Strings.PROMPT_PICK_UP.replace("{item}", "POLAROID"), 0.0)
			hud.notify(Strings.MSG_ARCHIVE_NOTE.replace("{id}", "G2"))
			_step(hud, 0.6)
			EventBus.unlock_earned.emit(&"radio")
			_step(hud, 0.15)
		&"hidden":
			fake.hidden_changed.emit(true)
			fake.prompt_changed.emit(Strings.PROMPT_LEAVE, 0.6)
			_step(hud, 0.3)
		&"cranking_low":
			fake.charge_changed.emit(12.0)
			fake.crank_changed.emit(true)
			fake.sprint_changed.emit(true)
			fake.stamina_exhausted.emit()
			fake.stamina_changed.emit(0.0)
			_step(hud, 0.45)
		&"substrate_sealed":
			EventBus.level_entered.emit(6, &"substrate", &"proper")
			hud.set_exit_status(&"sealed", 134.0)
			hud.caption(Strings.CAPTION_NULL.replace("{dir}", "ahead").replace("{dist}", Strings.CAPTION_DIST_FAR))
			_step(hud, 0.3)
		&"note_faller":
			EventBus.note_found.emit(&"H3")
			_step(hud, 0.9)
		&"note_builder":
			hud.show_note(DataRegistry.note(&"H4"))
			_step(hud, 5.0)
		&"captions_stack":
			fake.prompt_changed.emit(Strings.PROMPT_OPEN_DOOR, 0.0)
			var l := Transform3D.IDENTITY
			for c: Array in [[Strings.CAPTION_DOOR_SLAM, Vector3(-30, 0, 5)], [Strings.CAPTION_STATIC, Vector3(4, 0, -2)],
					[Strings.CAPTION_ECHO_FOOTSTEP, Vector3(0, 0, 4)]]:
				hud.caption(AudioMix.format_caption(c[0], l, c[1]))
				_step(hud, 0.3)
			hud.caption(Strings.CAPTION_STILL_SILENCE)
			_step(hud, 0.3)
		&"first_run_hint":
			hud.hints.logic.shown = [FirstRunHints.MOVE] as Array[StringName]
			hud.hints.set_charge(40.0)
			EventBus.level_entered.emit(2, &"pools", &"proper")
			_step(hud, 0.4)
		&"belt_live":
			hud.set_keycard(true)
			hud.set_items([ItemSlot.new(&"flare", 2, {FlareItem.BURN: 31.2}),
					ItemSlot.new(&"radio", 1, {RadioItem.ON: true}), ItemSlot.new(&"chalk", 6), null], 0)
			_step(hud, 0.4)
		&"colorblind":
			fake.set_coherence(52.0, &"still")
			_step(hud, 2.0)
			fake.set_coherence(18.0, &"still")
			hud.repaint()
			fake.noclip_state.emit(0.6, &"wall", true, &"")
			EventBus.unlock_earned.emit(&"radio")
			_step(hud, 0.6)
		&"note_captions":
			# M3.6: a note sheet and three captions at once; the stack ends above the sheet.
			hud.show_note(DataRegistry.note(&"H1"))
			var l := Transform3D.IDENTITY
			for c: Array in [[Strings.CAPTION_STATIC, Vector3(-4, 0, 0)], [Strings.CAPTION_ECHO_FOOTSTEP, Vector3(0, 0, 4)]]:
				hud.caption(AudioMix.format_caption(c[0], l, c[1]))
				_step(hud, 0.2)
			hud.caption(Strings.CAPTION_STILL_SILENCE)
			_step(hud, 1.0)
		&"note_stray":
			var stray: NoteData = null
			for n in DataRegistry.notes():
				if n.voice == &"stray":
					stray = n
					break
			hud.show_note(stray)
			_step(hud, 5.0)


static func _step(hud: Hud, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		var dt := minf(1.0 / 60.0, seconds - t)
		UiMotion.step(hud, dt)
		t += dt
