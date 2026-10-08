class_name PlayerAudio
extends RefCounted
## The Player's side of sound (03 Interfaces, 11 §2-§3). One-shots go to
## AudioManager.play_2d/play_3d by manifest id; loops (sprint breath, hidden breath, crank
## ratchet and whine) are AudioLoop handles from AudioManager.loop(id), one per key,
## started and stopped with their fades. `played` and is_looping() are the record the
## tests read (CI has a dummy audio driver, so nothing audible can be asserted).

## Loop keys the Player uses (one handle per key).
const LOOP_SPRINT_BREATH := &"sprint_breath"
const LOOP_HIDE_BREATH := &"hide_breath"
const LOOP_CRANK_RATCHET := &"crank_ratchet"
const LOOP_CRANK_WHINE := &"crank_whine"
## Most recent ids kept in `played`.
const LOG_SIZE := 64

## Ids played or started, oldest first (capped at LOG_SIZE).
var played: Array[StringName] = []

## key -> AudioLoop
var _loops: Dictionary = {}
## key -> true while started
var _on: Dictionary = {}
## key -> last pitch01
var _pitch01: Dictionary = {}
## Coherence units lost and not yet ticked, and the wait before the next tick.
const LOSS_QUIET_S := 1.0
var _loss_pending: float = 0.0
var _loss_wait: float = 0.0
## Seconds since the last loss; a loss after a quiet spell ticks at once even when it is
## a fraction of a unit (11 §3: the sound channel within 50 ms of the first loss).
var _since_loss: float = INF


func play(id: StringName) -> void:
	_log(id)
	AudioManager.play_2d(id)


## A positional one-shot; ids the catalogue lacks are skipped quietly (a hide spot kind
## whose sound has not been synthesized yet).
func play_at(id: StringName, pos: Vector3, bus: StringName = &"") -> void:
	_log(id)
	if AudioManager.has_sound(id):
		AudioManager.play_3d(id, pos, bus)


## Starts the loop `id` under `key`, fading in over `fade_in` s. A loop fading out turns
## around on the same handle.
func start_loop(key: StringName, id: StringName, fade_in: float = 0.0) -> void:
	if _on.get(key, false):
		return
	_on[key] = true
	_log(id)
	var h: AudioLoop = _loops.get(key)
	if h == null or not h.is_valid() or h.id != id:
		if h != null:
			h.release()
		h = AudioManager.loop(id)
		_loops[key] = h
	h.start(fade_in)


## Stops the loop under `key`, fading out over `fade_out` s.
func stop_loop(key: StringName, fade_out: float = 0.0) -> void:
	if not _on.get(key, false):
		return
	_on[key] = false
	var h: AudioLoop = _loops.get(key)
	if h != null:
		h.stop(fade_out)


## 03 / 11 §3 Coherence loss (any source): one tick per unit lost, at most
## AUDIO_LOSS_TICK_MAX_HZ. Fractions (Static's 4 per second) accumulate; the first tick
## of a loss plays at once.
func add_loss(units: float) -> void:
	if units <= 0.0:
		return
	var fresh := _since_loss >= LOSS_QUIET_S
	_since_loss = 0.0
	_loss_pending += units
	if fresh and _loss_wait <= 0.0 and _loss_pending < 1.0:
		_loss_pending = 1.0  # the first tick of a new loss pays for its fraction
	tick(0.0)


## Advances the loss-tick rate limit; called every physics frame by the Player.
func tick(dt: float) -> void:
	_since_loss += dt
	_loss_wait = maxf(0.0, _loss_wait - dt)
	if _loss_wait > 0.0 or _loss_pending < 1.0:
		return
	_loss_pending -= 1.0
	_loss_wait = 1.0 / Tuning.AUDIO_LOSS_TICK_MAX_HZ
	play(&"coherence_loss_tick")


func clear_loss() -> void:
	_loss_pending = 0.0


func loss_ticks_pending() -> int:
	return int(_loss_pending)


## A new run: every loop stopped, no loss ticks left.
func reset() -> void:
	stop_all()
	clear_loss()
	_loss_wait = 0.0
	_since_loss = INF


func stop_all() -> void:
	for key: StringName in _loops.keys():
		stop_loop(key)


## Frees every loop player (the Player leaves the tree).
func release_all() -> void:
	for h: AudioLoop in _loops.values():
		h.release()
	_loops.clear()
	_on.clear()


## True from start_loop until stop_loop (a loop fading out is not "looping").
func is_looping(key: StringName) -> bool:
	return bool(_on.get(key, false))


## Pitch across the manifest's runtime range, 0..1 (the crank whine follows charge).
func set_loop_pitch01(key: StringName, t: float) -> void:
	_pitch01[key] = t
	var h: AudioLoop = _loops.get(key)
	if h != null:
		h.set_pitch01(t)


func loop_pitch01(key: StringName) -> float:
	return float(_pitch01.get(key, -1.0))


func _log(id: StringName) -> void:
	played.append(id)
	if played.size() > LOG_SIZE:
		played.remove_at(0)
