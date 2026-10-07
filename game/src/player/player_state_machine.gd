class_name PlayerStateMachine
extends Node
## The player's state machine (06 §12). Flat, with an explicit transition table: the
## Player asks for a state and the table decides. Crank is a flag, not a state.
## Locomotion states (Idle, Walk, Sprint, Crouch) are re-derived from input every
## physics frame; the others are entered by events (noclip, contact, hide spot, run flow).

signal state_changed(from: StringName, to: StringName)

const IDLE := &"Idle"
const WALK := &"Walk"
const SPRINT := &"Sprint"
const CROUCH := &"Crouch"
const NOCLIP_CHARGE := &"NoclipCharge"
const NOCLIP_PASS := &"NoclipPass"
const STUNNED := &"Stunned"
const HIDDEN := &"Hidden"
const LANDING := &"Landing"
const DROPPING := &"Dropping"
const DISSOLVING := &"Dissolving"
const CINEMATIC := &"Cinematic"

const LOCOMOTION: Array[StringName] = [IDLE, WALK, SPRINT, CROUCH]
const ALL: Array[StringName] = [
	IDLE, WALK, SPRINT, CROUCH, NOCLIP_CHARGE, NOCLIP_PASS, STUNNED, HIDDEN,
	LANDING, DROPPING, DISSOLVING, CINEMATIC,
]

## from -> allowed targets (besides locomotion-to-locomotion, which is always allowed).
## 06 §12: Stunned interrupts NoclipCharge but not NoclipPass. 06 §8: a drop is committed
## before the fall, so Dropping never leads to Dissolving. Dissolving and Cinematic end
## the player's agency for the rest of the run.
const TRANSITIONS: Dictionary = {
	IDLE: [NOCLIP_CHARGE, STUNNED, HIDDEN, LANDING, DROPPING, DISSOLVING, CINEMATIC],
	WALK: [NOCLIP_CHARGE, STUNNED, HIDDEN, LANDING, DROPPING, DISSOLVING, CINEMATIC],
	SPRINT: [NOCLIP_CHARGE, STUNNED, HIDDEN, LANDING, DROPPING, DISSOLVING, CINEMATIC],
	CROUCH: [NOCLIP_CHARGE, STUNNED, HIDDEN, LANDING, DROPPING, DISSOLVING, CINEMATIC],
	NOCLIP_CHARGE: [IDLE, WALK, CROUCH, NOCLIP_PASS, DROPPING, STUNNED, DISSOLVING],
	NOCLIP_PASS: [IDLE, WALK, CROUCH, DISSOLVING],
	STUNNED: [IDLE, WALK, CROUCH, DISSOLVING],
	HIDDEN: [IDLE, CROUCH, STUNNED, DISSOLVING],
	LANDING: [IDLE, DISSOLVING, CINEMATIC],
	DROPPING: [IDLE, LANDING],
	DISSOLVING: [],
	CINEMATIC: [],
}

var state: StringName = IDLE


static func is_locomotion(s: StringName) -> bool:
	return s in LOCOMOTION


static func allowed(from: StringName, to: StringName) -> bool:
	if from == to:
		return false
	if is_locomotion(from) and is_locomotion(to):
		return true
	return to in (TRANSITIONS.get(from, []) as Array)


func can_transition(to: StringName) -> bool:
	return allowed(state, to)


## Moves to `to` if the table allows it; returns whether the state changed.
func transition_to(to: StringName) -> bool:
	if not can_transition(to):
		return false
	var from := state
	state = to
	state_changed.emit(from, to)
	return true


func is_in(s: StringName) -> bool:
	return state == s


## True while input drives the body (locomotion states, noclip charge, stunned).
func has_movement() -> bool:
	return is_locomotion(state) or state == NOCLIP_CHARGE or state == STUNNED


## Restores Idle unconditionally (a new run re-uses the persistent player, 14 §5).
func reset() -> void:
	if state == IDLE:
		return
	var from := state
	state = IDLE
	state_changed.emit(from, IDLE)
