class_name NoclipTargeting
extends Node
## Noclip, the signature verb (06 §8), and its Feedback Contract rows (11 §2: charge,
## cancel, commit wall, commit floor, invalid). The Player's exported `noclip_targeting`
## seam calls physics_update(player, held, delta) every physics frame while the player has
## agency; the pass and the fall (NoclipMotion) run in this node's own _physics_process
## (pausable, so both start after the 80 ms hitstop). Validity lives in NoclipQuery.
## Phases: IDLE -> CHARGING -> PASSING or DROPPING -> IDLE. A wall pass counts only when it
## ends beyond the wall; a fallback to its start refunds the cost and records nothing.
## Floor drop hook: at a floor commit the Player emits `floor_drop_committed` (06 §8 step
## 3); the run flow calls GameState.descend(false) at once and moves the Player out of
## Dropping. Unconnected (direct launch, benches, tests), the drop is a debug loop: 1.2 s
## of black, then a respawn where the player was first seen, then Idle.

const PASS_TIME := NoclipMotion.PASS_TIME
const LOOP_CHARGE := &"noclip_charge"

enum Phase { IDLE, CHARGING, PASSING, DROPPING }

## Solid floor (05 §4) when no run is active and no level says so (benches).
@export var floor_solid: bool = false

var phase: Phase = Phase.IDLE
var charge_elapsed: float = 0.0
## Seconds before another charge may begin (06 §8 step 4).
var cooldown: float = 0.0
## The last NoclipQuery evaluation and the one being charged.
var aim: Dictionary = {}
var locked: Dictionary = {}
var reported: Array = [0.0, &"", true, &""]
## The committed pass and fall (null until bound to a player).
var motion: NoclipMotion

var _p: Player
var _need_release: bool = false
var _invalid_toned: bool = false
var _preview_tween: Tween
var _pass_target: StringName = &""
var _pass_sounded: bool = false
var _home: Transform3D
## Landing cache handed to NoclipQuery (find_landing_cached).
var _landing_cache: Dictionary = {}


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
		_show_blocked()
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
			-cam.global_basis.z, _p.global_position, shape, _p.coherence, is_floor_solid(), [_p.get_rid()],
			_landing_cache)


## 05 §4, 06 §8: depth 6 of a Descent has a solid floor; Endless never does. Without a run
## (direct launch `--depth 6`, benches) the live level's data decides, then the export.
func is_floor_solid() -> bool:
	if GameState.is_run_active() and GameState.run != null:
		if GameState.run.mode == Tuning.MODE_ENDLESS:
			return false
		return GameState.run.depth >= Tuning.RUN_FINAL_DEPTH
	if floor_solid:
		return true
	if _p != null and _p.is_inside_tree():
		for n in _p.get_tree().get_nodes_in_group(Level.GROUP):
			var lv := n as Level
			if lv != null and lv.data != null and not lv.is_queued_for_deletion():
				return lv.data.floor_solid
	return false


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


## Seconds into the current pass (0 outside one).
func pass_time() -> float:
	return motion.t if phase == Phase.PASSING and motion != null else 0.0


## A new run (Player.reset_for_run): idle, collision restored, presentation cleared.
func reset() -> void:
	if _p == null:
		return
	motion.restore()
	if _p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE):
		_p.end_noclip_charge()
	phase = Phase.IDLE
	charge_elapsed = 0.0
	cooldown = 0.0
	locked = {}
	_need_release = false
	_landing_cache.clear()
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
	# 06 §8: looking away from the target cancels (as does the aim turning invalid). The
	# target is the wall kind and plane, not the collider shape (NoclipQuery.same_target).
	if not aim[&"valid"] or not NoclipQuery.same_target(aim, locked):
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
	_dashed_preview()
	_tone_once()
	_report(0.0, aim[&"target"], false, aim[&"reason"])


## A press during the cooldown or before a fresh release (noclip review): the dashed
## preview (image), a dull tone once per hold (sound), the arc dimmed without a reason
## word (UI). The hold that committed already spoke, so holding through a pass is quiet.
func _show_blocked() -> void:
	_dashed_preview()
	_tone_once()
	var target: StringName = aim[&"target"] if aim[&"target"] != NoclipQuery.TARGET_NONE else NoclipQuery.TARGET_WALL
	_report(Tuning.NOCLIP_INVALID_PREVIEW, target, false, &"")


func _dashed_preview() -> void:
	if aim.get(&"distance", INF) < INF:
		CoherenceRenderer.set_noclip_target(aim[&"point"], aim[&"normal"])
		CoherenceRenderer.set_noclip_charge(Tuning.NOCLIP_INVALID_PREVIEW)
	else:
		CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_invalid(true)


