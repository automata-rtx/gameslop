class_name EndingCorridor
extends Node3D
## The ending corridor (01 §8 step 2, 02): a Halls module, 2 m wide with its 3 m ceiling and
## its carpet, but with clean white walls, its tubes dark (the only room without a hum, 03),
## and daylight through a window in the far wall of a small bay at the end: a real sun with
## real shadows (the mullions print a cross on the carpet) and a warm bounce. Under the window
## a single soft wall shimmer (02 §5 `soft`). The variant (01 §8, all notes found) prints the
## title menu on the far wall beside the window; DESCEND there is an Interactable the player
## presses like any other, and `descend_chosen` goes up to the Ending.
## Built from primitives and the world shader only (02 T8). Local space: the player starts at
## the origin facing -Z; the far wall stands at -(ENDING_CORRIDOR_LENGTH + bay depth).

signal descend_chosen

const HALLS_WALL := "res://data/materials/halls/wallpaper.tres"
const HALLS_CARPET := "res://data/materials/halls/carpet.tres"
const HALLS_CEILING := "res://data/materials/halls/ceiling_tile.tres"
const HALLS_HOUSING := "res://data/materials/halls/fixture_housing.tres"
const HALLS_TUBE := "res://data/materials/halls/fixture_emissive.tres"
const FLOOR_SURFACE := &"carpet"
const WALL_T := 0.2
const BACK_Z := 1.5
const FRAME_T := 0.06
const MENU_FONT_PX := 48
const MENU_PIXEL := 0.0024
const MENU_LINE_M := 0.17
## The menu block's top-left on the far wall, left of the window (x, y).
const MENU_ORIGIN := Vector2(-2.75, 1.95)

var width: float = Tuning.HALLS_CORRIDOR_WIDTH
var height: float = Tuning.STRATUM_CEILING_HEIGHT[&"halls"]
var length: float = Tuning.ENDING_CORRIDOR_LENGTH
var bay: Vector2 = Tuning.ENDING_BAY_SIZE
var far_z: float = 0.0
var sun: DirectionalLight3D
var variant: bool = false
## The variant's DESCEND line and its Interactable (null without the variant).
var descend_label: Label3D
var descend_interactable: Interactable
var menu_labels: Array[Label3D] = []

var _wall: ShaderMaterial
var _soft: ShaderMaterial
var _built: bool = false


## Builds the corridor once; `with_menu` adds the variant's in-world title menu.
func build(with_menu: bool) -> void:
	if _built:
		return
	_built = true
	variant = with_menu
	far_z = -(length + bay.y)
	_make_materials()
	_build_shell()
	_build_window()
	_build_fixtures()
	_build_lights()
	if with_menu:
		_build_menu()


## Where the player starts: the corridor's near end, facing the window.
func spawn_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3.ZERO)


## Metres from `world_pos` to the far wall along the corridor.
func distance_to_far_wall(world_pos: Vector3) -> float:
	return to_local(world_pos).z - far_z


## A point in front of the window, at eye height (benches and tests).
func window_point() -> Vector3:
	return to_global(Vector3(0.0, Tuning.ENDING_WINDOW_SILL + Tuning.ENDING_WINDOW_SIZE.y * 0.5, far_z))


# --- materials ---------------------------------------------------------------------------------

func _make_materials() -> void:
	_wall = (load(HALLS_WALL) as ShaderMaterial).duplicate() as ShaderMaterial
	_wall.set_shader_parameter(&"albedo", Tuning.ENDING_WALL_COLOR)
	_wall.set_shader_parameter(&"albedo_secondary", Tuning.ENDING_WALL_COLOR.darkened(0.04))
	_wall.set_shader_parameter(&"pattern_mode", 0)
	_wall.set_shader_parameter(&"print_amount", 0.0)
	_wall.set_shader_parameter(&"noise_albedo_amount", 0.04)
	_wall.set_shader_parameter(&"cell_tint", 0.0)
	_wall.set_shader_parameter(&"roughness", 0.8)
	_wall.set_shader_parameter(&"soft", 0.0)
	_soft = _wall.duplicate() as ShaderMaterial
	_soft.set_shader_parameter(&"soft", 1.0)


func _paint(color: Color, rough: float) -> ShaderMaterial:
	var m := (load(HALLS_HOUSING) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"albedo", color)
	m.set_shader_parameter(&"roughness", rough)
	m.set_shader_parameter(&"metallic", 0.0)
	return m


# --- geometry ------------------------------------------------------------------------------------

