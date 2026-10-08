class_name ItemSpawner
extends RefCounted
## Turns a LevelData's item and note placements (07 §2) into pickups in the level (09 §2).
## `populate(level_root, level, rng)` is the call the level builder makes after the geometry:
## one ItemPickup per P_ITEM (the kind the generator chose; a Polaroid gets its photo from the
## seeded rng) and one NotePickup per P_NOTE (the note id drawn here, 09 §2: unfound notes of
## the allowed tiers first, then found ones at half weight; the first Descent's marked note is H1).
## Every kind has a world scene since M2.8; a kind without one is skipped with a warning, and
## skipping a fuse is an error (07 §6: Variant B always has exactly one fuse in the level).
## One KeycardPickup per P_KEYCARD (the Keyed lock's card, 09 §2; not a belt item).
## Each pickup lies at a jittered spot in its cell with a jittered yaw, from the seeded rng.

const NOTE_SCENE := "res://scenes/interactables/note_pickup.tscn"
const FIRST_DESCENT_NOTE := &"H1"
## Options keys: `found` (Array of note ids already in the Archive; default GameState.meta),
## `stratum_reached` (bool: tier 2 notes allowed; default from GameState.meta).
const OPT_FOUND := &"found"
const OPT_STRATUM_REACHED := &"stratum_reached"


## Spawns every item and note placement under `level_root`; returns the spawned pickups.
static func populate(level_root: Node, level: LevelData, rng: RandomNumberGenerator,
		options: Dictionary = {}) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p in level.placements_of(LevelData.P_ITEM):
		var node := _spawn_item(level_root, level, p, rng)
		if node != null:
			out.append(node)
	for p in level.placements_of(LevelData.P_KEYCARD):
		var card := _spawn_keycard(level_root, level, p, rng)
		if card != null:
			out.append(card)
	var ids := pick_notes(level, rng, options)
	var note_scene := load(NOTE_SCENE) as PackedScene
	var placements := level.placements_of(LevelData.P_NOTE)
	for i in placements.size():
		if i >= ids.size() or ids[i] == &"":
			continue
		var n := note_scene.instantiate() as NotePickup
		n.note_id = ids[i]
		n.name = "Note_%s" % ids[i]
		level_root.add_child(n)
		n.position = _floor_position(level, placements[i])
		n.rotation.y = placements[i][&"yaw"] + rng.randf_range(-0.6, 0.6)
		out.append(n)
	return out


static func _spawn_item(level_root: Node, level: LevelData, p: Dictionary,
		rng: RandomNumberGenerator) -> Node3D:
	var kind := StringName(p[&"params"].get(&"item", &""))
	var data := DataRegistry.item(kind)
	if data == null or data.world_scene == null or not data.belt_item:
		if kind == &"fuse":
			# 07 §6 Variant B: the level is unwinnable without it (until M2.8 adds the scene).
			push_error("ItemSpawner: the fuse placement at %s has no world scene; Variant B is unwinnable" % p[&"cell"])
		else:
			push_warning("ItemSpawner: no world scene for item '%s'; skipped" % kind)
		return null
	var pickup := data.world_scene.instantiate() as ItemPickup
	pickup.count = data.pickup_count
	if kind == &"polaroid":
		pickup.set_polaroid_image(rng.randi_range(0, Tuning.POLAROID_IMAGE_COUNT - 1))
	pickup.name = "Item_%s" % kind
	level_root.add_child(pickup)
	var j := Tuning.ITEM_PLACE_JITTER
	pickup.position = _floor_position(level, p) + Vector3(rng.randf_range(-j, j), 0.0, rng.randf_range(-j, j))
	pickup.rotation.y = p[&"yaw"] + rng.randf_range(-PI, PI)
	return pickup


static func _spawn_keycard(level_root: Node, level: LevelData, p: Dictionary,
		rng: RandomNumberGenerator) -> Node3D:
	var data := DataRegistry.item(KeycardPickup.KEY)
	if data == null or data.world_scene == null:
		push_error("ItemSpawner: the keycard has no world scene; a Keyed exit is unwinnable")
		return null
	var card := data.world_scene.instantiate() as ItemPickup
	card.name = "Item_keycard"
	level_root.add_child(card)
	var j := Tuning.ITEM_PLACE_JITTER
	card.position = _floor_position(level, p) + Vector3(rng.randf_range(-j, j), 0.0, rng.randf_range(-j, j))
	card.rotation.y = p[&"yaw"] + rng.randf_range(-PI, PI)
	return card


static func _floor_position(level: LevelData, p: Dictionary) -> Vector3:
	var cell: Vector2i = p[&"cell"]
	var base := Vector3(cell.x * Tuning.GRID_CELL_SIZE, 0.0, cell.y * Tuning.GRID_CELL_SIZE)
	if level.grid != null:
		base = level.grid.world_of(cell)
	return base + (p[&"offset"] as Vector3)


## The note id for each P_NOTE placement of `level`, in placement order ("" when the stratum has
## nothing left to offer). Never repeats an id within the level.
static func pick_notes(level: LevelData, rng: RandomNumberGenerator, options: Dictionary = {}) -> Array[StringName]:
	var found: Array = options.get(OPT_FOUND, _meta_found())
	var tier2: bool = options.get(OPT_STRATUM_REACHED, stratum_reached(level.stratum))
	var pool: Array[NoteData] = []
	for n in DataRegistry.notes_for(level.stratum):
		if n.tier == NoteData.TIER_FIRST_RUN or (n.tier == NoteData.TIER_STRATUM_REACHED and tier2):
			pool.append(n)
	var out: Array[StringName] = []
	for p in level.placements_of(LevelData.P_NOTE):
		var chosen: NoteData = null
		if bool(p[&"params"].get(&"first_descent", false)):
			for n in pool:
				if n.id == FIRST_DESCENT_NOTE:
					chosen = n
		if chosen == null:
			chosen = _draw(pool, found, rng)
		if chosen == null:
			out.append(&"")
			continue
		pool.erase(chosen)
		out.append(chosen.id)
	return out


## Unfound notes first (equal weight); when none remain, found ones at half weight.
static func _draw(pool: Array[NoteData], found: Array, rng: RandomNumberGenerator) -> NoteData:
	var unfound: Array[NoteData] = []
	for n in pool:
		if not found.has(n.id):
			unfound.append(n)
	var candidates := unfound if not unfound.is_empty() else pool
	if candidates.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	for n in candidates:
		var w := 1.0 if found.find(n.id) == -1 else Tuning.NOTES_FOUND_REPEAT_WEIGHT
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in candidates.size():
		r -= weights[i]
		if r <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


static func _meta_found() -> Array:
	var meta: MetaState = GameState.meta
	return meta.notes_found if meta != null else []


## 01 §6: tier 2 notes appear once the player has reached the stratum before. The meta keeps
## `stats.strata_reached` (M2.10); until it does, any note found in the stratum proves it.
static func stratum_reached(stratum: StringName) -> bool:
	var meta: MetaState = GameState.meta
	if meta == null:
		return false
	var reached: Variant = meta.stats.get("strata_reached", [])
	if reached is Array and (reached as Array).has(String(stratum)):
		return true
	for n in DataRegistry.notes_for(stratum):
		if meta.notes_found.has(n.id):
			return true
	return false
