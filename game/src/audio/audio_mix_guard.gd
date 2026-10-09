class_name AudioMixGuard
extends Node
## Keeps the audio mix thread out of AudioServer.update() (RCA1).
##
## Godot 4.7.2 engine race: a playing player that changes its bus volumes (every
## AudioStreamPlayer3D each physics step, any volume_db change) retires its old bus-details
## block to a graveyard that AudioServer.update() frees on the main thread one to two frames
## later, without the driver lock. The mix thread reads that block without a lock too
## (`_mix_step`: load the pointer, then copy it). If the mix thread is preempted between
## the two for a frame or more, it copies freed memory: signal 11 on the audio thread
## (logged as `propagate_notification()` from a non-main thread), or a heap abort (exit 134).
##
## Every driver (Dummy, PulseAudio, ALSA, WASAPI) runs each mix step under its driver lock,
## so holding AudioServer.lock() while update() runs closes the race: no mix step is in
## flight when the graveyard is freed, and a step that starts later only loads live blocks.
## update() runs late in Main::iteration (after RenderingServer.draw and ScriptServer.frame,
## before the frame delay) and GDScript has no hook right after it, so the guard holds the
## lock from a point before update() to the next frame signal (physics_frame/process_frame):
##
## - HEADLESS: from the end of the process step (no draw, dummy output, unthrottled frames:
##   the race's main exposure, two frames can be well under 1 ms).
## - FRAME_TAIL (a window, M3.3): from RenderingServer.frame_post_draw, after the draw and its
##   vsync wait, so the hold covers ScriptServer.frame, update(), the OS event pump and the
##   start of the next iteration. It only engages when that tail cannot sleep: Engine.max_fps
##   0, no low-processor mode, no fixed frame delay, the window drawable and not minimized,
##   and only on the main thread. A watchdog measures every hold and every wait for the lock;
##   after WATCHDOG_STRIKES holds or waits over WATCHDOG_BUDGET_USEC, or one over
##   WATCHDOG_HARD_USEC, it turns itself off for the session (a slow machine, or a window drag
##   on Windows, which runs a modal loop inside the event pump). Measured on the CPU renderer
##   (lavapipe, 4 cores) the tail is 4 ms p50 and 13 ms p95, so it trips there; a real GPU
##   machine must be measured with tests/stress/audio_guard_window.gd (docs/qa). With a
##   frame cap the guard stays off and the race needs a mix-thread stall of a whole capped
##   frame (2.8 ms at 360 fps, 33 ms at 30) inside a few instructions.
## The driver mutex is recursive, so main-thread audio calls while it is held are fine.

enum Mode { OFF, HEADLESS, FRAME_TAIL }

## A hold or a lock wait longer than this is a strike (the mix thread waits this long; the
## drivers' default 15 ms output latency absorbs it).
const WATCHDOG_BUDGET_USEC := 2000
## Strikes before FRAME_TAIL turns itself off for the session.
const WATCHDOG_STRIKES := 4
## One hold or wait this long turns it off at once (close to an underrun).
const WATCHDOG_HARD_USEC := 6000

## Stress hook: false leaves the race open (tests/stress/audio_mix_race.gd A/B runs).
static var enabled: bool = true

var mode: Mode = Mode.OFF
var held: bool = false
## Frames the guard has covered (tests).
var locks: int = 0
## FRAME_TAIL readouts: the longest hold and lock wait (usec), the strikes, and whether the
## watchdog has turned the guard off.
var max_hold_usec: int = 0
var max_wait_usec: int = 0
var strikes: int = 0
var tripped: bool = false
var _held_at: int = 0


## Adds the guard under `parent`: HEADLESS in a headless process, FRAME_TAIL with a window.
static func install(parent: Node) -> AudioMixGuard:
	var g := AudioMixGuard.new()
	g.name = "AudioMixGuard"
	g.mode = Mode.HEADLESS if DisplayServer.get_name() == "headless" else Mode.FRAME_TAIL
	parent.add_child(g)
	return g


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Last in the process step (Node process_priority is an int32).
	process_priority = 2147483647
	get_tree().physics_frame.connect(release)
	get_tree().process_frame.connect(release)
	if mode == Mode.FRAME_TAIL:
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _process(_delta: float) -> void:
	if mode == Mode.HEADLESS and enabled and not held:
		_hold()


func _on_frame_post_draw() -> void:
	if mode == Mode.FRAME_TAIL and enabled and not tripped and not held and tail_cannot_sleep() \
			and OS.get_thread_caller_id() == OS.get_main_thread_id():
		_hold()


## True when nothing between the draw and the next frame sleeps: no frame cap, no
## low-processor mode, no fixed frame delay, the window drawable and not minimized.
static func tail_cannot_sleep() -> bool:
	if Engine.max_fps > 0 or OS.low_processor_usage_mode:
		return false
	if int(ProjectSettings.get_setting("application/run/frame_delay_msec", 0)) > 0:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	return DisplayServer.window_can_draw() \
		and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED


func _hold() -> void:
	var t0 := Time.get_ticks_usec()
	AudioServer.lock()
	_held_at = Time.get_ticks_usec()
	held = true
	locks += 1
	_watch(_held_at - t0, false)


## Lets the mix thread run again (the start of every physics step and process step).
func release() -> void:
	if held:
		held = false
		AudioServer.unlock()
		_watch(Time.get_ticks_usec() - _held_at, true)


## FRAME_TAIL watchdog: counts holds and lock waits over budget; trips after the limit.
func _watch(usec: int, is_hold: bool) -> void:
	if mode != Mode.FRAME_TAIL:
		return
	if is_hold:
		max_hold_usec = maxi(max_hold_usec, usec)
	else:
		max_wait_usec = maxi(max_wait_usec, usec)
	if usec > WATCHDOG_BUDGET_USEC:
		strikes += 1
		if (strikes >= WATCHDOG_STRIKES or usec > WATCHDOG_HARD_USEC) and not tripped:
			tripped = true
			push_warning("AudioMixGuard: frame-tail lock off for this session (%d holds or waits over %d us)" \
				% [strikes, WATCHDOG_BUDGET_USEC])


func _exit_tree() -> void:
	# The driver joins its thread at shutdown; never leave the lock held.
	release()
