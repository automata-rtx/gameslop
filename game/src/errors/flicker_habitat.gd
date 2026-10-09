class_name FlickerHabitat
extends RefCounted
## Flicker's habitat rules (08 §5) as pure queries over the LightPool. Every distance is in
## XZ to the fixture's floor projection (ceiling height is irrelevant). Only fixtures count:
## chemical light (glowsticks, flares) is not a fixture, so it never makes a lit area, a
## habitat or a beam to attach to (08 §5 "chemical light is immune"). A fixture lights a
## point only along a clear grid sight line (CHANGELOG 2026-10-08), via
## LightPool.lit_fixtures_near.


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A group Flicker can live in: it exists and is powered (an unpowered group is dark).
static func habitable(pool: LightPool, group: int) -> bool:
	return pool != null and group >= 0 and pool.is_group_lit(group)


## 08 §5 lit area: within 3 m in XZ of any lit fixture of the group, or standing in a cell
## whose nearest lit fixture belongs to the group within 4 m in XZ.
static func in_lit_area(pool: LightPool, group: int, pos: Vector3) -> bool:
	if pool == null or group < 0:
		return false
	if not pool.lit_fixtures_near(pos, Tuning.FLICKER_LIT_AREA_DIST, group).is_empty():
		return true
	var centre := pos
	if pool.grid != null:
		var c := pool.grid.cell_of(pos)
		if pool.grid.in_bounds(c):
			centre = pool.grid.world_of(c)
	var near := pool.lit_fixtures_near(centre, Tuning.FLICKER_LIT_AREA_CELL_DIST)
	return not near.is_empty() and near[0].group_id == group


## True when a lit fixture of `group` lies within `radius` in XZ of `pos` with a clear
## grid sight line (the attach test: the beam near a fixture of its group).
static func near_lit_fixture(pool: LightPool, group: int, pos: Vector3, radius: float) -> bool:
	if pool == null or group < 0:
		return false
	return not pool.lit_fixtures_near(pos, radius, group).is_empty()


## XZ distance from `pos` to the nearest fixture of `group` (INF when none). The lunge range.
static func group_distance(pool: LightPool, group: int, pos: Vector3) -> float:
	var best := INF
	if pool == null:
		return best
	for f in pool.group(group):
		best = minf(best, flat(f.global_position, pos))
	return best


## XZ distance from `pos` to the nearest powered fixture of `group` (INF when none).
static func lit_group_distance(pool: LightPool, group: int, pos: Vector3) -> float:
	var best := INF
	if pool == null:
		return best
	for f in pool.group(group):
		if f.powered:
			best = minf(best, flat(f.global_position, pos))
	return best


## The habitable group nearest `pos` (its nearest powered fixture within `max_dist` in XZ),
## or -1. Ties go to the lower id (deterministic).
static func nearest_habitable(pool: LightPool, pos: Vector3, max_dist: float, exclude: int = -1) -> int:
	if pool == null:
		return -1
	var ids: Array = pool.group_ids()
	ids.sort()
	var best := -1
	var best_d := max_dist
	for id: int in ids:
		if id == exclude or not habitable(pool, id):
			continue
		var d := lit_group_distance(pool, id, pos)
		if d <= best_d and (best < 0 or d < best_d):
			best = id
			best_d = d
	return best


static func habitable_neighbours(pool: LightPool, group: int) -> Array[int]:
	var out: Array[int] = []
	if pool == null:
		return out
	for id in pool.groups_adjacent(group):
		if habitable(pool, id):
			out.append(id)
	return out


## Of `ids`, the group whose centroid is nearest `pos` in XZ (`farthest`: the farthest).
static func by_centroid(pool: LightPool, ids: Array[int], pos: Vector3, farthest: bool = false) -> int:
	var best := -1
	var best_d := 0.0
	for id in ids:
		var d := flat(pool.group_centroid(id), pos)
		if best < 0 or (d > best_d if farthest else d < best_d):
			best = id
			best_d = d
	return best


## 08 §5 Resident hop: with probability `near_chance` (when Flicker has heard something) the
## adjacent habitable group nearest `last_known`; otherwise the one nearest the Director's
## hint when one is held, else a random one. -1 when no adjacent group is habitable.
static func pick_hop(pool: LightPool, group: int, rng: RandomNumberGenerator, near_chance: float,
		last_known: Vector3, hint: Vector3) -> int:
	var ids := habitable_neighbours(pool, group)
	if ids.is_empty():
		return -1
	var roll := rng.randf()
	var pick := rng.randi_range(0, ids.size() - 1)
	if last_known != Vector3.INF and roll < near_chance:
		return by_centroid(pool, ids, last_known)
	if hint != Vector3.INF:
		return by_centroid(pool, ids, hint)
	return ids[pick]


## 10 §4 respawn candidates: habitable groups whose nearest fixture is at least `min_dist`
## from `player_pos` in XZ, sorted by id. `visible` (Vector3 -> bool) drops groups with a
## fixture in view (no error spawns in view, 00 §5).
static func respawn_groups(pool: LightPool, player_pos: Vector3, min_dist: float, visible: Callable = Callable()) -> Array[int]:
	var out: Array[int] = []
	if pool == null:
		return out
	var ids: Array = pool.group_ids()
	ids.sort()
	for id: int in ids:
		if not habitable(pool, id) or group_distance(pool, id, player_pos) < min_dist:
			continue
		var seen := false
		if visible.is_valid():
			for f in pool.group(id):
				seen = seen or bool(visible.call(f.global_position))
		if not seen:
			out.append(id)
	return out
