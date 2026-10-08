class_name RunState
extends RefCounted
## One Descent's state (05 Interfaces), held by the GameState autoload.
## GameState.start_run fills it from the mode and the loadout (05 §7, §8); the run scene
## and the errors feed the counters through GameState.record_*.

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
## Total evasions (05 §5 score term); evasions_by holds the per-error split.
var evasions: int = 0
## error id -> evasion count this run (Unlock #6: Flicker x3 in one run).
var evasions_by: Dictionary = {}
## Deepest depth reached this run (05 §5 max_depth_reached).
var max_depth: int = 1
var walls_passed: int = 0
## Every drop this run (drops_in_a_row resets on a proper exit; this does not).
var drops_total: int = 0
var coherence_spent: float = 0.0
var distance_m: float = 0.0
## error id -> notice count this run.
var encounters: Dictionary = {}
var started_at_ms: int = 0
## 05 §10: this Descent is the save's first (scripted guarantees apply).
var first_descent: bool = false
## Loadout multipliers (05 §7 Lightbearer): flashlight crank rate, Flicker light attraction distance.
var crank_rate_mult: float = 1.0
var flicker_attract_mult: float = 1.0
## The loadout's starting belt (item kind -> count); the run puts it on the belt.
var start_items: Dictionary = {}
## Daily Descent: the UTC "YYYYMMDD" this attempt belongs to (13 §4); empty otherwise.
var daily_key: String = ""
## Final Descent Score, set by GameState.end_run (05 §5).
var score: int = 0
## Unlock ids earned during this run, in order (Run Summary unlock lines, 04 §7).
var unlocks_earned: Array[StringName] = []
