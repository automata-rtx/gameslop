class_name ErrorFlicker
extends ErrorBase
## Flicker (08 §5). Rule: it lives in lit fixtures; it lunges at the player who stands in
## its light; it jumps to the flashlight kept on near it. Counter: darkness (flashlight off,
## unlit groups); chemical light is immune. Tell: its group's fixtures stutter at 8 to 20 Hz
## (only Flicker makes lights flicker). Cost: 30 on a lunge.
##
## No body: it is a fixture group id (`current_group`) in the level's LightPool; its
## position (proximity, captions, the lunge push) is the group centroid's floor projection.
## Every distance is XZ (FlickerHabitat). Senses: proximity (the lit area) and hearing at
## 0.8, which only steers hops. States (08 §5):
##   Resident  the group stutters (8 Hz); every 6 to 12 s (x 1.2..0.7) it hops to an adjacent
##             habitable group: with p = 0.4 + 0.4 x aggression the one nearest what it last
##             heard, else a random one (the Director's hint, when held, replaces random).
##   Stalk     the player stands in the group's lit area: charge 0 -> 1 over 2.0 s (x 1.3..0.8),
##             the stutter rising 8 -> 20 Hz; outside it drains at 2/s, and at 0 it is an evasion.
##   Lunge     at charge 1: the group flashes white 2 frames; contact for 30 (through the gates)
##             if the player is still in the lit area within 6 m of a fixture of the group; hit
##             or miss the group is dark and silent 1.5 s, then it hops to a random adjacent
##             group and is Satiated (no Stalk, no attach for 20 s).
##   Attached  the flashlight on within 4 m (x RunState.flicker_attract_mult: Lightbearer 6 m)
##             of a lit fixture of its group for 1.5 s: the beam stutters, the group goes
##             steady, the charge builds wherever the player goes; at 1 the beam flashes white
##             and contact for 30 with no push, then it sheds and is Satiated. Turning the
##             flashlight off sheds it (an evasion): it drops to the nearest habitable group
##             within 10 m of the player, else it despawns. Cranking does not shed it.
## A group that loses power is left for the nearest habitable group within 10 m, else Flicker
## despawns: it stays Dormant with `despawned` until the Director's respawn_at (10 §4).
## Chase-like states map: Wander, Search and Chase are Resident (the Director's wake,
## awake arrival and the base machine name them).

## The LightPool it lives in (the level's; hand-built rooms set it).
var light_pool: LightPool
## The fixture group it lives in; -1 while attached or despawned.
var current_group: int = -1
## Stalk charge 0..1.
var charge: float = 0.0
## Continuous seconds the attach condition has held.
var attach_time: float = 0.0
## Lost its habitat: Dormant until the Director respawns it (10 §4).
var despawned: bool = false
## > 0 overrides RunState.flicker_attract_mult (benches, tests).
var attract_mult_override: float = 0.0
## Counters for tests and the bench.
var hops: int = 0
var lunges: int = 0
var sheds: int = 0

var _hop_left: float = 0.0
var _lunge_frames: int = 0
var _lunge_attached: bool = false
var _dark_group: int = -1
var _dark_left: float = 0.0
var _silence_left: float = -1.0
var _hop_after_dark: bool = false
var _retreat_from: Vector3 = Vector3.INF
var _flicker_group: int = -1
var _present_rng: RandomNumberGenerator = Seeds.rng(0)
var _beam_state: Array = Fixture.new_stutter_state()
var _flash_frame: int = -1
var _flash_usec: int = -1
## The stutter's sound emitter (the group centroid, or the beam while attached).
var _emitter: Node3D
var _loops: Array[AudioLoop] = []


func _configure() -> void:
	error_id = &"flicker"
	senses.sight_range = 0.0
	senses.hearing_mult = Tuning.FLICKER_HEARING_MULT
	_emitter = Node3D.new()
	_emitter.name = "Emitter"
	_emitter.top_level = true
	add_child(_emitter)
	_loops = FlickerPresent.stutter_loops(_emitter)


