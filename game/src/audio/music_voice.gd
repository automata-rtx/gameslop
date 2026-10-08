class_name MusicVoice
extends RefCounted
## One voice of the MusicDirector drone (03 §5): a pitch, the pad stem it plays (pitched
## from the nearest of A1/A2/A3), its gain, and two Music-bus players that crossfade the
## stem's three 12 s variations every 10 s over 2 s so the drone never loops audibly.

const ROLE_CHORD := &"chord"
const ROLE_FOURTH := &"fourth"
const ROLE_FIFTH := &"fifth"
const NOTE_INDEX: Dictionary = {
	"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
	"G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
}
const FLOOR_GAIN := 0.0001

var hz: float
var role: StringName
var db: float
var pitch: float = 1.0
var gain: float = 0.0
var target: float = 0.0
var streams: Array = []
var players: Array[AudioStreamPlayer] = []
var cur: int = 0
var variation: int = 0
var xfade: float = 1.0           # 0..1 progress of the crossfade into players[cur]
var swap_left: float = 0.0


## "A2", "Bb1", "C#4" -> Hz (A4 = 440).
static func note_hz(note: String) -> float:
	var octave := int(note.right(1))
	var name := note.left(note.length() - 1)
	var midi := 12 * (octave + 1) + int(NOTE_INDEX.get(name, 9))
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## The stem nearest `p_hz` (in octaves) from {id: {hz}}, or &"".
static func nearest_stem(p_hz: float, stems: Dictionary) -> StringName:
	var best := &""
	var best_d := INF
	for id: StringName in stems:
		var s_hz := float(stems[id][&"hz"])
		if s_hz <= 0.0:
			continue
		var d := absf(log(p_hz / s_hz) / log(2.0))
		if d < best_d:
			best_d = d
			best = id
	return best


## A voice at `p_hz` playing the nearest stem of `stems`, its players under `parent`.
static func create(parent: Node, p_hz: float, p_role: StringName, p_db: float, stems: Dictionary) -> MusicVoice:
	var v := MusicVoice.new()
	v.hz = p_hz
	v.role = p_role
	v.db = p_db
	var stem := nearest_stem(p_hz, stems)
	if stem != &"":
		v.streams = stems[stem][&"streams"]
		v.pitch = p_hz / float(stems[stem][&"hz"])
		for k in 2:
			var p := AudioStreamPlayer.new()
			p.bus = &"Music"
			p.pitch_scale = v.pitch
			parent.add_child(p)
			v.players.append(p)
	return v


func is_playing() -> bool:
	return players.any(func(p: AudioStreamPlayer) -> bool: return p.playing)


func free_players() -> void:
	for p in players:
		p.stop()
		p.queue_free()
	players.clear()


## Starts, crossfades and levels the players; `trem` scales the gain (title tremolo).
func drive(delta: float, rng: RandomNumberGenerator, trem: float) -> void:
	if players.is_empty():
		return
	if gain <= 0.0 and target <= 0.0:
		for p in players:
			if p.playing:
				p.stop()
		return
	if not players[cur].playing:
		players[cur].stream = streams[variation]
		players[cur].play()
		xfade = 1.0
		swap_left = Tuning.MUSIC_PAD_LOOP_TIME - Tuning.MUSIC_PAD_CROSSFADE
	swap_left -= delta
	if swap_left <= 0.0 and streams.size() > 1:
		variation = (variation + 1 + rng.randi_range(0, streams.size() - 2)) % streams.size()
		cur = 1 - cur
		players[cur].stream = streams[variation]
		players[cur].play()
		xfade = 0.0
		swap_left = Tuning.MUSIC_PAD_LOOP_TIME - Tuning.MUSIC_PAD_CROSSFADE
	xfade = minf(1.0, xfade + delta / Tuning.MUSIC_PAD_CROSSFADE)
	var old := players[1 - cur]
	if xfade >= 1.0 and old.playing:
		old.stop()
	var g := gain * trem
	players[cur].volume_db = linear_to_db(maxf(g * sqrt(xfade), FLOOR_GAIN)) + db
	old.volume_db = linear_to_db(maxf(g * sqrt(1.0 - xfade), FLOOR_GAIN)) + db
