class_name ErrorBase
extends Node3D
## The shared architecture of the five errors (08 §2). Each error has one rule, one
## counter, one tell and one cost (08 §1); this base holds only what they share: the
## state machine with canonical ids (Tuning.ERROR_STATE_*), honest senses (a Senses
## child), notice and evasion events, contact through Player.contact, the Director link,
## and the processing budget. Subclasses implement the rule in _tick().
##
## Director link (10): set_aggression(a), hint(pos), wake(), sleep(), retreat(seconds),
## start_search(pos) (awake arrivals, 10 §4). The Director may put an error near the
## player; it never tells it where the player is. A chase starts only from Senses.
## Errors stay Dormant until the level's navigation is ready (07 §3, 14 §12): wake()
## before that is remembered and applied when it is.
## Contact (08 §2): `contact_request` (error) -> bool, injected by the Director, is asked
## first; then Player.contact(self, cost), whose own `contact_gate` may refuse too. Use one
## of the two for the 3 s exclusivity, not both (each approval starts the 3 s window).

signal state_changed(from: StringName, to: StringName)
signal contacted_player(cost: float)
## An evasion (08 §2 per-error definitions; Archive, unlocks, score).
signal lost_player
## An encounter (08 §2 per-error definitions; Archive counter).
signal noticed_player

const GROUP := &"errors"
const SCENES: Dictionary = {
	&"static": "res://scenes/errors/static.tscn",
	&"still": "res://scenes/errors/still.tscn",
}

@export var error_id: StringName = &""

var state: StringName = Tuning.ERROR_STATE_DORMANT
## 0..1 from the Director; mapped per 08 §8 (clamped to the [0.25, 0.75] columns).
var aggression: float = 0.0
var player: Player
var level: Level
## The level grid (Static's drift). Null in hand-built test rooms.
var grid: LevelGrid
var rng: RandomNumberGenerator = Seeds.rng(0)
## (error: ErrorBase) -> bool. Asked before Player.contact; false refuses the contact.
var contact_request: Callable
var data: ErrorData
var navigation_ready: bool = false
var senses: Senses
## Seconds in the current state.
var state_time: float = 0.0
## Recent transitions, `STILL: Wander → Chase (seen 1.5 s)` (14 §9 debug overlay).
var log_lines: PackedStringArray = []
## The seed given to setup() (presentation rngs derive from it).
var seed_value: int = 0

var _wake_pending: bool = false
## start_search() before navigation was ready: enter Search (not Wander) once it is.
var _search_pending: bool = false
var _dormant_acc: float = 0.0
var _sense_acc: float = 0.0
var _prox_acc: float = 0.0
var _hint: Vector3 = Vector3.ZERO
var _has_hint: bool = false
## True between a notice and its end (evasion, contact, retreat or sleep).
var _engaged: bool = false
var _contact_frames: int = 0
var _satiated_left: float = 0.0


## Instances the scene for `id` (Director: spawn_error). Null for an unknown id.
static func create(id: StringName) -> ErrorBase:
	if not SCENES.has(id):
		push_error("ErrorBase.create: no scene for error %s" % id)
		return null
	return (load(SCENES[id]) as PackedScene).instantiate() as ErrorBase


## Seed label for the error's rng (Seeds.derive(level_seed, label)).
static func seed_label(id: StringName, index: int) -> String:
	return Tuning.SEED_LABEL_ERROR % [id, index]


## 08 §8: the position of `a` between the 0.25 and 0.75 columns, clamped.
static func aggr_t(a: float) -> float:
	return clampf((a - Tuning.AGGR_MIN) / (Tuning.AGGR_MAX - Tuning.AGGR_MIN), 0.0, 1.0)


static func aggr_lerp(low: float, high: float, a: float) -> float:
	return lerpf(low, high, aggr_t(a))


func _init() -> void:
	add_to_group(GROUP)
	add_to_group(DebugOverlay.GROUP)
	ErrorTiming.ensure_monitor()


func _ready() -> void:
	data = load("res://data/errors/%s.tres" % error_id) as ErrorData
	senses = get_node_or_null(^"%Senses") as Senses
	if senses == null:
		senses = Senses.new()
		senses.name = "Senses"
		add_child(senses)
	senses.error = self
	senses.heard.connect(_on_heard)
	_configure()
	_set_active(false)


