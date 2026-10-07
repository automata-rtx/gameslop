class_name MetaState
extends RefCounted
## Persistent meta progression (13 §2 schema v1), held by GameState, read and
## written as meta.json by SaveManager. Placeholder: the fields and the simple
## accessors exist; serialisation, validation, migrations, and record_run are M2.10.

const VERSION := 1

var version: int = VERSION
var created_at: String = ""
var first_descent_done: bool = false
var unlocks: Dictionary = {}
var notes_found: Array[StringName] = []
var codex: Dictionary = {}
var polaroids_seen: Array[int] = []
## 13 §2 stats block. `depth_reached_counts` (string depth -> times a run reached it) backs
## unlock #7, "reach depth 4 twice" (05 §6).
var stats: Dictionary = {"depth_reached_counts": {}}
var daily: Dictionary = {}
var last_run: Dictionary = {}
var endless_best_depth: int = 0
var cycle_unlocked: bool = false
## Keys this build does not know, preserved on save (13 §2).
var unknown: Dictionary = {}


func is_unlocked(id: StringName) -> bool:
	return bool(unlocks.get(String(id), false))


## Returns true when `id` was not already earned.
func earn(id: StringName) -> bool:
	if is_unlocked(id):
		return false
	unlocks[String(id)] = true
	return true


## Returns true when the note is new to the Archive.
func note_found(id: StringName) -> bool:
	if notes_found.has(id):
		return false
	notes_found.append(id)
	return true


## 08 §2 "noticed_player": one Archive encounter for error `id`. Returns the new count.
func codex_notice(id: StringName) -> int:
	var n: int = int(codex.get(String(id), 0)) + 1
	codex[String(id)] = n
	return n


## A run reached `depth`. Returns how many runs have reached it, this one included.
func depth_reached(depth: int) -> int:
	var counts: Dictionary = stats.get("depth_reached_counts", {})
	var n: int = int(counts.get(str(depth), 0)) + 1
	counts[str(depth)] = n
	stats["depth_reached_counts"] = counts
	return n


func record_run(_result: Dictionary) -> void:
	push_warning("not implemented: MetaState.record_run (M2.10)")
