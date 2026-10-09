class_name SimBotTelemetry
extends RefCounted
## M3.4 tuning telemetry for one level a SimBot plays (test-bot code, no game rule): the
## Coherence lost per source (an error id, `noclip`, ...), the light the player stood in at
## each contact (the Offices light dilemma, 08 §5: lit fixture within 4 m, flashlight on),
## when the breaker was thrown, and the Director's intensity per phase (the sawtooth and the
## Pursuit, 10 §2). `results(result)` merges the keys `losses`, `contact_light`,
## `breaker_s`, `phase_intensity`, `last_losses`, `evasions` (error id -> `lost_player` on this level) into
## the bot's result.

## A contact counts as "lit" when a powered fixture stands within this of the player (XZ):
## Flicker's lit-area cell rule (08 §5, FLICKER_LIT_AREA_CELL_DIST).
const LIT_DIST := Tuning.FLICKER_LIT_AREA_CELL_DIST

var bot: SimBot
## source -> Coherence lost (positive).
var losses: Dictionary = {}
## [t, error id, lit fixture near, flashlight on]
var contact_light: Array = []
var breaker_s: float = -1.0
## phase -> [sum of intensity, ticks]
var _phase_i: Dictionary = {}
var _player: Player
var _on_coh: Callable
var _on_breaker: Callable
var _evasions0: Dictionary = {}
## The last LAST_LOSSES losses [physics frame, source, amount] (the death-cause check, 06 §9).
var _last: Array = []
const LAST_LOSSES := 6


func start() -> void:
	_player = bot.run.player
	_evasions0 = GameState.run.evasions_by.duplicate() if GameState.run != null else {}
	_on_coh = func(_v: float, delta: float, source: StringName) -> void:
		if delta < 0.0:
			var k := String(source)
			losses[k] = snappedf(float(losses.get(k, 0.0)) - delta, 0.01)
			_last.append([Engine.get_physics_frames(), k, snappedf(-delta, 0.001)])
			if _last.size() > LAST_LOSSES:
				_last.pop_front()
	_player.coherence_changed.connect(_on_coh)
	_on_breaker = func(_pos: Vector3) -> void:
		if breaker_s < 0.0:
			breaker_s = snappedf(bot.time(), 0.1)
	EventBus.breaker_thrown.connect(_on_breaker)


## Once per physics frame.
func tick() -> void:
	var ph := String(bot.director.phase)
	var a: Array = _phase_i.get(ph, [0.0, 0])
	a[0] = float(a[0]) + bot.director.intensity
	a[1] = int(a[1]) + 1
	_phase_i[ph] = a


## The light around the player at a contact by `id`.
func contact(id: StringName) -> void:
	var lit := false
	var pool: LightPool = bot.run.level.light_pool if bot.run.level != null else null
	if pool != null and is_instance_valid(_player):
		lit = not pool.lit_fixtures_near(_player.global_position, LIT_DIST).is_empty()
	var torch := is_instance_valid(_player) and _player.flashlight.on
	contact_light.append([snappedf(bot.time(), 0.1), String(id), lit, torch])


func stop() -> void:
	if is_instance_valid(_player) and _player.coherence_changed.is_connected(_on_coh):
		_player.coherence_changed.disconnect(_on_coh)
	if EventBus.breaker_thrown.is_connected(_on_breaker):
		EventBus.breaker_thrown.disconnect(_on_breaker)


func results(result: Dictionary) -> void:
	result[&"losses"] = losses.duplicate()
	result[&"last_losses"] = _last.duplicate(true)
	result[&"contact_light"] = contact_light.duplicate(true)
	result[&"breaker_s"] = breaker_s
	var ev := {}
	if GameState.run != null:
		for id: Variant in GameState.run.evasions_by:
			var n := int(GameState.run.evasions_by[id]) - int(_evasions0.get(id, 0))
			if n > 0:
				ev[String(id)] = n
	result[&"evasions"] = ev
	var pi := {}
	for ph: String in _phase_i:
		var a: Array = _phase_i[ph]
		pi[ph] = [snappedf(float(a[0]) / maxf(int(a[1]), 1), 0.01), snappedf(int(a[1]) / 60.0, 0.1)]
	result[&"phase_intensity"] = pi
