class_name Player
extends CharacterBody3D
## The player (06). A capsule with eyes and no visible body: move, look, light, interact,
## noclip (M1.4 seam), use item (M1.10 seam). Owns Coherence (the only health), stun,
## hiding and death; locomotion and stamina live in PlayerLocomotion. Every action
## implements its Feedback Contract row (11 §2-§3) through the CameraRig (motion),
## CoherenceRenderer (image), AudioManager (sound) and the signals the HUD reads.
## Components (%UniqueName): StateMachine, CameraRig, Flashlight, Interactor, Collision.

# 06 Interfaces
signal coherence_changed(value: float, delta: float, source: StringName)
signal stamina_changed(value: float)
signal charge_changed(value: float)
signal noclip_state(charge: float, target: StringName, valid: bool, reason: StringName)
signal contacted(by: StringName)
signal dissolved(cause: StringName)
signal hidden_changed(on: bool)
# Proposed additions: HUD readouts the 06 list does not carry (see the M1.3 report).
signal state_changed(from: StringName, to: StringName)
signal sprint_changed(on: bool)
signal stamina_exhausted
signal stun_changed(on: bool)
signal flashlight_toggled(on: bool)
signal crank_changed(turning: bool)
signal prompt_changed(text: String, hold_time: float)
signal prompt_progress(fraction: float)
## M1.4 (06 Interfaces): a pass or drop committed (`to` = `from` for a drop); the floor
## drop hook the run flow consumes (it calls GameState.descend(false)). See NoclipTargeting.
signal noclip_committed(target: StringName, from: Vector3, to: Vector3)
signal floor_drop_committed

const SETTING_SENSITIVITY := &"mouse_sensitivity"
const SETTING_INVERT_Y := &"invert_y"
const CAUSE_SUBSTRATE := &"substrate"
const SOURCE_UNKNOWN_ERROR := &"error"
## A wall pass that ended back at its start returns its cost under this source (no gain
## feedback; the HUD snaps the numeral back).
const SOURCE_NOCLIP_REFUND := &"noclip_refund"
## States in which Coherence cannot fall (the drop's fall and the Landing cabin).
const NO_LOSS_STATES: Array[StringName] = [PlayerStateMachine.DROPPING, PlayerStateMachine.LANDING]
## 11 §3 dissolve: the camera drifts 0.02 m (down) over the 1.5 s sequence.
const DISSOLVE_DRIFT_DIR := Vector3.DOWN
## States in which the player has no legs of their own: entering one halts locomotion
## (sprint ends with its FOV hold and breath loop). Stunned keeps crouch-speed movement.
const HALT_STATES: Array[StringName] = [
	PlayerStateMachine.STUNNED, PlayerStateMachine.HIDDEN, PlayerStateMachine.NOCLIP_PASS,
	PlayerStateMachine.LANDING, PlayerStateMachine.DROPPING, PlayerStateMachine.DISSOLVING,
	PlayerStateMachine.CINEMATIC,
]

@onready var state_machine: PlayerStateMachine = %StateMachine
@onready var rig: CameraRig = %CameraRig
@onready var flashlight: Flashlight = %Flashlight
@onready var interactor: Interactor = %Interactor
## The belt (09): select by keys and wheel, use_item uses the selected kind. Routed below.
@onready var inventory: Inventory = %Inventory
@onready var collision: CollisionShape3D = %Collision

## M1.4 seam: a NoclipTargeting component with physics_update(player, held, delta),
## cancel() and reset(). It calls begin_noclip_charge / end_noclip_charge / report_noclip.
@export var noclip_targeting: Node
## Floor surface when the floor collider has no `surface` meta (the stratum's floor).
@export var default_surface: StringName = NoiseModel.DEFAULT_SURFACE

var coherence: float = Tuning.COHERENCE_MAX
var input := PlayerInput.new()
var locomotion: PlayerLocomotion
var hiding: PlayerHiding
## Sound for every Feedback Contract row (one-shots and loop handles; 03 Interfaces).
var sounds: PlayerAudio
## Flashlight and crank wiring (06 §5, 11 §2).
var light: PlayerLight
## Contact exclusivity hook (10 §4): the Director sets this to its try_contact,
## (error: Node3D) -> bool. Asked only after the player's own state allows a contact.
var contact_gate: Callable
## Water depth under the player (Pools): > 0 steps in water, > 0.3 m wading (06 §3).
var water_depth: float = 0.0

