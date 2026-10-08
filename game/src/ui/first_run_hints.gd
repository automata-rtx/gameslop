class_name FirstRunHints
extends RefCounted
## The rules of first-run guidance (04 §9), with no nodes: which hint shows when, and when
## it goes. HudHints feeds it what the player does and what the world looks like; it answers
## with the hint on screen. Seven hints, each shown once per save (`shown`, kept in
## meta.json), one at a time, for 6 s or until the action is performed:
##   move        on spawn, until 3 m walked;
##   flashlight  at 15 s into a level, or when the player stands where no fixture lights;
##   crank       the first time the flashlight charge is below 60%;
##   noclip      a soft wall within 3 m and aimed at;
##   drop        depth 2 or deeper: aiming at a droppable floor after 5 s with no soft wall aimed at;
##   items       the first item picked up;
##   coherence   the first time Coherence is below 50.
## A hint whose action the player performs before it shows is never shown (they know it).

signal changed(id: StringName)

const MOVE := &"move"
const FLASHLIGHT := &"flashlight"
const CRANK := &"crank"
const NOCLIP := &"noclip"
const DROP := &"drop"
const ITEMS := &"items"
const COHERENCE := &"coherence"
const NONE := &""

## Ids shown (or made unnecessary) on this save, in order.
var shown: Array[StringName] = []
## The Hints option (12 §6) and the depth-3 retirement (04 §9): false shows nothing.
var enabled: bool = true
## The hint on screen (NONE when none).
var current: StringName = NONE
## Seconds the current hint has been up.
var current_t: float = 0.0
var depth: int = 1
var level_t: float = 0.0
## Seconds since a soft wall was last aimed at (the drop hint's 5 s).
var no_soft_t: float = 0.0
var _queue: Array[StringName] = []


## The hint's template in Strings (04 §9; key names filled from the bindings by the HUD).
static func template(id: StringName) -> String:
	var i := Strings.HINT_IDS.find(id)
	return Strings.HINTS_IN_ORDER[i] if i != -1 else ""


func is_done(id: StringName) -> bool:
	return shown.has(id)


## A level begins (level_entered): the move hint is due on the first spawn.
func level_started(d: int) -> void:
	depth = d
	level_t = 0.0
	no_soft_t = 0.0
	_request(MOVE)
	_pump()


## One frame of play. `sense` keys (all optional): walked (m from the spawn point), dark
## (bool), charge (flashlight %, 0..100), soft_aim (bool), floor_aim (bool), coherence.
func tick(dt: float, sense: Dictionary) -> void:
	level_t += dt
	var soft := bool(sense.get(&"soft_aim", false))
	no_soft_t = 0.0 if soft else no_soft_t + dt
	if float(sense.get(&"walked", 0.0)) >= Tuning.HINT_MOVE_DIST:
		performed(MOVE)
	if level_t >= Tuning.HINT_FLASHLIGHT_DELAY or bool(sense.get(&"dark", false)):
		_request(FLASHLIGHT)
	if float(sense.get(&"charge", Tuning.FLASH_CHARGE_MAX)) < Tuning.HINT_CRANK_BELOW:
		_request(CRANK)
	if soft:
		_request(NOCLIP)
	if depth >= Tuning.HINT_FLOOR_MIN_DEPTH and no_soft_t >= Tuning.HINT_FLOOR_AIM_TIME \
			and bool(sense.get(&"floor_aim", false)):
		_request(DROP)
	if float(sense.get(&"coherence", Tuning.COHERENCE_MAX)) < Tuning.COHERENCE_HINT_BELOW:
		_request(COHERENCE)
	if current != NONE:
		current_t += dt
		# The move hint stays until 3 m walked; the others 6 s.
		if current != MOVE and current_t >= Tuning.HINT_SHOW_TIME:
			_end()
	_pump()


## The first item picked up.
func item_picked() -> void:
	_request(ITEMS)
	_pump()


## The player did what hint `id` teaches: it leaves now, or is never needed.
func performed(id: StringName) -> void:
	_queue.erase(id)
	if current == id:
		_end()
	elif not shown.has(id):
		shown.append(id)
	_pump()


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_queue.clear()
		if current != NONE:
			current = NONE
			current_t = 0.0
			changed.emit(NONE)
	_pump()


## Forgets every shown hint (the Hints option turned back on).
func reset() -> void:
	shown.clear()
	_queue.clear()


func _request(id: StringName) -> void:
	if not enabled or shown.has(id) or current == id or _queue.has(id):
		return
	_queue.append(id)


func _end() -> void:
	current = NONE
	current_t = 0.0
	changed.emit(NONE)


func _pump() -> void:
	if not enabled or current != NONE or _queue.is_empty():
		return
	current = _queue.pop_front()
	current_t = 0.0
	shown.append(current)
	changed.emit(current)
