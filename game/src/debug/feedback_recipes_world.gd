class_name FeedbackRecipesWorld
extends FeedbackRecipesPlayer
## Recipes for noclip (11 §2) and for the things that happen to the player (11 §3): Coherence,
## errors, the exit and breaker, notes, and the Descent's transitions.


# --- noclip -----------------------------------------------------------------------------------

func noclip_charge(b: FeedbackBench) -> void:
	var spots := noclip_spots(b)
	await face_edge(b, spots[&"good"])
	b.set_coherence(80.0)
	await b.arm()
	b.anchor()
	b.press(&"noclip")
	await b.ticks(6)


func noclip_cancel(b: FeedbackBench) -> void:
	var spots := noclip_spots(b)
	await face_edge(b, spots[&"good"])
	b.set_coherence(80.0)
	var nt := b.player().noclip_targeting as NoclipTargeting
	b.press(&"noclip")
	await b.until(func() -> bool: return nt.charge_fraction() >= 0.4, 240)
	b.anchor()
	b.release(&"noclip")
	await b.ticks(4)


func noclip_invalid(b: FeedbackBench) -> void:
	var spots := noclip_spots(b)
	if (spots[&"bad"] as Array).is_empty():
		push_warning("noclip_invalid: no refused wall in this level")
		return
	await face_edge(b, spots[&"bad"])
	b.set_coherence(80.0)
	await b.arm()
	b.anchor()
	b.press(&"noclip")
	await b.ticks(6)


func noclip_commit_wall(b: FeedbackBench) -> void:
	var spots := noclip_spots(b)
	await face_edge(b, spots[&"good"])
	b.set_coherence(80.0)
	await b.arm()
	# noclip_committed fires at the end of a wall pass (R6); the commit itself is the
	# switch into NoclipPass, which happens before its sound and motion.
	var sm := b.player().state_machine
	var on_pass := func(_from: StringName, to: StringName) -> void:
		if to == PlayerStateMachine.NOCLIP_PASS:
			b.anchor()
	sm.state_changed.connect(on_pass)
	b.press(&"noclip")
	await b.until(b.is_anchored, 400)
	sm.state_changed.disconnect(on_pass)
	b.release(&"noclip")


func noclip_commit_floor(b: FeedbackBench) -> void:
	var p := b.player()
	await b.pose_sightline()
	b.set_coherence(90.0)
	p.flashlight.set_on(true, true)
	p.rig.add_pitch(deg_to_rad(-80.0))
	await b.ticks(6)
	await b.arm()
	b.anchor_on(p.noclip_committed)
	b.press(&"noclip")
	await b.until(b.is_anchored, 600)
	b.release(&"noclip")


# --- Coherence and contact ----------------------------------------------------------------------