var _stun_left: float = 0.0
var _last_damage_source: StringName = &""
## M3.4: recent death-cause losses [physics frame, source, amount] within DEATH_CAUSE_WINDOW.
var _recent_losses: Array = []
var _light_queries: Array[Callable] = []


func _init() -> void:
	locomotion = PlayerLocomotion.new(self)
	hiding = PlayerHiding.new(self)
	sounds = PlayerAudio.new()
	light = PlayerLight.new(self)


func _ready() -> void:
	add_to_group(&"gameplay")
	collision_layer = PlayerLayers.PLAYER_MASK
	collision_mask = PlayerLayers.WORLD_MASK
	floor_snap_length = Tuning.PLAYER_STEP_HEIGHT
	floor_max_angle = deg_to_rad(Tuning.PLAYER_FLOOR_MAX_ANGLE)
	locomotion.setup()
	interactor.camera = rig.camera
	interactor.body = self
	locomotion.stamina.changed.connect(func(v: float) -> void: stamina_changed.emit(v))
	locomotion.stamina_exhausted.connect(func() -> void: stamina_exhausted.emit())
	locomotion.sprint_changed.connect(func(on: bool) -> void: sprint_changed.emit(on))
	light.setup()
	interactor.prompt_changed.connect(func(t: String, h: float) -> void: prompt_changed.emit(t, h))
	interactor.prompt_progress.connect(func(f: float) -> void: prompt_progress.emit(f))
	interactor.hold_tick.connect(func() -> void: sounds.play(&"ui_hold_tick"))
	interactor.interacted.connect(func(_t: Interactable) -> void: rig.nod(Tuning.FEEDBACK_INTERACT_NOD_DEG))
	state_machine.state_changed.connect(_on_state_changed)
	_feed_coherence()


## A new Descent re-uses the persistent player (14 §5): full meters, Idle, light off.
func reset_for_run(start_coherence: float = Tuning.COHERENCE_MAX) -> void:
	coherence = clampf(start_coherence, 0.0, Tuning.COHERENCE_MAX)
	_last_damage_source = &""
	_recent_losses = []
	_stun_left = 0.0
	locomotion.reset()
	light.reset()  # silent: a new run is not a toggle
	sounds.reset()
	rig.fov_hold(0.0, 0.0, CameraRig.HOLD_SPRINT)
	rig.fov_hold(0.0, 0.0, CameraRig.HOLD_NOCLIP)
	if noclip_targeting != null and noclip_targeting.has_method(&"reset"):
		noclip_targeting.call(&"reset")
	state_machine.reset()
	inventory.reset()
	_feed_coherence()
	coherence_changed.emit(coherence, 0.0, &"reset")


# --- 06 Interfaces ----------------------------------------------------------------------

func eye_position() -> Vector3:
	return rig.camera.global_position


func is_hidden() -> bool:
	return hiding.is_hidden()


## True when a hide spot may take the player now (the state machine can enter Hidden).
func can_hide() -> bool:
	return hiding.spot == null and state_machine.can_transition(PlayerStateMachine.HIDDEN)


## 08 Interfaces (Echo): every step event, oldest first, as a RingBuffer of
## {position: Vector3, time: float (s, Time ticks), surface: StringName, speed_kind:
## StringName (walk / sprint / crouch)}.
func step_trail() -> RingBuffer:
	return locomotion.trail


func is_stunned() -> bool:
	return state_machine.is_in(PlayerStateMachine.STUNNED)


func is_dissolving() -> bool:
	return state_machine.is_in(PlayerStateMachine.DISSOLVING)


## 08 §4: frustum, <= 30 m, unoccluded, lit. See PlayerObservation.
func is_observing(node: Node3D) -> bool:
	if is_dissolving():
		return false
	return PlayerObservation.is_observing(rig.camera, node, flashlight.on, flashlight.beam_origin(),
			flashlight.beam_axis(), _light_queries, [get_rid()])


## Lights other than the flashlight register here: (pos: Vector3) -> bool. LightPool
## (powered fixtures' ranges), glowsticks (4 m) and burning flares (8 m). 08 §4.
func add_light_query(query: Callable) -> void:
	if not _light_queries.has(query):
		_light_queries.append(query)


func remove_light_query(query: Callable) -> void:
	_light_queries.erase(query)


## Coherence feeds the renderer (image) and the audio bed/heartbeat floor (sound).
func _feed_coherence() -> void:
	CoherenceRenderer.set_coherence(coherence)
	AudioManager.set_coherence(coherence)


func _exit_tree() -> void:
	sounds.release_all()