func _on_seeded() -> void:
	_present_rng = Seeds.rng(Seeds.derive(seed_value, "flicker_present"))


func bind_level(p_level: Level) -> void:
	super.bind_level(p_level)
	pool()


func _exit_tree() -> void:
	FlickerPresent.stutter(_loops, false, 0.0)
	_show_group(-1)
	FlickerLunge.end_dark(self)
	_beam_steady()


## The pool (the bound level's when none was set).
func pool() -> LightPool:
	if light_pool == null and _level_bound and is_instance_valid(level):
		light_pool = level.get(&"light_pool") as LightPool
	return light_pool


# --- 08 §8 aggression -----------------------------------------------------------------------

func hop_interval() -> float:
	return rng.randf_range(Tuning.FLICKER_HOP_MIN, Tuning.FLICKER_HOP_MAX) \
		* aggr_lerp(Tuning.FLICKER_HOP_MULT_LOW, Tuning.FLICKER_HOP_MULT_HIGH, aggression)


func charge_time() -> float:
	return Tuning.FLICKER_CHARGE_TIME * aggr_lerp(Tuning.FLICKER_LUNGE_CHARGE_MULT_LOW, Tuning.FLICKER_LUNGE_CHARGE_MULT_HIGH, aggression)


func near_chance() -> float:
	return Tuning.FLICKER_HOP_NEAR_CHANCE_BASE + Tuning.FLICKER_HOP_NEAR_CHANCE_PER_AGGR * aggression


## 05 §7 Lightbearer: Flicker is attracted to the light from 1.5x the distance.
func attract_mult() -> float:
	if attract_mult_override > 0.0:
		return attract_mult_override
	if GameState.run != null and GameState.is_run_active():
		return maxf(GameState.run.flicker_attract_mult, 0.0)
	return 1.0


func attach_dist() -> float:
	return Tuning.FLICKER_ATTACH_DIST * attract_mult()


## The stutter rate: 8 Hz resident, rising to 20 Hz with the charge.
func stutter_hz() -> float:
	return lerpf(Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ, clampf(charge, 0.0, 1.0))


# --- position and the Director link -----------------------------------------------------------

func distance_to_player() -> float:
	if not has_player() or not is_inside_tree():
		return INF
	if state == Tuning.ERROR_STATE_ATTACHED or (state == Tuning.ERROR_STATE_LUNGE and _lunge_attached):
		return 0.0
	if current_group < 0:
		return INF
	return FlickerHabitat.flat(global_position, player.global_position)


## PlayerContact asks: the attached lunge has no body to push from (08 §5).
func contact_pushes() -> bool:
	return not _lunge_attached


func is_attached() -> bool:
	return state == Tuning.ERROR_STATE_ATTACHED


## Wander, Search and Chase are Flicker's Resident; with no habitat it stays Dormant.
func transition_to(to: StringName, reason: String = "", force: bool = false) -> void:
	if to == Tuning.ERROR_STATE_WANDER or to == Tuning.ERROR_STATE_SEARCH or to == Tuning.ERROR_STATE_CHASE:
		if not _ensure_habitat():
			return
		to = Tuning.ERROR_STATE_RESIDENT
	super.transition_to(to, reason, force)


func wake() -> void:
	if despawned:
		return
	super.wake()


## A Director hint steers Resident and Satiated hops; `immediate` hops toward it now.
func hint(destination: Vector3, immediate: bool = false) -> void:
	super.hint(destination, false)
	if immediate and (state == Tuning.ERROR_STATE_RESIDENT or state == Tuning.ERROR_STATE_SATIATED) and _dark_left <= 0.0:
		_hop_left = 0.0


## 10 §4: the Director respawns a despawned Flicker at a lit group. False when the group is
## not habitable.
func respawn_at(group: int) -> bool:
	if not FlickerHabitat.habitable(pool(), group):
		return false
	despawned = false
	_set_group(group)
	FlickerPresent.spark(self, light_pool.group_centroid(group))
	transition_to(Tuning.ERROR_STATE_RESIDENT, "respawn", true)
	return true


