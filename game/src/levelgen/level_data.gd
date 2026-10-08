class_name LevelData
extends RefCounted
## One generated level (07 Interfaces): the grid, the placements, and the metadata the
## builder, Director, exit and HUD read. Pure data; produced on a worker thread.
##
## A placement is {kind: StringName, cell: Vector2i, offset: Vector3, yaw: float,
## params: Dictionary} (07 §2). `offset` is relative to LevelGrid.world_of(cell); `yaw`
## follows Godot (0 faces -Z, i.e. north). Kinds are the P_* constants below.

const P_SPAWN := &"spawn"                 # params: cabin_dir (edge the Landing cabin sits on)
const P_EXIT := &"exit"                   # params: exit_kind, lock, dir (edge the exit sits in)
const P_BREAKER := &"breaker"             # params: variant (&"a" or &"b"), dir
const P_KEYCARD := &"keycard"
const P_ITEM := &"item"                   # params: item (kind), guaranteed (bool)
const P_NOTE := &"note"                   # params: slot (0 or 1), early (bool), first_descent (bool)
const P_HIDE_SPOT := &"hide_spot"         # params: kind (&"locker"), dir, view_yaw_limit
const P_PROP := &"prop"                   # params: prop, dir (wall it stands against, -1 free)
const P_FIXTURE := &"fixture"             # params: group, fixture
const P_ERROR_SPAWN := &"error_spawn"     # params: off_path (bool); Substrate: error (&"null", &"static")
## M2.1 (07 §2 "water volumes"): one per wet basin. cell = the basin rect's first cell;
## params: rect (Rect2i, the basin cells), surface_y (water level, m), floor_y (basin floor).
const P_WATER := &"water"

const NO_CELL := Vector2i(-1, -1)

var stratum: StringName = &""
var depth: int = 1
var cycle: int = 1
var run_seed: int = 0
var level_seed: int = 0
var first_run: bool = false
## Retry index that produced this level (0 = first try).
var attempt: int = 0
## True when every retry failed and the stratum's simplest grammar was used (14 §12).
var fallback: bool = false
## Empty when valid; otherwise the validator's failure lines for the shipped level.
var failures: PackedStringArray = PackedStringArray()

var grid: LevelGrid = null
var placements: Array[Dictionary] = []

var exit_lock: StringName = Tuning.LOCK_OPEN
## &"a" (plain breaker) or &"b" (fuse socket, 07 §6) when Powered; &"" otherwise.
var lock_variant: StringName = &""
var spawn_cell: Vector2i = NO_CELL
var spawn_dir: int = -1
var exit_cell: Vector2i = NO_CELL
var exit_dir: int = -1
var breaker_cell: Vector2i = NO_CELL
var keycard_cell: Vector2i = NO_CELL
var fuse_cell: Vector2i = NO_CELL
var critical_path: Array[Vector2i] = []
## Vector3i(x, z, dir) of every SOFT edge.
var soft_walls: Array[Vector3i] = []
## 07 §7: floor drops are refused on the last depth of the run.
var floor_solid: bool = false
## Number of item and note placements the grammar intended (validator rule 8).
var expected_items: int = 0
var expected_notes: int = 0
var expected_hide_spots: int = 0
var expected_soft_walls: int = 0
## M2.3 Substrate (07 §5.6): Null's spawn cell (55% of the critical path), the cells the
## unfinish step removed (VOID now), and the corridor cell count it removed them from.
var null_spawn_cell: Vector2i = NO_CELL
var unfinished_void: Array[Vector2i] = []
var unfinish_base: int = 0


func add_placement(kind: StringName, cell: Vector2i, offset: Vector3 = Vector3.ZERO,
		yaw: float = 0.0, params: Dictionary = {}) -> Dictionary:
	var p := {&"kind": kind, &"cell": cell, &"offset": offset, &"yaw": yaw, &"params": params}
	placements.append(p)
	return p


