class_name RunLevelSetup
extends RefCounted
## The run's calls down into a freshly built level (14 §5, 07 Interfaces): exit and breaker
## prefabs in place of their placement markers, the Powered lock's dark exit room, the item
## and note pickups (ItemSpawner.populate), plus the pure rules the run needs around a level:
## the unlocked item pool, the Landing's two-item draw (05 §4, 09 §2) and the drop arrival
## cell (05 §4). Static and stateless so tests call each rule directly.

const EXIT_SCENES: Dictionary = {&"elevator": "res://scenes/exits/elevator.tscn"}
const DEFAULT_EXIT_SCENE := "res://scenes/exits/elevator.tscn"
const BREAKER_SCENE := "res://scenes/interactables/breaker.tscn"


## Replaces the exit, breaker, item and note markers of `level` (after `geometry_ready`).
## Returns {exit: Exit, breaker: Breaker or null, pickups: Array}.
static func prepare(level: Level, data: LevelData) -> Dictionary:
	var out := {&"exit": null, &"breaker": null, &"pickups": []}
	var tree := level.get_tree()
	for m: Node in tree.get_nodes_in_group(LevelPlacer.group_of(LevelData.P_EXIT)):
		if not level.is_ancestor_of(m):
			continue
		var p: Dictionary = m.get_meta(LevelPlacer.META_PLACEMENT, {})
		var params: Dictionary = p.get(&"params", {})
		var path: String = EXIT_SCENES.get(params.get(&"exit_kind", &""), DEFAULT_EXIT_SCENE)
		var exit := (load(path) as PackedScene).instantiate() as Exit
		exit.lock = data.exit_lock
		_swap(m as Node3D, exit)
		out[&"exit"] = exit
	for m: Node in tree.get_nodes_in_group(LevelPlacer.group_of(LevelData.P_BREAKER)):
		if not level.is_ancestor_of(m):
			continue
		var b := (load(BREAKER_SCENE) as PackedScene).instantiate() as Breaker
		var p: Dictionary = m.get_meta(LevelPlacer.META_PLACEMENT, {})
		var variant: StringName = (p.get(&"params", {}) as Dictionary).get(&"variant", Breaker.VARIANT_A)
		b.variant = variant if variant != &"" else Breaker.VARIANT_A
		_swap(m as Node3D, b)
		out[&"breaker"] = b
	if data.exit_lock == Tuning.LOCK_POWERED:
		darken_exit_room(level, data)
	# Orchestrator decision (M1.9): the run populates pickups, seeded from the level seed,
	# and frees the item and note markers.
	for kind: StringName in [LevelData.P_ITEM, LevelData.P_NOTE, LevelData.P_KEYCARD]:
		for m: Node in tree.get_nodes_in_group(LevelPlacer.group_of(kind)):
			if level.is_ancestor_of(m):
				m.queue_free()
	var rng := Seeds.rng(Seeds.derive(data.level_seed, Tuning.SEED_LABEL_ITEMS))
	out[&"pickups"] = ItemSpawner.populate(level.content, data, rng)
	return out


static func _swap(marker: Node3D, node: Node3D) -> void:
	var parent := marker.get_parent()
	node.transform = marker.transform
	node.name = marker.name
	marker.name = String(marker.name) + "_marker"
	parent.add_child(node)
	marker.queue_free()


## 07 §6 Powered: "the exit is dark and dead until the breaker is thrown". The exit room's
## fixtures start unpowered; the breaker's power wave lights them (M1.9 reading for Halls).
static func darken_exit_room(level: Level, data: LevelData) -> Array[Fixture]:
	var out: Array[Fixture] = []
	for f in level.light_pool.fixtures():
		var c := data.grid.cell_of(f.global_position)
		if data.grid.in_bounds(c) and data.grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			f.set_powered(false)
			out.append(f)
	level.light_pool.reevaluate()
	return out


