class_name NoclipTargeting
extends Node
## Noclip, the signature verb (06 §8), and its Feedback Contract rows (11 §2: charge,
## cancel, commit wall, commit floor, invalid). The Player's exported `noclip_targeting`
## seam calls physics_update(player, held, delta) every physics frame while the player has
## agency; the pass and the fall run in this node's own _physics_process (pausable, so
## both start after the 80 ms hitstop). Validity lives in NoclipQuery. Phases: IDLE ->
## CHARGING (NoclipCharge) -> PASSING (NoclipPass) or DROPPING (Dropping) -> IDLE.
## Floor drop hook: at a floor commit the Player emits `floor_drop_committed` (06 §8 step
## 3). The run flow consumes it and owns the transition from there: it calls
## GameState.descend(false) at once (so a death during the fall is impossible), shows the
## drop black, builds depth + 1 and moves the Player out of Dropping (to Landing or Idle).
## With nothing connected to that signal (direct launch, benches, tests) the drop is a
## debug loop: 1.2 s of black, then a respawn where the player was first seen, then Idle.

const PASS_TIME := Tuning.NOCLIP_PASS_TIME_MS / 1000.0
const LOOP_CHARGE := &"noclip_charge"

enum Phase { IDLE, CHARGING, PASSING, DROPPING }

## Solid floor (05 §4) when no run is active (benches, direct launch at depth 6).
@export var floor_solid: bool = false

var phase: Phase = Phase.IDLE
var charge_elapsed: float = 0.0
## Seconds before another charge may begin (06 §8 step 4).
var cooldown: float = 0.0
## The last NoclipQuery evaluation and the one being charged.
var aim: Dictionary = {}
var locked: Dictionary = {}
var reported: Array = [0.0, &"", true, &""]

var _p: Player
var _need_release: bool = false
var _invalid_toned: bool = false
var _preview_tween: Tween
var _pass_from: Vector3
var _pass_to: Vector3
var _pass_t: float = 0.0
var _pass_sounded: bool = false
var _pass_soft: bool = false
var _fall_t: float = 0.0
var _fall_pitch: float = 0.0
var _home: Transform3D
var _world_off: bool = false


# --- the seam (06 Interfaces) -------------------------------------------------------------

## One physics frame of targeting while the player has agency. `held` is the noclip input
## already gated by Player.can_noclip() (stun and crank read as released).
func physics_update(player: Player, held: bool, delta: float) -> void:
	_bind(player)
	if not held:
		_need_release = false
		_invalid_toned = false
		if phase == Phase.CHARGING:
			cancel()
		elif not reported[2]:
			_clear_invalid()
		return
	if phase != Phase.IDLE and phase != Phase.CHARGING:
		return
	aim = evaluate()
	if phase == Phase.CHARGING:
		_charge_frame(delta)
		return
	if _need_release or cooldown > 0.0:
		if not reported[2]:
			_clear_invalid()
		return
	if aim[&"valid"]:
		_begin_charge()
		if phase == Phase.CHARGING:
			_charge_frame(0.0)
	else:
		_show_invalid()


## The current aim as NoclipQuery sees it from the player's camera.
func evaluate() -> Dictionary:
	var cam := _p.rig.camera
	var shape := _p.collision.shape
	return NoclipQuery.evaluate(_p.get_world_3d().direct_space_state, cam.global_position,
			-cam.global_basis.z, _p.global_position, shape, _p.coherence, is_floor_solid(), [_p.get_rid()])


## 05 §4, 06 §8: depth 6 of a Descent has a solid floor; Endless never does.
func is_floor_solid() -> bool:
	if GameState.is_run_active() and GameState.run != null:
		if GameState.run.mode == Tuning.MODE_ENDLESS:
			return false
		return GameState.run.depth >= Tuning.RUN_FINAL_DEPTH
	return floor_solid


## 11 §2 noclip cancel: no cost; preview collapses 100 ms, descending tone, FOV returns
## 150 ms (the Player releases the hold when NoclipCharge ends), arc shutters out. Called
## on release and look-away, and by Player.contact() (contact cancels the charge).
func cancel(silent: bool = false) -> void:
	if phase != Phase.CHARGING:
		return
	phase = Phase.IDLE
	charge_elapsed = 0.0
	locked = {}
	_end_charge_presentation(Tuning.FEEDBACK_NOCLIP_CANCEL_COLLAPSE_MS / 1000.0)
	if not silent:
		_p.sounds.play(&"noclip_cancel")
	if _p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE):
		_p.end_noclip_charge()
	_report(0.0, NoclipQuery.TARGET_NONE, true, &"")


