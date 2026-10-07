extends TestCase
## M1.11a: the Coherence static bed (03 §2, §4) follows the Coherence it is fed: silent at
## 100, louder and brighter as Coherence falls, held at 0.6 drain inside Static.

const BLOCK := 4800


func _rms(buf: PackedVector2Array) -> float:
	var acc := 0.0
	for v in buf:
		acc += v.x * v.x + v.y * v.y
	return sqrt(acc / maxf(1.0, 2.0 * buf.size()))


## Settles the per-block gain ramp, then measures a block.
func _level(bed: GeneratorLayers) -> float:
	bed.render(BLOCK)
	return _rms(bed.render(BLOCK))


func test_bed_curve_matches_03() -> void:
	assert_eq(AudioMix.bed_gain_linear(0.0), 0.0, "silent at 100 Coherence")
	assert_approx(AudioMix.bed_gain_db(1.0), -18.0)
	assert_approx(AudioMix.bed_gain_db(0.5), lerpf(-60.0, -18.0, pow(0.5, 1.5)))
	assert_approx(AudioMix.bed_cutoff_hz(0.0), 200.0)
	assert_approx(AudioMix.bed_cutoff_hz(1.0), 6000.0)
	assert_approx(AudioMix.drain_from_coherence(25.0), 0.75)


func test_bed_amplitude_follows_coherence() -> void:
	var bed := GeneratorLayers.new()
	add_child(bed)
	bed.set_coherence(100.0)
	assert_eq(_level(bed), 0.0, "silent at 100")
	bed.set_coherence(70.0)
	var r70 := _level(bed)
	bed.set_coherence(40.0)
	var r40 := _level(bed)
	bed.set_coherence(10.0)
	var r10 := _level(bed)
	assert_gt(r70, 0.0)
	assert_gt(r40, r70 * 2.0, "louder as Coherence falls")
	assert_gt(r10, r40 * 2.0)
	assert_approx(bed.current_gain(), AudioMix.bed_gain_linear(0.9), 1e-6, "gain reached its target")
	bed.set_coherence(100.0)
	assert_eq(_level(bed), 0.0, "back to silence")
	bed.queue_free()


func test_static_holds_the_bed_at_0_6() -> void:
	var bed := GeneratorLayers.new()
	add_child(bed)
	bed.set_coherence(100.0)
	bed.set_static_inside(true)
	assert_approx(bed.drain(), Tuning.STATIC_FORCED_BED)
	assert_gt(_level(bed), 0.0, "audible inside Static at full Coherence")
	bed.set_coherence(10.0)
	assert_approx(bed.drain(), 0.9, 0.0001, "a floor, not a cap")
	bed.set_static_inside(false)
	bed.set_coherence(100.0)
	assert_approx(bed.drain(), 0.0)
	bed.queue_free()


func test_audio_manager_feeds_its_bed() -> void:
	AudioManager.set_coherence(30.0)
	assert_approx(AudioManager.bed.drain(), 0.7)
	assert_eq(AudioManager.bed.get_node("StaticBed").bus, &"Player")
	await await_frames(2)
	assert_true(AudioManager.bed.is_running(), "the generator runs while the bed is audible")
	AudioManager.set_coherence(100.0)
	assert_approx(AudioManager.bed.drain(), 0.0)
	await await_frames(3)
	assert_false(AudioManager.bed.is_running(), "and stops at full Coherence")
