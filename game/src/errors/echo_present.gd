class_name EchoPresent
extends RefCounted
## Echo's presentation (02 §8, 03 Errors, 11 §3 "Echo at 4 m"), split out of ErrorEcho
## (14 §6 400-line limit). It is the tell and nothing else: the player's own footstep
## samples played at Echo's position on the Errors bus, -3 dB (AudioManager captions
## footsteps on Errors as Echo's: `[footsteps, {dir}, late]`); within 4 m the man-sized
## heat-shimmer (refraction 0.015, no fill) and a breathing-length noise swell every 2 s.
## Never any other sound. Nothing here changes the rule.

const BREATH_SOUND := &"echo_breath"
const BUS := &"Errors"
const SHIMMER_PARAM := &"presence"


## One of Echo's own steps: the player's recorded surface sample at Echo's feet.
static func play_step(e: ErrorEcho, surface: StringName) -> void:
	e.steps_played += 1
	var id := StringName("foot_%s" % surface)
	if not AudioManager.has_sound(id):
		id = StringName("foot_%s" % NoiseModel.DEFAULT_SURFACE)
	AudioManager.play_3d(id, e.body_position(), BUS, Tuning.ECHO_STEP_PLAYBACK_DB)


## 0..1: full within ECHO_SHIMMER_RANGE (4 m) of the player, gone ECHO_SHIMMER_FADE beyond.
static func presence_at(distance: float) -> float:
	return clampf((Tuning.ECHO_SHIMMER_RANGE + Tuning.ECHO_SHIMMER_FADE - distance) / Tuning.ECHO_SHIMMER_FADE, 0.0, 1.0)


## Each tick: the shimmer's presence and the breath swell (every 2 s within 4 m).
static func tick(e: ErrorEcho, delta: float) -> void:
	var d := e.distance_to_player()
	set_presence(e, presence_at(d) if e.state != Tuning.ERROR_STATE_DORMANT else 0.0)
	if d <= Tuning.ECHO_SHIMMER_RANGE and e.state != Tuning.ERROR_STATE_DORMANT:
		e._breath_acc -= delta
		if e._breath_acc <= 0.0:
			e._breath_acc += Tuning.ECHO_BREATH_SWELL_INTERVAL
			e.breaths += 1
			AudioManager.play_3d(BREATH_SOUND, e.body_position() + Vector3.UP * Tuning.ERROR_EYE_HEIGHT, BUS)
	else:
		# Entering the 4 m range swells at once, then every 2 s.
		e._breath_acc = 0.0


static func set_presence(e: ErrorEcho, p: float) -> void:
	e.presence = p
	if e.shimmer == null:
		return
	e.shimmer.visible = p > 0.0
	e.shimmer.set_instance_shader_parameter(SHIMMER_PARAM, p)


## 02 §8: a man-sized capsule (0.35 x 1.8 m, Echo's body) standing on its origin.
static func shimmer_mesh() -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = Tuning.ECHO_CAPSULE_RADIUS
	m.height = Tuning.ECHO_CAPSULE_HEIGHT
	m.radial_segments = 24
	m.rings = 8
	return m