func _tone_once() -> void:
	if not _invalid_toned:
		_invalid_toned = true
		_p.sounds.play(&"noclip_fail")


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
	if not _p.state_machine.can_transition(to_state):
		cancel()
		return
	var cost := NoclipQuery.cost(target)
	var from := _p.global_position
	# The cost lands at commit so the readout meets the 50 ms contract, before Dropping
	# (where Coherence cannot fall); TOO THIN made sure it cannot dissolve the player
	# (source &"noclip" is never a death cause).
	_p.apply_coherence(-cost, &"noclip")
	_p.state_machine.transition_to(to_state)
	_need_release = true
	_invalid_toned = true
	charge_elapsed = 0.0
	_end_charge_presentation(0.0)
	# Image: hitstop, world lines within 3 m (g_noclip_commit), CA pulse, grain spike.
	# Sound: sub thump, tear, 60 ms gap (one sample, captioned [tear]). Motion: hitstop,
	# FOV +8 punch, 0.8 trauma. Readout: the Coherence loss (and the caption).
	Clock.hitstop(Tuning.NOCLIP_COMMIT_HITSTOP_MS)
	CoherenceRenderer.pulse(&"noclip_commit")
	_p.sounds.play(&"noclip_commit")
	_p.rig.fov_punch(Tuning.NOCLIP_FOV_PUNCH_DEG, PASS_TIME * 1000.0, Tuning.NOCLIP_FOV_PUNCH_RETURN_MS)
	_p.rig.add_trauma(Tuning.FEEDBACK_NOCLIP_COMMIT_TRAUMA)
	NoiseModel.emit(from, Tuning.NOISE_NOCLIP_COMMIT_RADIUS, Tuning.NOISE_KIND_TEAR)
	_report(0.0, NoclipQuery.TARGET_NONE, true, &"")
	if floor_drop:
		_commit_floor(from, cost)
	else:
		_commit_wall(target)


func _commit_wall(target: StringName) -> void:
	phase = Phase.PASSING
	_pass_target = target
	_pass_sounded = false
	motion.begin_pass(locked, -_p.rig.camera.global_basis.z)
	locked = {}


func _commit_floor(from: Vector3, cost: float) -> void:
	phase = Phase.DROPPING
	locked = {}
	motion.begin_fall()
	# 11 §2 commit (floor): as wall, then 1.2 s black with grain, a falling sine, the
	# camera pitching down 10 deg, `DROPPED · THEY ARE AWAKE` on arrival (run flow).
	CoherenceRenderer.pulse(&"drop")
	_p.sounds.play(&"noclip_fall")
	GameState.record_spend(NoclipQuery.spend_kind(NoclipQuery.TARGET_FLOOR), cost)
	GameState.record_drop()
	_p.noclip_committed.emit(NoclipQuery.TARGET_FLOOR, from, from)
	_p.floor_drop_committed.emit()


# --- pass and fall (own physics frames, after the hitstop) -----------------------------

func _physics_process(delta: float) -> void:
	if cooldown > 0.0 and phase == Phase.IDLE:
		cooldown = maxf(0.0, cooldown - delta)
	match phase:
		Phase.PASSING:
			if not _pass_sounded:
				_pass_sounded = true
				_p.sounds.play(&"noclip_pass_soft" if _pass_target == NoclipQuery.TARGET_SOFT else &"noclip_pass_wall")
			if motion.pass_frame(delta):
				_finish_pass()
		Phase.DROPPING:
			motion.fall_frame(delta)
			if motion.fall_t >= Tuning.NOCLIP_FLOOR_FALL_TIME and _p.floor_drop_committed.get_connections().is_empty():
				_debug_arrive()


## Lands, never inside geometry: the found spot if it is still free, else a spot found
## again in the landing cell, else the start (which the body stood in). Only a pass that
## ends beyond the wall counts; the fallback refunds the cost (not a gain) and records
## nothing. Then collision back on and a 1 s cooldown.
func _finish_pass() -> void:
	var dest: Variant = motion.landing_now()
	var cost := NoclipQuery.cost(_pass_target)
	phase = Phase.IDLE
	cooldown = Tuning.NOCLIP_COOLDOWN
	if dest == null:
		motion.land(motion.from)
		_p.apply_coherence(cost, Player.SOURCE_NOCLIP_REFUND)
	else:
		motion.land(dest)
		GameState.record_spend(NoclipQuery.spend_kind(_pass_target), cost)
		GameState.record_wall_pass()
		_p.noclip_committed.emit(_pass_target, motion.from, dest as Vector3)
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)


## Direct launch without a run: the drop arrival at the first place the player stood.
func _debug_arrive() -> void:
	motion.debug_arrive(_home)
	phase = Phase.IDLE
	cooldown = Tuning.NOCLIP_COOLDOWN
	_p.state_machine.transition_to(PlayerStateMachine.IDLE)


# --- wiring -------------------------------------------------------------------------------

func _bind(player: Player) -> void:
	if _p == player:
		return
	_p = player
	_home = player.global_transform
	motion = NoclipMotion.new(player)
	if not player.state_changed.is_connected(_on_state_changed):
		player.state_changed.connect(_on_state_changed)


## Any exit from the noclip states that this node did not make (hiding or walking into an
## exit mid-charge, dissolve, the run flow taking the player out of Dropping) cleans up
## silently. A charge ended that way needs a fresh press.
func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == PlayerStateMachine.NOCLIP_CHARGE and phase == Phase.CHARGING \
			and to != PlayerStateMachine.NOCLIP_PASS and to != PlayerStateMachine.DROPPING:
		cancel(true)
		_need_release = true
		_invalid_toned = true
	elif from == PlayerStateMachine.DROPPING and phase == Phase.DROPPING:
		motion.end_fall()
		phase = Phase.IDLE
		cooldown = Tuning.NOCLIP_COOLDOWN
	elif from == PlayerStateMachine.NOCLIP_PASS and phase == Phase.PASSING:
		# Dissolved mid-pass: never left inside the wall; the pass counts for nothing.
		motion.snap_free()
		phase = Phase.IDLE


func _report(charge: float, target: StringName, valid: bool, reason: StringName) -> void:
	var r: Array = [charge, target, valid, reason]
	if r == reported:
		return
	reported = r
	if _p != null:
		_p.report_noclip(charge, target, valid, reason)
