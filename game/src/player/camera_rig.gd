class_name CameraRig
extends Node3D
## The player's eyes (02 §11, 11 §1, 11 Interfaces). Owns pitch, eye height, head bob,
## strafe lean, trauma shake, FOV (settings plus holds and punches), nods and roll kicks.
## The Player owns yaw (its body) and feeds this rig its motion every physics frame.
## Hierarchy: CameraRig (pitch, height) > %Motion (bob, shake, lean, kicks) > %Camera.

## Settings keys (12 §2, §5).
const SETTING_FOV := &"fov"
const SETTING_HEAD_BOB := &"head_bob"
const SETTING_SCREEN_SHAKE := &"screen_shake"

## Smoothing of the strafe lean and bob amplitude (per second, exponential).
const LEAN_SMOOTH := 10.0
const BOB_AMP_SMOOTH := 8.0
const KICK_DECAY := 8.0              # roll kicks and nods return at this exponential rate
const STEP_SMOOTH := 14.0            # a step-up lift is absorbed over ~0.1 s
const SHAKE_NOISE_HZ := 18.0         # trauma noise frequency

## fov_hold keys the player uses (one hold per key; holds sum).
const HOLD_DEFAULT := &"default"
const HOLD_SPRINT := &"sprint"       # +4 while sprinting (11 §2)
const HOLD_NOCLIP := &"noclip"       # -6 over the noclip charge (06 §8, 11 §2)

@onready var _motion: Node3D = %Motion
@onready var camera: Camera3D = %Camera

var pitch: float = 0.0               # rad, clamped to +-89 deg
var trauma: float = 0.0
var bob_scale: float = 1.0           # set_bob_scale (11 Interfaces); stacks with the setting

var _hfov_base: float = float(Tuning.CAMERA_FOV_DEFAULT)
var _fov_punch: float = 0.0          # deg, tweened
## fov_hold: key -> held offset in deg (tweened); the holds sum (06 Interfaces).
var _holds: Dictionary = {}
var _hold_tweens: Dictionary = {}
var _punch_tween: Tween
var _height_tween: Tween
var _dip_tween: Tween
var _dip: float = 0.0
var _step_offset: float = 0.0
var _lean: float = 0.0               # rad
var _bob_amp: float = 0.0            # 0 still, 1 walk, 1.6 sprint
var _bob_phase: float = 0.0          # rad
var _bob_amp_target: float = 0.0
var _lean_target: float = 0.0
var _sway_amp: float = 0.0           # m, crank / noclip sway (11 §2)
var _sway_phase: float = 0.0
var _kick_roll: float = 0.0          # rad
var _kick_pitch: float = 0.0         # rad
var _jitter: float = 0.0             # m, continuous jitter (Static, Null; 11 §3)
var _drift: Vector3 = Vector3.ZERO   # dissolve drift target (11 §3)
var _shake_time: float = 0.0
var _noise := FastNoiseLite.new()
## Hide spots (06 §10): while anchored the rig is top-level at the spot's view point.
var _anchored: bool = false
var _anchor_yaw: float = 0.0
var _hide_yaw: float = 0.0
var _anchor_tween: Tween


func _ready() -> void:
	# Cosmetic noise only (14 §6 allows a cosmetic seed).
	_noise.seed = 7
	_noise.frequency = 1.0
	camera.near = Tuning.CAMERA_NEAR
	camera.far = Tuning.CAMERA_FAR
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_hfov_base = clampf(_setting_float(SETTING_FOV, float(Tuning.CAMERA_FOV_DEFAULT)),
			Tuning.CAMERA_FOV_MIN, Tuning.CAMERA_FOV_MAX)
	_apply_fov()
	SettingsManager.changed.connect(_on_setting_changed)


## 12 §2: settings hold a horizontal FOV at 16:9; Camera3D gets the vertical one and
## keeps height, so wider monitors gain width and never lose height.
static func hfov_to_vfov(hfov_deg: float) -> float:
	var ratio := Tuning.SETTINGS_FOV_HFOV_TO_VFOV_NUM / Tuning.SETTINGS_FOV_HFOV_TO_VFOV_DEN
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(hfov_deg) * 0.5) * ratio))


## 06 §3 / 12 §5: radians of look for `pixels` of mouse motion at `sensitivity`.
static func mouse_to_radians(pixels: float, sensitivity: float) -> float:
	var s := clampf(sensitivity, Tuning.PLAYER_MOUSE_SENS_MIN, Tuning.PLAYER_MOUSE_SENS_MAX)
	return pixels * Tuning.PLAYER_MOUSE_RAD_PER_PIXEL * s


## Applies pitch (clamped); `limit_deg` narrows it (hide spots, 06 §10).
func add_pitch(delta_rad: float, limit_deg: float = Tuning.PLAYER_PITCH_LIMIT) -> void:
	var lim := deg_to_rad(minf(limit_deg, Tuning.PLAYER_PITCH_LIMIT))
	pitch = clampf(pitch + delta_rad, -lim, lim)
	rotation.x = pitch


