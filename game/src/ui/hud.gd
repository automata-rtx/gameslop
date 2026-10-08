class_name Hud
extends Control
## The in-play readout (04 §6): what the world prints about the player. Sparse; animates
## only to show a value changing. PROCESS_MODE_ALWAYS so it keeps moving through hitstop
## and the pause (11 §4). Calls down only: the run binds it to the Player with
## bind_player() (signals up), to the Inventory with bind_inventory(), and it listens to
## EventBus for level, exit, note and unlock events. It never reaches into the player.
## Parts: HudCoherence, HudDepth, HudNotifications, HudPrompt (prompt and caption),
## HudCrank, HudBelt, HudCrosshair, NoteSheet; all motion is UiShutter / UiTypedLabel.

const HIDDEN_ALPHA := Tuning.HIDE_HUD_DIM
const LOCKED_STATUSES: Array[StringName] = [&"powered", &"keyed", &"sealed"]
const SOURCE_RESET := &"reset"
## A noclip pass that fell back returns its cost: not a gain, the numeral snaps back.
const SOURCE_NOCLIP_REFUND := &"noclip_refund"
const ARRIVAL_DROP := &"drop"
## Unlock ids by message kind (05 §6, Strings.MSG_*).
const ITEM_UNLOCKS: Array[StringName] = [&"glowstick", &"radio", &"flare", &"fuse"]
const LOADOUT_UNLOCKS: Array[StringName] = [&"cartographer", &"lightbearer", &"diver"]
const MODE_UNLOCKS: Array[StringName] = [&"daily", &"endless"]
## Player signals the HUD reads (06 Interfaces and its production additions).
const PLAYER_SIGNALS: Array[StringName] = [
	&"coherence_changed", &"stamina_changed", &"stamina_exhausted", &"sprint_changed",
	&"charge_changed", &"flashlight_toggled", &"crank_changed", &"noclip_state",
	&"stun_changed", &"hidden_changed", &"prompt_changed", &"prompt_progress", &"dissolved",
]

var player: Node = null
var inventory: Node = null
var hidden_state: bool = false
## 12 §6 HUD option: &"full", &"minimal", &"off".
var hud_mode: StringName = &"full"

var _dim_from: float = 1.0
var _dim_to: float = 1.0
var _dim_t: float = INF
var _dissolve_t: float = -1.0
## True from the dissolve shutter until restore() (11 §3).
var dissolved_state: bool = false

@onready var frame: Control = %Frame
@onready var coherence_shutter: UiShutter = %CoherenceShutter
@onready var crank_shutter: UiShutter = %CrankShutter
@onready var belt_shutter: UiShutter = %BeltShutter
@onready var dimmable: Control = %Dimmable
@onready var coherence: HudCoherence = %Coherence
@onready var depth: HudDepth = %Depth
@onready var notifications: HudNotifications = %Notifications
@onready var prompt: HudPrompt = %Prompt
@onready var caption_line: HudPrompt = %Caption
@onready var crank: HudCrank = %Crank
@onready var belt: HudBelt = %Belt
@onready var crosshair: HudCrosshair = %Crosshair
@onready var note_sheet: NoteSheet = %NoteSheet


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s: UiShutter in _frame_shutters():
		s.show_now(true)
	EventBus.level_entered.connect(_on_level_entered)
	EventBus.level_left.connect(_on_level_left)
	EventBus.exit_status_changed.connect(set_exit_status)
	EventBus.note_found.connect(_on_note_found)
	EventBus.unlock_earned.connect(_on_unlock_earned)
	EventBus.threat_changed.connect(_on_threat_changed)
	SettingsManager.changed.connect(_on_setting_changed)
	for key: StringName in [&"hud_mode", &"crosshair", &"show_depth", &"show_exit_status"]:
		_on_setting_changed(key, SettingsManager.get_value(key))


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


## Own timers only: every part advances itself (UiMotion.step drives the whole tree).
func advance(dt: float) -> void:
	if _dim_t < INF:
		_dim_t += dt
		dimmable.modulate.a = UiMotion.value_tween(_dim_from, _dim_to, _dim_t)
		if _dim_t >= UiTokens.VALUE_TWEEN_S:
			_dim_t = INF
	if _dissolve_t >= 0.0:
		_dissolve_t += dt
		if _dissolve_t >= Tuning.FEEDBACK_DISSOLVE_HUD_SHUTTER:
			_dissolve_t = -1.0
			_shutter_all_out()


# --- binding ------------------------------------------------------------------------------

## Subscribes to a Player's readout signals (06 Interfaces). Any node with the same signals
## works (the gallery's fake player). Rebinding drops the previous player.
func bind_player(p: Node) -> void:
	unbind_player()
	player = p
	if p == null:
		return
	for sig in PLAYER_SIGNALS:
		if p.has_signal(sig):
			p.connect(sig, Callable(self, "_on_" + String(sig)))
	var c: Variant = p.get(&"coherence")
	if c is float or c is int:
		set_coherence(float(c), 0.0)


