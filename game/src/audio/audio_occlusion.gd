class_name AudioOcclusion
extends RefCounted
## 03 §3 occlusion: every 3D emitter on the Errors and Interact buses is checked every
## 0.2 s with a ray to the listener on the `world` layer; occluded emitters get a low-pass
## at 800 Hz and -6 dB, tweened over 100 ms. Sounds marked `through_walls` in the manifest
## (Static, Null, the Cycled exit tone) are never occluded.

const BUSES: Array[StringName] = [&"Errors", &"Interact"]
const WORLD_MASK := 1                 # physics layer 1 `world` (14 §7)
const OPEN_CUTOFF_HZ := 20500.0       # AudioStreamPlayer3D: this value disables the filter
const META_OCCLUDED := &"audio_occluded"
const META_THROUGH := &"audio_through_walls"
const START_NUDGE := 0.25             # m toward the listener before the ray starts


static func wants_check(p: AudioStreamPlayer3D) -> bool:
	return p.playing and p.bus in BUSES and not bool(p.get_meta(META_THROUGH, false))


## True when level geometry blocks the straight line from `p` to `listener_pos`. The ray
## starts START_NUDGE toward the listener and ignores the emitter's own bodies (a door's
## leaf, a fixture's housing), so a sound is never occluded by the thing that makes it.
## Emitters beyond their max_distance are silent anyway and are not traced.
static func is_occluded(p: AudioStreamPlayer3D, listener_pos: Vector3) -> bool:
	if not p.is_inside_tree():
		return false
	var from := p.global_position
	var dist := from.distance_to(listener_pos)
	if dist <= START_NUDGE or (p.max_distance > 0.0 and dist > p.max_distance):
		return false
	var space := p.get_world_3d().direct_space_state
	if space == null:
		return false
	from += (listener_pos - from) / dist * START_NUDGE
	var q := PhysicsRayQueryParameters3D.create(from, listener_pos, WORLD_MASK, _own_bodies(p))
	q.hit_from_inside = false
	return not space.intersect_ray(q).is_empty()


static func _own_bodies(p: Node) -> Array[RID]:
	var out: Array[RID] = []
	var n := p.get_parent()
	while n != null:
		if n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()
	return out


## Tweens `p` to the occluded or open state if it changed.
static func set_occluded(p: AudioStreamPlayer3D, occluded: bool) -> void:
	if bool(p.get_meta(META_OCCLUDED, false)) == occluded:
		return
	p.set_meta(META_OCCLUDED, occluded)
	var t := p.create_tween().set_parallel(true)
	var secs := Tuning.AUDIO_OCCLUSION_TWEEN_MS / 1000.0
	var cutoff := Tuning.AUDIO_OCCLUSION_LOWPASS_HZ if occluded else OPEN_CUTOFF_HZ
	t.tween_property(p, ^"attenuation_filter_cutoff_hz", cutoff, secs)
	var from_db := float(p.get_meta(AudioLoop.META_OCCLUSION, 0.0))
	var to_db := Tuning.AUDIO_OCCLUSION_DB if occluded else 0.0
	t.tween_method(func(v: float) -> void: AudioLoop.set_part(p, AudioLoop.META_OCCLUSION, v), from_db, to_db, secs)


## Sets the state at once, no tween: a one-shot decided at play time (a door behind a
## wall is muffled from its first sample, not 0.2 s later).
static func apply_now(p: AudioStreamPlayer3D, occluded: bool) -> void:
	p.set_meta(META_OCCLUDED, occluded)
	p.attenuation_filter_cutoff_hz = Tuning.AUDIO_OCCLUSION_LOWPASS_HZ if occluded else OPEN_CUTOFF_HZ
	AudioLoop.set_part(p, AudioLoop.META_OCCLUSION, Tuning.AUDIO_OCCLUSION_DB if occluded else 0.0)


## Resets a pooled player to the open state immediately.
static func reset(p: AudioStreamPlayer3D) -> void:
	p.set_meta(META_OCCLUDED, false)
	p.attenuation_filter_cutoff_hz = OPEN_CUTOFF_HZ
	p.set_meta(AudioLoop.META_OCCLUSION, 0.0)


## One 0.2 s pass over `players`.
static func tick(players: Array, listener_pos: Vector3) -> void:
	for p: Variant in players:
		if not is_instance_valid(p):
			continue
		var p3 := p as AudioStreamPlayer3D
		if p3 != null and wants_check(p3):
			set_occluded(p3, is_occluded(p3, listener_pos))
