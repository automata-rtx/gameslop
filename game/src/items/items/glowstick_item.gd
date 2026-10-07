class_name GlowstickItem
extends ItemBase
## The Glowstick belt item (09 §2, 11 §2). use_item taps: crack it and throw (8 m at 45
## degrees, bounces once, settles; the landing is a 6 m impact noise). use_item held 0.5 s: set
## it down at the feet, silently. The throw happens when the key comes up (a tap) so a hold
## can still become a drop; the hand winds back the moment the key goes down.

const SOUND_CRACK := &"glowstick_crack"
const EYE_ABOVE_THROW := 0.2
const DEFAULT_HEIGHT := 1.45

## Seconds the key has been held in this press; -1 when not arming.
var held_for: float = -1.0


func input(slot: ItemSlot, pressed: bool, held: bool, dt: float) -> void:
	if pressed and held_for < 0.0:
		held_for = 0.0
		_wind_up()
		return
	if held_for < 0.0:
		return
	if held:
		held_for += dt
		if held_for >= Tuning.GLOWSTICK_DROP_HOLD:
			held_for = -1.0
			_release_hand()
			drop_at_feet(slot)
	else:
		held_for = -1.0
		throw(slot)


func abort_hold() -> void:
	if held_for >= 0.0:
		held_for = -1.0
		_release_hand()


func cancel() -> void:
	busy = false
	abort_hold()


## Press semantics (Inventory.use_selected): throw now.
func use(slot: ItemSlot) -> bool:
	return throw(slot) != null


## Cracks and throws one glowstick. Returns the stick, or null when none was thrown.
func throw(slot: ItemSlot) -> Glowstick:
	if slot == null or slot.count <= 0:
		return null
	var p := player()
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
	var height := _height_above_floor(origin, p)
	var speed := Glowstick.throw_speed(Tuning.GLOWSTICK_THROW_DIST, height)
	var angle := deg_to_rad(Tuning.GLOWSTICK_THROW_ANGLE)
	var stick := _spawn()
	stick.launch(origin, flat * cos(angle) * speed + Vector3.UP * sin(angle) * speed)
	AudioManager.play_3d(SOUND_CRACK, origin)
	if p != null:
		p.rig.nod(Tuning.FEEDBACK_THROW_RECOIL_DEG)
	_throw_hand()
	inventory.consume(kind, 1)
	return stick


## Sets one glowstick down at the player's feet; no impact noise.
func drop_at_feet(slot: ItemSlot) -> Glowstick:
	if slot == null or slot.count <= 0:
		return null
	var p := player()
	var pos := Vector3(0.0, 0.05, -0.4)
	var yaw := 0.0
	if p != null:
		var f := -p.global_transform.basis.z
		f.y = 0.0
		pos = p.global_position + f.normalized() * 0.4 + Vector3(0.0, 0.05, 0.0)
		yaw = p.global_rotation.y
	var stick := _spawn()
	stick.set_down(pos, yaw)
	AudioManager.play_3d(SOUND_CRACK, pos, &"", -6.0)
	inventory.consume(kind, 1)
	return stick


func _spawn() -> Glowstick:
	var stick := Glowstick.new()
	var tree := inventory.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(stick)
	return stick


## Metres from `origin` down to the floor (a ray on the world layer), else a standing default.
func _height_above_floor(origin: Vector3, p: Player) -> float:
	if p == null:
		return DEFAULT_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.0, PlayerLayers.WORLD_MASK)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return origin.y - (hit["position"] as Vector3).y if not hit.is_empty() else DEFAULT_HEIGHT


# --- held visuals ----------------------------------------------------------------------------

var _hand: Tween = null


func _wind_up() -> void:
	var m := _model()
	if m == null:
		return
	_hand_to(m, Vector3(0.04, 0.05, 0.08), 0.15)


func _release_hand() -> void:
	var m := _model()
	if m != null:
		_hand_to(m, Vector3.ZERO, 0.2)


func _throw_hand() -> void:
	var m := _model()
	if m == null:
		return
	if _hand != null:
		_hand.kill()
	_hand = create_tween().set_trans(Tween.TRANS_QUAD)
	_hand.tween_property(m, "position", Vector3(-0.03, 0.0, -0.12), 0.08).set_ease(Tween.EASE_OUT)
	_hand.tween_property(m, "position", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN_OUT)


func _hand_to(m: Node3D, to: Vector3, t: float) -> void:
	if _hand != null:
		_hand.kill()
	_hand = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hand.tween_property(m, "position", to, t)


func _model() -> Node3D:
	var m := inventory.held_model()
	return m if m != null and m.get_meta(&"kind", &"") == kind else null
