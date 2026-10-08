class_name FlickerPresent
extends RefCounted
## Flicker's presentation (02 §8, 03 Errors, 11 §3): the spark burst when it jumps (1 cm
## white sparks, 0.3 s, GPUParticles3D), the flash noise and the 1.5 s total silence of a
## lunge, and the attached beam's stutter and flash. The group stutter itself is the
## fixtures' (Fixture.set_flicker, rate by LightPool.set_group_flicker_rate) and its sound
## is the fixture hum gated by the LightPool. Sounds play only when the sample exists (03:
## `flicker_spark`, `flicker_flash`; the audio recipes own them).

const SPARK_SOUND := &"flicker_spark"
const FLASH_SOUND := &"flicker_flash"
const BUS := &"Errors"

static var _spark_mesh: QuadMesh
static var _spark_material: ParticleProcessMaterial


## A spark burst at `pos` (world), parented to `owner` as a top-level node.
static func spark(owner: Node3D, pos: Vector3) -> void:
	if owner == null or not owner.is_inside_tree() or pos == Vector3.INF:
		return
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.top_level = true
	p.one_shot = true
	p.amount = Tuning.FLICKER_SPARK_COUNT
	p.lifetime = Tuning.FLICKER_SPARK_LIFETIME
	p.explosiveness = 1.0
	p.local_coords = false
	p.draw_pass_1 = _mesh()
	p.process_material = _material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	play(SPARK_SOUND, pos)


static func play(id: StringName, pos: Vector3) -> void:
	if AudioManager.has_sound(id):
		AudioManager.play_3d(id, pos, BUS)


## 03 §6 rule 3: room tone -inf for the 1.5 s lunge dark (after the 100 ms flash noise).
static func silence() -> void:
	AudioManager.silence(Tuning.FLICKER_SILENCE_BUS, Tuning.FLICKER_DARK_TIME)


## Attached (08 §5): the beam stutters at `hz` (an on/off gate stepped by `rng`, a
## presentation rng). `state` holds [on, seconds to the next toggle].
static func beam_stutter(f: Flashlight, state: Array, hz: float, delta: float, rng: RandomNumberGenerator) -> void:
	if f == null:
		return
	state[1] = float(state[1]) - delta
	if float(state[1]) <= 0.0:
		state[0] = not bool(state[0])
		var lo := clampf(hz, Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ)
		state[1] = 1.0 / rng.randf_range(lo, minf(lo * Tuning.LIGHT_FLICKER_RATE_SPREAD, Tuning.FLICKER_STUTTER_MAX_HZ))
		f.stutter = (1.0 if bool(state[0]) else 1.0 - Fixture.flicker_depth())
		f.refresh()


## The beam back to steady (shed, lunge resolved, player gone).
static func beam_steady(f: Flashlight) -> void:
	if f == null or not is_instance_valid(f):
		return
	f.stutter = 1.0
	f.flash = 0.0
	f.refresh()


## The beam's lunge flash amount for this frame (2 frames, or the reduced soft fade).
static func beam_flash(f: Flashlight, frame0: int, usec0: int) -> void:
	if f == null:
		return
	var reduce := CoherenceRenderer.reduce_flashing
	f.flash = CoherencePost.flash_amount(Engine.get_process_frames() - frame0, (Time.get_ticks_usec() - usec0) / 1000000.0, reduce)
	f.stutter = 1.0
	f.refresh()


static func _mesh() -> QuadMesh:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2.ONE * Tuning.FLICKER_VISUAL_SPARK_SIZE
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.WHITE
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = 4.0
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mesh.material = m
	return _spark_mesh


static func _material() -> ParticleProcessMaterial:
	if _spark_material == null:
		_spark_material = ParticleProcessMaterial.new()
		_spark_material.direction = Vector3.DOWN
		_spark_material.spread = 70.0
		_spark_material.initial_velocity_min = 1.5
		_spark_material.initial_velocity_max = 4.0
		_spark_material.gravity = Vector3(0, -9.8, 0)
	return _spark_material