func is_charging() -> bool:
	return phase == Phase.CHARGING


## Charge progress 0..1 on the locked target.
func charge_fraction() -> float:
	if phase != Phase.CHARGING or locked.is_empty():
		return 0.0
	return clampf(charge_elapsed / NoclipQuery.charge_time(locked[&"target"]), 0.0, 1.0)


## A new run (Player.reset_for_run): idle, collision restored, presentation cleared.
func reset() -> void:
	if _p == null:
		return
	_set_world_collision(true)
	if _p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE):
		_p.end_noclip_charge()
	phase = Phase.IDLE
	charge_elapsed = 0.0
	cooldown = 0.0
	locked = {}
	_need_release = false
	_end_charge_presentation(0.0)
	_clear_invalid()
	_report(0.0, NoclipQuery.TARGET_NONE, true, &"")


# --- charge (11 §2 noclip charge) ------------------------------------------------------

func _begin_charge() -> void:
	if not _p.begin_noclip_charge():
		return
	phase = Phase.CHARGING
	charge_elapsed = 0.0
	locked = aim
	_invalid_toned = false
	var t := NoclipQuery.charge_time(locked[&"target"])
	# Image: preview at the target, flashlight dims 30%. Sound: the rising sine cluster.
	# Motion: FOV -6 over the charge, 0.003 m sway.
	if _preview_tween != null:
		_preview_tween.kill()
	CoherenceRenderer.set_noclip_invalid(false)
	_p.flashlight.dim = Tuning.FEEDBACK_NOCLIP_FLASHLIGHT_DIM
	_p.sounds.start_loop(LOOP_CHARGE, &"noclip_charge")
	_p.sounds.set_loop_pitch01(LOOP_CHARGE, 0.0)
	_p.rig.fov_hold(-Tuning.NOCLIP_FOV_PULL_DEG, t * 1000.0, CameraRig.HOLD_NOCLIP)
	_p.rig.set_sway(Tuning.FEEDBACK_NOCLIP_SWAY)


func _charge_frame(delta: float) -> void:
	# 06 §8: looking away from the target cancels (as does the aim turning invalid).
	if not aim[&"valid"] or aim[&"key"] != locked[&"key"] or aim[&"target"] != locked[&"target"]:
		cancel()
		_invalid_toned = true  # the cancel tone already spoke for this hold
		_show_invalid()
		return
	locked = aim
	charge_elapsed += delta
	var f := charge_fraction()
	CoherenceRenderer.set_noclip_target(aim[&"point"], aim[&"normal"])
	CoherenceRenderer.set_noclip_charge(f)
	_p.sounds.set_loop_pitch01(LOOP_CHARGE, f)
	_report(f, locked[&"target"], true, &"")
	if f >= 1.0:
		_commit()


## 11 §2 noclip invalid: dashed preview, a dull tone once, the reason under the crosshair.
func _show_invalid() -> void:
	var has_point: bool = aim.get(&"distance", INF) < INF
	if has_point:
		CoherenceRenderer.set_noclip_target(aim[&"point"], aim[&"normal"])
		CoherenceRenderer.set_noclip_charge(Tuning.NOCLIP_INVALID_PREVIEW)
	else:
		CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_invalid(true)
	if not _invalid_toned:
		_invalid_toned = true
		_p.sounds.play(&"noclip_fail")
	_report(0.0, aim[&"target"], false, aim[&"reason"])


func _clear_invalid() -> void:
	CoherenceRenderer.set_noclip_invalid(false)
	if phase == Phase.IDLE:
		CoherenceRenderer.set_noclip_charge(0.0)
		CoherenceRenderer.set_noclip_target(CoherenceRenderer.NOCLIP_TARGET_ABSENT, Vector3.ZERO)
	if _p != null:
		_report(0.0, NoclipQuery.TARGET_NONE, true, &"")


