class_name DirectorStatics
extends RefCounted
## The Director's Static fairness (05 §10, 08 §3, 10 §7 rule 4), split out of DirectorHunters
## (14 §6 400-line limit, M2.7): the first Descent's wander filters and the critical-path cut
## timer with its nudge.

var director: Director
## Static instance id -> seconds its field has cut the only route (08 §3).
var _cut_time: Dictionary = {}


## 05 §10 first Descent, as the M1.13 ruling places it: the first Static spawns between the
## breaker and the exit and its drift stays within 6 m of that stretch of the critical path
## (`DirectorSpawn.breaker_exit_band`); any other Static drifts in a side loop
## (`side_loop_cells`). Each gets its wander filter through `ErrorStatic.set_wander_filter`
## (called only when it exists). Returns the first Static's filter, or an invalid Callable
## when none applies.
func bound_statics_off_path() -> Callable:
	var d := director
	var h := d.hunters
	if not h._first_descent_depth1():
		return Callable()
	var statics := h._statics()
	if statics.is_empty():
		return Callable()
	var first := Callable()
	for i in statics.size():
		var st := statics[i]
		var allowed := DirectorSpawn.breaker_exit_band(d.data) if i == 0 else {}
		if allowed.is_empty():
			allowed = DirectorSpawn.side_loop_cells(h._grid(), d.data.critical_path, st.global_position)
		if allowed.is_empty():
			continue
		var filter := DirectorSpawn.cell_filter(h._grid(), allowed)
		if i == 0:
			first = filter
		if st.has_method(&"set_wander_filter"):
			st.call(&"set_wander_filter", filter)
	return first


## 08 §3, 10 §7 rule 4: every 5 s, does a Static field cut the only route from the player
## to the exit? After 40 s cumulative it is nudged off the critical path at 1.2 m/s.
func static_fairness(interval: float) -> void:
	var h := director.hunters
	if not h._player_ok() or h._grid() == null or director.data.exit_cell == LevelData.NO_CELL:
		return
	var from := h._grid().cell_of(director.player.global_position)
	for st in h._statics():
		if st.is_dormant():
			continue
		var key := st.get_instance_id()
		if DirectorSpawn.static_cuts_path(h._grid(), st.centre(), st.radius, from, director.data.exit_cell):
			_cut_time[key] = float(_cut_time.get(key, 0.0)) + interval
		if float(_cut_time.get(key, 0.0)) >= Tuning.STATIC_FAIR_CUMULATIVE_LIMIT:
			_cut_time[key] = 0.0
			h._hint_off_path(st, true)


func cut_time(st: ErrorStatic) -> float:
	return float(_cut_time.get(st.get_instance_id(), 0.0))