func unbind_player() -> void:
	if player == null or not is_instance_valid(player):
		player = null
		return
	for sig in PLAYER_SIGNALS:
		var cb := Callable(self, "_on_" + String(sig))
		if player.has_signal(sig) and player.is_connected(sig, cb):
			player.disconnect(sig, cb)
	player = null


## Subscribes to the belt (09 Interfaces: Inventory signal changed(slots, selected)).
func bind_inventory(inv: Node) -> void:
	if inventory != null and is_instance_valid(inventory) and inventory.is_connected(&"changed", set_items):
		inventory.disconnect(&"changed", set_items)
	inventory = inv
	if inv == null:
		set_items([], -1)
		return
	if inv.has_signal(&"changed"):
		inv.connect(&"changed", set_items)
	var slots: Variant = inv.get(&"slots")
	var sel: Variant = inv.get(&"selected")
	set_items(slots if slots is Array else [], int(sel) if sel is int else -1)


# --- 04 Interfaces ----------------------------------------------------------------------

func set_coherence(v: float, delta: float) -> void:
	coherence.set_value(v, delta)


func set_depth(d: int, stratum: StringName) -> void:
	depth.set_depth(d, stratum)


func set_exit_status(status: StringName, timer: float) -> void:
	var before := depth.set_exit_status(status, timer)
	if before in LOCKED_STATUSES and status == HudDepth.STATUS_OPEN:
		notify(Strings.MSG_EXIT_UNLOCKED)


func set_stamina(v: float) -> void:
	crosshair.set_stamina(v)


func set_crank(v: float) -> void:
	crank.set_charge(v)