## 06 §9: the only way Coherence changes. Clamped 0..100; no passive regeneration.
## Coherence cannot fall during a drop or the Landing (noclip review): the player has no
## body in the level then, so losses are ignored. SOURCE_NOCLIP_REFUND (a pass that fell
## back to its start) restores the cost without the gain feedback: it is not a gain.
func apply_coherence(delta: float, source: StringName) -> void:
	if is_dissolving() or is_zero_approx(delta):
		return
	if delta < 0.0 and state_machine.state in NO_LOSS_STATES:
		return
	var before := coherence
	coherence = clampf(coherence + delta, 0.0, Tuning.COHERENCE_MAX)
	# A slow drain (0.2/s, R15) leaves float residue near 0; a loss that reaches it is 0.
	if delta < 0.0 and is_zero_approx(coherence):
		coherence = 0.0
	var applied := coherence - before
	if is_zero_approx(applied) and coherence > 0.0:
		return
	if applied < 0.0 and is_death_cause(source):
		_last_damage_source = _frame_cause(source, -applied)
	_feed_coherence()
	coherence_changed.emit(coherence, applied, source)
	if applied < 0.0:
		# 11 §3 Coherence loss (any source): the loss tick per unit lost, rate-limited.
		sounds.add_loss(-applied)
	if applied > 0.0 and source != SOURCE_NOCLIP_REFUND:
		# 11 §3 Coherence gain: saturation overshoot, warm chord, FOV +2 then back 400 ms.
		CoherenceRenderer.pulse(&"coherence_gain")
		sounds.play(&"coherence_gain")
		rig.fov_punch(Tuning.FEEDBACK_GAIN_FOV_DEG, Tuning.FEEDBACK_FOV_TWEEN_MIN_MS, Tuning.FEEDBACK_GAIN_FOV_MS)
	elif coherence <= 0.0:
		_dissolve(death_cause(source))


## Whole Coherence loss ticks still to play (11 §3).
func loss_ticks_pending() -> int:
	return sounds.loss_ticks_pending()


## M3.4 (06 §9 reading): the death-cause source that took the most within the last
## DEATH_CAUSE_WINDOW (physics frames), counting `amount` just lost to `source`. Drains that
## overlap (Null's core and a Static field) are one moment, so the order the errors process in
## within a frame no longer picks the cause.
func _frame_cause(source: StringName, amount: float) -> StringName:
	var now := Engine.get_physics_frames()
	var window := roundi(Tuning.DEATH_CAUSE_WINDOW * Engine.physics_ticks_per_second)
	while not _recent_losses.is_empty() and now - int(_recent_losses[0][0]) >= window:
		_recent_losses.pop_front()
	_recent_losses.append([now, source, amount])
	var sums := {}
	for e: Array in _recent_losses:
		sums[e[1]] = float(sums.get(e[1], 0.0)) + float(e[2])
	var best := source
	for k: StringName in sums:
		if float(sums[k]) > float(sums[best]):
			best = k
	return best


## 06 §9: an error id or the Substrate. Noclip is never a cause (06 §8 TOO THIN).
static func is_death_cause(source: StringName) -> bool:
	return source in Tuning.ERROR_IDS or source == CAUSE_SUBSTRATE


func death_cause(source: StringName) -> StringName:
	if _last_damage_source != &"":
		return _last_damage_source
	return source


## 06 §9 contact rules (PlayerContact): cost (at most COHERENCE_MAX_SINGLE_HIT), 1.2 s
## stun, 1.5 m push, trauma 0.6, 60 ms hitstop. Refused (false, nothing applied) when the
## player has no body to touch; `contact_gate` (the Director, 10 §4) may refuse too.
func contact(error: Node3D, amount: float) -> bool:
	return PlayerContact.contact(self, error, amount)


## The player's own refusals only (06 Interfaces readings): no contact during the noclip
## pass, the Landing, a drop, the dissolve or the ending.
func can_be_contacted() -> bool:
	var s := state_machine.state
	return PlayerStateMachine.is_locomotion(s) or s in [
		PlayerStateMachine.NOCLIP_CHARGE, PlayerStateMachine.STUNNED, PlayerStateMachine.HIDDEN]


func _dissolve(cause: StringName) -> void:
	PlayerContact.dissolve(self, cause)


# --- input ------------------------------------------------------------------------------

## True while the player controls the body (not dissolving, dropping, passing, landing, hidden).
func has_agency() -> bool:
	return state_machine.has_movement()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look((event as InputEventMouseMotion).relative)


