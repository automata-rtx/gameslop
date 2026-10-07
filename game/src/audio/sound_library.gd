class_name SoundLibrary
extends RefCounted
## The sample catalogue (03 Interfaces additions): game/assets/audio/manifest.json, written by
## tools/audio/synth.py. id -> files, bus, loop, channels, runtime hints. One-shots come back
## as an AudioStreamRandomizer over their variations with +-4% pitch (03 §6 rule 5); loops as
## their first AudioStreamWAV, so a pitch set on a loop is exact. Missing files are reported
## once with push_error and leave the id silent (14 §12).

const MANIFEST := "res://assets/audio/manifest.json"

var _sounds: Dictionary = {}       # StringName -> Dictionary (manifest entry)
var _streams: Dictionary = {}      # StringName -> AudioStream (or null when nothing loads)
var _reported: Dictionary = {}


func _init(path: String = MANIFEST) -> void:
	load_manifest(path)


func load_manifest(path: String) -> bool:
	_sounds.clear()
	_streams.clear()
	if not FileAccess.file_exists(path):
		push_error("AudioManager: no sound manifest at %s (run tools/audio/synth.py)" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("AudioManager: unreadable sound manifest %s" % path)
		return false
	var sounds: Variant = (parsed as Dictionary).get("sounds", {})
	if not sounds is Dictionary:
		push_error("AudioManager: manifest %s has no sounds" % path)
		return false
	for id: String in sounds:
		var entry: Variant = sounds[id]
		if entry is Dictionary:
			_sounds[StringName(id)] = entry
	return true


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _sounds:
		out.append(id)
	return out


func has(id: StringName) -> bool:
	return _sounds.has(id)


func entry(id: StringName) -> Dictionary:
	return _sounds.get(id, {})


func bus(id: StringName) -> StringName:
	return StringName(entry(id).get("bus", "World"))


func is_loop(id: StringName) -> bool:
	return bool(entry(id).get("loop", false))


func runtime(id: StringName) -> Dictionary:
	var r: Variant = entry(id).get("runtime", {})
	return r if r is Dictionary else {}


## The playable stream for `id`, or null (unknown id or no file loads; reported once).
func stream(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStream = null
	if not _sounds.has(id):
		_report(id, "AudioManager: unknown sound id %s" % id)
	else:
		s = _build(id)
	_streams[id] = s
	return s


func _build(id: StringName) -> AudioStream:
	var files: Array = entry(id).get("files", [])
	var loaded: Array[AudioStream] = []
	for f: Variant in files:
		var path := String(f)
		var res: Resource = load(path) if ResourceLoader.exists(path) else null
		if res is AudioStream:
			loaded.append(res)
		else:
			_report(StringName(path), "AudioManager: missing audio file %s (%s)" % [path, id])
	if loaded.is_empty():
		_report(id, "AudioManager: sound %s has no playable file; it stays silent" % id)
		return null
	if is_loop(id):
		return loaded[0]
	var r := AudioStreamRandomizer.new()
	for i in loaded.size():
		r.add_stream(i, loaded[i], 1.0)
	r.random_pitch = 1.0 + Tuning.AUDIO_PITCH_VARIATION
	r.random_volume_offset_db = 0.0
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if loaded.size() > 1 \
		else AudioStreamRandomizer.PLAYBACK_RANDOM
	return r


func _report(key: StringName, msg: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_error(msg)