## The group nearest the error's position within 10 m, when it has none (wake, spawn).
func _ensure_habitat() -> bool:
	if FlickerHabitat.habitable(pool(), current_group):
		return true
	var g := FlickerHabitat.nearest_habitable(light_pool, global_position, Tuning.FLICKER_HABITAT_LOST_DIST)
	if g < 0:
		despawned = true
		return false
	_set_group(g)
	return true


func _set_group(g: int) -> void:
	current_group = g
	if g >= 0 and light_pool != null and is_inside_tree():
		var c := light_pool.group_centroid(g)
		global_position = Vector3(c.x, _floor_y(c), c.z)
	_apply_presence()


func _floor_y(c: Vector3) -> float:
	if grid != null:
		var cell := grid.cell_of(c)
		if grid.in_bounds(cell):
			return grid.floor_y(cell)
	return player.global_position.y if has_player() else 0.0


# --- the rule ---------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	if pool() == null:
		return
	FlickerLunge.tick_dark(self, delta)
	if state != Tuning.ERROR_STATE_ATTACHED and state != Tuning.ERROR_STATE_LUNGE and current_group >= 0 \
			and _dark_left <= 0.0 and not FlickerHabitat.habitable(light_pool, current_group):
		# "Does not persist in darkness": the nearest lit group within 10 m, else despawn.
		var g := FlickerHabitat.nearest_habitable(light_pool, global_position, Tuning.FLICKER_HABITAT_LOST_DIST, current_group)
		if g < 0:
			FlickerMoves.despawn(self, "habitat dark")
			return
		FlickerMoves.hop_to(self, g)
	_tick_sound()
	match state:
		Tuning.ERROR_STATE_RESIDENT:
			_tick_resident(delta)
		Tuning.ERROR_STATE_STALK:
			_tick_stalk(delta)
		Tuning.ERROR_STATE_LUNGE:
			_tick_lunge()
		Tuning.ERROR_STATE_ATTACHED:
			_tick_attached(delta)
		Tuning.ERROR_STATE_SATIATED:
			FlickerMoves.tick_satiated(self, delta)


func _player_in_lit_area() -> bool:
	return has_player() and not player.is_hidden() \
		and FlickerHabitat.in_lit_area(light_pool, current_group, player.global_position)


## The attach condition: the flashlight on within the attach distance of a lit fixture of
## its group (a clear grid line). Cranking changes nothing.
func _beam_near() -> bool:
	return has_player() and player.flashlight.on and not player.is_hidden() \
		and FlickerHabitat.near_lit_fixture(light_pool, current_group, player.global_position, attach_dist())


## Advances the attach timer; true when Flicker attached this step.
func _attach_step(delta: float) -> bool:
	if not _beam_near():
		attach_time = 0.0
		return false
	attach_time += delta
	if attach_time < Tuning.FLICKER_ATTACH_TIME:
		return false
	FlickerMoves.attach(self)
	return true


func _tick_resident(delta: float) -> void:
	if _attach_step(delta):
		return
	if _player_in_lit_area():
		transition_to(Tuning.ERROR_STATE_STALK, "in its light")
		if state == Tuning.ERROR_STATE_STALK:
			_notice()
		return
	_hop_left -= delta
	if _hop_left <= 0.0:
		FlickerMoves.hop_resident(self)
		_hop_left = hop_interval()


func _tick_stalk(delta: float) -> void:
	if _attach_step(delta):
		return
	if _player_in_lit_area():
		charge = minf(charge + delta / charge_time(), 1.0)
	else:
		charge = maxf(charge - Tuning.FLICKER_CHARGE_DRAIN * delta, 0.0)
		if charge <= 0.0:
			transition_to(Tuning.ERROR_STATE_RESIDENT, "charge drained")
			_evade()
			return
	light_pool.set_group_flicker_rate(current_group, stutter_hz())
	if charge >= 1.0:
		FlickerLunge.begin_lunge(self, false)


