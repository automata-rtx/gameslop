class_name AudioMix
extends RefCounted
## Pure mix math for AudioManager (03 §3, §6): slider and duck levels, the Ambience floor
## of rule 3, the static bed curve, heartbeat rate, position-hashed pitch, caption
## direction and distance (04 §8). No nodes, no state: every function is unit-tested.

## Ambience duck floors (03 §6 rule 3), as a state of the room.
enum Floor { NORMAL, STILL, MUTE }


## 12 §4: sliders map to dB with linear_to_db(v / 100) and -80 dB at 0.
static func slider_db(v: float) -> float:
	if v <= 0.0:
		return Tuning.AUDIO_SLIDER_MUTE_DB
	return maxf(linear_to_db(clampf(v, 0.0, 100.0) / 100.0), Tuning.AUDIO_SLIDER_MUTE_DB)


## Sum of the active ducks on `bus`. `ducks` holds dictionaries {bus, db, until};
## an entry whose `until` is at or before `now` has expired.
static func bus_duck_db(ducks: Array, bus: StringName, now: float) -> float:
	var total := 0.0
	for d: Dictionary in ducks:
		if StringName(d.get("bus", &"")) == bus and float(d.get("until", 0.0)) > now:
			total += float(d.get("db", 0.0))
	return total


## The deepest Ambience may be ducked so the room tone (rendered at `room_tone_db`) stays
## at or above -40 dB, or -46 dB during Still's silence, or goes to -inf for a mute
## (Flicker's lunge). Returns a negative dB offset (or 0).
static func ambience_floor_db(room_tone_db: float, room_floor: Floor) -> float:
	match room_floor:
		Floor.MUTE:
			return Tuning.AUDIO_SLIDER_MUTE_DB
		Floor.STILL:
			return minf(0.0, Tuning.AUDIO_STILL_SILENCE_FLOOR_DB - room_tone_db)
		_:
			return minf(0.0, Tuning.AUDIO_ROOM_TONE_FLOOR_DB - room_tone_db)


## The Ambience duck after the rule-3 clamp.
static func clamp_ambience(duck_db: float, room_tone_db: float, room_floor: Floor) -> float:
	return maxf(duck_db, ambience_floor_db(room_tone_db, room_floor))


## 03 §6 rule 2: the most a sound may be played at on the Errors bus so its peak stays at or
## under -6 dBFS before the limiter. `peak_db` is the file's peak (manifest), `distance` the
## emitter's distance to the listener; the attenuation follows AudioStreamPlayer3D's inverse
## model (unit size `unit_size`) capped at the player's `max_db`, and panning is taken at its
## loudest (one channel at full), so the bound holds for any direction. Returns a dB offset
## (may be positive: a quiet or distant sound is never turned up by it, callers take the min).
static func errors_headroom_db(peak_db: float, distance: float, max_db: float = 3.0, unit_size: float = Tuning.AUDIO_UNIT_SIZE) -> float:
	var att := minf(linear_to_db(unit_size / maxf(distance, 0.001)), max_db)
	return Tuning.AUDIO_ERRORS_BUS_MAX_DB - peak_db - att


## Coherence (0..100) to drain (0..1).
static func drain_from_coherence(coherence: float) -> float:
	return clampf(1.0 - coherence / 100.0, 0.0, 1.0)


## 03 §4 static bed: gain lerp(-60 dB, -18 dB, drain^1.5), silent at drain 0.
static func bed_gain_db(drain: float) -> float:
	if drain <= 0.0:
		return -INF
	var d := clampf(drain, 0.0, 1.0)
	return lerpf(Tuning.AUDIO_BED_GAIN_MIN_DB, Tuning.AUDIO_BED_GAIN_MAX_DB, pow(d, 1.5))


static func bed_gain_linear(drain: float) -> float:
	var g := bed_gain_db(drain)
	return 0.0 if is_inf(g) else db_to_linear(g)


## 03 §4 static bed: low-pass cutoff lerp(200, 6000, drain).
static func bed_cutoff_hz(drain: float) -> float:
	return lerpf(Tuning.AUDIO_BED_CUTOFF_MIN_HZ, Tuning.AUDIO_BED_CUTOFF_MAX_HZ, clampf(drain, 0.0, 1.0))


## 03 §4 heartbeat: 60 to 140 bpm by threat; 06 §10: floor 90 bpm below 25 Coherence.
static func heartbeat_bpm(threat: float, coherence: float) -> float:
	var bpm := lerpf(Tuning.AUDIO_HEARTBEAT_MIN_BPM, Tuning.AUDIO_HEARTBEAT_MAX_BPM, clampf(threat, 0.0, 1.0))
	if coherence < Tuning.COHERENCE_DANGER_BELOW:
		bpm = maxf(bpm, Tuning.COHERENCE_HEARTBEAT_FLOOR_BPM)
	return bpm


## Heartbeat strength 0..1: the threat, or full in the danger state. 0 means no heartbeat.
static func heartbeat_level(threat: float, coherence: float) -> float:
	if coherence < Tuning.COHERENCE_DANGER_BELOW:
		return 1.0
	return clampf(threat, 0.0, 1.0)


## 03 §4 power wave: pitch hashed from the emitter's position, +-`spread`. Deterministic.
static func hashed_pitch(pos: Vector3, spread: float) -> float:
	var h := hash(Vector3i(roundi(pos.x * 10.0), roundi(pos.y * 10.0), roundi(pos.z * 10.0)))
	var u := float(posmod(h, 2001)) / 1000.0 - 1.0
	return 1.0 + spread * u


## 04 §8: listener-relative sector, 0 = ahead, clockwise in 8 sectors (Strings.CAPTION_DIRECTIONS).
static func caption_sector(listener: Transform3D, pos: Vector3) -> int:
	var local := listener.affine_inverse() * pos
	if Vector2(local.x, local.z).length_squared() < 1e-6:
		return 0
	var ang := atan2(local.x, -local.z)
	var step := TAU / float(Tuning.CAPTION_SECTORS)
	return posmod(roundi(ang / step), Tuning.CAPTION_SECTORS)


## 04 §8: ", near" under 6 m, nothing from 6 to 20 m, ", far" over 20 m.
static func caption_dist(distance: float) -> String:
	if distance < Tuning.CAPTION_NEAR_DIST:
		return Strings.CAPTION_DIST_NEAR
	if distance > Tuning.CAPTION_FAR_DIST:
		return Strings.CAPTION_DIST_FAR
	return Strings.CAPTION_DIST_MID


## Fills {dir} and {dist} of a 04 §10 caption template for a sound at `pos`.
static func format_caption(template: String, listener: Transform3D, pos: Vector3) -> String:
	var dir: String = Strings.CAPTION_DIRECTIONS[caption_sector(listener, pos)]
	var dist := caption_dist(listener.origin.distance_to(pos))
	return template.replace("{dir}", dir).replace("{dist}", dist)
