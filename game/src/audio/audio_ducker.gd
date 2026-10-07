class_name AudioDucker
extends RefCounted
## Bus levels for AudioManager: the settings sliders (12 §4) plus the ducks of 03 §3, with
## the room-tone floor of 03 §6 rule 3 applied to Ambience. Timed ducks expire on the
## ducker's own clock (advanced by AudioManager in real time, so they run through pauses).

## The rendered level of the current room tone (manifest runtime.level_db); 0 when there is
## none, which leaves only the -40 dB floor itself.
var room_tone_db: float = 0.0
var _ducks: Array[Dictionary] = []
var _clock: float = 0.0
var _slider_db: Dictionary = {}
var _applied_db: Dictionary = {}


func advance(delta: float) -> void:
	_clock += delta
	_ducks = _ducks.filter(func(d: Dictionary) -> bool: return float(d[&"until"]) > _clock)


func duck(bus: StringName, db: float, seconds: float) -> void:
	_ducks.append({&"key": &"", &"bus": bus, &"db": db, &"until": _clock + seconds, &"mute": false})


func hold(key: StringName, bus: StringName, db: float) -> void:
	release(key)
	_ducks.append({&"key": key, &"bus": bus, &"db": db, &"until": INF, &"mute": false})


func release(key: StringName) -> void:
	_ducks = _ducks.filter(func(d: Dictionary) -> bool: return d[&"key"] != key)


func has(key: StringName) -> bool:
	return _ducks.any(func(d: Dictionary) -> bool: return d[&"key"] == key)


func silence(bus: StringName, seconds: float) -> void:
	_ducks.append({&"key": &"", &"bus": bus, &"db": Tuning.AUDIO_SLIDER_MUTE_DB, &"until": _clock + seconds, &"mute": true})


func clear() -> void:
	_ducks.clear()


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


func slider_db(bus: StringName) -> float:
	return float(_slider_db.get(bus, 0.0))


## Slider + duck for `bus`, floored at -80 dB.
func level_db(bus: StringName, still_key: StringName = &"") -> float:
	return maxf(slider_db(bus) + duck_db(bus, still_key), Tuning.AUDIO_SLIDER_MUTE_DB)


## Writes every bus level to the AudioServer (only the ones that changed).
func apply(still_key: StringName = &"") -> void:
	for bus: StringName in Tuning.AUDIO_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var db := level_db(bus, still_key)
		if not is_equal_approx(float(_applied_db.get(bus, INF)), db):
			AudioServer.set_bus_volume_db(i, db)
			_applied_db[bus] = db
