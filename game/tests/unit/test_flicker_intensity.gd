extends TestCase
## 12 §6 Flicker intensity (R16, M2.17 review S2): below 1.0 Flicker's stutter blends toward
## a 2 Hz sine pulse. The shared stutter gate (Fixture.stutter_step, used by the group's
## fixtures and the attached beam) is stepped by hand at 0.3, 0.65 and 1.0, and its cycle
## rate and depth are measured: 2 Hz at depth 0.3, interpolated at 0.65, the unchanged 8 to
## 20 Hz on/off stutter at full depth at 1.0.

const DT := 1.0 / 240.0
const SECONDS := 20.0

var _saved: Variant


func before_each() -> void:
	_saved = SettingsManager.get_value(&"flicker_intensity")


func after_each() -> void:
	SettingsManager.set_value(&"flicker_intensity", _saved)


## Steps a fresh gate for SECONDS at toggle rate `hz`; returns {cycles_hz, min, max, step}
## (step: the largest change between two samples).
func _measure(setting: float, hz: float, seed_value: int = 3) -> Dictionary:
	SettingsManager.set_value(&"flicker_intensity", setting)
	var rng := make_rng(seed_value)
	var state := Fixture.new_stutter_state()
	var lo := INF
	var hi := -INF
	var step := 0.0
	var offs := 0
	var was_on := true
	var last := 1.0
	for i in int(SECONDS / DT):
		var m := Fixture.stutter_step(state, hz, DT, rng)
		lo = minf(lo, m)
		hi = maxf(hi, m)
		if i > 0:
			step = maxf(step, absf(m - last))
		last = m
		var on := bool(state[0])
		if was_on and not on:
			offs += 1
		was_on = on
	return {&"cycles_hz": offs / SECONDS, &"min": lo, &"max": hi, &"step": step}


func test_rate_and_depth_formulas() -> void:
	for hz: float in [Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ]:
		assert_approx(Fixture.stutter_cycle_hz(0.3, hz), Tuning.SETTINGS_FLICKER_REDUCED_PULSE_HZ, 0.0001, "0.3: the 2 Hz pulse whatever the charge")
		assert_approx(Fixture.stutter_cycle_hz(1.0, hz), hz * 0.5, 0.0001, "1.0: the stutter's own on/off cycle")
		assert_approx(Fixture.stutter_cycle_hz(0.65, hz), lerpf(Tuning.SETTINGS_FLICKER_REDUCED_PULSE_HZ, hz * 0.5, 0.5), 0.0001, "0.65: halfway")
	assert_approx(Fixture.stutter_blend(0.3), 0.0, 0.0001)
	assert_approx(Fixture.stutter_blend(0.65), 0.5, 0.0001)
	assert_approx(Fixture.stutter_blend(1.0), 1.0, 0.0001)
	for v: float in [0.3, 0.65, 1.0]:
		SettingsManager.set_value(&"flicker_intensity", v)
		assert_approx(Fixture.flicker_depth(), v, 0.0001, "depth = the setting")
	assert_approx(Fixture.pulse_shape(0.25, 0.0), 0.5, 0.0001, "a sine at 0.3")
	assert_approx(Fixture.pulse_shape(0.5, 0.0), 1.0, 0.0001, "deepest mid-cycle")
	assert_approx(Fixture.pulse_shape(0.25, 1.0), 0.0, 0.0001, "a square at 1.0")


func test_at_0_3_a_2_hz_pulse_with_depth_0_3() -> void:
	for hz: float in [Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ]:
		var r := _measure(0.3, hz)
		assert_approx(float(r[&"cycles_hz"]), Tuning.SETTINGS_FLICKER_REDUCED_PULSE_HZ, 0.06, "2 Hz at %d Hz charge" % hz)
		assert_approx(float(r[&"min"]), 0.7, 0.002, "never below 70%: depth 0.3")
		assert_approx(float(r[&"max"]), 1.0, 0.002)
		assert_lt(float(r[&"step"]), 0.02, "a smooth pulse, no on/off steps")


func test_at_0_65_rate_and_depth_halfway() -> void:
	var hz := Tuning.FLICKER_STUTTER_MIN_HZ
	var base := Fixture.stutter_cycle_hz(0.65, hz)
	assert_approx(base, 3.0, 0.0001)
	var r := _measure(0.65, hz)
	var spread := lerpf(1.0, Tuning.LIGHT_FLICKER_RATE_SPREAD, 0.5)
	assert_gt(float(r[&"cycles_hz"]), base - 0.06, "at least the blended rate")
	assert_lt(float(r[&"cycles_hz"]), base * spread + 0.06, "within half the stutter's random spread")
	assert_approx(float(r[&"min"]), 0.35, 0.002, "depth 0.65")
	assert_approx(float(r[&"max"]), 1.0, 0.002)


func test_at_1_0_the_full_stutter_is_unchanged() -> void:
	for hz: float in [Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ]:
		var r := _measure(1.0, hz)
		var top := minf(hz * Tuning.LIGHT_FLICKER_RATE_SPREAD, Tuning.FLICKER_STUTTER_MAX_HZ)
		# 1 / random(hz, 1.5 hz) s per toggle (each rounded up to a step): two toggles a cycle.
		assert_gt(float(r[&"cycles_hz"]), 0.5 / (1.0 / hz + DT) - 0.1, "%d Hz toggles" % hz)
		assert_lt(float(r[&"cycles_hz"]), top * 0.5 + 0.1)
		assert_approx(float(r[&"min"]), 0.0, 0.0001, "fully dark off instants")
		assert_approx(float(r[&"max"]), 1.0, 0.0001)
		assert_approx(float(r[&"step"]), 1.0, 0.0001, "hard on/off")


func test_slower_below_1_0_everywhere() -> void:
	# The photosensitive point: lowering the option never speeds the stutter up.
	var hz := Tuning.FLICKER_STUTTER_MAX_HZ
	var prev := INF
	for v: float in [1.0, 0.9, 0.8, 0.65, 0.5, 0.4, 0.3]:
		var c := Fixture.stutter_cycle_hz(v, hz)
		assert_lt(c, prev + 0.0001, "%.2f" % v)
		prev = c