func reset_pitch() -> void:
	pitch = 0.0
	rotation.x = 0.0


# --- hide spots (06 §10, 11 §2: camera slides 0.6 s) -------------------------------

## Slides the eye to `view` (global) over `seconds` and anchors it there.
func anchor_to(view: Transform3D, seconds: float) -> Tween:
	if _anchor_tween:
		_anchor_tween.kill()
	var start := global_transform
	top_level = true
	global_transform = start
	_anchored = true
	_hide_yaw = 0.0
	_anchor_yaw = view.basis.get_euler().y
	pitch = 0.0
	_anchor_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anchor_tween.tween_property(self, ^"global_transform", view.orthonormalized(), seconds)
	return _anchor_tween


## Slides back to `eye` (global) over `seconds`, then re-joins the body at `eye_height`.
func release_to(eye: Transform3D, eye_height: float, seconds: float) -> Tween:
	if _anchor_tween:
		_anchor_tween.kill()
	_anchor_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anchor_tween.tween_property(self, ^"global_transform", eye.orthonormalized(), seconds)
	_anchor_tween.tween_callback(_rejoin.bind(eye_height))
	return _anchor_tween


func is_anchored() -> bool:
	return _anchored


## Look while hidden: yaw and pitch within +-limit of the spot's view direction.
func anchored_look(dyaw: float, dpitch: float, limit_deg: float) -> void:
	if _anchor_tween and _anchor_tween.is_running():
		return
	var lim := deg_to_rad(limit_deg)
	_hide_yaw = clampf(_hide_yaw + dyaw, -lim, lim)
	pitch = clampf(pitch + dpitch, -lim, lim)
	rotation = Vector3(pitch, _anchor_yaw + _hide_yaw, 0.0)


func _rejoin(eye_height: float) -> void:
	top_level = false
	_anchored = false
	position = Vector3(0.0, eye_height, 0.0)
	pitch = 0.0
	rotation = Vector3.ZERO


# --- 11 Interfaces ------------------------------------------------------------------

func add_trauma(v: float) -> void:
	trauma = clampf(trauma + v, 0.0, 1.0)


## A FOV punch: +delta over up_ms, back to 0 over down_ms (TRANS_EXPO / EASE_OUT, 11 §1).
func fov_punch(delta_deg: float, up_ms: float, down_ms: float) -> void:
	if _punch_tween:
		_punch_tween.kill()
	_punch_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, ^"_fov_punch", delta_deg, maxf(up_ms, 1.0) / 1000.0)
	_punch_tween.tween_property(self, ^"_fov_punch", 0.0, maxf(down_ms, 1.0) / 1000.0)


## A held FOV offset under `key` (sprint +4, noclip charge -6), tweened over `ms`
## (0 snaps). One hold per key; a new hold on a key replaces that key's hold only, and
## the holds sum, so releasing sprint never wipes the noclip pull-in.
func fov_hold(delta_deg: float, ms: float = Tuning.FEEDBACK_FOV_TWEEN_MIN_MS, key: StringName = HOLD_DEFAULT) -> void:
	var old: Variant = _hold_tweens.get(key)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_hold_tweens.erase(key)
	if ms <= 0.0 or not is_inside_tree():
		_set_hold(delta_deg, key)
		return
	var tw := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_hold.bind(key), float(_holds.get(key, 0.0)), delta_deg, ms / 1000.0)
	_hold_tweens[key] = tw


## The current (tweened) hold under `key`, in degrees.
func fov_hold_of(key: StringName) -> float:
	return float(_holds.get(key, 0.0))


## Sum of every hold, in degrees.
func fov_hold_total() -> float:
	var t := 0.0
	for v: float in _holds.values():
		t += v
	return t


func _set_hold(v: float, key: StringName) -> void:
	if is_zero_approx(v):
		_holds.erase(key)
	else:
		_holds[key] = v


func set_bob_scale(v: float) -> void:
	bob_scale = maxf(v, 0.0)


func nod(pitch_deg: float) -> void:
	_kick_pitch -= deg_to_rad(pitch_deg)


func roll_kick(deg: float) -> void:
	_kick_roll += deg_to_rad(deg)


# --- additions used by the Player -----------------------------------------------------

## Eye height tween (crouch/stand, 120 ms) with the 0.05 m dip (02 §11, 11 §2).
func set_eye_height(h: float, animate: bool = true) -> void:
	if _height_tween:
		_height_tween.kill()
	if not animate:
		position.y = h
		return
	_height_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_height_tween.tween_property(self, ^"position:y", h, Tuning.PLAYER_CROUCH_TRANSITION_MS / 1000.0)
	dip()