## Stops the charge loop, sway and dimming; collapses the preview over `collapse_s`.
func _end_charge_presentation(collapse_s: float) -> void:
	if _p == null:
		return
	_p.sounds.stop_loop(LOOP_CHARGE)
	_p.rig.set_sway(0.0)
	_p.flashlight.dim = 0.0
	CoherenceRenderer.set_noclip_invalid(false)
	if _preview_tween != null:
		_preview_tween.kill()
	if collapse_s <= 0.0 or not is_inside_tree():
		_preview_done()
		return
	_preview_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_preview_tween.tween_method(CoherenceRenderer.set_noclip_charge, CoherenceRenderer.noclip_charge, 0.0, collapse_s)
	_preview_tween.tween_callback(_preview_done)


func _preview_done() -> void:
	CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_target(CoherenceRenderer.NOCLIP_TARGET_ABSENT, Vector3.ZERO)


# --- commit (06 §8, 11 §2 commit wall / floor) ----------------------------------------------

func _commit() -> void:
	var target: StringName = locked[&"target"]
	var floor_drop := target == NoclipQuery.TARGET_FLOOR
	var to_state := PlayerStateMachine.DROPPING if floor_drop else PlayerStateMachine.NOCLIP_PASS
	if not _p.state_machine.transition_to(to_state):
		cancel()
		return
	var cost := NoclipQuery.cost(target)
	var from := _p.global_position
	_need_release = true
	charge_elapsed = 0.0
	_end_charge_presentation(0.0)
	_set_world_collision(false)
	# Image: hitstop, world lines within 3 m (g_noclip_commit), CA pulse, grain spike.
	# Sound: sub thump, tear, 60 ms gap (one sample, captioned [tear]). Motion: hitstop,
	# FOV +8 punch, 0.8 trauma. Readout: the Coherence loss (and the caption).
	Clock.hitstop(Tuning.NOCLIP_COMMIT_HITSTOP_MS)
	CoherenceRenderer.pulse(&"noclip_commit")
	_p.sounds.play(&"noclip_commit")
	_p.rig.fov_punch(Tuning.NOCLIP_FOV_PUNCH_DEG, PASS_TIME * 1000.0, Tuning.NOCLIP_FOV_PUNCH_RETURN_MS)
	_p.rig.add_trauma(Tuning.FEEDBACK_NOCLIP_COMMIT_TRAUMA)
	NoiseModel.emit(from, Tuning.NOISE_NOCLIP_COMMIT_RADIUS, Tuning.NOISE_KIND_TEAR)
	# The cost lands at commit so the readout meets the 50 ms contract; TOO THIN made
	# sure it cannot dissolve the player (source &"noclip" is never a death cause).
	_p.apply_coherence(-cost, &"noclip")
	GameState.record_spend(NoclipQuery.spend_kind(target), cost)
	_report(0.0, NoclipQuery.TARGET_NONE, true, &"")
	if floor_drop:
		_commit_floor(from)
	else:
		_commit_wall(from, target)


func _commit_wall(from: Vector3, target: StringName) -> void:
	phase = Phase.PASSING
	_pass_from = from
	_pass_to = locked[&"landing"]
	_pass_t = 0.0
	_pass_sounded = false
	_pass_soft = target == NoclipQuery.TARGET_SOFT
	GameState.record_wall_pass()
	_p.noclip_committed.emit(target, from, _pass_to)
	locked = {}


func _commit_floor(from: Vector3) -> void:
	phase = Phase.DROPPING
	_fall_t = 0.0
	_fall_pitch = 0.0
	locked = {}
	# 11 §2 commit (floor): as wall, then 1.2 s black with grain, a falling sine, the
	# camera pitching down 10 deg, `DROPPED · THEY ARE AWAKE` on arrival (run flow).
	CoherenceRenderer.pulse(&"drop")
	_p.sounds.play(&"noclip_fall")
	GameState.record_drop()
	_p.noclip_committed.emit(NoclipQuery.TARGET_FLOOR, from, from)
	_p.floor_drop_committed.emit()


# --- pass and fall (own physics frames, after the hitstop) -----------------------------

func _physics_process(delta: float) -> void:
	if cooldown > 0.0 and phase == Phase.IDLE:
		cooldown = maxf(0.0, cooldown - delta)
	match phase:
		Phase.PASSING:
			_pass_frame(delta)
		Phase.DROPPING:
			_fall_frame(delta)


