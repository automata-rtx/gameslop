class_name CoherencePost
extends RefCounted
## Pure math of the Coherence post stack (02 §4) and its transient pulses (02 §4, 11).
## CoherenceRenderer feeds it the state and writes the result to coherence_post.gdshader.
## Nothing here touches nodes, so every curve is unit-tested.

## Result keys, one per post shader uniform.
const KEYS: Array[StringName] = [&"ca", &"sat", &"warmth", &"grain", &"vig", &"scan", &"invert", &"flash",
		&"black", &"ripple"]

## Frames a hit inversion or a white flash lasts (02 §4, 11 §3, 12 §6).
const FLASH_FRAMES := Tuning.POST_PULSE_HIT_INVERT_FRAMES


## 1 - coherence01, the input of every curve.
static func drain_of(coherence01: float) -> float:
	return clampf(1.0 - coherence01, 0.0, 1.0)


## 02 §4 step 1: ca = lerp(0, 0.012, smoothstep(0.1, 1.0, drain)).
static func base_ca(drain: float) -> float:
	return lerpf(0.0, Tuning.POST_CA_MAX, smoothstep(Tuning.POST_DRAIN_SMOOTH_MIN, Tuning.POST_DRAIN_SMOOTH_MAX, drain))


## 02 §4 step 2: sat = lerp(1.0, 0.08, smoothstep(0.3, 1.0, drain)).
static func base_saturation(drain: float) -> float:
	return lerpf(1.0, Tuning.POST_SAT_MIN, smoothstep(Tuning.POST_SAT_SMOOTH_MIN, Tuning.POST_SAT_SMOOTH_MAX, drain))


## 02 §4 step 3: grain = lerp(0.02, 0.18, drain); never below the minimum.
static func base_grain(drain: float) -> float:
	return lerpf(Tuning.POST_GRAIN_MIN, Tuning.POST_GRAIN_MAX, drain)


## 02 §4 step 4: lerp(0.15, 0.45, drain) plus up to 0.3 from threat, pulsing with the
## heartbeat. `beat_phase` is CoherenceRenderer's accumulated heartbeat phase (0..1, 0 on
## the beat), so a rate change never jumps the pulse.
static func vignette(drain: float, threat: float, beat_phase: float) -> float:
	var beat := 0.5 + 0.5 * cos(TAU * beat_phase)
	var threat_vig := Tuning.POST_THREAT_VIGNETTE_MAX * threat * lerpf(0.6, 1.0, beat)
	return lerpf(Tuning.POST_VIGNETTE_MIN, Tuning.POST_VIGNETTE_MAX, drain) + threat_vig


## 02 §4 step 5: tied to drain^2 and to the noclip charge; invisible at full Coherence.
static func base_scan(drain: float, noclip_charge: float) -> float:
	return clampf(maxf(drain * drain, noclip_charge), 0.0, 1.0)


## A TRANS_EXPO / EASE_OUT fall from 1 to 0 over `duration_s` (11 §1). 0 when never fired.
static func expo_decay(age_s: float, duration_s: float) -> float:
	if age_s < 0.0 or age_s >= duration_s or duration_s <= 0.0:
		return 0.0
	return pow(2.0, -10.0 * age_s / duration_s)


## 06 §8, 11 §2, 02 §4: held at 1.0 through the 80 ms hitstop and the 250 ms pass, then
## decays over 300 ms. Drives both g_noclip_commit and the post's commit pulse.
static func commit_envelope(age_s: float) -> float:
	var hold := (Tuning.NOCLIP_COMMIT_HITSTOP_MS + Tuning.NOCLIP_PASS_TIME_MS) / 1000.0
	if age_s < 0.0:
		return 0.0
	if age_s < hold:
		return 1.0
	return expo_decay(age_s - hold, Tuning.POST_PULSE_NOCLIP_DECAY_MS / 1000.0)


## 0 -> 1 over the 1.5 s dissolve, then stays (until the run resets the pulses).
static func dissolve_progress(age_s: float) -> float:
	if age_s < 0.0 or is_inf(age_s):
		return 0.0
	return clampf(age_s / Tuning.POST_PULSE_DISSOLVE_TIME, 0.0, 1.0)


## Landing ripple progress 0..1 over its duration; -1 when idle (11 §3).
static func ripple_progress(age_s: float) -> float:
	var dur := Tuning.POST_PULSE_RIPPLE_MS / 1000.0
	if age_s < 0.0 or age_s >= dur:
		return -1.0
	return age_s / dur


