class_name AudioPool
extends RefCounted
## AudioManager's one-shot players: 32 AudioStreamPlayer3D (14 §3) and a smaller set of
## non-spatial players. A busy pool steals the player that started longest ago, so the
## count never grows. The 3D pool pauses with the world (hitstop, pause menu); the 2D pool
## runs always, so pulses and UI sounds carry through both (11 §4).

const SIZE_2D := 16
const META_ID := &"audio_id"
const META_STARTED := &"audio_started"

var players_3d: Array[AudioStreamPlayer3D] = []
var players_2d: Array[AudioStreamPlayer] = []


func _init(parent: Node) -> void:
	var root3d := Node.new()
	root3d.name = "Pool3D"
	root3d.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(root3d)
	for i in Tuning.AUDIO_PLAYER_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		setup_3d(p)
		root3d.add_child(p)
		players_3d.append(p)
	var root2d := Node.new()
	root2d.name = "Pool2D"
	root2d.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(root2d)
	for i in SIZE_2D:
		var p := AudioStreamPlayer.new()
		root2d.add_child(p)
		players_2d.append(p)


## 03 §3 attenuation: inverse distance, unit size 1, Doppler off, no distance filter.
static func setup_3d(p: AudioStreamPlayer3D) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = Tuning.AUDIO_UNIT_SIZE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.attenuation_filter_cutoff_hz = AudioOcclusion.OPEN_CUTOFF_HZ


func take_3d() -> AudioStreamPlayer3D:
	return _take(players_3d) as AudioStreamPlayer3D


func take_2d() -> AudioStreamPlayer:
	return _take(players_2d) as AudioStreamPlayer


func active_3d() -> int:
	return players_3d.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing).size()


## Sounds that fire as a burst of overlapping instances and caption once per burst (a power
## wave igniting fixture after fixture is one caption). Every other sound captions each time;
## the HUD caption stack merges an identical line that is still on screen (04 §10).
const BURST_CAPTION_IDS: Array[StringName] = [&"power_wave_ignite"]


## Starts `p` (already given its stream and bus). Returns whether it may caption.
func start(p: Node, id: StringName, volume_db: float, clock: float) -> bool:
	var captioned := not (id in BURST_CAPTION_IDS and is_playing(id, StringName(p.get(&"bus"))))
	p.set_meta(META_ID, id)
	p.set_meta(META_STARTED, clock)
	p.set_meta(AudioLoop.META_BASE, volume_db)
	p.set_meta(AudioLoop.META_FADE, 0.0)
	AudioLoop.refresh_volume(p)
	p.call(&"play")
	return captioned


func is_playing(id: StringName, bus: StringName) -> bool:
	for pool: Array in [players_3d, players_2d]:
		for p: Node in pool:
			if p.get(&"playing") and p.get_meta(META_ID, &"") == id and StringName(p.get(&"bus")) == bus:
				return true
	return false


## A free player, or the one that started longest ago (voice steal).
func _take(pool: Array) -> Node:
	var oldest: Node = null
	for p: Node in pool:
		if not p.get(&"playing"):
			return p
		if oldest == null or float(p.get_meta(META_STARTED, 0.0)) < float(oldest.get_meta(META_STARTED, 0.0)):
			oldest = p
	oldest.call(&"stop")
	return oldest
