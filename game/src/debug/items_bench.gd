extends Node3D
## Items bench (M1.10, M2.8, 09 §10): a Halls-coloured room with one pickup of each kind on the
## floor, a note, a wall for chalk, an error stand-in for the Polaroid's cone, and the HUD bound
## to the belt. Click to capture the mouse, Esc to release. Keys: 1-4 / wheel select, right
## mouse use. Bench keys: J = add a Polaroid, a Glowstick x2 and Chalk x8 to the belt, K = drain
## 40 Coherence, L = clear the chalk. `-- --bench-shots <dir>` saves the item screenshots
## (pickups, held items, Polaroid held up and flash, glowstick lit on the floor, chalk) and quits;
## use it with tools/ci/render.sh.

const ROOM := Vector3(14.0, 3.0, 12.0)
const WALL_T := 0.2
const ERROR_POS := Vector3(4.0, 0.0, -2.0)

@onready var player: Player = %Player
@onready var hud: Hud = %Hud
@onready var readout: Label = %Readout
@onready var fixture: OmniLight3D = %FixtureLight

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceiling_mat: StandardMaterial3D
var _stand_in: ItemsErrorStandIn
var _last: String = ""
var _photo: int = 0
## The M2.8 props, interactables and hide spots (ItemsBenchM28).
var _m28: Dictionary = {}


func _ready() -> void:
	_wall_mat = _mat(Color(0.788, 0.635, 0.153), 0.85)
	_floor_mat = _mat(Color(0.545, 0.478, 0.227), 1.0)
	_ceiling_mat = _mat(Color(0.91, 0.886, 0.812), 0.9)
	_build_room()
	_place_pickups()
	_m28 = ItemsBenchM28.build(self, _wall_mat)
	player.default_surface = &"carpet"
	hud.bind_player(player)
	hud.bind_inventory(player.inventory)
	EventBus.item_used.connect(func(k: StringName) -> void: _last = "used %s" % k)
	EventBus.item_picked.connect(func(k: StringName) -> void: _last = "picked %s" % k)
	EventBus.note_found.connect(func(id: StringName) -> void: _last = "note %s" % id)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--bench-shots")
	if i != -1:
		_shots.call_deferred(args[i + 1] if i + 1 < args.size() else "build/items")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_J:
				_photo = (_photo + 1) % PolaroidPainter.COUNT
				player.inventory.add(&"polaroid", 1, {&"images": [_photo]})
				player.inventory.add(&"glowstick", 2)
				player.inventory.add(&"chalk", 8)
			KEY_K:
				player.apply_coherence(-40.0, &"static")
			KEY_L:
				ChalkItem.clear_decals(get_tree())


func _process(_delta: float) -> void:
	var inv := player.inventory
	var belt := ""
	for s in inv.slots:
		belt += ("[%s x%d] " % [s.kind, s.count]) if s != null else "[-] "
	readout.text = "COHERENCE %.0f   ITEM %s\nBELT %s\nPROMPT %s\nLAST %s   POLAROID FLASHES AT STAND-IN %d" % [
		player.coherence, inv.selected_kind(), belt,
		player.interactor.target.prompt_text() if player.interactor.target else "-", _last,
		_stand_in.flashes if _stand_in else 0]