## The drop's black (11 §2, §3). `fall_age_s`: since the floor commit (INF when none);
## `arrive_age_s`: since the drop arrival (INF when none). 1.2 s to black with grain, held
## black until the arrival, then black to the world over 400 ms. The fade never starts
## before the fall has run its 1.2 s; an arrival without a fall just fades in.
static func drop_black(fall_age_s: float, arrive_age_s: float) -> float:
	var fall := Tuning.NOCLIP_FLOOR_FALL_TIME
	var fade := Tuning.DROP_ARRIVAL_FADE_MS / 1000.0
	var falling := fall_age_s >= 0.0 and not is_inf(fall_age_s)
	var arrived := arrive_age_s >= 0.0 and not is_inf(arrive_age_s)
	if not arrived:
		if not falling:
			return 0.0
		return clampf(fall_age_s / fall, 0.0, 1.0) if fall > 0.0 else 1.0
	var since := arrive_age_s
	if falling:
		since = minf(arrive_age_s, fall_age_s - fall)
	if since < 0.0:
		return clampf(fall_age_s / fall, 0.0, 1.0) if falling else 1.0
	return clampf(1.0 - since / fade, 0.0, 1.0)


## A 2-frame flash, or with reduce_flashing a 200 ms soft fade to 60% white (12 §6).
static func flash_amount(frames_since: int, age_s: float, reduce_flashing: bool) -> float:
	if frames_since < 0:
		return 0.0
	if reduce_flashing:
		var fade := Tuning.SETTINGS_REDUCE_FLASHING_FADE_MS / 1000.0
		if age_s >= fade:
			return 0.0
		return Tuning.LIGHT_FLICKER_REDUCED_WHITE * (1.0 - age_s / fade)
	return 1.0 if frames_since < FLASH_FRAMES else 0.0


## The full uniform set. `ages` maps pulse kind -> seconds since it fired (INF or < 0 when
## never), plus `drop_arrival`; `frames` maps kind -> process frames since it fired (-1 when
## never). `beat_phase`: the heartbeat phase. `static_amount`: 0..1 inside Static's field.
static func compute(coherence01: float, noclip_charge: float, threat: float, ages: Dictionary,
		frames: Dictionary, beat_phase: float, reduce_noise: bool, reduce_flashing: bool,
		static_amount: float = 0.0) -> Dictionary:
	var drain := drain_of(coherence01)
	var hit_age: float = ages.get(&"hit", INF)
	var hit := expo_decay(hit_age, Tuning.POST_PULSE_HIT_DECAY_MS / 1000.0)
	var commit := commit_envelope(ages.get(&"noclip_commit", INF))
	var gain := expo_decay(ages.get(&"coherence_gain", INF), Tuning.POST_PULSE_GAIN_MS / 1000.0)
	var dissolve := dissolve_progress(ages.get(&"dissolve", INF))

	var ca := base_ca(drain) + Tuning.POST_PULSE_HIT_CA * hit + Tuning.POST_PULSE_NOCLIP_CA * commit
	var sat := base_saturation(drain) * lerpf(1.0, Tuning.POST_PULSE_GAIN_SATURATION, gain)
	sat = lerpf(sat, 0.0, dissolve)
	# 11 §2-§3: the commit and the contact both spike the grain; the spike is the
	# full-drain grain level so no new number is introduced.
	var grain := base_grain(drain) + Tuning.POST_GRAIN_MAX * maxf(hit, commit)
	grain = lerpf(grain, 1.0, dissolve)
	var scan := maxf(base_scan(drain, noclip_charge), Tuning.POST_PULSE_NOCLIP_SCANLINE * commit)
	# 02 §8, 11 §3: inside Static, grain to 0.6 and CA to 0.02 (never lower than without it).
	var st := clampf(static_amount, 0.0, 1.0)
	grain = lerpf(grain, maxf(grain, Tuning.POST_STATIC_GRAIN), st)
	ca = lerpf(ca, maxf(ca, Tuning.POST_STATIC_CA), st)
	# 11 §2-§3 drop: black with grain (the grain spike level, as for the commit).
	var black := drop_black(ages.get(&"drop", INF), ages.get(&"drop_arrival", INF))
	grain = maxf(grain, (Tuning.POST_GRAIN_MIN + Tuning.POST_GRAIN_MAX) * black)
	var ripple := ripple_progress(ages.get(&"ripple", INF))

	var invert := 0.0
	var flash := 0.0
	var hit_frames: int = frames.get(&"hit", -1)
	if reduce_flashing:
		# 12 §6: the contact inversion becomes the soft fade too.
		flash = maxf(flash_amount(hit_frames, hit_age, true), 0.0)
	elif hit_frames >= 0 and hit_frames < FLASH_FRAMES:
		invert = 1.0
	flash = maxf(flash, flash_amount(frames.get(&"flash", -1), ages.get(&"flash", INF), reduce_flashing))

	if reduce_noise:
		# 02 §4 accessibility: caps grain and CA, no scanline. Desaturation and vignette stay.
		grain = minf(grain, Tuning.POST_REDUCED_GRAIN_CAP)
		ca = minf(ca, Tuning.POST_REDUCED_CA_CAP)
		scan = 0.0
	return {
		&"ca": ca, &"sat": sat, &"warmth": Tuning.POST_PULSE_GAIN_WARMTH * gain, &"grain": grain,
		&"vig": vignette(drain, threat, beat_phase), &"scan": scan, &"invert": invert, &"flash": flash,
		&"black": black, &"ripple": ripple,
	}
