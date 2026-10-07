class_name PlayerLight
extends RefCounted
## The flashlight and crank for the Player (06 §5) with their Feedback Contract rows
## (11 §2): toggle (beam and lens, relay click, roll kick, 2 m noise, HUD), crank (wheel
## and lens glow, ratchet loop with the whine following charge, 1 Hz sway, 12 m noise
## every 0.5 s, HUD) and crank full (bright click). The Flashlight node owns charge and
## visuals; this helper wires it to input, camera, sound and noise.

var _p: Player


func _init(player: Player) -> void:
	_p = player


func setup() -> void:
	var f := _p.flashlight
	f.charge_changed.connect(func(v: float) -> void: _p.charge_changed.emit(v))
	f.toggled.connect(_on_toggled)
	f.crank_changed.connect(_on_crank_changed)
	f.crank_tick.connect(_on_crank_tick)
	f.crank_full.connect(func() -> void: _p.sounds.play(&"crank_full"))


## One physics frame: toggle on press, crank while held (not while dissolving).
func physics_update(delta: float) -> void:
	var f := _p.flashlight
	var alive := not _p.is_dissolving()
	if _p.input.flashlight_pressed and alive:
		f.toggle()
	f.set_cranking(_p.input.crank and alive)
	f.tick(delta, _p.rig.bob_phase(), _p.rig.bob_amount())
	if f.is_turning():
		# 03: the whine's pitch follows charge (200 -> 900 Hz across the manifest range).
		_p.sounds.set_loop_pitch01(PlayerAudio.LOOP_CRANK_WHINE, f.charge / Tuning.FLASH_CHARGE_MAX)


## A new run: light off without a click, kick or noise; full charge; crank stopped.
func reset() -> void:
	var f := _p.flashlight
	f.set_cranking(false)
	f.set_on(false, true)
	f.set_charge(Tuning.FLASH_CHARGE_MAX)


func _on_toggled(on: bool, quiet: bool) -> void:
	# 11 §2: beam + lens (Flashlight), relay click, 0.3 deg roll kick toward the hand, 2 m noise.
	if not quiet:
		_p.sounds.play(&"flashlight_toggle")
		_p.rig.roll_kick(-Tuning.FEEDBACK_FLASHLIGHT_ROLL_KICK_DEG)
		NoiseModel.emit(_p.global_position, Tuning.NOISE_FLASHLIGHT_TOGGLE_RADIUS, Tuning.NOISE_KIND_MECH)
	_p.flashlight_toggled.emit(on)


func _on_crank_changed(turning: bool) -> void:
	# 11 §2 crank: wheel and lens (Flashlight), ratchet loop with the rising whine,
	# 1 Hz 0.004 m sway, gauge (HUD). Both loops stop when the crank stops or is full.
	_p.rig.set_sway(Tuning.FEEDBACK_CRANK_SWAY if turning else 0.0)
	if turning:
		_p.sounds.start_loop(PlayerAudio.LOOP_CRANK_RATCHET, &"crank_loop")
		_p.sounds.start_loop(PlayerAudio.LOOP_CRANK_WHINE, &"crank_whine")
		_p.sounds.set_loop_pitch01(PlayerAudio.LOOP_CRANK_WHINE, _p.flashlight.charge / Tuning.FLASH_CHARGE_MAX)
	else:
		_p.sounds.stop_loop(PlayerAudio.LOOP_CRANK_RATCHET)
		_p.sounds.stop_loop(PlayerAudio.LOOP_CRANK_WHINE)
	_p.crank_changed.emit(turning)


func _on_crank_tick() -> void:
	NoiseModel.emit(_p.global_position, Tuning.NOISE_CRANK_RADIUS, Tuning.NOISE_KIND_MECH)