## Call before or after adding to the tree. `level` may be null in hand-built rooms (then
## call set_navigation_ready yourself). `seed_value`: Seeds.derive(level_seed, seed_label()).
func setup(p_player: Player, p_level: Level = null, p_seed: int = 0) -> void:
	player = p_player
	seed_value = p_seed
	rng = Seeds.rng(p_seed)
	_on_seeded()
	if p_level != null:
		bind_level(p_level)


func bind_level(p_level: Level) -> void:
	level = p_level
	if level.data != null:
		grid = level.data.grid
	if level.is_ready():
		set_navigation_ready(level.builder.navigation_ok)
	elif not level.navigation_ready.is_connected(set_navigation_ready):
		level.navigation_ready.connect(set_navigation_ready, CONNECT_ONE_SHOT)


## 07 §3: errors stay dormant until the navigation mesh is baked; a failed bake keeps
## them dormant for the whole level (14 §12).
func set_navigation_ready(ok: bool) -> void:
	navigation_ready = ok
	if ok and _wake_pending:
		_wake_pending = false
		if _search_pending:
			_search_pending = false
			transition_to(Tuning.ERROR_STATE_SEARCH, "awake", true)
		else:
			wake()


# --- Director link (08 §2, 10) --------------------------------------------------------

func set_aggression(a: float) -> void:
	aggression = clampf(a, 0.0, 1.0)
	_on_aggression()


## A suggested destination, used only in Wander, Search and the Satiated retreat.
## `immediate` (10 §2 Relief, 2026-10-08): in Wander or Search the error re-targets to it
## at once instead of when its current leg ends. In any other state it is only stored.
func hint(destination: Vector3, immediate: bool = false) -> void:
	_hint = destination
	_has_hint = true
	if immediate and (state == Tuning.ERROR_STATE_WANDER or state == Tuning.ERROR_STATE_SEARCH):
		_retarget_to_hint()


func clear_hint() -> void:
	_has_hint = false


func has_hint() -> bool:
	return _has_hint


func wake() -> void:
	if not navigation_ready:
		_wake_pending = true
		return
	if state == Tuning.ERROR_STATE_DORMANT:
		transition_to(Tuning.ERROR_STATE_WANDER, "wake")


func sleep() -> void:
	_wake_pending = false
	_search_pending = false
	_engaged = false
	transition_to(Tuning.ERROR_STATE_DORMANT, "sleep")


## Satiated for `seconds`: retreat, no chase (10: the Peak cap, a refused contact).
func retreat(seconds: float) -> void:
	if state == Tuning.ERROR_STATE_DORMANT:
		return
	_engaged = false
	_satiated_left = maxf(seconds, 0.0)
	transition_to(Tuning.ERROR_STATE_SATIATED, "retreat %.0f s" % seconds, true)


## 10 §4 awake arrivals: Search from a Director-chosen point (never the player's).
## Before navigation is ready the Search is remembered and entered when it is.
func start_search(pos: Vector3) -> void:
	senses.last_known_pos = pos
	senses.last_known_time = senses.clock
	if not navigation_ready:
		_wake_pending = true
		_search_pending = true
		return
	transition_to(Tuning.ERROR_STATE_SEARCH, "awake", true)


func distance_to_player() -> float:
	if not has_player() or not is_inside_tree():
		return INF
	return body_position().distance_to(player.global_position)


## True while the player is a live node in the tree. A freed player is forgotten here
## (the run or a tour may free it while the level lives on): nothing ticks against it.
func has_player() -> bool:
	if player != null and not is_instance_valid(player):
		player = null
	return player != null and player.is_inside_tree()


## The player when it is alive (in or out of the tree), else null.
func live_player() -> Player:
	if player != null and not is_instance_valid(player):
		player = null
	return player


func is_dormant() -> bool:
	return state == Tuning.ERROR_STATE_DORMANT


func is_engaged() -> bool:
	return _engaged


# --- body (overridden by movers) ------------------------------------------------------

## Where the error stands (movers: their CharacterBody3D).
func body_position() -> Vector3:
	return global_position


func ear_position() -> Vector3:
	return body_position() + Vector3.UP * Tuning.ERROR_EYE_HEIGHT


## RIDs the senses' rays ignore.
func body_rids() -> Array[RID]:
	return []


# --- state machine ----------------------------------------------------------------------

func transition_to(to: StringName, reason: String = "", force: bool = false) -> void:
	if to == state and not force:
		return
	var from := state
	_exit_state(from, to)
	state = to
	state_time = 0.0
	_set_active(to != Tuning.ERROR_STATE_DORMANT)
	_enter_state(to, from)
	var line := "%s: %s → %s" % [String(error_id).to_upper(), String(from).capitalize(), String(to).capitalize()]
	if reason != "":
		line += " (%s)" % reason
	log_lines.append(line)
	if log_lines.size() > Tuning.ERROR_LOG_LINES:
		log_lines.remove_at(0)
	print_verbose(line)
	state_changed.emit(from, to)
	EventBus.error_state.emit(error_id, from, to)