## 06 §8 step 2: 250 ms along the aim to the free spot, collision with the world off.
func _pass_frame(delta: float) -> void:
	if not _pass_sounded:
		_pass_sounded = true
		_p.sounds.play(&"noclip_pass_soft" if _pass_soft else &"noclip_pass_wall")
	_pass_t = minf(_pass_t + delta, PASS_TIME)
	var k := Tween.interpolate_value(0.0, 1.0, _pass_t, PASS_TIME, Tween.TRANS_EXPO, Tween.EASE_OUT) as float
	_p.velocity = Vector3.ZERO
	_p.global_position = _pass_from.lerp(_pass_to, k)
	if _pass_t >= PASS_TIME:
		_finish_pass()


## Lands, never inside geometry: the found spot if it is still free, else the start
## (which the body stood in), then collision back on and a 1 s cooldown.
func _finish_pass() -> void:
	var space := _p.get_world_3d().direct_space_state
	var shape := _p.collision.shape
	var dest := _pass_to
	if not NoclipQuery.is_free(space, dest, shape, [_p.get_rid()]):
		dest = _pass_from
	_p.global_position = dest
	_p.velocity = Vector3.ZERO
	_set_world_collision(true)
	phase = Phase.IDLE
	cooldown = Tuning.NOCLIP_COOLDOWN
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)


func _fall_frame(delta: float) -> void:
	_fall_t += delta
	# Into the floor and black (the drop pulse), the camera pitching down 10 deg.
	_p.velocity = Vector3.ZERO
	_p.global_position += Vector3.DOWN * Tuning.PLAYER_GRAVITY * _fall_t * delta
	var want := minf(_fall_t / Tuning.NOCLIP_FLOOR_FALL_TIME, 1.0) * Tuning.FEEDBACK_NOCLIP_FALL_PITCH_DEG
	_p.rig.add_pitch(-deg_to_rad(want - _fall_pitch))
	_fall_pitch = want
	if _fall_t >= Tuning.NOCLIP_FLOOR_FALL_TIME and _p.floor_drop_committed.get_connections().is_empty():
		_debug_arrive()


## Direct launch without a run: the drop arrival at the first place the player stood.
func _debug_arrive() -> void:
	_p.global_transform = _home
	_p.velocity = Vector3.ZERO
	_p.rig.reset_pitch()
	_set_world_collision(true)
	phase = Phase.IDLE
	cooldown = Tuning.NOCLIP_COOLDOWN
	# 11 §3 arrival (drop): black to the world over 400 ms, sub settle, 0.3 trauma.
	CoherenceRenderer.pulse(&"drop")
	_p.sounds.play(&"drop_arrival")
	_p.rig.add_trauma(Tuning.FEEDBACK_ARRIVAL_DROP_TRAUMA)
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)


# --- wiring -------------------------------------------------------------------------------

func _bind(player: Player) -> void:
	if _p == player:
		return
	_p = player
	_home = player.global_transform
	if not player.state_changed.is_connected(_on_state_changed):
		player.state_changed.connect(_on_state_changed)


## Any exit from the noclip states that this node did not make (dissolve, the run flow
## taking the player out of Dropping) cleans up silently.
func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == PlayerStateMachine.NOCLIP_CHARGE and phase == Phase.CHARGING \
			and to != PlayerStateMachine.NOCLIP_PASS and to != PlayerStateMachine.DROPPING:
		cancel(true)
	elif from == PlayerStateMachine.DROPPING and phase == Phase.DROPPING:
		_set_world_collision(true)
		_p.rig.reset_pitch()
		phase = Phase.IDLE
		cooldown = Tuning.NOCLIP_COOLDOWN
	elif from == PlayerStateMachine.NOCLIP_PASS and phase == Phase.PASSING:
		_set_world_collision(true)
		phase = Phase.IDLE


## World collision off for the pass and the fall (06 §8 step 2); back on afterwards.
func _set_world_collision(on: bool) -> void:
	if on == _world_off:
		_world_off = not on
		_p.collision_mask = (_p.collision_mask | PlayerLayers.WORLD_MASK) if on else (_p.collision_mask & ~PlayerLayers.WORLD_MASK)


func _report(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	var r: Array = [charge, target, valid, reason]
	if r == reported:
		return
	reported = r
	if _p != null:
		_p.report_noclip(charge, target, valid, reason)
