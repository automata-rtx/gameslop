extends SceneTree
## Stress repro for the engine audio race behind RCA1 (see AudioMixGuard): many positional
## players change their bus volumes every frame on an unthrottled headless main loop while
## short one-shots start and finish. Run several copies at once to load the machine:
##   godot --headless --fixed-fps 60 --path game --script tests/stress/audio_mix_race.gd -- \
##         [--seconds 60] [--players 24] [--no-guard]
## Exit 0 after the time is up; without the guard, loaded runs crash (signal 11 in the
## audio thread, or abort) within minutes. Not part of the gate (no test_ prefix).


var _seconds: float = 60.0
var _count: int = 24
var _players: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _cam: Camera3D
var _t0: int = 0
var _frames: int = 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--seconds" and i + 1 < a.size():
			_seconds = a[i + 1].to_float()
		elif a[i] == "--players" and i + 1 < a.size():
			_count = maxi(a[i + 1].to_int(), 1)
		elif a[i] == "--no-guard":
			AudioMixGuard.enabled = false
	var world := Node3D.new()
	root.add_child(world)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.make_current()
	var blip := _tone(0.04, false)
	var hum := _tone(0.5, true)
	for i in _count:
		var p := AudioStreamPlayer3D.new()
		p.stream = hum if i % 3 == 0 else blip
		p.max_polyphony = 4
		p.position = Vector3(i % 8, 0.0, i / 8)
		world.add_child(p)
		_players.append(p)
	for i in 8:
		var f := AudioStreamPlayer.new()
		f.stream = hum
		root.add_child(f)
		_flat.append(f)
	_t0 = Time.get_ticks_msec()
	print("audio_mix_race: guard %s, %d players, %.0f s" % ["on" if AudioMixGuard.enabled else "off", _count, _seconds])


func _process(_delta: float) -> bool:
	_frames += 1
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	_cam.position = Vector3(sin(t * 3.0) * 4.0, 0.0, cos(t * 2.0) * 4.0)
	for i in _players.size():
		var p := _players[i]
		p.position.y = sin(t * 5.0 + i)
		if not p.playing or _frames % 7 == i % 7:
			p.play()
	for i in _flat.size():
		if not _flat[i].playing:
			_flat[i].play()
		_flat[i].volume_db = -6.0 + 3.0 * sin(t * 7.0 + i)
	if t >= _seconds:
		print("audio_mix_race: survived %.0f s, %d frames" % [t, _frames])
		return true
	return false


static func _tone(seconds: float, looped: bool) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(sin(TAU * 220.0 * i / rate) * 8000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	if looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = n
	return s