func _set_active(on: bool) -> void:
	if senses != null:
		senses.listen(on)
	_set_body_active(on)


# --- notice, evasion, contact (08 §2) ----------------------------------------------------

## Once per engagement.
func _notice() -> void:
	if _engaged:
		return
	_engaged = true
	noticed_player.emit()
	GameState.record_notice(error_id)


## An evasion closes an engagement that had a notice.
func _evade() -> void:
	if not _engaged:
		return
	_engaged = false
	lost_player.emit()
	GameState.record_evasion(error_id)


## The 08 §2 contact test, called each physics frame by an error that contacts: within
## `radius` (XZ, one floor) for 2 consecutive physics frames and not hidden.
func contact_step(radius: float, cost: float) -> bool:
	if not has_player() or player.is_hidden():
		_contact_frames = 0
		return false
	var a := body_position()
	var b := player.global_position
	var near := Vector2(a.x - b.x, a.z - b.z).length() <= radius and absf(a.y - b.y) < Tuning.ERROR_CONTACT_MAX_DY
	_contact_frames = _contact_frames + 1 if near else 0
	if _contact_frames < Tuning.CONTACT_RADIUS_FRAMES:
		return false
	_contact_frames = 0
	return try_contact(cost)


## Contact through the gates: contact_request (Director), then Player.contact (which
## applies cost, stun, push and asks its own contact_gate). On success: Satiated 20 s.
func try_contact(cost: float) -> bool:
	if not has_player():
		return false
	if contact_request.is_valid() and not bool(contact_request.call(self)):
		return false
	if not player.contact(self, cost):
		return false
	_engaged = false
	contacted_player.emit(cost)
	_on_contact()
	_satiated_left = Tuning.ERROR_SATIATED_TIME
	transition_to(Tuning.ERROR_STATE_SATIATED, "contact %.0f" % cost, true)
	return true


# --- processing budget (08 §2) -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_error(delta)
	ErrorTiming.account(error_id, Time.get_ticks_usec() - t0)


func _process_error(delta: float) -> void:
	if live_player() == null or (level != null and not is_instance_valid(level)):
		# No player to hunt (freed) or the level is gone: nothing ticks (R9 item 16).
		_on_player_gone()
		return
	if state == Tuning.ERROR_STATE_DORMANT:
		# Dormant errors run only a 1 s timer.
		_dormant_acc += delta
		if _dormant_acc >= Tuning.ERROR_DORMANT_TICK:
			_dormant_acc = 0.0
			_dormant_tick()
		return
	state_time += delta
	_sense_acc += delta
	var far := distance_to_player() > Tuning.ERROR_FAR_DIST
	if not far or _sense_acc >= Tuning.ERROR_FAR_SENSE_INTERVAL:
		senses.tick(_sense_acc, player if has_player() else null)
		_sense_acc = 0.0
	_tick(delta)
	_prox_acc += delta
	if _prox_acc >= Tuning.ERROR_PROXIMITY_INTERVAL:
		_prox_acc = 0.0
		EventBus.error_proximity.emit(error_id, distance_to_player())


## 14 §9 debug overlay line.
func debug_info() -> Dictionary:
	var d := distance_to_player()
	return {String(error_id): "%s %s" % [state, "-" if is_inf(d) else "%.1f m" % d],
		"errors ms": "%.3f" % ErrorTiming.errors_ms()}


# --- virtuals -------------------------------------------------------------------------------

## Overridden by each error (one line each; see the subclasses).
func _configure() -> void: pass
func _on_seeded() -> void: pass
func _on_aggression() -> void: pass
func _set_body_active(_on: bool) -> void: pass
func _dormant_tick() -> void: pass
func _enter_state(_to: StringName, _from: StringName) -> void: pass
func _exit_state(_from: StringName, _to: StringName) -> void: pass
func _tick(_delta: float) -> void: pass
func _on_heard(_pos: Vector3, _radius: float, _kind: StringName) -> void: pass
func _on_contact() -> void: pass
## Called each physics frame while there is no live player (or the level was freed).
func _on_player_gone() -> void: pass
## A hint marked immediate arrived in Wander or Search: re-target to `_hint` now.
func _retarget_to_hint() -> void: pass