## The breaker was thrown: every dark fixture lights in walking-distance order from the
## breaker (02 §6), and the exit powers when the wave reaches it. Returns the seconds until
## the exit powers.
static func run_power_wave(level: Level, data: LevelData, exit: Exit, breaker_pos: Vector3) -> float:
	var from := data.grid.cell_of(breaker_pos)
	if not data.grid.is_walkable(from):
		from = data.breaker_cell
	var dark: Array[Fixture] = []
	var positions: Array[Vector3] = []
	for f in level.light_pool.fixtures():
		if not f.powered:
			dark.append(f)
			positions.append(f.global_position)
	if exit != null:
		positions.append(exit.global_position)
	var delays := Breaker.wave_delays(data.grid, from, positions)
	for i in dark.size():
		dark[i].power_on_wave(delays[i])
	var exit_delay := delays[delays.size() - 1] if exit != null else 0.0
	if exit != null:
		var tw := exit.create_tween()
		tw.tween_interval(exit_delay)
		tw.tween_callback(exit.power)
	# The pool re-lends lights as fixtures come on.
	var pool_tw := level.light_pool.create_tween()
	pool_tw.tween_interval(exit_delay + Tuning.LIGHT_BREAKER_SETTLE_MS / 1000.0)
	pool_tw.tween_callback(level.light_pool.reevaluate)
	return exit_delay


# --- pure rules --------------------------------------------------------------------------

## 05 §6, 09 §2: the kinds the pool may offer this run. A kind needs a world scene (every belt
## kind has one since M2.8) and its unlock; Daily Descent ignores unlock state (05 §8).
static func item_pool(meta: MetaState, daily: bool = false) -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in Tuning.ITEM_WEIGHT:
		var d := DataRegistry.item(kind)
		if d == null or not d.belt_item or d.world_scene == null:
			continue
		if d.unlock_id != &"" and not daily and (meta == null or not meta.is_unlocked(d.unlock_id)):
			continue
		out.append(kind)
	return out


## 05 §4, 09 §2: two different kinds from `pool`, by the base weights, excluding kinds the
## belt cannot take (`can_accept`), favouring kinds the player holds none of (`count_of`).
static func landing_choices(pool: Array[StringName], can_accept: Callable, count_of: Callable,
		rng: RandomNumberGenerator, n: int = Tuning.LANDING_CHOICE_COUNT) -> Array[StringName]:
	var candidates: Array[StringName] = []
	var weights: Array[float] = []
	for kind in pool:
		if can_accept.is_valid() and not bool(can_accept.call(kind)):
			continue
		var w := float(Tuning.ITEM_WEIGHT.get(kind, 0))
		if w <= 0.0:
			continue
		if count_of.is_valid() and int(count_of.call(kind)) == 0:
			w *= Tuning.LANDING_LACKING_WEIGHT_MULT
		candidates.append(kind)
		weights.append(w)
	var out: Array[StringName] = []
	while out.size() < n and not candidates.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var r := rng.randf() * total
		var pick := candidates.size() - 1
		for i in candidates.size():
			r -= weights[i]
			if r <= 0.0:
				pick = i
				break
		out.append(candidates[pick])
		candidates.remove_at(pick)
		weights.remove_at(pick)
	return out


## 05 §4 drop arrival: a random walkable cell at least 15 m from every error and not in the
## exit room, with an open neighbour to face (06 §11: never face a wall at arrival).
## Returns NO_CELL when no cell qualifies.
static func pick_drop_cell(data: LevelData, rng: RandomNumberGenerator, error_positions: Array[Vector3]) -> Vector2i:
	var g := data.grid
	var ok: Array[Vector2i] = []
	for i in g.cell_count():
		var c := g.cell_at(i)
		if is_drop_cell(data, c, error_positions):
			ok.append(c)
	if ok.is_empty():
		return LevelData.NO_CELL
	return ok[rng.randi_range(0, ok.size() - 1)]


static func is_drop_cell(data: LevelData, c: Vector2i, error_positions: Array[Vector3]) -> bool:
	var g := data.grid
	if not g.in_bounds(c) or not g.is_walkable(c) or g.has_flag(c, LevelGrid.F_EXIT_ROOM):
		return false
	if open_dir(g, c) < 0:
		return false
	var p := g.world_of(c)
	for e in error_positions:
		if p.distance_to(e) < Tuning.DROP_ARRIVAL_MIN_ERROR_DIST:
			return false
	return true


## A direction with at least ARRIVAL_MIN_WALL_DIST of walkable space ahead, or -1.
static func open_dir(g: LevelGrid, c: Vector2i) -> int:
	var cells := ceili(Tuning.ARRIVAL_MIN_WALL_DIST / Tuning.GRID_CELL_SIZE)
	for d in 4:
		var cur := c
		var free := true
		for k in cells:
			if not g.can_step(cur, d):
				free = false
				break
			cur += LevelGrid.DIRS[d]
		if free:
			return d
	return -1
