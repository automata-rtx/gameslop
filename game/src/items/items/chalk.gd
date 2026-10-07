class_name ChalkItem
extends ItemBase
## Chalk (09 §2, §9, 11 §2): stamp an arrow decal on the aimed wall or floor within 2 m,
## pointing the way the player faces (yaw snapped to 45 degrees). The stamp lands the frame
## the key goes down (decal scale-in 100 ms, three scrapes, a 1 degree nod, one use spent); the
## hand then spends 0.3 s on the stroke, during which the chalk is busy. Aiming at nothing
## within reach stamps nothing and costs nothing. Decals persist for the level (at most 40;
## the oldest is removed) and are cleared when the level is left or a run starts.

const SOUND := &"chalk_mark"
const SOURCE_GROUP := ChalkDecal.GROUP

var _left: float = 0.0
var _stroke: Tween = null


func _ready() -> void:
	EventBus.level_left.connect(_on_level_left)
	EventBus.run_started.connect(_on_run_started)


func _physics_process(dt: float) -> void:
	tick(dt)


## Counts the stroke down (public so tests step time).
func tick(dt: float) -> void:
	if not busy:
		return
	_left -= dt
	if _left <= 0.0:
		busy = false
		_left = 0.0


func cancel() -> void:
	busy = false
	_left = 0.0


func use(slot: ItemSlot) -> bool:
	if busy or slot == null or slot.count <= 0:
		return false
	var cam := camera()
	if cam == null:
		return false
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := raycast(cam, origin, dir)
	if hit.is_empty():
		return false
	var facing := -player().global_transform.basis.z
	stamp(hit["position"], hit["normal"], facing)
	busy = true
	_left = Tuning.CHALK_STAMP_TIME
	return true


## The aimed world point within CHALK_STAMP_RANGE, or {}.
func raycast(cam: Camera3D, origin: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * Tuning.CHALK_STAMP_RANGE,
			PlayerLayers.WORLD_MASK)
	var p := player()
	if p != null:
		q.exclude = [p.get_rid()]
	return cam.get_world_3d().direct_space_state.intersect_ray(q)


## Places an arrow decal at `point` on a surface with `normal`, spends one use, plays the
## feedback. Returns the decal.
func stamp(point: Vector3, normal: Vector3, facing: Vector3) -> ChalkDecal:
	var d := ChalkDecal.new()
	d.name = "ChalkDecal"
	_decal_parent().add_child(d)
	d.global_transform = Transform3D(ChalkDecal.arrow_basis(normal, facing), point + normal.normalized() * 0.02)
	_trim(Tuning.CHALK_MAX_DECALS)
	# 11 §2: the decal scales in over 100 ms.
	var full := d.size
	d.size = full * 0.25
	var tw := d.create_tween()
	tw.tween_property(d, "size", full, float(Tuning.CHALK_SCALE_IN_MS) / 1000.0)
	AudioManager.play_3d(SOUND, point)
	var p := player()
	if p != null:
		p.rig.nod(Tuning.FEEDBACK_CHALK_NOD_DEG)
	_stroke_hand()
	inventory.consume(kind, 1)
	return d


## Removes the oldest decals until at most `limit` remain.
func _trim(limit: int) -> void:
	var decals := inventory.get_tree().get_nodes_in_group(SOURCE_GROUP)
	while decals.size() > limit:
		var oldest: ChalkDecal = null
		for n in decals:
			if n is ChalkDecal and (oldest == null or (n as ChalkDecal).serial < oldest.serial):
				oldest = n
		if oldest == null:
			return
		decals.erase(oldest)
		oldest.queue_free()
		oldest.remove_from_group(SOURCE_GROUP)


func _decal_parent() -> Node:
	var tree := inventory.get_tree()
	return tree.current_scene if tree.current_scene != null else tree.root


## The hand swipes forward and back over the 0.3 s of the stamp.
func _stroke_hand() -> void:
	var model := inventory.held_model()
	if model == null or model.get_meta(&"kind", &"") != kind:
		return
	if _stroke != null:
		_stroke.kill()
	var t := Tuning.CHALK_STAMP_TIME * 0.5
	model.position = Vector3.ZERO
	_stroke = create_tween().set_trans(Tween.TRANS_QUAD)
	_stroke.tween_property(model, "position", Vector3(-0.02, 0.01, -0.07), t).set_ease(Tween.EASE_OUT)
	_stroke.tween_property(model, "position", Vector3.ZERO, t).set_ease(Tween.EASE_IN)


## Removes every chalk decal (a new level or run).
static func clear_decals(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(SOURCE_GROUP):
		n.remove_from_group(SOURCE_GROUP)
		n.queue_free()


func _on_level_left(_proper: bool) -> void:
	clear_decals(get_tree())


func _on_run_started(_mode: StringName, _seed: int) -> void:
	clear_decals(get_tree())
