extends Node
## Time authority (14 §3): hitstop through the scene tree pause, wall-clock timers
## that keep running while the tree is paused, and the run timer.
## 11 §4 / 14 §6: hitstop and the pause menu share get_tree().paused; there is no
## custom time scale. Clock owns the pause flag so the two never fight over it:
## the pause menu calls set_menu_pause() instead of writing get_tree().paused.

## The microsecond source. Tests may swap it for a fake; gameplay never does.
var now_usec: Callable = Time.get_ticks_usec

var _hitstop_end_usec: int = 0
var _hitstop_active: bool = false
var _menu_paused: bool = false
var _wall_timers: Array[WallTimer] = []

var _run_started: bool = false
var _run_running: bool = false
var _run_start_usec: int = 0
var _run_paused_usec: int = 0
var _run_pause_began_usec: int = 0
var _run_stopped_usec: int = 0


func _ready() -> void:
	# 11 §4: the Clock itself must run while the tree is paused, or it could never unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)


func _process(_delta: float) -> void:
	var now: int = now_usec.call()
	if _hitstop_active and now >= _hitstop_end_usec:
		_end_hitstop()
	if not _wall_timers.is_empty():
		_fire_wall_timers(now)


## 11 §4: freeze the world for `ms` milliseconds of wall-clock time.
## A hitstop that arrives during another extends to whichever ends later; the two
## never add up. Refused while the menu (or anything else) holds the pause.
func hitstop(ms: int) -> void:
	if ms <= 0:
		return
	var tree := get_tree()
	if _menu_paused or (tree.paused and not _hitstop_active):
		return
	var end_usec: int = now_usec.call() + ms * 1000
	if _hitstop_active:
		_hitstop_end_usec = maxi(_hitstop_end_usec, end_usec)
		return
	_hitstop_active = true
	_hitstop_end_usec = end_usec
	tree.paused = true


func is_hitstopping() -> bool:
	return _hitstop_active


func hitstop_remaining_ms() -> float:
	if not _hitstop_active:
		return 0.0
	return maxf(0.0, float(_hitstop_end_usec - int(now_usec.call())) / 1000.0)


## The pause menu's entry to the tree pause. Opening ends any running hitstop (11 §4).
func set_menu_pause(on: bool) -> void:
	if on == _menu_paused:
		return
	_menu_paused = on
	if on:
		_hitstop_active = false
		if _run_running:
			_run_pause_began_usec = now_usec.call()
		get_tree().paused = true
	else:
		if _run_running:
			_run_paused_usec += now_usec.call() - _run_pause_began_usec
		get_tree().paused = false


func is_menu_paused() -> bool:
	return _menu_paused


## A one-shot timer measured in wall-clock time that keeps counting while the tree
## is paused (menus, transitions, anything that must survive a hitstop).
## Usage: `await Clock.wall_timer(0.5).timeout`.
func wall_timer(seconds: float) -> WallTimer:
	var t := WallTimer.new()
	t.end_usec = int(now_usec.call()) + int(round(seconds * 1_000_000.0))
	_wall_timers.append(t)
	return t


## Run timer: wall-clock seconds of the current Descent, excluding pause-menu time.
func start_run_timer() -> void:
	_run_started = true
	_run_running = true
	_run_start_usec = now_usec.call()
	_run_paused_usec = 0
	_run_pause_began_usec = _run_start_usec


func stop_run_timer() -> void:
	if not _run_running:
		return
	_run_stopped_usec = now_usec.call()
	if _menu_paused:
		_run_paused_usec += _run_stopped_usec - _run_pause_began_usec
	_run_running = false


func run_seconds() -> float:
	if not _run_started:
		return 0.0
	var end_usec: int = now_usec.call() if _run_running else _run_stopped_usec
	var paused := _run_paused_usec
	if _run_running and _menu_paused:
		paused += end_usec - _run_pause_began_usec
	return maxf(0.0, float(end_usec - _run_start_usec - paused) / 1_000_000.0)


func is_run_timer_running() -> bool:
	return _run_running


func _on_run_started(_mode: StringName, _seed: int) -> void:
	start_run_timer()


func _on_run_ended(_cause: StringName, _score: int) -> void:
	stop_run_timer()


func _fire_wall_timers(now: int) -> void:
	var due: Array[WallTimer] = []
	for t in _wall_timers:
		if now >= t.end_usec:
			due.append(t)
	for t in due:
		_wall_timers.erase(t)
		t.timeout.emit()


func _end_hitstop() -> void:
	_hitstop_active = false
	if not _menu_paused:
		get_tree().paused = false


## Returned by wall_timer(); emits `timeout` once.
class WallTimer extends RefCounted:
	signal timeout
	var end_usec: int = 0
