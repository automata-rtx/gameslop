extends Node
## The global signal bus (14 §4). Exactly eighteen signals, canonical and complete.
## Lifecycle and cross-scene events only; local wiring uses direct signals.
## Holds no state and never emits on its own. Adding a signal needs a CHANGELOG entry.

@warning_ignore_start("unused_signal")

# lifecycle
signal run_started(mode: StringName, seed: int)
## arrival: &"proper" | &"drop" | &"start"
signal level_entered(depth: int, stratum: StringName, arrival: StringName)
signal level_left(proper: bool)
signal run_ended(cause: StringName, score: int)
signal unlock_earned(id: StringName)
signal settings_changed(key: StringName, value: Variant)

# world
signal noise_emitted(pos: Vector3, radius: float, kind: StringName)
signal note_found(id: StringName)
signal item_picked(kind: StringName)
signal item_used(kind: StringName)
signal breaker_thrown(pos: Vector3)
signal exit_status_changed(status: StringName, timer: float)
signal hide_state(on: bool)

# errors and director
signal error_proximity(id: StringName, distance: float)
signal error_state(id: StringName, from: StringName, to: StringName)
signal director_phase(phase: StringName)
signal threat_changed(threat: float)

# presentation
signal audio_cue(text: String, pos: Vector3)

@warning_ignore_restore("unused_signal")
