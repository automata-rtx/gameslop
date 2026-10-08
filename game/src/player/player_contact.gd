class_name PlayerContact
extends RefCounted
## Error contact and the dissolve (06 §9, 11 §3), split out of Player (14 §6 400-line
## limit). Behaviour unchanged; Player.contact and Player._dissolve delegate here.


## 06 §9 contact rules: cost (at most COHERENCE_MAX_SINGLE_HIT, 05 §9 rule 5), 1.2 s
## stun, 1.5 m push, trauma 0.6, 60 ms hitstop. Refused (false, nothing applied) when
## the player has no body to touch: passing through a wall, Landing, dropping,
## dissolving, cinematic. Contact exclusivity (3 s) belongs to the Director (10 §4):
## `contact_gate` is asked after the player's own refusals and may refuse too.
static func contact(p: Player, error: Node3D, amount: float) -> bool:
	if not p.can_be_contacted():
		return false
	if p.contact_gate.is_valid() and not bool(p.contact_gate.call(error)):
		return false
	var id := error_id(error)
	if p.hiding.spot != null:
		p.hiding.eject()
	if p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE) and p.noclip_targeting != null \
			and p.noclip_targeting.has_method(&"cancel"):
		p.noclip_targeting.call(&"cancel")
	p.contacted.emit(id)
	p.apply_coherence(-minf(absf(amount), Tuning.COHERENCE_MAX_SINGLE_HIT), id)
	if p.is_dissolving():
		return true
	if p.state_machine.transition_to(PlayerStateMachine.STUNNED) or p.is_stunned():
		p._stun_left = Tuning.CONTACT_STUN_TIME
		p.stun_changed.emit(true)
	if error != null and error.is_inside_tree():
		p.locomotion.push(p.global_position - error.global_position)
	else:
		p.locomotion.push(p.global_transform.basis.z)
	# 11 §3 error contact: flash/CA/grain (post), contact hit, push + trauma + stun, readout.
	p.rig.add_trauma(Tuning.CONTACT_TRAUMA)
	CoherenceRenderer.pulse(&"hit")
	p.sounds.play(&"error_contact_hit")
	NoiseModel.emit(p.global_position, Tuning.NOISE_CONTACT_RADIUS, Tuning.NOISE_KIND_TEAR)
	Clock.hitstop(Tuning.CONTACT_HITSTOP_MS)
	return true


static func error_id(error: Node3D) -> StringName:
	if error != null:
		var id: Variant = error.get(&"error_id")
		if id is StringName or id is String:
			return StringName(id)
	return Player.SOURCE_UNKNOWN_ERROR


## 06 §9 dissolve: input locked; 11 §3: the grid dissolve (post), the dissolve sound,
## 0.02 m drift. The run flow (M1.9) plays the 1.5 s sequence and then calls
## GameState.end_run(cause).
static func dissolve(p: Player, cause: StringName) -> void:
	if not p.state_machine.transition_to(PlayerStateMachine.DISSOLVING):
		return
	p.velocity = Vector3.ZERO
	p.flashlight.set_cranking(false)
	p.interactor.clear()
	p._stun_left = 0.0
	var tw := p.create_tween()
	tw.tween_method(p.rig.drift, Vector3.ZERO, Player.DISSOLVE_DRIFT_DIR * Tuning.FEEDBACK_DISSOLVE_DRIFT,
			Tuning.COHERENCE_DISSOLVE_TIME)
	p.sounds.clear_loss()
	CoherenceRenderer.pulse(&"dissolve")
	p.sounds.play(&"dissolve")
	p.dissolved.emit(cause)
