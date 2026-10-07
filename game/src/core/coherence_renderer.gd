extends Node
## The Coherence renderer's driver (02 §4-§5, 14 §3, §11). Writes the six global
## shader parameters every frame from values it is fed through setters and
## EventBus signals. It never reads the player (14 §3).
## The post stack, pulse shapes, and threat vignette belong to M1.5; this autoload
## owns the plumbing and the globals.

const G_COHERENCE := &"g_coherence"
const G_NOCLIP_CHARGE := &"g_noclip_charge"
const G_NOCLIP_COMMIT := &"g_noclip_commit"
const G_NULL_POS := &"g_null_pos"
const G_NULL_RADIUS := &"g_null_radius"
const G_TIME := &"g_time"

## 14 §11 declared defaults; also the reset state at run start.
const NULL_POS_ABSENT := Vector3(0.0, -1000.0, 0.0)
## TODO(M0.3): move to Tuning (06 §9: Coherence max 100).
const COHERENCE_MAX := 100.0
## TODO(M0.3): move to Tuning (02 §4: noclip_commit pulse decays over 300 ms).
const NOCLIP_COMMIT_DECAY_S := 0.3
## g_time wraps so float precision in shaders never degrades in long sessions.
const TIME_WRAP_S := 3600.0
## 11 Interfaces: the pulse kinds.
const PULSE_KINDS: Array[StringName] = [&"hit", &"noclip_commit", &"coherence_gain", &"dissolve", &"flash"]

## Values as written to the globals (normalised where the shader expects 0..1).
var coherence01: float = 1.0
var noclip_charge: float = 0.0
var noclip_commit: float = 0.0
var null_pos: Vector3 = NULL_POS_ABSENT
var null_radius: float = 0.0
var world_time: float = 0.0
var threat: float = 0.0

## Wall-clock microseconds when each pulse kind last fired (-1 when never).
## Pulses are wall-clock so they keep decaying through hitstop (11 §4).
var _pulse_at_usec: Dictionary = {}
var _warned: Dictionary = {}


func _ready() -> void:
	# 11 §4: the post stack keeps running through hitstop and the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_pulses()
	EventBus.threat_changed.connect(set_threat)
	EventBus.run_started.connect(_on_run_started)
	_write_globals()


func _process(delta: float) -> void:
	# World time freezes with the tree (hitstop, pause) so world-shader motion freezes too.
	if not get_tree().paused:
		world_time = fmod(world_time + delta, TIME_WRAP_S)
	noclip_commit = clampf(1.0 - pulse_age(&"noclip_commit") / NOCLIP_COMMIT_DECAY_S, 0.0, 1.0)
	_write_globals()


## Coherence in player units (0..COHERENCE_MAX); written to g_coherence as 0..1.
func set_coherence(v: float) -> void:
	coherence01 = clampf(v / COHERENCE_MAX, 0.0, 1.0)


func set_threat(v: float) -> void:
	threat = clampf(v, 0.0, 1.0)


func set_null(pos: Vector3, radius: float) -> void:
	null_pos = pos
	null_radius = maxf(radius, 0.0)


## Proposed Interfaces addition (02): the noclip charge preview, 0..1.
func set_noclip_charge(v: float) -> void:
	noclip_charge = clampf(v, 0.0, 1.0)


func pulse(kind: StringName) -> void:
	if not _pulse_at_usec.has(kind):
		push_warning("CoherenceRenderer: unknown pulse kind %s" % kind)
		return
	_pulse_at_usec[kind] = Time.get_ticks_usec()
	if kind == &"noclip_commit":
		noclip_commit = 1.0
	else:
		_todo("pulse(%s) post-stack shape (M1.5)" % kind)


## Seconds since `kind` last fired; INF if never.
func pulse_age(kind: StringName) -> float:
	var at: int = _pulse_at_usec.get(kind, -1)
	if at < 0:
		return INF
	return float(Time.get_ticks_usec() - at) / 1_000_000.0


func _on_run_started(_mode: StringName, _seed: int) -> void:
	coherence01 = 1.0
	noclip_charge = 0.0
	threat = 0.0
	set_null(NULL_POS_ABSENT, 0.0)
	noclip_commit = 0.0
	_clear_pulses()


func _clear_pulses() -> void:
	for kind in PULSE_KINDS:
		_pulse_at_usec[kind] = -1


func _write_globals() -> void:
	RenderingServer.global_shader_parameter_set(G_COHERENCE, coherence01)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_CHARGE, noclip_charge)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_COMMIT, noclip_commit)
	RenderingServer.global_shader_parameter_set(G_NULL_POS, null_pos)
	RenderingServer.global_shader_parameter_set(G_NULL_RADIUS, null_radius)
	RenderingServer.global_shader_parameter_set(G_TIME, world_time)


func _todo(what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("not implemented: CoherenceRenderer.%s" % what)
