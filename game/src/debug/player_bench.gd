extends Node3D
## Player bench (M1.3): a Halls-coloured room from primitives with a fixture-lit half, a
## dark corner, a low beam (crouch), a 0.2 m step, and a locker hide spot.
## Click to capture the mouse, Esc to release. Debug keys (bench only): K = a 35 contact
## from a dummy error in front, J = +25 Coherence, L = -10 Coherence (static).
## `-- --bench-shots <dir>` saves four frames (room, flashlight in the dark corner,
## cranking with the light off there, inside the locker) and quits; use it with tools/ci/render.sh.

const ROOM := Vector3(12.0, 3.0, 12.0)
const WALL_T := 0.2
const FIXTURE_POS := Vector3(-1.5, 2.9, 2.0)

@onready var player: Player = %Player
@onready var fixture_light: OmniLight3D = %FixtureLight
@onready var readout: Label = %Readout
@onready var locker: HideSpot = %Locker

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceiling_mat: StandardMaterial3D
var _partition_mat: StandardMaterial3D
var _last_noise: String = ""


func _ready() -> void:
	_wall_mat = _mat(Color(0.788, 0.635, 0.153), 0.85)
	_floor_mat = _mat(Color(0.545, 0.478, 0.227), 1.0)
	_ceiling_mat = _mat(Color(0.91, 0.886, 0.812), 0.9)
	_partition_mat = _mat(Color(0.541, 0.561, 0.588), 0.8)
	_build_room()
	player.add_light_query(_fixture_lights)
	player.default_surface = &"carpet"
	EventBus.noise_emitted.connect(_on_noise)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--bench-shots")
	if i != -1:
		var dir := args[i + 1] if i + 1 < args.size() else "build/bench"
		_shots.call_deferred(dir)


func _fixture_lights(pos: Vector3) -> bool:
	return fixture_light.visible and pos.distance_to(fixture_light.global_position) <= fixture_light.omni_range


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_K:
				var dummy := Node3D.new()
				add_child(dummy)
				dummy.global_position = player.global_position - player.global_transform.basis.z
				dummy.set(&"error_id", &"still")
				player.contact(dummy, Tuning.COHERENCE_CONTACT_STILL)
				dummy.queue_free()
			KEY_J:
				player.apply_coherence(Tuning.COHERENCE_GAIN_POLAROID, &"polaroid")
			KEY_L:
				player.apply_coherence(-10.0, &"static")


func _process(_delta: float) -> void:
	readout.text = "COHERENCE %.0f  STAMINA %.0f  CHARGE %.0f\nSTATE %s  CRANK %s  LIGHT %s\nPROMPT %s\nNOISE %s" % [
		player.coherence, player.locomotion.stamina.value, player.flashlight.charge,
		player.state_machine.state, player.flashlight.is_turning(), player.flashlight.on,
		player.interactor.target.prompt_text() if player.interactor.target else "-", _last_noise]


func _on_noise(_pos: Vector3, radius: float, kind: StringName) -> void:
	_last_noise = "%s %.1f m" % [kind, radius]


# --- screenshots ------------------------------------------------------------------------

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _settle(30)
	_pose(Vector3(0.0, 0.0, 4.5), 0.0, -0.05)
	await _settle(40)
	_save(dir + "/bench_room.png")
	_pose(Vector3(5.0, 0.0, -1.0), deg_to_rad(20.0), -0.15)
	player.flashlight.set_on(true)
	await _settle(40)
	_save(dir + "/bench_dark_corner_flashlight.png")
	player.flashlight.set_on(false)
	player.flashlight.set_charge(0.0)
	Input.action_press(&"crank")
	await _settle(4)
	_save(dir + "/bench_crank_dark.png")
	Input.action_release(&"crank")
	_pose(Vector3(-4.5, 0.0, 0.0), deg_to_rad(90.0), 0.0)
	await _settle(10)
	player.enter_hide(locker)
	await _settle(60)
	_save(dir + "/bench_locker.png")
	get_tree().quit(0)


func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.rotation = Vector3(0.0, yaw, 0.0)
	player.rig.reset_pitch()
	player.rig.add_pitch(pitch)


func _settle(frames: int) -> void:
	for f in frames:
		await get_tree().process_frame


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("bench shot %s (%s)" % [path, error_string(err)])


# --- room ---------------------------------------------------------------------------------

func _build_room() -> void:
	var h := ROOM.y
	_box(Vector3(ROOM.x, WALL_T, ROOM.z), Vector3(0, -WALL_T * 0.5, 0), _floor_mat)
	_box(Vector3(ROOM.x, WALL_T, ROOM.z), Vector3(0, h + WALL_T * 0.5, 0), _ceiling_mat)
	_box(Vector3(ROOM.x, h, WALL_T), Vector3(0, h * 0.5, -ROOM.z * 0.5), _wall_mat, &"perimeter")
	_box(Vector3(ROOM.x, h, WALL_T), Vector3(0, h * 0.5, ROOM.z * 0.5), _wall_mat, &"perimeter")
	_box(Vector3(WALL_T, h, ROOM.z), Vector3(-ROOM.x * 0.5, h * 0.5, 0), _wall_mat, &"perimeter")
	_box(Vector3(WALL_T, h, ROOM.z), Vector3(ROOM.x * 0.5, h * 0.5, 0), _wall_mat, &"perimeter")
	# The dark corner (north-east): an L of partitions that keeps the fixture's light out.
	_box(Vector3(3.0, h, WALL_T), Vector3(2.5, h * 0.5, -2.5), _partition_mat, &"interior")
	_box(Vector3(WALL_T, h, 1.6), Vector3(1.0, h * 0.5, -3.3), _partition_mat, &"interior")
	# A low beam to crouch under (1.25 m clearance) and a 0.2 m step.
	_box(Vector3(2.0, 0.25, 1.2), Vector3(-3.0, 1.375, -4.5), _partition_mat)
	_box(Vector3(2.0, 0.2, 2.0), Vector3(3.5, 0.1, 3.5), _partition_mat)
	# The fixture: an emissive tube (light comes from the OmniLight in the scene).
	var tube := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.2, 0.05, 0.15)
	var em := _mat(Color(1, 0.949, 0.769), 0.5)
	em.emission_enabled = true
	em.emission = Color(1, 0.949, 0.769)
	em.emission_energy_multiplier = 8.0
	tm.material = em
	tube.mesh = tm
	tube.position = FIXTURE_POS + Vector3(0, 0.06, 0)
	add_child(tube)


## `wall_kind` marks walls for noise attenuation (06 Interfaces), as the level builder does.
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
