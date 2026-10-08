class_name FlickerMoves
extends RefCounted
## Flicker's moves (08 §5), split out of ErrorFlicker under the 400-line limit: hops between
## adjacent habitable groups (Resident: toward what it heard or the Director's hint, else
## random; Satiated: toward the hint, else away from where it struck), attaching to the
## beam, shedding off it, and despawning when it has no habitat. Static, on the error.


static func hop_resident(e: ErrorFlicker) -> void:
	var lk := e.senses.last_known_pos if e.senses.has_last_known() else Vector3.INF
	var h := e._hint if e._has_hint else Vector3.INF
	var g := FlickerHabitat.pick_hop(e.light_pool, e.current_group, e.rng, e.near_chance(), lk, h)
	if g >= 0:
		FlickerMoves.hop_to(e, g)
	FlickerMoves.clear_reached_hint(e)


static func hop_retreat(e: ErrorFlicker) -> void:
	var ids := FlickerHabitat.habitable_neighbours(e.light_pool, e.current_group)
	if ids.is_empty():
		return
	var g := -1
	if e._has_hint:
		g = FlickerHabitat.by_centroid(e.light_pool, ids, e._hint)
	elif e._retreat_from != Vector3.INF:
		g = FlickerHabitat.by_centroid(e.light_pool, ids, e._retreat_from, true)
		var here := FlickerHabitat.flat(e.light_pool.group_centroid(e.current_group), e._retreat_from)
		if FlickerHabitat.flat(e.light_pool.group_centroid(g), e._retreat_from) <= here:
			g = -1
	if g >= 0:
		FlickerMoves.hop_to(e, g)
	FlickerMoves.clear_reached_hint(e)


static func clear_reached_hint(e: ErrorFlicker) -> void:
	if not e._has_hint or e.current_group < 0:
		return
	var here := FlickerHabitat.flat(e.light_pool.group_centroid(e.current_group), e._hint)
	for id in FlickerHabitat.habitable_neighbours(e.light_pool, e.current_group):
		if FlickerHabitat.flat(e.light_pool.group_centroid(id), e._hint) < here:
			return
	e.clear_hint()


static func hop_to(e: ErrorFlicker, g: int) -> void:
	if g == e.current_group:
		return
	var from := e.light_pool.group_centroid(e.current_group) if e.current_group >= 0 else Vector3.INF
	FlickerPresent.spark(e, from)
	e._set_group(g)
	FlickerPresent.spark(e, e.light_pool.group_centroid(g))
	e.hops += 1


static func attach(e: ErrorFlicker) -> void:
	FlickerPresent.spark(e, e.light_pool.group_centroid(e.current_group))
	e._set_group(-1)
	e.attach_time = 0.0
	e._beam_state = [true, 0.0]
	e.transition_to(Tuning.ERROR_STATE_ATTACHED, "beam on near it %.1f s" % Tuning.FLICKER_ATTACH_TIME)
	if e.state == Tuning.ERROR_STATE_ATTACHED:
		e._notice()
		if e.has_player():
			FlickerPresent.spark(e, e.player.flashlight.beam_origin())


static func shed(e: ErrorFlicker, reason: String, evasion: bool) -> void:
	e._beam_steady()
	var at := e.player.global_position if e.has_player() else e.global_position
	if e.has_player():
		FlickerPresent.spark(e, e.player.flashlight.beam_origin())
	e.sheds += 1
	e.charge = 0.0
	e.attach_time = 0.0
	if evasion:
		e._evade()
	var g := FlickerHabitat.nearest_habitable(e.light_pool, at, Tuning.FLICKER_SHED_DIST)
	if g < 0:
		FlickerMoves.despawn(e, reason)
		return
	e._set_group(g)
	FlickerPresent.spark(e, e.light_pool.group_centroid(g))
	if e.state == Tuning.ERROR_STATE_ATTACHED:
		e.transition_to(Tuning.ERROR_STATE_RESIDENT, "shed: %s" % reason)


static func despawn(e: ErrorFlicker, reason: String) -> void:
	e._set_group(-1)
	e.despawned = true
	e._engaged = false
	e.transition_to(Tuning.ERROR_STATE_DORMANT, "despawn: %s" % reason)


## Satiated (08 §5): after the dark the hop to a random adjacent group, then retreat hops;
## Resident again when the 20 s are over.
static func tick_satiated(e: ErrorFlicker, delta: float) -> void:
	e._satiated_left -= delta
	if e.current_group < 0 and not e.despawned:
		# Retreated while attached: shed now (no lunge, no evasion: the Director sent it).
		FlickerMoves.shed(e, "retreat", false)
		if e.despawned:
			return
	if e._dark_left <= 0.0:
		if e._hop_after_dark:
			e._hop_after_dark = false
			var ids := FlickerHabitat.habitable_neighbours(e.light_pool, e.current_group)
			if not ids.is_empty():
				FlickerMoves.hop_to(e, ids[e.rng.randi_range(0, ids.size() - 1)])
			e._hop_left = e.hop_interval()
		else:
			e._hop_left -= delta
			if e._hop_left <= 0.0:
				FlickerMoves.hop_retreat(e)
				e._hop_left = e.hop_interval()
	if e._satiated_left <= 0.0 and e._dark_left <= 0.0:
		e.transition_to(Tuning.ERROR_STATE_RESIDENT, "satiated over")
