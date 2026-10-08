class_name Cycle2Ops
extends RefCounted
## Cycle 2 corruption (07 §9 generator side, 02 §7 look), run by StratumGenerator.generate
## after `decorate` on every Cycle 2+ level, on its own sub-seed (SEED_LABEL), so a Cycle 1
## level's streams never move. Each stratum keeps its palette; what changes:
##   - 10% of corridor fixtures removed (07 §9);
##   - 25% of the remaining fixtures dead: fixture params `dead = true` (02 §7 "25% of
##     fixtures dark"; LevelPlacer leaves them unpowered and out of the pool, so no breaker
##     wave ever lights them and Flicker cannot live in them);
##   - 10% of the surfaces in units (whole rooms or corridor segments) flagged UNFINISHED,
##     which the world shader draws at u = 0.2 in Cycle 2 materials (02 §7);
##   - the spawn room and the exit room keep their fixtures and surfaces;
##   - one extra Static spawn point, the braid halved, one more soft wall and Offices' 60%
##     dark groups are the grammars' own (PopulateOps.error_spawns, the Cycle 2 multipliers).
## Render side (LevelMaterials.for_level, LevelPlacer, Level): fixture hue 12 deg towards
## the next stratum's light colour, fog density x1.3, vertex jitter floor 0.004.
## The Substrate unfinishes itself; it takes none of this.

const SEED_LABEL := "cycle2"
## The next stratum's light colour (02 §7) follows the order of the five ordinary strata,
## wrapping (the Substrate has no fixtures).
const ORDER: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server"]


static func corrupt(gen: StratumGenerator, rng: RandomNumberGenerator) -> void:
	var data := gen.data
	if data.stratum == Tuning.STRATUM_SUBSTRATE:
		return
	var grid := gen.grid
	var keep_flags := LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM
	# 07 §9: 10% of corridor fixtures removed.
	var corridor: Array[int] = []
	for k in data.placements.size():
		var p := data.placements[k]
		if p[&"kind"] == LevelData.P_FIXTURE and grid.kind(p[&"cell"]) == LevelGrid.FLOOR \
				and not grid.has_flag(p[&"cell"], keep_flags):
			corridor.append(k)
	RoomOps.shuffle(corridor, rng)
	var drop: Dictionary = {}
	for k in roundi(corridor.size() * Tuning.CYCLE2_FIXTURES_REMOVED):
		drop[corridor[k]] = true
	var kept: Array[Dictionary] = []
	for k in data.placements.size():
		if not drop.has(k):
			kept.append(data.placements[k])
	data.placements = kept
	_prune_groups(data)
	# 02 §7: 25% of the remaining fixtures dark (dead).
	var live: Array[Dictionary] = []
	for p in data.placements:
		if p[&"kind"] == LevelData.P_FIXTURE and not grid.has_flag(p[&"cell"], keep_flags):
			live.append(p)
	RoomOps.shuffle(live, rng)
	for k in roundi(live.size() * Tuning.CYCLE2_FIXTURES_DARK):
		live[k][&"params"][&"dead"] = true
	# 02 §7: 10% of surfaces at u = 0.2, by room or corridor segment.
	var skip: Array[RoomData] = []
	for r in grid.room_list:
		if grid.has_flag(r.rect.position, keep_flags):
			skip.append(r)
	var units := SubstrateUnfinish.units(grid, skip)
	var clean: Array[Array] = []
	for u in units:
		var ok := true
		for c: Vector2i in u:
			ok = ok and not grid.has_flag(c, keep_flags)
		if ok:
			clean.append(u)
	SubstrateUnfinish.mark_units(grid, clean, Tuning.CYCLE2_SURFACE_UNRENDER_FRACTION, rng)


## Fixture groups keep only the cells that still hold a fixture; a group left empty goes.
static func _prune_groups(data: LevelData) -> void:
	var grid := data.grid
	var held: Dictionary = {}
	for p in data.placements_of(LevelData.P_FIXTURE):
		var g := int(p[&"params"].get(&"group", -1))
		if not held.has(g):
			held[g] = {}
		(held[g] as Dictionary)[p[&"cell"]] = true
	for g: int in grid.groups.keys():
		if not held.has(g):
			grid.groups.erase(g)
			continue
		var cells: Array[Vector2i] = []
		for c: Vector2i in grid.groups[g]:
			if (held[g] as Dictionary).has(c):
				cells.append(c)
		grid.groups[g] = cells


## 02 §7: `base` with its hue turned CYCLE2_FIXTURE_HUE_SHIFT degrees towards `target`'s
## (the short way round), saturation and value kept. A grey target leaves the hue alone.
static func hue_toward(base: Color, target: Color, degrees: float = Tuning.CYCLE2_FIXTURE_HUE_SHIFT) -> Color:
	if target.s < 0.05 or base.s < 0.001:
		return base
	var delta := wrapf(target.h - base.h, -0.5, 0.5)
	var step := degrees / 360.0
	var h := base.h + clampf(delta, -step, step)
	return Color.from_hsv(wrapf(h, 0.0, 1.0), base.s, base.v, base.a)


## The stratum after `id` in ORDER (wrapping); `id` itself when it is not an ordinary stratum.
static func next_stratum(id: StringName) -> StringName:
	var k := ORDER.find(id)
	return ORDER[(k + 1) % ORDER.size()] if k >= 0 else id