## Mouse look (06 §3): yaw unbounded on the body, pitch +-89 on the rig; inside a hide
## spot both stay within the spot's limit (06 §10). The Landing cabin camera is free (05 §4):
## look works there, movement does not.
func look(relative: Vector2) -> void:
	var sens: Variant = SettingsManager.get_value(SETTING_SENSITIVITY)
	var s := float(sens) if sens is float or sens is int else Tuning.PLAYER_MOUSE_SENS_DEFAULT
	var invert: Variant = SettingsManager.get_value(SETTING_INVERT_Y)
	var dyaw := -CameraRig.mouse_to_radians(relative.x, s)
	var dpitch := -CameraRig.mouse_to_radians(relative.y, s) * (-1.0 if invert is bool and invert else 1.0)
	if is_hidden():
		rig.anchored_look(dyaw, dpitch, hiding.spot.yaw_limit_deg)
	elif (has_agency() or state_machine.is_in(PlayerStateMachine.LANDING)) and not rig.is_anchored():
		rotate_y(dyaw)
		rig.add_pitch(dpitch)


# --- physics frame --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var hidden := hiding.spot != null
	input.poll(not (has_agency() or hidden))
	tick_timers(delta)
	light.physics_update(delta)
	# 09: use_item acts on the selected belt kind (not while cranking or without agency).
	inventory.feed_use(input.use_item_pressed, input.use_item_held, delta, can_use_item())
	if hidden:
		interactor.physics_update(self, input.interact_held, input.interact_pressed, delta, hiding.is_hidden())
	elif not has_agency():
		velocity = Vector3.ZERO
		interactor.physics_update(self, false, false, delta, false)
	else:
		if noclip_targeting != null and noclip_targeting.has_method(&"physics_update"):
			noclip_targeting.call(&"physics_update", self, input.noclip and can_noclip(), delta)
		locomotion.physics_update(delta)
		interactor.physics_update(self, input.interact_held, input.interact_pressed, delta, true)
	# 06 §4: stamina ticks every frame (regeneration continues while hidden or passing).
	locomotion.end_frame(delta)


## Countdown timers (stun, bob cut, loss ticks). Public so tests can step time.
func tick_timers(dt: float) -> void:
	sounds.tick(dt)
	if _stun_left > 0.0:
		_stun_left -= dt
		if _stun_left <= 0.0:
			_stun_left = 0.0
			if is_stunned():
				state_machine.transition_to(PlayerStateMachine.IDLE)
			stun_changed.emit(false)
	locomotion.tick_timers(dt)


## Speed capped to crouch speed: cranking, charging noclip, stunned (06 §3, §9).
func is_speed_capped() -> bool:
	return flashlight.is_cranking() or is_stunned() or state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE)


func is_wading() -> bool:
	return water_depth > Tuning.PLAYER_WADE_DEPTH


# --- noclip seam (06 §8, task M1.4) -------------------------------------------------------

## 06 §5, §9: no noclip while stunned, cranking, hidden, or without agency.
func can_noclip() -> bool:
	return has_agency() and not is_stunned() and not flashlight.is_cranking()


## 06 §5: no items while cranking (M1.10 asks before use_selected()).
func can_use_item() -> bool:
	return has_agency() and not flashlight.is_cranking()


func begin_noclip_charge() -> bool:
	return state_machine.transition_to(PlayerStateMachine.NOCLIP_CHARGE)


func end_noclip_charge() -> void:
	if state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE):
		state_machine.transition_to(PlayerStateMachine.IDLE)


func report_noclip(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	noclip_state.emit(charge, target, valid, reason)


func _on_state_changed(from: StringName, to: StringName) -> void:
	if to in HALT_STATES:
		locomotion.halt()
	if from == PlayerStateMachine.NOCLIP_CHARGE:
		# The charge's -6 deg pull-in (key HOLD_NOCLIP, set by the targeting) returns in
		# 150 ms on any exit; the commit adds its own +8 punch on top.
		rig.fov_hold(0.0, Tuning.FEEDBACK_NOCLIP_CANCEL_FOV_MS, CameraRig.HOLD_NOCLIP)
	state_changed.emit(from, to)


# --- hiding (06 §10, 09 §6) --------------------------------------------------------------

## Called by a HideSpot when the player interacts with it.
func enter_hide(spot: HideSpot) -> void:
	hiding.enter(spot)


## Called by the HideSpot when the 0.6 s leave hold completes.
func leave_hide() -> void:
	hiding.leave()