# --- screenshots ------------------------------------------------------------------------

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var inv := player.inventory
	await _settle(30)
	_pose(Vector3(0.0, 0.0, 5.0), 0.0, -0.18)
	await _settle(40)
	_save(dir + "/items_pickups.png")
	# The belt, held items.
	inv.add(&"polaroid", 2, {&"images": [0, 5]})
	inv.add(&"glowstick", 3)
	inv.add(&"chalk", 8)
	inv.select(1)
	await _wait(1.0)
	_save(dir + "/items_held_glowstick.png")
	inv.select(2)
	await _wait(1.0)
	_save(dir + "/items_held_chalk.png")
	inv.select(0)
	await _wait(1.0)
	_save(dir + "/items_held_polaroid.png")
	# Polaroid: held up, the frames converging, the flash.
	player.apply_coherence(-40.0, &"static")
	_pose(Vector3(0.0, 0.0, 5.0), 0.0, 0.0)
	await _settle(10)
	var pol := inv.behavior_for(&"polaroid") as PolaroidItem
	var flash_shot := [false]
	player.coherence_changed.connect(func(_v: float, d: float, _s: StringName) -> void:
		if d > 0.0 and not flash_shot[0]:
			flash_shot[0] = true
			_flash_shot.call_deferred(dir + "/items_polaroid_flash.png"))
	inv.use_selected()
	var frames_shot := false
	var held_shot := false
	var guard := 0
	while pol.busy and guard < 2000:
		await get_tree().process_frame
		guard += 1
		if not held_shot and pol.elapsed >= 0.72:
			held_shot = true
			_save(dir + "/items_polaroid_held_up.png")
		if not frames_shot and pol.elapsed >= 0.95:
			frames_shot = true
			_save(dir + "/items_polaroid_frames.png")
	await _wait(1.0)
	# Glowstick thrown into the dark half, lit on the floor.
	fixture.visible = false
	_pose(Vector3(0.0, 0.0, 5.0), 0.0, -0.1)
	inv.select(1)
	await _wait(0.8)
	inv.use_selected()
	await _wait(3.0)
	_save(dir + "/items_glowstick_lit.png")
	inv.use_selected()
	_pose(Vector3(1.5, 0.0, 5.0), deg_to_rad(10.0), -0.1)
	await _wait(3.0)
	_save(dir + "/items_glowstick_two.png")
	fixture.visible = true
	# Chalk on the wall and the floor.
	inv.select(2)
	_pose(Vector3(-4.0, 0.0, -4.4), deg_to_rad(15.0), 0.05)
	await _wait(1.0)
	inv.use_selected()
	await _wait(0.5)
	_pose(Vector3(-3.0, 0.0, -4.4), deg_to_rad(-20.0), 0.05)
	await _wait(0.3)
	inv.use_selected()
	await _wait(0.5)
	_pose(Vector3(-3.5, 0.0, -2.0), deg_to_rad(40.0), -1.0)
	await _wait(0.5)
	inv.use_selected()
	await _wait(0.8)
	_pose(Vector3(-3.5, 0.0, -1.0), 0.0, -0.1)
	await _wait(0.6)
	_save(dir + "/items_chalk_dark.png")
	player.flashlight.set_on(true)
	_pose(Vector3(-3.5, 0.0, -2.2), deg_to_rad(10.0), -0.2)
	await _wait(0.8)
	_save(dir + "/items_chalk.png")
	player.flashlight.set_on(false)
	await ItemsBenchM28.shots(self, dir, _m28)
	get_tree().quit(0)


func _flash_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	_save(path)


func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.rotation = Vector3(0.0, yaw, 0.0)
	player.rig.reset_pitch()
	player.rig.add_pitch(pitch)


func _settle(frames: int) -> void:
	for f in frames:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await _settle(3)


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("bench shot %s (%s)" % [path, error_string(err)])


# --- room ---------------------------------------------------------------------------------

func _place_pickups() -> void:
	var row := [&"polaroid", &"chalk", &"glowstick", &"polaroid", &"glowstick"]
	for i in row.size():
		var p := ItemPickup.spawn(self, row[i], 0, {}, Vector3(-3.0 + 1.5 * float(i), 0.0, 1.5))
		if row[i] == &"polaroid":
			p.set_polaroid_image(i)
	var note := (load("res://scenes/interactables/note_pickup.tscn") as PackedScene).instantiate() as NotePickup
	note.note_id = &"H5"
	add_child(note)
	note.position = Vector3(4.5, 0.0, 1.5)
	_stand_in = ItemsErrorStandIn.new()
	add_child(_stand_in)
	_stand_in.position = ERROR_POS


func _build_room() -> void:
	var h := ROOM.y
	_box(Vector3(ROOM.x, WALL_T, ROOM.z), Vector3(0, -WALL_T * 0.5, 0), _floor_mat)
	_box(Vector3(ROOM.x, WALL_T, ROOM.z), Vector3(0, h + WALL_T * 0.5, 0), _ceiling_mat)
	_box(Vector3(ROOM.x, h, WALL_T), Vector3(0, h * 0.5, -ROOM.z * 0.5), _wall_mat, &"perimeter")
	_box(Vector3(ROOM.x, h, WALL_T), Vector3(0, h * 0.5, ROOM.z * 0.5), _wall_mat, &"perimeter")
	_box(Vector3(WALL_T, h, ROOM.z), Vector3(-ROOM.x * 0.5, h * 0.5, 0), _wall_mat, &"perimeter")
	_box(Vector3(WALL_T, h, ROOM.z), Vector3(ROOM.x * 0.5, h * 0.5, 0), _wall_mat, &"perimeter")


func _box(size: Vector3, pos: Vector3, mat: Material, wall_kind: StringName = &"") -> void:
	var body := StaticBody3D.new()
	if wall_kind != &"":
		body.set_meta(NoiseModel.WALL_META, wall_kind)
	body.collision_layer = PlayerLayers.WORLD_MASK
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	add_child(body)


func _mat(c: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	return m