func set_noclip(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	crosshair.set_noclip(charge, target, valid, reason)


## `text` is the interactable's words; `hold_time` > 0 makes it a hold prompt (additive to
## the 04 signature, which the Player's prompt_changed(text, hold_time) carries).
func show_prompt(text: String, hold_time: float = 0.0) -> void:
	if text.is_empty():
		hide_prompt()
		return
	prompt.show_text(text, hold_time)
	crosshair.set_target(true)


## 04 §6: a dim, keyless notice in the prompt position (`FUSE MISSING`). Not an action, so
## the crosshair does not take the target state.
func show_notice_prompt(text: String) -> void:
	if text.is_empty():
		hide_prompt()
		return
	prompt.show_notice(text)
	crosshair.set_target(false)


func hide_prompt() -> void:
	prompt.hide_text()
	crosshair.set_target(false)


func set_items(slots: Array, selected: int) -> void:
	belt.set_items(slots, selected)


func notify(text: String, color: Color = UiTokens.UI_DIM) -> void:
	notifications.notify(text, color)


func show_note(note: NoteData) -> void:
	note_sheet.show_note(note)


## 04 §6 hidden state: everything but the crosshair dims to 40%; the crosshair is the eye.
func set_hidden(on: bool) -> void:
	hidden_state = on
	crosshair.set_hidden(on)
	_dim_from = dimmable.modulate.a
	_dim_to = HIDDEN_ALPHA if on else 1.0
	_dim_t = 0.0


## 04 §8 captions: bottom-centre above the prompt, ui_fg on 60% black. Empty clears.
## Timing and the captions setting belong to the captions task (M2.12).
func caption(text: String) -> void:
	if text.is_empty():
		caption_line.hide_text()
		return
	var segs: Array[Dictionary] = [{UiKeys.TEXT: text, UiKeys.KEY: false}]
	caption_line.set_segments(segs)


## Shows the whole readout again (a new Descent, a new level).
func restore() -> void:
	_dissolve_t = -1.0
	if not dissolved_state:
		return
	dissolved_state = false
	crosshair.visible = true
	for s: UiShutter in _frame_shutters():
		s.shutter_in()
	if depth.depth > 0:
		depth.depth_shutter.shutter_in()
		depth.exit_shutter.shutter_in()
	_apply_visibility()


## The always-present readouts, each behind its own shutter (shutters do not nest: a
## clip parent inside another clip parent is not supported by the renderer).
func _frame_shutters() -> Array[UiShutter]:
	return [coherence_shutter, crank_shutter, belt_shutter]


## 11 §3 dissolve: every element leaves by its shutter; the crosshair goes with them.
func _shutter_all_out() -> void:
	dissolved_state = true
	for s: UiShutter in _frame_shutters():
		s.shutter_out()
	depth.depth_shutter.shutter_out()
	depth.exit_shutter.shutter_out()
	prompt.hide_text()
	caption_line.hide_text()
	note_sheet.shutter_out()
	notifications.clear()
	crosshair.stamina_shutter.shutter_out()
	crosshair.noclip_shutter.shutter_out()
	crosshair.reason_shutter.shutter_out()
	crosshair.visible = false


# --- player signals ---------------------------------------------------------------------

func _on_coherence_changed(value: float, delta: float, source: StringName) -> void:
	if source == SOURCE_RESET:
		restore()
		delta = 0.0
	set_coherence(value, 0.0 if source == SOURCE_NOCLIP_REFUND else delta)


func _on_stamina_changed(value: float) -> void:
	set_stamina(value)


func _on_stamina_exhausted() -> void:
	crosshair.stamina_exhausted()


func _on_sprint_changed(on: bool) -> void:
	crosshair.set_sprinting(on)


func _on_charge_changed(value: float) -> void:
	set_crank(value)


func _on_flashlight_toggled(on: bool) -> void:
	crank.set_light(on)


func _on_crank_changed(turning: bool) -> void:
	crank.set_turning(turning)


func _on_noclip_state(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	set_noclip(charge, target, valid, reason)


func _on_stun_changed(on: bool) -> void:
	crosshair.set_stunned(on)


func _on_hidden_changed(on: bool) -> void:
	set_hidden(on)


func _on_prompt_changed(text: String, hold_time: float) -> void:
	if Strings.NOTICE_PROMPTS.has(text):
		show_notice_prompt(text)
	else:
		show_prompt(text, hold_time)


func _on_prompt_progress(fraction: float) -> void:
	prompt.set_progress(fraction)


## 11 §3 dissolve: the HUD shutters out 0.5 s into the sequence.
func _on_dissolved(_cause: StringName) -> void:
	_dissolve_t = 0.0
	# 04 §6: the numeral snaps to the target (000) rather than walking down under the dissolve.
	coherence.snap()


# --- EventBus -----------------------------------------------------------------------------

func _on_level_entered(d: int, stratum: StringName, arrival: StringName) -> void:
	restore()
	set_depth(d, stratum)
	depth.set_exit_status(HudDepth.STATUS_UNKNOWN, 0.0)
	if arrival == ARRIVAL_DROP:
		notify(Strings.MSG_DROPPED)


func _on_level_left(proper: bool) -> void:
	if proper:
		notify(Strings.MSG_DESCENDING)
	# 05 §4: the cabin has no exit; the status line shutters out until the next level.
	depth.clear_exit_status()


func _on_note_found(id: StringName) -> void:
	var n := DataRegistry.note(id)
	if n != null:
		show_note(n)
	notify(Strings.MSG_ARCHIVE_NOTE.replace("{id}", String(id)))


## 11 §3 Unlock earned: the unlock chime and the notification in ui_accent.
func _on_unlock_earned(id: StringName) -> void:
	AudioManager.play_2d(&"ui_unlock")
	notify(unlock_message(id), UiTokens.accent())


func _on_threat_changed(threat: float) -> void:
	coherence.threat = threat


static func unlock_message(id: StringName) -> String:
	var name_text := String(Strings.UNLOCK_NAMES.get(id, String(id).to_upper()))
	if id in ITEM_UNLOCKS:
		return Strings.MSG_ITEM_UNLOCKED.replace("{name}", name_text)
	if id in LOADOUT_UNLOCKS:
		return Strings.MSG_LOADOUT_UNLOCKED.replace("{name}", name_text)
	if id in MODE_UNLOCKS:
		return Strings.MSG_MODE_UNLOCKED.replace("{name}", name_text)
	return Strings.MSG_ARCHIVE_UNLOCKED.replace("{name}", name_text)


# --- settings (12 §6, §7) -------------------------------------------------------------------

func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"hud_mode":
			hud_mode = StringName(value) if value is String or value is StringName else &"full"
			_apply_visibility()
		&"crosshair":
			crosshair.style = StringName(value) if value is String or value is StringName else &"dot_ring"
			crosshair.queue_redraw()
		&"show_depth", &"show_exit_status":
			_apply_visibility()


## 12 §6: Minimal keeps Coherence, prompts and captions; Off keeps the Coherence bar only.
## 12 §7: the depth line and the exit status line can be turned off.
func _apply_visibility() -> void:
	var full := hud_mode == &"full"
	var minimal := hud_mode == &"minimal"
	depth.visible = full and _setting_on(&"show_depth")
	depth.set_exit_line_enabled(_setting_on(&"show_exit_status"))
	notifications.visible = full
	crank_shutter.visible = full and crank_shutter.is_shown()
	belt_shutter.visible = full and belt_shutter.is_shown()
	prompt.visible = full or minimal
	caption_line.visible = full or minimal


func _setting_on(key: StringName) -> bool:
	var v: Variant = SettingsManager.get_value(key)
	return not (v is bool) or bool(v)
