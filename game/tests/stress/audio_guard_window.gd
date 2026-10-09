extends SceneTree
## M3.3 / RCA1: measures AudioMixGuard's FRAME_TAIL lock in a windowed process (a real
## renderer, and on a player's machine a real audio driver). Plays positional sounds that
## update their bus volumes every frame, a small lit scene so each frame draws, and prints
## the guard's mode, holds, longest hold and longest lock wait. Not part of the gate.
##   tools/ci/render.sh --path game --script tests/stress/audio_guard_window.gd -- [--seconds 20] [--cap 60]
##   godot --path game --script tests/stress/audio_guard_window.gd     (real driver, real GPU)
## Exit 0 when the guard engaged (or stayed off under --cap) and never tripped; 1 otherwise.

var _seconds: float = 20.0
var _cap: int = 0
var _players: Array[AudioStreamPlayer3D] = []
var _cam: Camera3D
var _t0: int = 0
var _frames: int = 0
var _guard: AudioMixGuard
var _tail_from: int = 0
var _tails: Array[int] = []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--seconds" and i + 1 < a.size():
			_seconds = a[i + 1].to_float()
		elif a[i] == "--cap" and i + 1 < a.size():
			_cap = a[i + 1].to_int()
	DisplayServer.window_set_size(Vector2i(640, 360))
	var world := Node3D.new()
	root.add_child(world)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.make_current()
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2, 0)
	world.add_child(light)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0, 0, -3)
	world.add_child(box)
	var hum := _tone(0.5)
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.stream = hum
		p.position = Vector3(i % 8 - 4, 0.0, -2.0 - i / 8)
		world.add_child(p)
		_players.append(p)
	# The same tail the guard holds, timed independently of it (frame_post_draw to the
	# next frame signal), so a tripped guard still reports what the tail costs.
	RenderingServer.frame_post_draw.connect(func() -> void: _tail_from = Time.get_ticks_usec())
	physics_frame.connect(_tail_end)
	process_frame.connect(_tail_end)


func _tail_end() -> void:
	if _tail_from > 0:
		_tails.append(Time.get_ticks_usec() - _tail_from)
		_tail_from = 0


func _process(_delta: float) -> bool:
	if _t0 == 0:
		_t0 = Time.get_ticks_msec()  # after the first frame's shader compiles
		Engine.max_fps = _cap         # after SettingsManager applied the saved cap
		_tails.clear()
	_frames += 1
	if _guard == null:
		_guard = root.get_node_or_null(^"AudioManager/AudioMixGuard") as AudioMixGuard
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	_cam.position = Vector3(sin(t * 2.0) * 2.0, 0.0, cos(t * 1.5))
	for p in _players:
		if not p.playing:
			p.play()
	if t < _seconds:
		return false
	var g := _guard
	if g == null:
		print("audio_guard_window: no AudioMixGuard under AudioManager")
		quit(1)
		return true
	var hold_ms := g.max_hold_usec / 1000.0
	var wait_ms := g.max_wait_usec / 1000.0
	print("audio_guard_window: display %s, audio %s, mode %s, cap %d, %d frames in %.1f s, %d holds, max hold %.3f ms, max wait %.3f ms, strikes %d, tripped %s" % [
		DisplayServer.get_name(), AudioServer.get_driver_name() if AudioServer.has_method(&"get_driver_name") else "?",
		AudioMixGuard.Mode.keys()[g.mode], _cap, _frames, t, g.locks, hold_ms, wait_ms, g.strikes, g.tripped])
	_tails.sort()
	if not _tails.is_empty():
		print("audio_guard_window: tail p50 %.3f ms, p95 %.3f ms, max %.3f ms over %d frames" % [
			_tails[_tails.size() / 2] / 1000.0, _tails[_tails.size() * 95 / 100] / 1000.0, _tails[-1] / 1000.0, _tails.size()])
	var ok := not g.tripped and (g.locks == 0 if _cap > 0 else g.locks >= _frames - 2)
	quit(0 if ok else 1)
	return true


static func _tone(seconds: float) -> AudioStreamWAV:
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
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s
