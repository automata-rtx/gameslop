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

const SETTING_SENSITIVITY := &"mouse_sensitivity"
const SETTING_INVERT_Y := &"invert_y"
const CAUSE_SUBSTRATE := &"substrate"
const SOURCE_UNKNOWN_ERROR := &"error"
## 11 §3 dissolve: the camera drifts 0.02 m (down) over the 1.5 s sequence.
const DISSOLVE_DRIFT_DIR := Vector3.DOWN

@onready var state_machine: PlayerStateMachine = %StateMachine
@onready var rig: CameraRig = %CameraRig
@onready var flashlight: Flashlight = %Flashlight
@onready var interactor: Interactor = %Interactor
@onready var collision: CollisionShape3D = %Collision

## M1.4 seam: a NoclipTargeting component with physics_update(player, held, delta) and
## cancel(). It calls begin_noclip_charge / end_noclip_charge / report_noclip.
@export var noclip_targeting: Node
## Floor surface when the floor collider has no `surface` meta (the stratum's floor).
@export var default_surface: StringName = NoiseModel.DEFAULT_SURFACE

var coherence: float = Tuning.COHERENCE_MAX
var input := PlayerInput.new()
var locomotion: PlayerLocomotion
var hiding: PlayerHiding
## Water depth under the player (Pools): > 0 steps in water, > 0.3 m wading (06 §3).
var water_depth: float = 0.0

var _stun_left: float = 0.0
var _contact_cooldown: float = 0.0
var _last_damage_source: StringName = &""
var _light_queries: Array[Callable] = []


func _init() -> void:
	locomotion = PlayerLocomotion.new(self)
	hiding = PlayerHiding.new(self)


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
	flashlight.charge_changed.connect(func(v: float) -> void: charge_changed.emit(v))
	flashlight.toggled.connect(_on_flashlight_toggled)
	flashlight.crank_changed.connect(_on_crank_changed)
	flashlight.crank_tick.connect(_on_crank_tick)
	flashlight.crank_full.connect(func() -> void: AudioManager.play_2d(&"crank_full"))
	interactor.prompt_changed.connect(func(t: String, h: float) -> void: prompt_changed.emit(t, h))
	interactor.prompt_progress.connect(func(f: float) -> void: prompt_progress.emit(f))
	interactor.hold_tick.connect(func() -> void: AudioManager.play_2d(&"ui_tick"))
	interactor.interacted.connect(func(_t: Interactable) -> void: rig.nod(Tuning.FEEDBACK_INTERACT_NOD_DEG))
	state_machine.state_changed.connect(func(a: StringName, b: StringName) -> void: state_changed.emit(a, b))
	CoherenceRenderer.set_coherence(coherence)


## A new Descent re-uses the persistent player (14 §5): full meters, Idle, light off.
func reset_for_run(start_coherence: float = Tuning.COHERENCE_MAX) -> void:
	coherence = clampf(start_coherence, 0.0, Tuning.COHERENCE_MAX)
	_last_damage_source = &""
	_stun_left = 0.0
	_contact_cooldown = 0.0
	locomotion.reset()
	flashlight.set_on(false)
	flashlight.set_charge(Tuning.FLASH_CHARGE_MAX)
	state_machine.reset()
	CoherenceRenderer.set_coherence(coherence)
	coherence_changed.emit(coherence, 0.0, &"reset")


# --- 06 Interfaces ----------------------------------------------------------------------

func eye_position() -> Vector3:
	return rig.camera.global_position


func is_hidden() -> bool:
	return hiding.is_hidden()


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


## 06 §9: the only way Coherence changes. Clamped 0..100; no passive regeneration.
func apply_coherence(delta: float, source: StringName) -> void:
	if is_dissolving() or is_zero_approx(delta):
		return
	var before := coherence
	coherence = clampf(coherence + delta, 0.0, Tuning.COHERENCE_MAX)
	var applied := coherence - before
	if is_zero_approx(applied):
		return
	if applied < 0.0 and is_death_cause(source):
		_last_damage_source = source
	CoherenceRenderer.set_coherence(coherence)
	coherence_changed.emit(coherence, applied, source)
	if applied > 0.0:
		# 11 §3 Coherence gain: saturation overshoot, warm chord, FOV +2 then back 400 ms.
		CoherenceRenderer.pulse(&"coherence_gain")
		AudioManager.play_2d(&"coherence_gain")
		rig.fov_punch(Tuning.FEEDBACK_GAIN_FOV_DEG, Tuning.FEEDBACK_FOV_TWEEN_MIN_MS, Tuning.FEEDBACK_GAIN_FOV_MS)
	elif coherence <= 0.0:
		_dissolve(death_cause(source))


