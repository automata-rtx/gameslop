class_name ItemThrow
extends RefCounted
## The throw shared by the Glowstick and the Flare (09 §2): 8 m at 45 degrees from just in
## front of the right hand, speed from the release height above the floor so it lands at 8 m.

const EYE_ABOVE_THROW := 0.2
const DEFAULT_HEIGHT := 1.45


## {origin: Vector3, velocity: Vector3} of a throw by `p` (null: a standing default facing -Z).
static func plan(p: Player) -> Dictionary:
	var origin := Vector3(0.0, DEFAULT_HEIGHT + EYE_ABOVE_THROW, 0.0)
	var flat := Vector3(0.0, 0.0, -1.0)
	var right := Vector3.RIGHT
	if p != null:
		var cam := p.rig.camera
		origin = cam.global_position
		flat = -p.global_transform.basis.z
		flat.y = 0.0
		flat = flat.normalized()
		right = flat.cross(Vector3.UP)
	origin += flat * 0.35 + right * 0.12 + Vector3.DOWN * EYE_ABOVE_THROW
	var height := height_above_floor(origin, p)
	var speed := Glowstick.throw_speed(Tuning.GLOWSTICK_THROW_DIST, height)
	var angle := deg_to_rad(Tuning.GLOWSTICK_THROW_ANGLE)
	return {&"origin": origin, &"velocity": flat * cos(angle) * speed + Vector3.UP * sin(angle) * speed}


## Metres from `origin` down to the floor (a ray on the world layer), else a standing default.
static func height_above_floor(origin: Vector3, p: Player) -> float:
	if p == null:
		return DEFAULT_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.0, PlayerLayers.WORLD_MASK)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return origin.y - (hit["position"] as Vector3).y if not hit.is_empty() else DEFAULT_HEIGHT