## A box with its mesh and (unless `solid` is false) a world-layer body.
func _box(size: Vector3, center: Vector3, mat: Material, solid: bool = true, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = PlayerLayers.WORLD_MASK
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		body.position = center
		add_child(body)
		mi.set_meta(&"body", body)
	return mi


func _build_shell() -> void:
	var half_w := width * 0.5
	var half_bay := bay.x * 0.5
	var depth := BACK_Z - far_z
	var mid_z := (BACK_Z + far_z) * 0.5
	var carpet := _box(Vector3(bay.x + 2.0 * WALL_T, WALL_T, depth), Vector3(0.0, -WALL_T * 0.5, mid_z),
			load(HALLS_CARPET) as Material)
	(carpet.get_meta(&"body") as StaticBody3D).set_meta(&"surface", FLOOR_SURFACE)
	_box(Vector3(bay.x + 2.0 * WALL_T, WALL_T, depth), Vector3(0.0, height + WALL_T * 0.5, mid_z),
			load(HALLS_CEILING) as Material)
	# The corridor: two long walls and the closed near end behind the player.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(WALL_T, height, length + BACK_Z), Vector3(side * (half_w + WALL_T * 0.5), height * 0.5,
				(BACK_Z - length) * 0.5), _wall)
	_box(Vector3(width, height, WALL_T), Vector3(0.0, height * 0.5, BACK_Z + WALL_T * 0.5), _wall)
	# The bay: its side walls and the shoulders where the corridor opens into it.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(WALL_T, height, bay.y), Vector3(side * (half_bay + WALL_T * 0.5), height * 0.5, -length - bay.y * 0.5), _wall)
		var shoulder := half_bay - half_w
		_box(Vector3(shoulder, height, WALL_T), Vector3(side * (half_w + shoulder * 0.5), height * 0.5, -length + WALL_T * 0.5), _wall)
	# The far wall around the window; the panel under the sill is the soft wall.
	var win := Tuning.ENDING_WINDOW_SIZE
	var sill := Tuning.ENDING_WINDOW_SILL
	var wz := far_z - WALL_T * 0.5
	var side_w := half_bay - win.x * 0.5
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side_w, height, WALL_T), Vector3(side * (win.x * 0.5 + side_w * 0.5), height * 0.5, wz), _wall)
	_box(Vector3(win.x, sill, WALL_T), Vector3(0.0, sill * 0.5, wz), _soft)
	var top := height - sill - win.y
	_box(Vector3(win.x, top, WALL_T), Vector3(0.0, sill + win.y + top * 0.5, wz), _wall)


func _build_window() -> void:
	var win := Tuning.ENDING_WINDOW_SIZE
	var sill := Tuning.ENDING_WINDOW_SILL
	var frame := _paint(Color("#F4F1EA"), 0.5)
	var z := far_z - WALL_T * 0.5
	var cy := sill + win.y * 0.5
	# Jambs, head and sill board, then the mullion cross whose shadow lies on the carpet.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(FRAME_T, win.y, WALL_T + 0.02), Vector3(side * (win.x - FRAME_T) * 0.5, cy, z), frame, false)
	_box(Vector3(win.x, FRAME_T, WALL_T + 0.02), Vector3(0.0, sill + win.y - FRAME_T * 0.5, z), frame, false)
	_box(Vector3(win.x + 0.12, 0.04, WALL_T + 0.12), Vector3(0.0, sill + 0.02, z + 0.04), frame, false)
	_box(Vector3(0.04, win.y, 0.05), Vector3(0.0, cy, z), frame, false)
	_box(Vector3(win.x, 0.04, 0.05), Vector3(0.0, sill + win.y * 0.62, z), frame, false)
	# Outside: daylight. The Threshold's strip of light (02 §7), now the whole window.
	var day := _paint(Tuning.ENDING_DAYLIGHT_COLOR, 1.0)
	day.set_shader_parameter(&"emission", Tuning.ENDING_DAYLIGHT_COLOR)
	day.set_shader_parameter(&"emission_strength", Tuning.ENDING_DAYLIGHT_EMISSION)
	_box(Vector3(bay.x * 2.0, height * 2.0, 0.05), Vector3(0.0, height * 0.5, far_z - 2.5), day, false, false)


