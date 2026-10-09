class_name AudioDucker
extends RefCounted
## Bus levels for AudioManager: the settings sliders (12 §4) plus the ducks of 03 §3, with
## the room-tone floor of 03 §6 rule 3 applied to Ambience. Timed ducks expire on the
## ducker's own clock (advanced by AudioManager in real time, so they run through pauses).

## The rendered level of the current room tone (manifest runtime.level_db); 0 when there is
## none, which leaves only the -40 dB floor itself.
var room_tone_db: float = 0.0:
	set(v):
		if v != room_tone_db:
			room_tone_db = v
			_version += 1
var _ducks: Array[Dictionary] = []
var _clock: float = 0.0
var _slider_db: Dictionary = {}
var _applied_db: Dictionary = {}
## R21: bumped by every change that can move a bus level (a duck added, released or
## expired, a slider, the room tone), so apply() skips the per-frame pass when the levels it
## would compute are the ones it computed last (the writes it would make are none).
var _version: int = 0
## The inputs of the last full apply() (-1: none yet).
var _applied_version: int = -1
var _applied_still: StringName = &""
var _applied_buses: int = -1
## The earliest `until` among the ducks (INF: none expires), so advance() filters only
## on the frame a duck ends.
var _next_expiry: float = INF


func advance(delta: float) -> void:
	_clock += delta
	if _next_expiry > _clock:
		return
	_ducks = _ducks.filter(func(d: Dictionary) -> bool: return float(d[&"until"]) > _clock)
	_changed()


## Notes a change to the duck list: the next apply() recomputes, the next expiry is found.
func _changed() -> void:
	_version += 1
	_next_expiry = INF
	for d in _ducks:
		_next_expiry = minf(_next_expiry, float(d[&"until"]))


func duck(bus: StringName, db: float, seconds: float) -> void:
	_ducks.append({&"key": &"", &"bus": bus, &"db": db, &"until": _clock + seconds, &"mute": false})
	_changed()


func hold(key: StringName, bus: StringName, db: float) -> void:
	release(key)
	_ducks.append({&"key": key, &"bus": bus, &"db": db, &"until": INF, &"mute": false})
	_changed()


## A held total mute (Null's core): like silence(), it lifts the rule-3 floor.
func hold_mute(key: StringName, bus: StringName) -> void:
	release(key)
	_ducks.append({&"key": key, &"bus": bus, &"db": Tuning.AUDIO_SLIDER_MUTE_DB, &"until": INF, &"mute": true})
	_changed()


func release(key: StringName) -> void:
	if has(key):
		_ducks = _ducks.filter(func(d: Dictionary) -> bool: return d[&"key"] != key)
		_changed()


func has(key: StringName) -> bool:
	for d in _ducks:
		if d[&"key"] == key:
			return true
	return false


func silence(bus: StringName, seconds: float) -> void:
	_ducks.append({&"key": &"", &"bus": bus, &"db": Tuning.AUDIO_SLIDER_MUTE_DB, &"until": _clock + seconds, &"mute": true})
	_changed()


func clear() -> void:
	_ducks.clear()
	_changed()


## Which floor rule 3 allows right now: a mute on Ambience or above it lifts the floor;
## Still's silence (key `still_key`) lowers it to -46 dB.
func ambience_floor(still_key: StringName) -> AudioMix.Floor:
	for d in _ducks:
		if d[&"mute"] and d[&"bus"] in [&"Ambience", &"World", &"Master"]:
			return AudioMix.Floor.MUTE
	return AudioMix.Floor.STILL if still_key != &"" and has(still_key) else AudioMix.Floor.NORMAL


## The duck offset on `bus`; Ambience is clamped so the room tone (inside World) stays at
## or above its floor counting World's own duck.
func duck_db(bus: StringName, still_key: StringName = &"") -> float:
	var d := AudioMix.bus_duck_db(_ducks, bus, _clock)
	if bus != &"Ambience":
		return d
	var world := AudioMix.bus_duck_db(_ducks, &"World", _clock)
	return AudioMix.clamp_ambience(d + world, room_tone_db, ambience_floor(still_key)) - world


func set_slider(buses: Array, v: float) -> void:
	for bus: StringName in buses:
		_slider_db[bus] = AudioMix.slider_db(v)
	_version += 1


func slider_db(bus: StringName) -> float:
	return float(_slider_db.get(bus, 0.0))


## Slider + duck for `bus`, floored at -80 dB.
func level_db(bus: StringName, still_key: StringName = &"") -> float:
	return maxf(slider_db(bus) + duck_db(bus, still_key), Tuning.AUDIO_SLIDER_MUTE_DB)


## Writes every bus level to the AudioServer (only the ones that changed).
func apply(still_key: StringName = &"") -> void:
	var buses := AudioServer.bus_count
	if _version == _applied_version and still_key == _applied_still and buses == _applied_buses:
		return
	_applied_version = _version
	_applied_still = still_key
	_applied_buses = buses
	for bus: StringName in Tuning.AUDIO_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var db := level_db(bus, still_key)
		if not is_equal_approx(float(_applied_db.get(bus, INF)), db):
			AudioServer.set_bus_volume_db(i, db)
			_applied_db[bus] = db
