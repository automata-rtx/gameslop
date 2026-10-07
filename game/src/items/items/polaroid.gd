class_name PolaroidItem
extends ItemBase
## The Polaroid (09 §2, 11 §2): hold it up for 1.2 s, the photo fills the lower half of the
## view, the view narrows 3 degrees, 12 frames converge, then a white flash on the last frame
## and +25 Coherence with the gain pulse. Refused while stunned or charging noclip; stun,
## noclip charge or losing agency mid-use cancels it and costs nothing.
## Errors in the flash cone get `on_polaroid(origin: Vector3, dir: Vector3)` if they implement it
## (09 defines no effect on errors; this is only the hook).

const PULSE_FLASH := &"flash"
const FOV_KEY := &"polaroid"
const SOUND_CHARGE := &"polaroid_charge"
const SOUND_SHUTTER := &"polaroid_shutter"
const SOURCE := &"polaroid"
const HOOK := &"on_polaroid"
const PHOTO_DISTANCE := 0.3
const FRAME_COUNT := Tuning.POLAROID_FRAMES

## Seconds into the current use (0 when idle).
var elapsed: float = 0.0
## The photo (PolaroidPainter index) of the current use.
var image_index: int = 0
var _fallback_next: int = 0
var _rise: Tween = null
var _frames: Array[MeshInstance3D] = []
var _frames_tween: Tween = null
var _frames_started: bool = false


func _physics_process(dt: float) -> void:
	if busy:
		tick(dt)


## Pure rule: the lockouts of 09 §2 (stunned, charging noclip) plus the Player's own.
static func blocked(p: Player) -> bool:
	if p == null:
		return false
	return p.is_stunned() or p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE) \
			or p.is_dissolving() or not p.can_use_item()


## True when `target` is inside the flash cone: within `max_dist` and `half_deg` of `dir`.
static func in_cone(origin: Vector3, dir: Vector3, target: Vector3,
		half_deg: float = Tuning.POLAROID_CONE_DEG, max_dist: float = Tuning.POLAROID_RANGE) -> bool:
	var to := target - origin
	var d := to.length()
	if d > max_dist:
		return false
	if d < 0.001:
		return true
	return rad_to_deg(dir.angle_to(to)) <= half_deg


func use(slot: ItemSlot) -> bool:
	if busy or slot == null or slot.count <= 0:
		return false
	if blocked(player()):
		return false
	busy = true
	elapsed = 0.0
	_frames_started = false
	image_index = _next_image(slot)
	AudioManager.play_2d(SOUND_CHARGE)
	var p := player()
	if p != null:
		p.rig.fov_hold(-Tuning.POLAROID_NARROW_DEG, Tuning.POLAROID_NARROW_TIME * 1000.0, FOV_KEY)
	_hold_up()
	return true


## Advances the use by `dt` seconds; completes it at 1.2 s. Public so tests step time.
func tick(dt: float) -> void:
	if not busy:
		return
	if blocked_mid_use():
		cancel()
		return
	elapsed += dt
	if not _frames_started and elapsed >= Tuning.POLAROID_USE_TIME - Tuning.POLAROID_FRAMES_TIME:
		_frames_started = true
		_spawn_frames()
	if elapsed >= Tuning.POLAROID_USE_TIME:
		_complete()


## Stun, noclip charge, or no agency ends the use early (can_use_item is not re-asked: it
## only gates starting).
func blocked_mid_use() -> bool:
	var p := player()
	if p == null:
		return false
	return p.is_stunned() or p.state_machine.is_in(PlayerStateMachine.NOCLIP_CHARGE) \
			or p.is_dissolving() or not p.has_agency()


func cancel() -> void:
	if not busy:
		return
	busy = false
	elapsed = 0.0
	_clear_frames()
	var p := player()
	if p != null:
		p.rig.fov_hold(0.0, 150.0, FOV_KEY)
	_put_down()


func on_unequipped() -> void:
	if busy:
		cancel()


func _complete() -> void:
	busy = false
	elapsed = 0.0
	_clear_frames()
	var p := player()
	var photo := image_index
	var slot := inventory.selected_slot()
	if slot != null and slot.kind == kind:
		var images: Variant = slot.state.get(&"images")
		if images is Array and not (images as Array).is_empty():
			(images as Array).remove_at(0)
	# 11 §2: the flash on the last frame, the shutter, the gain.
	CoherenceRenderer.pulse(PULSE_FLASH)
	AudioManager.play_2d(SOUND_SHUTTER)
	_note_seen(photo)
	if p != null:
		p.rig.fov_hold(0.0, 150.0, FOV_KEY)
		_flash_errors(p)
		p.apply_coherence(Tuning.COHERENCE_GAIN_POLAROID, SOURCE)
	inventory.consume(kind, 1)
	_put_down()


## The photo index of the next use: the oldest in the slot's image queue, else a stepping fallback.
func _next_image(slot: ItemSlot) -> int:
	var images: Variant = slot.state.get(&"images")
	if images is Array and not (images as Array).is_empty():
		return PolaroidPainter.index_for(int((images as Array)[0]))
	var i := PolaroidPainter.index_for(_fallback_next)
	_fallback_next += 1
	return i


