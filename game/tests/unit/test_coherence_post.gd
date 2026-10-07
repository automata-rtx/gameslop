extends TestCase
## The Coherence post stack's curves and pulse timing (02 §4, 06 §8, 11, 12 §6). Pure.

const NEVER := {}


func _compute(c01: float, ages: Dictionary = {}, frames: Dictionary = {}, charge: float = 0.0,
		threat: float = 0.0, reduce_noise: bool = false, reduce_flashing: bool = false) -> Dictionary:
	return CoherencePost.compute(c01, charge, threat, ages, frames, 0.0, reduce_noise, reduce_flashing)


func test_full_coherence_is_clean_but_never_grainless() -> void:
	var p := _compute(1.0)
	for key in CoherencePost.KEYS:
		assert_true(p.has(key), "key %s" % key)
	assert_approx(p[&"ca"], 0.0)
	assert_approx(p[&"sat"], 1.0)
	assert_approx(p[&"grain"], 0.02, 0.0001, "02 §4: grain is always present")
	assert_approx(p[&"scan"], 0.0, 0.0001, "scanline invisible at 100")
	assert_approx(p[&"invert"], 0.0)
	assert_approx(p[&"flash"], 0.0)


func test_curves_follow_02() -> void:
	# ca = lerp(0, 0.012, smoothstep(0.1, 1, drain))
	assert_approx(CoherencePost.base_ca(0.1), 0.0)
	assert_approx(CoherencePost.base_ca(1.0), 0.012)
	assert_approx(CoherencePost.base_ca(0.55), 0.012 * 0.5, 0.0001)
	# sat = lerp(1, 0.08, smoothstep(0.3, 1, drain)): untouched above 70, near mono below 30.
	assert_approx(CoherencePost.base_saturation(0.3), 1.0)
	assert_approx(CoherencePost.base_saturation(1.0), 0.08)
	assert_lt(CoherencePost.base_saturation(0.85), 0.25, "low Coherence is nearly monochrome")
	assert_approx(CoherencePost.base_grain(0.5), 0.10, 0.0001)
	assert_approx(CoherencePost.base_grain(1.0), 0.18)
	assert_approx(CoherencePost.vignette(0.0, 0.0, 0.0), 0.15)
	assert_approx(CoherencePost.vignette(1.0, 0.0, 0.0), 0.45)
	assert_approx(CoherencePost.vignette(0.0, 1.0, 0.0), 0.15 + 0.3, 0.0001, "threat vignette max 0.3 at the beat")
	assert_approx(CoherencePost.base_scan(0.5, 0.0), 0.25, 0.0001, "drain^2")
	assert_approx(CoherencePost.base_scan(0.0, 0.8), 0.8, 0.0001, "noclip charge")


func test_t4_frames_are_strictly_ordered() -> void:
	# T4: 100, 60, 30, 10 must be orderable: every channel moves monotonically.
	var prev := _compute(1.0)
	for c in [0.6, 0.3, 0.1]:
		var p := _compute(c)
		assert_gt(p[&"grain"], prev[&"grain"], "grain rises at %s" % c)
		assert_gt(p[&"ca"], prev[&"ca"], "ca rises at %s" % c)
		assert_lt(p[&"sat"], prev[&"sat"], "saturation falls at %s" % c)
		assert_gt(p[&"vig"], prev[&"vig"], "vignette rises at %s" % c)
		prev = p


func test_expo_decay_shape() -> void:
	assert_approx(CoherencePost.expo_decay(0.0, 0.4), 1.0)
	assert_approx(CoherencePost.expo_decay(INF, 0.4), 0.0, 0.0, "never fired")
	assert_approx(CoherencePost.expo_decay(-1.0, 0.4), 0.0)
	assert_approx(CoherencePost.expo_decay(0.4, 0.4), 0.0, 0.0, "gone at the duration")
	assert_lt(CoherencePost.expo_decay(0.2, 0.4), 0.05, "EASE_OUT expo: most of the fall is early")
	assert_gt(CoherencePost.expo_decay(0.01, 0.4), 0.8)