## Halls tubes every 4 m down the corridor, housings in place and every tube dark.
func _build_fixtures() -> void:
	var housing := load(HALLS_HOUSING) as Material
	var tube := (load(HALLS_TUBE) as ShaderMaterial).duplicate() as ShaderMaterial
	tube.set_shader_parameter(&"emission_strength", 0.0)
	tube.set_shader_parameter(&"albedo", Color("#D8D6CE"))
	var z := -2.0
	while z > -length:
		_box(Vector3(0.3, 0.06, 1.24), Vector3(0.0, height - 0.03, z), housing, false)
		_box(Vector3(0.18, 0.03, 1.16), Vector3(0.0, height - 0.075, z), tube, false, false)
		z -= Tuning.HALLS_FIXTURE_SPACING_CELLS * Tuning.HALLS_CORRIDOR_WIDTH


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Tuning.ENDING_SUN_COLOR
	sun.light_energy = Tuning.ENDING_SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = length + bay.y + 10.0
	sun.light_angular_distance = 0.5
	add_child(sun)
	# Low afternoon sun from beyond the window, travelling down the corridor toward the player.
	var travel := Vector3(0.12, -0.3, 1.0).normalized()
	sun.basis = Basis.looking_at(travel, Vector3.UP)
	# The bounce the sun would give the bay and the corridor (no GI in v1.0, 02 §3).
	var bounce := OmniLight3D.new()
	bounce.name = "Bounce"
	bounce.light_color = Tuning.ENDING_SUN_COLOR
	bounce.light_energy = 1.1
	bounce.omni_range = 14.0
	bounce.shadow_enabled = false
	bounce.position = Vector3(0.0, 1.0, -length - 1.0)
	add_child(bounce)
	var spill := OmniLight3D.new()
	spill.name = "Spill"
	spill.light_color = Tuning.ENDING_DAYLIGHT_COLOR
	spill.light_energy = 0.35
	spill.omni_range = 12.0
	spill.shadow_enabled = false
	spill.position = Vector3(0.0, 2.2, -length * 0.45)
	add_child(spill)


# --- the variant's menu (01 §8) --------------------------------------------------------------

## The title's menu as it stands for this save (04 §7): DESCEND selected, the rest as the title
## would list them. Only DESCEND can be chosen here.
static func menu_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": TitlePage.ITEM_DESCEND, "text": Strings.MENU_SELECTED_PREFIX + Strings.MENU_DESCEND, "on": true})
	out.append({"id": TitlePage.ITEM_DAILY, "text": Strings.MENU_DAILY, "on": GameState.is_mode_available(Tuning.MODE_DAILY)})
	if GameState.is_mode_available(Tuning.MODE_ENDLESS):
		out.append({"id": TitlePage.ITEM_ENDLESS, "text": Strings.MENU_ENDLESS, "on": true})
	out.append({"id": TitlePage.ITEM_ARCHIVE, "text": Strings.MENU_ARCHIVE, "on": true})
	out.append({"id": TitlePage.ITEM_SETTINGS, "text": Strings.MENU_SETTINGS, "on": true})
	out.append({"id": TitlePage.ITEM_QUIT, "text": Strings.MENU_QUIT, "on": true})
	return out


func _build_menu() -> void:
	var font := load(UiTokens.FONT_REGULAR_PATH) as Font
	var y := MENU_ORIGIN.y
	var z := far_z + 0.01
	for item: Dictionary in menu_items():
		var l := Label3D.new()
		l.text = String(item["text"])
		l.font = font
		l.font_size = MENU_FONT_PX
		l.pixel_size = MENU_PIXEL
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.modulate = UiTokens.accent() if item["id"] == TitlePage.ITEM_DESCEND else (UiTokens.UI_FG if item["on"] else UiTokens.UI_DIM)
		l.position = Vector3(MENU_ORIGIN.x, y, z)
		l.name = "Menu_%s" % item["id"]
		add_child(l)
		menu_labels.append(l)
		if item["id"] == TitlePage.ITEM_DESCEND:
			descend_label = l
			_make_descend_target(l)
		y -= MENU_LINE_M


## DESCEND is pressed like any interactable (06 §7): the camera ray finds this body.
func _make_descend_target(l: Label3D) -> void:
	var body := StaticBody3D.new()
	body.name = "DescendTarget"
	body.collision_layer = PlayerLayers.INTERACTABLE_MASK
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, MENU_LINE_M, 0.1)
	shape.shape = bs
	body.add_child(shape)
	body.position = l.position + Vector3(0.5, 0.0, 0.05)
	add_child(body)
	descend_interactable = Interactable.new()
	descend_interactable.prompt = Strings.MENU_DESCEND
	body.add_child(descend_interactable)
	descend_interactable.interacted.connect(func(_p: Node) -> void: descend_chosen.emit())
