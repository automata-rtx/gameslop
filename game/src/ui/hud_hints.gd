class_name HudHints
extends Control
## First-run guidance on the HUD (04 §9, 05 §10): single prompt-style lines in ui_dim, in
## the prompt position, shown once each, never blocking play (no input is taken, the world
## does not pause). The rules are FirstRunHints; this node feeds them and draws the line:
## - key names come from the current bindings (UiKeys.key_name), so a rebind shows at once;
## - the line shutters in and out, and gives way to an interaction prompt while one shows
##   (the hint's time keeps running);
## - what the player does arrives through the HUD's calls (charge, Coherence, flashlight,
##   crank, noclip charge, items); what the world looks like is sampled at 10 Hz from the
##   active camera: distance from the spawn point, the aimed surface (NoclipQuery.classify),
##   and whether a fixture lights the spot (LightPool.is_lit);
## - shown ids persist in meta.json (`hints_shown`); reaching depth 3 once retires the hints
##   by turning the Hints option off (`hints_retired`), and turning it back on resets them.

const SETTING := &"hints"
const SENSE_INTERVAL := 0.1
## Placeholders of a hint template are input actions (06 §2).
const PLACEHOLDER := "\\{([a-z_0-9]+)\\}"

var logic := FirstRunHints.new()
var line: HudPrompt
## Persist shown ids to GameState.meta (off in unit tests that drive the rules by hand).
var persist: bool = true
## The world sampler; tests replace it with a Callable returning a sense Dictionary.
var world_sense: Callable
var prompt_busy: bool = false
var charge: float = Tuning.FLASH_CHARGE_MAX
var coherence: float = Tuning.COHERENCE_MAX
var _sense: Dictionary = {}
var _sense_t: float = 0.0
var _spawn: Variant = null
var _regex := RegEx.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_regex.compile(PLACEHOLDER)
	line = HudPrompt.new()
	line.name = "HintLine"
	line.text_type = &"Hint"
	line.shutter_sound = true
	add_child(line)
	world_sense = _sense_world
	logic.changed.connect(_on_hint_changed)


func _ready() -> void:
	SettingsManager.changed.connect(_on_setting_changed)
	EventBus.level_entered.connect(_on_level_entered)
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.item_used.connect(func(_k: StringName) -> void: logic.performed(FirstRunHints.ITEMS))
	_load()


## The hint's text with key names from the bindings (04 §9), as key-cap segments.
static func segments_for(id: StringName) -> Array[Dictionary]:
	var t := FirstRunHints.template(id)
	var keys := {}
	var re := RegEx.new()
	re.compile(PLACEHOLDER)
	for m in re.search_all(t):
		var action := StringName(m.get_string(1))
		keys[action] = UiKeys.key_name(action)
	return UiKeys.segments(t, {}, keys)


func current() -> StringName:
	return logic.current


func plain_text() -> String:
	return line.plain_text()


func is_shown() -> bool:
	return line.is_shown()


# --- calls from the HUD (signals up, calls down) ---------------------------------------------

func set_charge(v: float) -> void:
	charge = v


func set_coherence(v: float) -> void:
	coherence = v


func flashlight_on(on: bool) -> void:
	if on:
		logic.performed(FirstRunHints.FLASHLIGHT)


func cranking(on: bool) -> void:
	if on:
		logic.performed(FirstRunHints.CRANK)


## A noclip charge in progress teaches the noclip (walls) or the drop (floor) hint.
func noclip_charging(charge_f: float, target: StringName) -> void:
	if charge_f <= 0.0:
		return
	logic.performed(FirstRunHints.DROP if target == NoclipQuery.TARGET_FLOOR else FirstRunHints.NOCLIP)


## An interaction prompt owns the prompt position while it shows (04 §9 hints sit there).
func set_prompt_busy(busy: bool) -> void:
	prompt_busy = busy
	_show_line()


func hide_now() -> void:
	line.hide_text()


# --- time -----------------------------------------------------------------------------------

func advance(dt: float) -> void:
	if is_inside_tree() and get_tree().paused:
		return
	_sense_t -= dt
	if _sense_t <= 0.0:
		_sense_t = SENSE_INTERVAL
		if world_sense.is_valid():
			_sense = world_sense.call()
	var s := _sense.duplicate()
	s[&"charge"] = charge
	s[&"coherence"] = coherence
	logic.tick(dt, s)


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)


func _sense_world() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return out
	var pos := cam.global_position
	if _spawn == null:
		_spawn = pos
	var flat := Vector2(pos.x - (_spawn as Vector3).x, pos.z - (_spawn as Vector3).z)
	out[&"walked"] = flat.length()
	var space := cam.get_world_3d().direct_space_state
	var reach := maxf(Tuning.HINT_SOFT_WALL_DIST, Tuning.NOCLIP_RANGE)
	var q := PhysicsRayQueryParameters3D.create(pos, pos - cam.global_basis.z * reach, PlayerLayers.WORLD_MASK)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var floor_solid := GameState.run != null and GameState.is_run_active() \
				and GameState.run.mode != Tuning.MODE_ENDLESS and GameState.run.depth >= Tuning.RUN_FINAL_DEPTH
		var kind := NoclipQuery.classify(hit, floor_solid)
		var dist := pos.distance_to(hit[&"position"])
		out[&"soft_aim"] = kind[&"target"] == NoclipQuery.TARGET_SOFT and dist <= Tuning.HINT_SOFT_WALL_DIST
		out[&"floor_aim"] = kind[&"target"] == NoclipQuery.TARGET_FLOOR and not kind[&"solid"] \
				and dist <= Tuning.NOCLIP_RANGE
	for n in get_tree().get_nodes_in_group(Level.GROUP):
		var lv := n as Level
		if lv != null and lv.light_pool != null and not lv.is_queued_for_deletion():
			out[&"dark"] = not lv.light_pool.is_lit(pos)
			break
	return out


# --- events -------------------------------------------------------------------------------------

func _on_level_entered(d: int, _stratum: StringName, _arrival: StringName) -> void:
	_spawn = null
	_sense = {}
	_sense_t = 0.0
	# 04 §9: suppressed after the player has reached depth 3 once.
	if persist and d >= Tuning.HINT_SUPPRESS_DEPTH and GameState.meta != null and not GameState.meta.hints_retired:
		GameState.meta.hints_retired = true
		_save(true)
		SettingsManager.set_value(SETTING, false)
	logic.level_started(d)


func _on_item_picked(kind: StringName) -> void:
	if kind != &"keycard":
		logic.item_picked()


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key != SETTING:
		return
	var on := value is bool and bool(value)
	if on and not logic.enabled:
		# 12 §6: turning the hints back on shows them again.
		logic.reset()
		_save()
	logic.set_enabled(on)


func _on_hint_changed(_id: StringName) -> void:
	_save()
	_show_line()


func _show_line() -> void:
	if logic.current == FirstRunHints.NONE or prompt_busy:
		line.hide_text()
		return
	line.set_segments(segments_for(logic.current), 0.0, UiTokens.UI_DIM)
	line.raw_text = String(logic.current)


func _load() -> void:
	logic.enabled = bool(SettingsManager.get_value(SETTING))
	if persist and GameState.meta != null:
		logic.shown = GameState.meta.hints_shown.duplicate()


func _save(force: bool = false) -> void:
	if not persist or GameState.meta == null:
		return
	if not force and GameState.meta.hints_shown == logic.shown:
		return
	GameState.meta.hints_shown = logic.shown.duplicate()
	SaveManager.save_meta()
