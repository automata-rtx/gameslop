class_name HudFakePlayer
extends Node
## Debug stand-in for the Player's readout signals (06 Interfaces and its production
## additions), so the gallery and tests can drive the HUD state by state without a level.
## Same signal names and arguments as Player; no behaviour of its own.

@warning_ignore_start("unused_signal")
signal coherence_changed(value: float, delta: float, source: StringName)
signal stamina_changed(value: float)
signal charge_changed(value: float)
signal noclip_state(charge: float, target: StringName, valid: bool, reason: StringName)
signal contacted(by: StringName)
signal dissolved(cause: StringName)
signal hidden_changed(on: bool)
signal state_changed(from: StringName, to: StringName)
signal sprint_changed(on: bool)
signal stamina_exhausted
signal stun_changed(on: bool)
signal flashlight_toggled(on: bool)
signal crank_changed(turning: bool)
signal prompt_changed(text: String, hold_time: float)
signal prompt_progress(fraction: float)
@warning_ignore_restore("unused_signal")

var coherence: float = Tuning.COHERENCE_MAX


## Mirrors Player.apply_coherence's signal (clamped, delta as applied).
func set_coherence(v: float, source: StringName = &"debug") -> void:
	var before := coherence
	coherence = clampf(v, 0.0, Tuning.COHERENCE_MAX)
	coherence_changed.emit(coherence, coherence - before, source)


## Mirrors Player.reset_for_run's signals.
func reset(start: float = Tuning.COHERENCE_MAX) -> void:
	coherence = start
	coherence_changed.emit(coherence, 0.0, &"reset")
	stamina_changed.emit(Tuning.STAMINA_MAX)
	charge_changed.emit(Tuning.FLASH_CHARGE_MAX)
	flashlight_toggled.emit(false)
	crank_changed.emit(false)
	stun_changed.emit(false)
	hidden_changed.emit(false)
	prompt_changed.emit("", 0.0)
	noclip_state.emit(0.0, &"", true, &"")