func test_noclip_commit_holds_through_the_pass_then_decays() -> void:
	# 06 §8: g_noclip_commit is 1.0 for the 250 ms pass; 02 §4: then decays over 300 ms.
	assert_approx(CoherencePost.commit_envelope(0.0), 1.0)
	assert_approx(CoherencePost.commit_envelope(0.249), 1.0)
	assert_lt(CoherencePost.commit_envelope(0.30), 1.0)
	assert_gt(CoherencePost.commit_envelope(0.26), 0.5)
	assert_approx(CoherencePost.commit_envelope(0.55), 0.0, 0.0, "fully decayed 300 ms after the pass")
	assert_approx(CoherencePost.commit_envelope(INF), 0.0)
	var p := _compute(1.0, {&"noclip_commit": 0.1})
	assert_approx(p[&"ca"], 0.05, 0.0001, "commit pulse CA 0.05")
	assert_approx(p[&"scan"], 1.0, 0.0001, "commit pulse scanline 1.0")
	assert_gt(p[&"grain"], 0.18, "grain spike on commit (11 §2)")


func test_hit_pulse() -> void:
	var p := _compute(1.0, {&"hit": 0.0}, {&"hit": 0})
	assert_approx(p[&"ca"], 0.03, 0.0001, "hit CA 0.03")
	assert_approx(p[&"invert"], 1.0, 0.0, "inverted-luminance flash")
	p = _compute(1.0, {&"hit": 0.03}, {&"hit": 2})
	assert_approx(p[&"invert"], 0.0, 0.0, "inversion lasts 2 frames")
	p = _compute(1.0, {&"hit": 0.4}, {&"hit": 24})
	assert_approx(p[&"ca"], 0.0, 0.0001, "decayed after 400 ms")


func test_coherence_gain_overshoots_saturation() -> void:
	var p := _compute(1.0, {&"coherence_gain": 0.0})
	assert_approx(p[&"sat"], 1.15, 0.0001)
	assert_approx(p[&"warmth"], 0.05, 0.0001)
	p = _compute(1.0, {&"coherence_gain": 0.6})
	assert_approx(p[&"sat"], 1.0, 0.0001, "over after 600 ms")


func test_dissolve_progresses_and_stays() -> void:
	var half := _compute(0.5, {&"dissolve": 0.75})
	var done := _compute(0.5, {&"dissolve": 1.5})
	var later := _compute(0.5, {&"dissolve": 5.0})
	assert_lt(half[&"sat"], CoherencePost.base_saturation(0.5))
	assert_approx(done[&"sat"], 0.0)
	assert_approx(done[&"grain"], 1.0, 0.0001, "grain to 1.0")
	assert_approx(later[&"grain"], 1.0, 0.0001, "the dissolve holds until reset")


func test_flash_two_frames_or_reduced_fade() -> void:
	assert_approx(_compute(1.0, {&"flash": 0.0}, {&"flash": 0})[&"flash"], 1.0)
	assert_approx(_compute(1.0, {&"flash": 0.02}, {&"flash": 1})[&"flash"], 1.0)
	assert_approx(_compute(1.0, {&"flash": 0.04}, {&"flash": 2})[&"flash"], 0.0)
	# 12 §6 reduce flashing: 200 ms soft fade to 60% white instead; the hit inversion too.
	var r := _compute(1.0, {&"flash": 0.0}, {&"flash": 0}, 0.0, 0.0, false, true)
	assert_approx(r[&"flash"], 0.6, 0.0001)
	r = _compute(1.0, {&"flash": 0.1}, {&"flash": 6}, 0.0, 0.0, false, true)
	assert_approx(r[&"flash"], 0.3, 0.0001)
	r = _compute(1.0, {&"hit": 0.0}, {&"hit": 0}, 0.0, 0.0, false, true)
	assert_approx(r[&"invert"], 0.0, 0.0, "no inversion with reduce flashing")
	assert_approx(r[&"flash"], 0.6, 0.0001)


func test_reduce_visual_noise_caps() -> void:
	var p := _compute(0.05, {&"noclip_commit": 0.0}, {}, 0.5, 0.0, true)
	assert_approx(p[&"grain"], 0.06, 0.0001, "grain cap")
	assert_approx(p[&"ca"], 0.004, 0.0001, "CA cap")
	assert_approx(p[&"scan"], 0.0, 0.0, "no scanline shimmer")
	assert_approx(p[&"sat"], CoherencePost.base_saturation(0.95), 0.0001, "desaturation preserved")
	assert_approx(p[&"vig"], CoherencePost.vignette(0.95, 0.0, 0.0), 0.0001, "vignette preserved")