func placements_of(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in placements:
		if p[&"kind"] == kind:
			out.append(p)
	return out


func critical_path_length_m() -> float:
	return PathOps.path_length_m(critical_path)


## Yaw that makes a node face direction `dir` (N, E, S, W).
static func yaw_facing(dir: int) -> float:
	return [0.0, -PI / 2.0, PI, PI / 2.0][dir]


# ------------------------------------------------------------------ determinism

func to_bytes() -> PackedByteArray:
	var out := grid.to_bytes() if grid != null else PackedByteArray()
	out.append_array(var_to_bytes([stratum, depth, cycle, run_seed, level_seed, first_run, attempt,
		fallback, exit_lock, lock_variant, spawn_cell, spawn_dir, exit_cell, exit_dir, breaker_cell,
		keycard_cell, fuse_cell, critical_path, soft_walls, floor_solid, null_spawn_cell, unfinished_void,
		unfinish_base]))
	out.append_array(var_to_bytes(placements))
	return out


## SHA-256 of to_bytes(), hex. Same seed, same hash (07 §10 determinism test).
func hash_hex() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(to_bytes())
	return ctx.finish().hex_encode()


# ------------------------------------------------------------------ ASCII dump

## Top-down debug map: one character per cell centre, one per edge.
## Cells: ' ' corridor (',' on Garage deck 1), '.' room, '#' void ('%' void the Substrate's
## unfinish step removed), '*' critical path,
## 'u' basin, 'W' deep water, '^' ramp or steps, 'I' pillar; markers S spawn, X exit,
## B breaker, K keycard, F fuse, i item, n note, h hide spot, p prop, e error spawn.
## Edges: '|' '-' wall, 'H' '=' solid, '}' '~' soft, 'd' door, ':' partition, 'g' glass.
func to_ascii() -> String:
	var w := grid.size.x
	var h := grid.size.y
	var rows: Array[PackedStringArray] = []
	for r in h * 2 + 1:
		var row := PackedStringArray()
		row.resize(w * 2 + 1)
		row.fill(" ")
		rows.append(row)
	for z in h:
		for x in w:
			var c := Vector2i(x, z)
			rows[z * 2 + 1][x * 2 + 1] = _cell_char(c)
			rows[z * 2 + 1][x * 2 + 2] = _edge_char(c, LevelGrid.E)
			rows[z * 2 + 2][x * 2 + 1] = _edge_char(c, LevelGrid.S)
			if z == 0:
				rows[0][x * 2 + 1] = _edge_char(c, LevelGrid.N)
			if x == 0:
				rows[z * 2 + 1][0] = _edge_char(c, LevelGrid.W)
	for z in h + 1:
		for x in w + 1:
			rows[z * 2][x * 2] = _corner_char(x, z, rows)
	for p in placements:
		var c: Vector2i = p[&"cell"]
		var ch := _marker(p)
		if not ch.is_empty():
			rows[c.y * 2 + 1][c.x * 2 + 1] = ch
	var lines := PackedStringArray()
	for row in rows:
		lines.append("".join(row))
	return "\n".join(lines)


func _cell_char(c: Vector2i) -> String:
	var k := grid.kind(c)
	if k == LevelGrid.DEEP:
		return "W"
	if grid.is_pillar(c):
		return "I"
	if not grid.is_walkable(c):
		return "%" if unfinished_void.has(c) else "#"
	if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
		return "*"
	match k:
		LevelGrid.RAMP:
			return "^"
		LevelGrid.BASIN:
			return "u"
		LevelGrid.ROOM:
			return "."
	return "," if grid.deck[grid.idx(c)] == 1 else " "


func _edge_char(c: Vector2i, dir: int) -> String:
	var o := c + LevelGrid.DIRS[dir]
	if not grid.is_sight_open(c) and not grid.is_sight_open(o):
		return "#"
	var vertical := dir == LevelGrid.E or dir == LevelGrid.W
	match grid.wall(c, dir):
		LevelGrid.NONE:
			return " "
		LevelGrid.WALL:
			return "|" if vertical else "-"
		LevelGrid.SOLID:
			return "H" if vertical else "="
		LevelGrid.SOFT:
			return "}" if vertical else "~"
		LevelGrid.DOOR:
			return "d"
		LevelGrid.PARTITION:
			return ":"
		LevelGrid.GLASS:
			return "g"
	return "?"


func _corner_char(x: int, z: int, rows: Array[PackedStringArray]) -> String:
	var r := z * 2
	var k := x * 2
	var around: Array[String] = []
	if r > 0:
		around.append(rows[r - 1][k])
	if r < rows.size() - 1:
		around.append(rows[r + 1][k])
	if k > 0:
		around.append(rows[r][k - 1])
	if k < rows[r].size() - 1:
		around.append(rows[r][k + 1])
	var all_void := true
	var any_wall := false
	for ch in around:
		if ch != "#":
			all_void = false
		if ch != " " and ch != "#":
			any_wall = true
	if all_void:
		return "#"
	return "+" if any_wall else " "


func _marker(p: Dictionary) -> String:
	match p[&"kind"]:
		P_SPAWN:
			return "S"
		P_EXIT:
			return "X"
		P_BREAKER:
			return "B"
		P_KEYCARD:
			return "K"
		P_ITEM:
			return "F" if p[&"params"].get(&"item", &"") == &"fuse" else "i"
		P_NOTE:
			return "n"
		P_HIDE_SPOT:
			return "h"
		P_PROP:
			return "p"
		P_ERROR_SPAWN:
			match p[&"params"].get(&"error", &""):
				&"null":
					return "N"
				&"static":
					return "s"
			return "e"
		P_FIXTURE:
			return "L" if p[&"params"].get(&"fixture", &"") == &"studio_light" else ""
	return ""
