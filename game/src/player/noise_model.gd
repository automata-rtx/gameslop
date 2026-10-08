class_name NoiseModel
extends RefCounted
## The player's noise model (06 §6). Static radius rules plus a per-player step cadence.
## Every player action emits EventBus.noise_emitted(pos, radius, kind); errors hear it if
## their distance is under the effective radius (walls reduce it 35% each, up to 3 rays).
## AudioManager plays the matching sample from the same event (03 Interfaces).

## Gaits that make steps.
const GAIT_WALK := &"walk"
const GAIT_SPRINT := &"sprint"
const GAIT_CROUCH := &"crouch"

## Surface used when the floor carries no `surface` meta.
const DEFAULT_SURFACE := &"carpet"
## Step surface id while standing in water (06 §6; Echo replays the water sample).
const SURFACE_WATER := &"water"

## Metres a follow-up ray starts inside the wall it just counted.
const WALL_STEP_IN := 0.02
## Meta a wall collider carries (the wall type name, e.g. &"WALL", &"SOFT", &"DOOR").
const WALL_META := &"wall_kind"
## A `wall_kind` that is not a wall: props, lockers, an open door leaf (06 Interfaces).
const KIND_PROP := &"PROP"
## Non-wall colliders a wall count may step over before it gives up.
const MAX_SKIPPED := 4

## Metres walked since the last step.
var _stride: float = 0.0


## 06 §6: walk radius by surface (or water), times the gait multiplier, times 1.6 wading.
static func step_radius(surface: StringName, gait: StringName, in_water: bool = false, wading: bool = false) -> float:
	var base: float
	if in_water:
		base = Tuning.NOISE_STEP_WATER_RADIUS
	else:
		base = float(Tuning.NOISE_STEP_RADIUS.get(surface, Tuning.NOISE_STEP_RADIUS[DEFAULT_SURFACE]))
	var r := base * gait_mult(gait)
	if wading:
		r *= Tuning.PLAYER_WADE_NOISE_MULT
	return r


static func gait_mult(gait: StringName) -> float:
	match gait:
		GAIT_SPRINT:
			return Tuning.NOISE_SPRINT_MULT
		GAIT_CROUCH:
			return Tuning.NOISE_CROUCH_MULT
	return 1.0


## 06 §6 step cadence: one step per 0.55 m walked (0.45 sprinting, 0.7 crouching).
static func step_distance(gait: StringName) -> float:
	match gait:
		GAIT_SPRINT:
			return Tuning.STEP_DISTANCE_SPRINT
		GAIT_CROUCH:
			return Tuning.STEP_DISTANCE_CROUCH
	return Tuning.STEP_DISTANCE_WALK


## Adds `distance` metres at `gait`; returns true when a step lands (at most one per call).
func advance(distance: float, gait: StringName) -> bool:
	_stride += distance
	var d := step_distance(gait)
	if _stride >= d:
		_stride = fmod(_stride, d)
		return true
	return false


func reset_stride() -> void:
	_stride = 0.0


## Fraction of the current stride, 0..1 (drives the head bob phase so bob and steps agree).
func stride_phase(gait: StringName) -> float:
	return clampf(_stride / step_distance(gait), 0.0, 1.0)


static func emit(pos: Vector3, radius: float, kind: StringName) -> void:
	EventBus.noise_emitted.emit(pos, radius, kind)


## 06 §6: the radius a listener at `listener` effectively hears, with each wall on the
## straight line reducing it by 35% (multiplicatively), counted with up to 3 raycasts on
## the world layer. Helper for errors (08 senses); `exclude` are RIDs to ignore.
static func effective_radius(space: PhysicsDirectSpaceState3D, pos: Vector3, listener: Vector3,
		radius: float, exclude: Array[RID] = []) -> float:
	var walls := count_walls(space, pos, listener, exclude)
	return radius * pow(1.0 - Tuning.NOISE_WALL_ATTENUATION, walls)


static func can_hear(space: PhysicsDirectSpaceState3D, pos: Vector3, listener: Vector3,
		radius: float, exclude: Array[RID] = []) -> bool:
	if pos.distance_to(listener) >= radius:
		return false
	return pos.distance_to(listener) < effective_radius(space, pos, listener, radius, exclude)


## Walls on the straight line `from` -> `to`, up to NOISE_WALL_RAYCASTS of them. Only
## colliders the level builder marks as walls count: a collider with the `wall_kind`
## meta other than PROP (06 Interfaces). Floors, props, open door leaves, void blocks and
## error bodies on the world layer are stepped over without counting, at most MAX_SKIPPED.
static func count_walls(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> int:
	if space == null:
		return 0
	var walls := 0
	var skipped := 0
	var origin := from
	var dir := (to - from).normalized()
	var ignore: Array[RID] = exclude.duplicate()
	while walls < Tuning.NOISE_WALL_RAYCASTS and skipped <= MAX_SKIPPED:
		var q := PhysicsRayQueryParameters3D.create(origin, to, PlayerLayers.WORLD_MASK, ignore)
		# Each next ray starts just inside the wall it hit; back faces and the inside of
		# convex shapes are not hits, so it finds the next wall (merged chunk colliders too).
		q.hit_back_faces = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if is_wall(hit["collider"]):
			walls += 1
			origin = (hit["position"] as Vector3) + dir * WALL_STEP_IN
		else:
			skipped += 1
			ignore.append(hit["rid"] as RID)
	return walls


## A wall collider for noise attenuation: carries the `wall_kind` meta (set by the level
## builder on wall and partition bodies; 06 Interfaces), except PROP (props, lockers, an open
## door leaf: noise must match what the player can read; CHANGELOG 2026-10-08).
static func is_wall(collider: Object) -> bool:
	return collider != null and collider.has_meta(WALL_META) and collider.get_meta(WALL_META) != KIND_PROP
