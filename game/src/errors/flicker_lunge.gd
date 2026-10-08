class_name FlickerLunge
extends RefCounted
## Flicker's lunge (08 §5, 02 §8, 03, 11 §3), split out of ErrorFlicker under the 400-line
## limit: the 2-frame white flash (the group, or the beam when attached), contact for 30
## through the gates (no push when attached), the group dark and the World bus silent for
## 1.5 s, then the hop and Satiated. Static, on the error.


static func begin_lunge(e: ErrorFlicker, attached: bool) -> void:
	e._lunge_attached = attached
	e._lunge_frames = 0
	e.lunges += 1
	e.charge = 1.0
	e._flash_frame = Engine.get_process_frames()
	e._flash_usec = Time.get_ticks_usec()
	var at := e.global_position
	if attached and e.has_player():
		at = e.player.flashlight.beam_origin()
		FlickerPresent.beam_flash(e.player.flashlight, e._flash_frame, e._flash_usec)
	elif e.current_group >= 0:
		at = e.light_pool.group_centroid(e.current_group)
		e.light_pool.group_lunge_flash(e.current_group)
	FlickerPresent.play(FlickerPresent.FLASH_SOUND, at)
	e._silence_left = Tuning.FLICKER_FLASH_NOISE_MS / 1000.0
	e.transition_to(Tuning.ERROR_STATE_LUNGE, "charge 1.0")


static func resolve_lunge(e: ErrorFlicker) -> void:
	if e._lunge_attached:
		FlickerLunge.resolve_attached_lunge(e)
		return
	var g := e.current_group
	var hit := e._player_in_lit_area() and FlickerHabitat.group_distance(e.light_pool, g, e.player.global_position) <= Tuning.FLICKER_LUNGE_RANGE
	e._retreat_from = e.global_position
	# Hit or miss: the group is dark and silent for 1.5 s, then it hops (08 §5).
	e._dark_group = g
	e._dark_left = Tuning.FLICKER_DARK_TIME
	e._hop_after_dark = true
	e.light_pool.set_group_lunge_dark(g, true)
	if hit and e.try_contact(Tuning.FLICKER_LUNGE_COST):
		return
	FlickerLunge.satiate(e, "lunge %s" % ("refused" if hit else "missed"))


static func resolve_attached_lunge(e: ErrorFlicker) -> void:
	e._beam_steady()
	e._retreat_from = e.player.global_position if e.has_player() else e.global_position
	var hit := e.has_player() and not e.player.is_hidden()
	var contacted := hit and e.try_contact(Tuning.FLICKER_LUNGE_COST)
	e._lunge_attached = false
	# Then it sheds itself and is Satiated (08 §5); the shed is not an evasion.
	var g := FlickerHabitat.nearest_habitable(e.light_pool, e._retreat_from, Tuning.FLICKER_SHED_DIST)
	if e.has_player():
		FlickerPresent.spark(e, e.player.flashlight.beam_origin())
	e.sheds += 1
	if g < 0:
		FlickerMoves.despawn(e, "shed after lunge")
		return
	e._set_group(g)
	FlickerPresent.spark(e, e.light_pool.group_centroid(g))
	if not contacted:
		FlickerLunge.satiate(e, "lunge %s" % ("refused" if hit else "missed"))


static func satiate(e: ErrorFlicker, reason: String) -> void:
	if e.state != Tuning.ERROR_STATE_LUNGE:
		return
	e._engaged = false
	e._satiated_left = Tuning.ERROR_SATIATED_TIME
	e.transition_to(Tuning.ERROR_STATE_SATIATED, reason)


static func tick_dark(e: ErrorFlicker, delta: float) -> void:
	if e._silence_left >= 0.0:
		e._silence_left -= delta
		if e._silence_left < 0.0:
			FlickerPresent.silence()
	if e._dark_left <= 0.0:
		return
	e._dark_left -= delta
	if e._dark_left <= 0.0:
		FlickerLunge.end_dark(e)
		e._apply_presence()


static func end_dark(e: ErrorFlicker) -> void:
	if e._dark_group >= 0 and e.light_pool != null and is_instance_valid(e.light_pool):
		e.light_pool.set_group_lunge_dark(e._dark_group, false)
	e._dark_group = -1
	e._dark_left = 0.0