func _tick_attached(delta: float) -> void:
	if not has_player() or not player.flashlight.on:
		FlickerMoves.shed(self, "flashlight off", true)
		return
	global_position = player.global_position
	charge = minf(charge + delta / charge_time(), 1.0)
	FlickerPresent.beam_stutter(player.flashlight, _beam_state, stutter_hz(), delta, _present_rng)
	if charge >= 1.0:
		FlickerLunge.begin_lunge(self, true)


func _tick_lunge() -> void:
	_lunge_frames += 1
	if _lunge_attached and has_player():
		FlickerPresent.beam_flash(player.flashlight, _flash_frame, _flash_usec)
	if _lunge_frames >= Tuning.FLICKER_LUNGE_FLASH_FRAMES:
		FlickerLunge.resolve_lunge(self)


## 03: the stutter sounds wherever Flicker shows (its stuttering group, or the beam).
func _tick_sound() -> void:
	var beam := state == Tuning.ERROR_STATE_ATTACHED and has_player()
	var on := beam or _flicker_group >= 0
	if on and _emitter != null:
		var at := player.flashlight.beam_origin() if beam else light_pool.group_centroid(_flicker_group)
		if _emitter.global_position != at:  # R21: a write re-propagates to both 3D players
			_emitter.global_position = at
	FlickerPresent.stutter(_loops, on, charge)


# --- state hooks ------------------------------------------------------------------------------

func _enter_state(to: StringName, from: StringName) -> void:
	match to:
		Tuning.ERROR_STATE_RESIDENT:
			charge = 0.0
			_hop_left = hop_interval()
		Tuning.ERROR_STATE_SATIATED:
			charge = 0.0
			attach_time = 0.0
			if _retreat_from == Vector3.INF or from != Tuning.ERROR_STATE_LUNGE:
				_retreat_from = global_position
			if from != Tuning.ERROR_STATE_LUNGE:
				_hop_left = hop_interval()
		Tuning.ERROR_STATE_DORMANT:
			charge = 0.0
			attach_time = 0.0
			_silence_left = -1.0
			_hop_after_dark = false
			FlickerLunge.end_dark(self)
	_apply_presence()


func _exit_state(from: StringName, to: StringName) -> void:
	if from == Tuning.ERROR_STATE_ATTACHED or (from == Tuning.ERROR_STATE_LUNGE and _lunge_attached):
		_beam_steady()
	if from == Tuning.ERROR_STATE_LUNGE and to != Tuning.ERROR_STATE_SATIATED:
		_lunge_attached = false


## The tell: the group stutters while Flicker lives in it (Resident, Stalk, Satiated) and is
## not dark; it goes steady when Flicker leaves, attaches or is dormant.
func _apply_presence() -> void:
	var want := -1
	if current_group >= 0 and _dark_group != current_group and state in [Tuning.ERROR_STATE_RESIDENT,
			Tuning.ERROR_STATE_STALK, Tuning.ERROR_STATE_SATIATED]:
		want = current_group
	_show_group(want)
	if want < 0 and state != Tuning.ERROR_STATE_ATTACHED:
		FlickerPresent.stutter(_loops, false, 0.0)
	if want >= 0:
		light_pool.set_group_flicker_rate(want, stutter_hz())


func _show_group(want: int) -> void:
	if want == _flicker_group:
		return
	if _flicker_group >= 0 and light_pool != null and is_instance_valid(light_pool):
		light_pool.set_group_flicker(_flicker_group, false)
	_flicker_group = want
	if want >= 0:
		light_pool.set_group_flicker(want, true)


func _beam_steady() -> void:
	if player != null and is_instance_valid(player) and player.flashlight != null:
		FlickerPresent.beam_steady(player.flashlight)


func _on_player_gone() -> void:
	_beam_steady()


func _on_contact() -> void:
	AudioManager.play_3d(&"error_contact_hit", player.global_position if has_player() else global_position, FlickerPresent.BUS)


func debug_info() -> Dictionary:
	var d := super.debug_info()
	d["flicker"] = "group %d, charge %.2f, attach %.1f s, hops %d, lunges %d%s" % [current_group, charge,
		attach_time, hops, lunges, ", despawned" if despawned else ""]
	return d
