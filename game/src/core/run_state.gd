class_name RunState
extends RefCounted
## One Descent's state (05 Interfaces), held by the GameState autoload.
## Placeholder data holder: M1.9 and M2.10 fill strata order, loadouts, and scoring.

var run_seed: int = 0
var mode: StringName = &"descent"
var loadout: StringName = &"faller"
var depth: int = 1
var strata_order: Array[StringName] = []
var coherence: float = Tuning.COHERENCE_MAX  # loadout start applies in start_run (05 §7)
## Array[ItemSlot] once 09's ItemSlot exists (M1.10).
var items: Array = []
var proper_exits: int = 0
var drops_in_a_row: int = 0
var notes_found: Array[StringName] = []
var evasions: int = 0
## error id -> notice count this run.
var encounters: Dictionary = {}
var started_at_ms: int = 0