func coherence_loss(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.set_coherence(70.0)
	# Row isolation: earlier rows' losses may still hold the loss tick's rate limit (11 §3
	# "rate-limited"); let it lapse so this row's first tick is its own.
	b.player().sounds.clear_loss()
	await b.ticks(12)
	await b.arm()
	b.anchor()
	b.player().apply_coherence(-10.0, &"bench")


func coherence_gain(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.set_coherence(60.0)
	await b.arm()
	b.anchor()
	b.player().apply_coherence(10.0, &"bench")


func error_contact(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.set_coherence(70.0)
	var s := spawn_error(b, &"still", ahead(b, -1.0))
	await b.arm()
	b.anchor()
	b.player().contact(s, Tuning.COHERENCE_CONTACT_STILL)
	await b.ticks(10)
	free_error(s)


func inside_static(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.set_coherence(90.0)
	var p := b.player()
	var s := spawn_error(b, &"static", p.global_position)
	await b.arm()
	b.anchor()
	s.wake()
	await b.until(func() -> bool: return (s as ErrorStatic).inside, 120)
	await b.ticks(30)
	free_error(s)
	CoherenceRenderer.set_static(0.0)
	AudioManager.set_static_inside(false)
	p.rig.set_jitter(0.0)


func still_within_8m(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.anchor()
	EventBus.error_proximity.emit(&"still", 6.0)
	await b.ticks(30)
	EventBus.error_proximity.emit(&"still", 40.0)


func still_observed(b: FeedbackBench) -> void:
	await b.pose_sightline()
	var p := b.player()
	p.flashlight.set_on(true, true)
	var s := spawn_error(b, &"still", ahead(b, 7.0)) as ErrorStill
	s.wake()
	await b.until(func() -> bool: return s.observed, 120)
	# The render tick lands on the physics tick that crosses 2 s; anchor on it.
	await b.until(func() -> bool: return s.ticks > 0, 400)
	b.anchor()
	await b.ticks(8)
	free_error(s)


## 11 §3 Echo at 4 m: an awake Echo steps inside 4 m of the player (placed, so the frame is
## exact): the shimmer appears and the breath swell plays at once.
func echo_4m(b: FeedbackBench) -> void:
	await b.pose_sightline()
	var e := spawn_error(b, &"echo", ahead(b, 7.0)) as ErrorEcho
	e.senses.hearing_mult = 0.0
	e.wake()
	await b.ticks(3)
	await b.arm()
	b.anchor()
	e.place_at(ahead(b, 3.5))
	# Echo comes inside 4 m by walking: the stride that lands it plays its step (the R
	# column's `[footsteps, …, late]` caption, M2.12). The placement stands in for the walk.
	EchoPresent.play_step(e, NoiseModel.DEFAULT_SURFACE)
	await b.ticks(8)
	free_error(e)


## 11 §3 Flicker lunge: the player stands under a lit fixture group with Flicker in it; at
## charge 1 the group flashes white 2 frames then goes dark 1.5 s, the World bus falls
## silent, and the contact lands (trauma, Coherence).
func flicker_lunge(b: FeedbackBench) -> void:
	await b.pose_sightline()
	var p := b.player()
	p.flashlight.set_on(false, true)
	var pool := b.run.level.light_pool
	var best: Fixture = null
	for f in pool.fixtures():
		if f.powered and f.group_id >= 0 and (best == null or FlickerHabitat.flat(f.global_position, p.global_position)
				< FlickerHabitat.flat(best.global_position, p.global_position)):
			best = f
	if best == null:
		push_warning("flicker_lunge: no lit fixture")
		return
	b.place(Vector3(best.global_position.x, p.global_position.y, best.global_position.z), p.rotation.y, 0.0)
	pool.reevaluate()
	var e := spawn_error(b, &"flicker", Vector3(best.global_position.x, p.global_position.y, best.global_position.z)) as ErrorFlicker
	e.set_aggression(0.75)
	await b.arm()
	# Anchor on the Lunge transition itself: the flash and the noise follow it in the same call.
	var on_lunge := func(_from: StringName, to: StringName) -> void:
		if to == Tuning.ERROR_STATE_LUNGE:
			b.anchor()
	e.state_changed.connect(on_lunge)
	e.wake()
	await b.until(b.is_anchored, 240)
	await b.ticks(30)
	free_error(e)


# --- the exit and the breaker ----------------------------------------------------------------------

func exit_seen(b: FeedbackBench) -> void:
	var ex := b.run.exit
	var cam := b.player().rig.camera
	ex.set_physics_process(false)
	for dist: float in [6.0, 5.0, 4.0, 3.0, 2.5]:
		var stand := ex.to_global(Vector3(0.0, 0.0, -dist))
		var eye := stand + Vector3(0.0, LevelShots.EYE, 0.0)
		var d := ex.sight_point.global_position - eye
		b.place(stand, FeedbackBench.yaw_to(eye, ex.sight_point.global_position),
				atan2(d.y, Vector2(d.x, d.z).length()))
		b.run.level.light_pool.reevaluate()
		await b.ticks(3)
		if ex.check_seen(cam):
			break
	ex.is_seen = false
	await b.arm()
	b.anchor_on(ex.seen)
	ex.set_physics_process(true)
	await b.until(b.is_anchored, 240)


func breaker(b: FeedbackBench) -> void:
	var br := b.run.breaker
	if br == null or not await face_interactable(b, br.interactable, 1.4):
		push_warning("breaker: none in reach")
		return
	probe(b, &"I", "lever", func() -> Variant: return br.pivot.rotation)
	await b.arm()
	b.anchor_on(br.thrown)
	b.press(&"interact")
	await b.until(b.is_anchored, 200)
	b.release(&"interact")


## Chained after the breaker: the real event is the power wave reaching the exit. If it
## already came, the exit is closed again and unlocked by hand for the row.
func exit_unlocked(b: FeedbackBench) -> void:
	var ex := b.run.exit
	var stand := ex.to_global(Vector3(0.0, 0.0, -5.0))
	b.place(stand, FeedbackBench.yaw_to(stand, ex.global_position), 0.0)
	if ex.is_open():
		ex.set_lock(Tuning.LOCK_POWERED)
		await b.arm()
		b.anchor()
		ex.power()
		return
	b.anchor_on(ex.status_changed, func(st: StringName) -> bool: return st == Tuning.EXIT_STATUS_OPEN)
	await b.until(b.is_anchored, 1200)


# --- notes and unlocks ----------------------------------------------------------------------------

func note_found(b: FeedbackBench) -> void:
	await b.pose_sightline()
	var pickup := (load("res://scenes/interactables/note_pickup.tscn") as PackedScene).instantiate() as NotePickup
	pickup.note_id = DataRegistry.notes()[0].id
	b.run.level.content.add_child(pickup)
	pickup.global_position = ahead(b, 1.5)
	await b.ticks(4)
	var pid := pickup.get_instance_id()
	probe(b, &"I", "paper", func() -> Variant:
		var n := instance_from_id(pid) as NotePickup
		return [n.paper.scale, n.light.light_energy] if n != null else [])
	await b.arm()
	b.anchor()
	pickup.read()
	await b.ticks(4)


func unlock_earned(b: FeedbackBench) -> void:
	await b.pose_sightline()
	await b.arm()
	b.anchor()
	EventBus.unlock_earned.emit(&"glowstick")


# --- the Descent --------------------------------------------------------------------------------------

## Chained after noclip_commit_floor: the drop's arrival.
func arrival_drop(b: FeedbackBench) -> void:
	b.anchor_on(EventBus.level_entered, func(_d: int, _s: StringName, how: StringName) -> bool:
		return how == Tuning.RUN_ARRIVE_DROP)
	await b.until(b.is_anchored, 3000)
	await b.ticks(30)


func enter_exit(b: FeedbackBench) -> void:
	await b.until(func() -> bool: return b.run.phase == Run.PHASE_PLAYING and b.run.exit != null, 600)
	var ex := b.run.exit
	ex.open()
	ex.accepting = true
	b.place(ex.to_global(Vector3(0.0, 0.0, -2.0)), FeedbackBench.yaw_to(ex.to_global(Vector3(0.0, 0.0, -2.0)), ex.global_position), 0.0)
	await b.ticks(30)
	await b.arm()
	b.anchor_on(ex.entering)
	b.player().global_position = ex.to_global(Vector3(0.0, 0.1, -0.45))
	await b.until(b.is_anchored, 120)


## Chained after enter_exit: the cabin.
func landing(b: FeedbackBench) -> void:
	b.anchor_on(b.run.phase_changed, func(ph: StringName) -> bool: return ph == Run.PHASE_LANDING)
	await b.until(b.is_anchored, 600)
	await b.ticks(30)


## Chained after landing: the proper arrival.
func arrival_proper(b: FeedbackBench) -> void:
	b.anchor_on(EventBus.level_entered, func(_d: int, _s: StringName, how: StringName) -> bool:
		return how == Tuning.RUN_ARRIVE_PROPER)
	await b.until(b.is_anchored, 3000)
	await b.ticks(30)


func dissolve(b: FeedbackBench) -> void:
	await b.pose_sightline()
	b.set_coherence(30.0)
	await b.arm()
	b.anchor()
	b.player().apply_coherence(-1000.0, &"still")
	await b.ticks(40)