## 06 §9: an error id or the Substrate. Noclip is never a cause (06 §8 TOO THIN).
static func is_death_cause(source: StringName) -> bool:
	return source in Tuning.ERROR_IDS or source == CAUSE_SUBSTRATE


func death_cause(source: StringName) -> StringName:
	if is_death_cause(source):
		return source
	return _last_damage_source if _last_damage_source != &"" else source


## 06 §9 contact rules: cost, 1.2 s stun, 1.5 m push, trauma 0.6, 60 ms hitstop. Refused
## (false) within 3 s of the previous contact, while passing through a wall, and when the
## player has no body in the level (dropping, landing, dissolving, cinematic).
func contact(error: Node3D, amount: float) -> bool:
	if not can_be_contacted():
		return false
	_contact_cooldown = Tuning.CONTACT_EXCLUSIVITY_TIME
	var id := _error_id(error)
	if hiding.spot != null:
		hiding.eject()
	if state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE) and noclip_targeting != null \
			and noclip_targeting.has_method(&"cancel"):
		noclip_targeting.call(&"cancel")
	contacted.emit(id)
	apply_coherence(-absf(amount), id)
	if is_dissolving():
		return true
	if state_machine.transition_to(PlayerStateMachine.STUNNED) or is_stunned():
		_stun_left = Tuning.CONTACT_STUN_TIME
		stun_changed.emit(true)
	if error != null and error.is_inside_tree():
		locomotion.push(global_position - error.global_position)
	else:
		locomotion.push(global_transform.basis.z)
	# 11 §3 error contact: flash/CA/grain (post), contact hit, push + trauma + stun, readout.
	rig.add_trauma(Tuning.CONTACT_TRAUMA)
	CoherenceRenderer.pulse(&"hit")
	AudioManager.play_2d(&"contact_hit")
	NoiseModel.emit(global_position, Tuning.NOISE_CONTACT_RADIUS, Tuning.NOISE_KIND_TEAR)
	Clock.hitstop(Tuning.CONTACT_HITSTOP_MS)
	return true


func can_be_contacted() -> bool:
	if _contact_cooldown > 0.0:
		return false
	var s := state_machine.state
	return PlayerStateMachine.is_locomotion(s) or s in [
		PlayerStateMachine.NOCLIP_CHARGE, PlayerStateMachine.STUNNED, PlayerStateMachine.HIDDEN]


func contact_cooldown_left() -> float:
	return _contact_cooldown


func _error_id(error: Node3D) -> StringName:
	if error != null:
		var id: Variant = error.get(&"error_id")
		if id is StringName or id is String:
			return StringName(id)
	return SOURCE_UNKNOWN_ERROR


func _dissolve(cause: StringName) -> void:
	if not state_machine.transition_to(PlayerStateMachine.DISSOLVING):
		return
	# 06 §9: input locked; 11 §3: the grid dissolve (post), the dissolve sound, 0.02 m drift.
	velocity = Vector3.ZERO
	flashlight.set_cranking(false)
	interactor.clear()
	_stun_left = 0.0
	var tw := create_tween()
	tw.tween_method(rig.drift, Vector3.ZERO, DISSOLVE_DRIFT_DIR * Tuning.FEEDBACK_DISSOLVE_DRIFT,
			Tuning.COHERENCE_DISSOLVE_TIME)
	CoherenceRenderer.pulse(&"dissolve")
	AudioManager.play_2d(&"dissolve")
	# The run flow (M1.9) plays the 1.5 s sequence and then calls GameState.end_run(cause).
	dissolved.emit(cause)


# --- input ------------------------------------------------------------------------------

## True while the player controls the body (not dissolving, dropping, passing, landing, hidden).
func has_agency() -> bool:
	return state_machine.has_movement()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look((event as InputEventMouseMotion).relative)