func _note_seen(photo: int) -> void:
	var meta: MetaState = GameState.meta
	if meta != null and not meta.polaroids_seen.has(photo):
		meta.polaroids_seen.append(photo)


# --- the flash and the errors ----------------------------------------------------------------

func _flash_errors(p: Player) -> void:
	var cam := p.rig.camera
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var space := cam.get_world_3d().direct_space_state
	for e in inventory.get_tree().get_nodes_in_group(&"errors"):
		if not (e is Node3D) or not e.has_method(HOOK):
			continue
		var pos := (e as Node3D).global_position
		if not in_cone(origin, dir, pos):
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, pos, PlayerLayers.WORLD_MASK)
		q.exclude = [p.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		e.call(HOOK, origin, dir)


# --- held visuals ----------------------------------------------------------------------------

## Vertical size of the view at `dist` metres, from the camera's actual projection.
static func view_height_at(cam: Camera3D, dist: float) -> float:
	var vfov := cam.fov
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		var size := cam.get_viewport().get_visible_rect().size
		vfov = rad_to_deg(2.0 * atan(tan(deg_to_rad(cam.fov) * 0.5) * size.y / maxf(size.x, 1.0)))
	return 2.0 * dist * tan(deg_to_rad(vfov) * 0.5)


## Raises the held card so it fills the lower half of the view, face to the camera, with the
## painted photo on the inner quad.
func _hold_up() -> void:
	var model := inventory.held_model()
	var cam := camera()
	if model == null or cam == null or model.get_meta(&"kind", &"") != kind:
		return
	var card := model.get_node_or_null("Card") as MeshInstance3D
	var photo := model.get_node_or_null("Photo") as MeshInstance3D
	_overlay(card, Color(ItemModels.WHITE), null, 1)
	_overlay(photo, Color.WHITE, PolaroidPainter.texture(image_index), 2)
	var h := view_height_at(cam, PHOTO_DISTANCE)
	var s := (h * 0.5) / ItemModels.POLAROID_H
	var target := Vector3(0.0, -h * 0.25, -PHOTO_DISTANCE) - Inventory.HELD_REST
	if _rise != null:
		_rise.kill()
	_rise = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var t := Tuning.POLAROID_NARROW_TIME
	_rise.tween_property(model, "position", target, t)
	_rise.tween_property(model, "rotation", Vector3.ZERO, t)
	_rise.tween_property(model, "scale", Vector3.ONE * s, t)


func _put_down() -> void:
	var model := inventory.held_model()
	if _rise != null:
		_rise.kill()
	if model == null or model.get_meta(&"kind", &"") != kind:
		return
	var card := model.get_node_or_null("Card") as MeshInstance3D
	var photo := model.get_node_or_null("Photo") as MeshInstance3D
	_overlay(card, ItemModels.WHITE, null, 0, false)
	_overlay(photo, Color.BLACK, null, 0, false)
	var rest := ItemModels.held(kind)
	_rise = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_rise.tween_property(model, "position", Vector3.ZERO, 0.2)
	_rise.tween_property(model, "rotation", rest.rotation, 0.2)
	_rise.tween_property(model, "scale", Vector3.ONE, 0.2)
	rest.free()


## Draws a part over the world and unshaded (the card held up must not clip into walls).
static func _overlay(mi: MeshInstance3D, color: Color, tex: Texture2D, priority: int, on: bool = true) -> void:
	if mi == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if on:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = priority
		m.albedo_texture = tex
	mi.material_override = m


## 02 §10: twelve small frames float in around the view and converge into the camera, landing
## on the flash.
func _spawn_frames() -> void:
	var cam := camera()
	if cam == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(0.034, 0.041)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.97, 0.88, 1.0)
	mat.no_depth_test = true
	mat.render_priority = 3
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_frames_tween = tw
	for i in FRAME_COUNT:
		var a := TAU * float(i) / float(FRAME_COUNT) + 0.3 * float(i % 3)
		var r := 0.2 + 0.05 * float(i % 4)
		var f := MeshInstance3D.new()
		f.mesh = quad
		f.material_override = mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = Vector3(cos(a) * r * 1.4, sin(a) * r, -0.4)
		f.rotation = Vector3(0.0, 0.0, a * 0.5)
		cam.add_child(f)
		_frames.append(f)
		tw.tween_property(f, "position", Vector3(0.0, 0.0, -0.08), Tuning.POLAROID_FRAMES_TIME)
		tw.tween_property(f, "scale", Vector3.ONE * 0.2, Tuning.POLAROID_FRAMES_TIME)
	tw.finished.connect(_clear_frames)


func _clear_frames() -> void:
	if _frames_tween != null:
		_frames_tween.kill()
		_frames_tween = null
	for f in _frames:
		if is_instance_valid(f):
			f.queue_free()
	_frames.clear()