## The 0.05 m landing/crouch dip over 120 ms.
func dip() -> void:
	if _dip_tween:
		_dip_tween.kill()
	var half := Tuning.CAMERA_DIP_MS / 2000.0
	_dip_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_dip_tween.tween_property(self, ^"_dip", -Tuning.CAMERA_DIP, half).set_ease(Tween.EASE_OUT)
	_dip_tween.tween_property(self, ^"_dip", 0.0, half).set_ease(Tween.EASE_IN_OUT)


## A step-up raised the body by `lift`; the eye follows smoothly instead of popping.
func absorb_step(lift: float) -> void:
	_step_offset -= lift


## Continuous jitter in metres (Static 0.002, Null 0.004 / 0.01; 11 §3). 0 to stop.
func set_jitter(m: float) -> void:
	_jitter = maxf(m, 0.0)


## Crank sway (1 Hz, 0.004 m) or noclip sway (0.003 m); 0 to stop.
func set_sway(m: float) -> void:
	_sway_amp = maxf(m, 0.0)


## Dissolve: the camera drifts 0.02 m (11 §3).
func drift(offset: Vector3) -> void:
	_drift = offset


## Called by the Player each physics frame with its locomotion: `stride_phase` 0..1 of the
## current step, `amp` 0 (still) / 1 (walk) / 1.6 (sprint), `lateral` -1..1 strafe speed.
func feed_motion(stride_phase: float, step_index_odd: bool, amp: float, lateral: float) -> void:
	# One vertical cycle per step; one lateral cycle per two steps, so the step lands in the trough.
	_bob_phase = (stride_phase + (1.0 if step_index_odd else 0.0)) * PI
	_bob_amp_target = amp
	_lean_target = -lateral * deg_to_rad(Tuning.CAMERA_LEAN_DEG)


func _process(delta: float) -> void:
	_bob_amp = lerpf(_bob_amp, _bob_amp_target, 1.0 - exp(-BOB_AMP_SMOOTH * delta))
	_lean = lerpf(_lean, _lean_target, 1.0 - exp(-LEAN_SMOOTH * delta))
	_kick_roll *= exp(-KICK_DECAY * delta)
	_kick_pitch *= exp(-KICK_DECAY * delta)
	_step_offset *= exp(-STEP_SMOOTH * delta)
	trauma = maxf(0.0, trauma - Tuning.CAMERA_TRAUMA_DECAY * delta)
	_shake_time += delta
	_sway_phase = fmod(_sway_phase + TAU * Tuning.FEEDBACK_CRANK_SWAY_HZ * delta, TAU)
	_apply_motion()
	_apply_fov()


func _apply_motion() -> void:
	var bob_setting := _setting_float(SETTING_HEAD_BOB, Tuning.SETTINGS_HEAD_BOB_DEFAULT)
	var b := _bob_amp * bob_scale * bob_setting
	var pos := Vector3(
		sin(_bob_phase * 0.5) * Tuning.CAMERA_BOB_LATERAL * b,
		-absf(sin(_bob_phase)) * Tuning.CAMERA_BOB_VERTICAL * b,
		0.0)
	pos.y += _dip + _step_offset
	pos.x += sin(_sway_phase) * _sway_amp
	pos += _drift
	var rot := Vector3(_kick_pitch, 0.0, _lean + _kick_roll)
	# 11 §1: shake = trauma^2, max 0.04 m / 1.2 deg, scaled by the setting.
	var shake := trauma * trauma * _setting_float(SETTING_SCREEN_SHAKE, Tuning.SETTINGS_SHAKE_DEFAULT)
	if shake > 0.0 or _jitter > 0.0:
		var t := _shake_time * SHAKE_NOISE_HZ
		var n := Vector3(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(t, 100.0), _noise.get_noise_2d(t, 200.0))
		pos += n * (Tuning.CAMERA_SHAKE_MAX_TRANSLATION * shake + _jitter)
		var r := Vector3(_noise.get_noise_2d(t, 300.0), _noise.get_noise_2d(t, 400.0), _noise.get_noise_2d(t, 500.0))
		rot += r * deg_to_rad(Tuning.CAMERA_SHAKE_MAX_ROTATION) * shake
	_motion.position = pos
	_motion.rotation = rot


## The bob's phase (rad) and effective amplitude, for the held flashlight's bob (02 §9).
func bob_phase() -> float:
	return _bob_phase


func bob_amount() -> float:
	return _bob_amp * bob_scale * _setting_float(SETTING_HEAD_BOB, Tuning.SETTINGS_HEAD_BOB_DEFAULT)


func current_hfov() -> float:
	return clampf(_hfov_base + fov_hold_total() + _fov_punch, 1.0, 170.0)


func _apply_fov() -> void:
	camera.fov = hfov_to_vfov(current_hfov())


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == SETTING_FOV and (value is int or value is float):
		_hfov_base = clampf(float(value), Tuning.CAMERA_FOV_MIN, Tuning.CAMERA_FOV_MAX)
		_apply_fov()


static func _setting_float(key: StringName, fallback: float) -> float:
	var v: Variant = SettingsManager.get_value(key)
	return float(v) if v is int or v is float else fallback