## Mouse look (06 §3): yaw unbounded on the body, pitch +-89 on the rig; inside a hide
## spot both stay within the spot's limit (06 §10).
func look(relative: Vector2) -> void:
	var sens: Variant = SettingsManager.get_value(SETTING_SENSITIVITY)
	var s := float(sens) if sens is float or sens is int else Tuning.PLAYER_MOUSE_SENS_DEFAULT
	var invert: Variant = SettingsManager.get_value(SETTING_INVERT_Y)
	var dyaw := -CameraRig.mouse_to_radians(relative.x, s)
	var dpitch := -CameraRig.mouse_to_radians(relative.y, s) * (-1.0 if invert is bool and invert else 1.0)
	if is_hidden():
		rig.anchored_look(dyaw, dpitch, hiding.spot.yaw_limit_deg)
	elif has_agency() and not rig.is_anchored():
		rotate_y(dyaw)
		rig.add_pitch(dpitch)


# --- physics frame --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var hidden := hiding.spot != null
	input.poll(not (has_agency() or hidden))
	tick_timers(delta)
	_update_light_and_crank(delta)
	if hidden:
		interactor.physics_update(self, input.interact_held, input.interact_pressed, delta, hiding.is_hidden())
		return
	if not has_agency():
		velocity = Vector3.ZERO
		interactor.physics_update(self, false, false, delta, false)
		return
	if noclip_targeting != null and noclip_targeting.has_method(&"physics_update"):
		noclip_targeting.call(&"physics_update", self, input.noclip and can_noclip(), delta)
	locomotion.physics_update(delta)
	interactor.physics_update(self, input.interact_held, input.interact_pressed, delta, true)


## Countdown timers (stun, contact exclusivity, bob cut). Public so tests can step time.
func tick_timers(dt: float) -> void:
	_contact_cooldown = maxf(0.0, _contact_cooldown - dt)
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


## 06 §6 step radius for the current floor, water and gait.
func step_radius(gait: StringName) -> float:
	return NoiseModel.step_radius(floor_surface(), gait, water_depth > 0.0, is_wading())


func floor_surface() -> StringName:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.7 and c.get_collider() != null:
			var col := c.get_collider()
			if col.has_meta(&"surface"):
				return StringName(col.get_meta(&"surface"))
	return default_surface


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


# --- flashlight and crank (06 §5) --------------------------------------------------------

func _update_light_and_crank(delta: float) -> void:
	var alive := not is_dissolving()
	if input.flashlight_pressed and alive:
		flashlight.toggle()
	flashlight.set_cranking(input.crank and alive)
	flashlight.tick(delta, rig.bob_phase(), rig.bob_amount())


func _on_flashlight_toggled(on: bool) -> void:
	# 11 §2: beam + lens (Flashlight), relay click, 0.3 deg roll kick toward the hand, 2 m noise.
	AudioManager.play_2d(&"relay_click")
	rig.roll_kick(-Tuning.FEEDBACK_FLASHLIGHT_ROLL_KICK_DEG)
	NoiseModel.emit(global_position, Tuning.NOISE_FLASHLIGHT_TOGGLE_RADIUS, Tuning.NOISE_KIND_MECH)
	flashlight_toggled.emit(on)


func _on_crank_changed(turning: bool) -> void:
	# 11 §2 crank: wheel (Flashlight), ratchet loop, 1 Hz 0.004 m sway, gauge (HUD).
	rig.set_sway(Tuning.FEEDBACK_CRANK_SWAY if turning else 0.0)
	if turning:
		AudioManager.play_2d(&"crank_ratchet")
	crank_changed.emit(turning)


func _on_crank_tick() -> void:
	NoiseModel.emit(global_position, Tuning.NOISE_CRANK_RADIUS, Tuning.NOISE_KIND_MECH)


# --- hiding (06 §10, 09 §6) --------------------------------------------------------------

## Called by a HideSpot when the player interacts with it.
func enter_hide(spot: HideSpot) -> void:
	hiding.enter(spot)


## Called by the HideSpot when the 0.6 s leave hold completes.
func leave_hide() -> void:
	hiding.leave()
