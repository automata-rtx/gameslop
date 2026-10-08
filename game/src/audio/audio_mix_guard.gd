class_name AudioMixGuard
extends Node
## Keeps the audio mix thread out of AudioServer.update() in headless runs (RCA1).
##
## Godot 4.7.2 engine race: a playing player that changes its bus volumes (every
## AudioStreamPlayer3D each frame, any volume_db change) retires its old bus-details block
## to a graveyard that AudioServer.update() frees on the main thread two frames later,
## without the driver lock. The mix thread reads that block without a lock too
## (`_mix_step`: load the pointer, then copy it). If the mix thread is preempted between
## the two for two main frames, it copies freed memory: signal 11 on the audio thread
## (the crash handler then logs `propagate_notification()` from a non-main thread), or a
## heap abort (exit 134). Headless runs hit it: the main loop is unthrottled (hundreds of
## frames a second, `--fixed-fps`), so two frames can be well under a millisecond of
## preemption under load. At play frame rates two frames are 14 ms or more and the race
## needs an audio thread stall that long inside a few instructions.
##
## The guard holds the audio driver lock from the end of the frame's process step until
## the next frame starts, so AudioServer.update() (late in Main::iteration) never runs
## while the mix thread is inside a mix step. Headless only: the dummy driver's output is
## discarded, while a real driver must never wait across render and the frame delay.
## The driver mutex is recursive, so main-thread audio calls while it is held are fine.

## Stress hook: false leaves the race open (tests/stress/audio_mix_race.gd A/B runs).
static var enabled: bool = true

var held: bool = false
## Frames the guard has covered (tests).
var locks: int = 0


## Adds the guard under `parent` when this process runs headless. Returns it, or null.
static func install(parent: Node) -> AudioMixGuard:
	if DisplayServer.get_name() != "headless":
		return null
	var g := AudioMixGuard.new()
	g.name = "AudioMixGuard"
	parent.add_child(g)
	return g


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Last in the process step (Node process_priority is an int32).
	process_priority = 2147483647
	get_tree().physics_frame.connect(release)
	get_tree().process_frame.connect(release)


func _process(_delta: float) -> void:
	if enabled and not held:
		AudioServer.lock()
		held = true
		locks += 1


## Lets the mix thread run again (the start of every physics step and process step).
func release() -> void:
	if held:
		held = false
		AudioServer.unlock()


func _exit_tree() -> void:
	# The driver joins its thread at shutdown; never leave the lock held.
	release()
