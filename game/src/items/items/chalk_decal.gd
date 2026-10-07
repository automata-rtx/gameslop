class_name ChalkDecal
extends Decal
## One chalk arrow (09 §9): a Decal 0.4 x 0.4 x 0.1 m, `#F2F2F2` arrow glyph with a slight
## roughness, emission 0.15 so it reads in the dark, rendered on world geometry only (visual
## layer 1). Decals are not the world shader, so unrender does not touch them (09 §9) and a
## stamped arrow stays visible through a Null's unrendering, as designed. Group `chalk`.

const GROUP := &"chalk"
const COLOR := Color("F2F2F2")
## Texture size in px; the arrow is drawn procedurally (no imported image, 02 T8).
const TEX_SIZE := 256
const WORLD_CULL_MASK := 1

static var _arrow: ImageTexture = null
static var _glow: ImageTexture = null
static var _serial: int = 0

## Stamp order, so the oldest can be removed first (a Dictionary-free counter).
var serial: int = 0


func _init() -> void:
	size = Vector3(Tuning.CHALK_DECAL_SIZE, Tuning.CHALK_DECAL_DEPTH, Tuning.CHALK_DECAL_SIZE)
	texture_albedo = arrow_texture()
	texture_emission = emission_texture()
	emission_energy = Tuning.CHALK_DECAL_EMISSION
	modulate = COLOR
	cull_mask = WORLD_CULL_MASK
	_serial += 1
	serial = _serial


func _enter_tree() -> void:
	add_to_group(GROUP)


## The arrow texture, pointing along the decal's -Z (the top of the image): a thick shaft and
## a head, edges wobbled by noise and the whole glyph speckled so it reads as chalk.
static func arrow_texture() -> ImageTexture:
	if _arrow == null:
		_arrow = ImageTexture.create_from_image(arrow_image())
	return _arrow


## The emission map: a decal's emission is not masked by the albedo's alpha, so the arrow is
## white on black here and the emission stays on the arrow only.
static func emission_texture() -> ImageTexture:
	if _glow == null:
		var img := arrow_texture().get_image()
		for y in TEX_SIZE:
			for x in TEX_SIZE:
				var a := img.get_pixel(x, y).a
				img.set_pixel(x, y, Color(a, a, a, 1.0))
		_glow = ImageTexture.create_from_image(img)
	return _glow


static func arrow_image() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var wobble := FastNoiseLite.new()
	wobble.seed = 41
	wobble.frequency = 0.045
	var grain := FastNoiseLite.new()
	grain.seed = 97
	grain.frequency = 0.9
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var px := float(x) + wobble.get_noise_2d(float(x), float(y)) * 9.0
			var py := float(y) + wobble.get_noise_2d(float(x) + 500.0, float(y)) * 9.0
			if not _in_arrow(px, py):
				continue
			var g := 0.78 + 0.22 * (grain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5)
			var holes := grain.get_noise_2d(float(x) + 300.0, float(y) + 300.0)
			var a := g if holes > -0.72 else g * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## The arrow shape in texture pixels: head from y=22 to y=122 (width 160), shaft below it.
static func _in_arrow(x: float, y: float) -> bool:
	if y < 22.0 or y > 236.0:
		return false
	if y <= 122.0:
		var half := (y - 22.0) / 100.0 * 82.0
		return absf(x - 128.0) <= half
	return absf(x - 128.0) <= 21.0


## The basis that lays the arrow on a surface (decals project along their local -Y, so Y is
## the surface normal and the arrow's tip, local -Z, points where the player faced).
## Floors and ceilings: the arrow points along the player's facing, yaw snapped to 45 degrees.
## Walls: ahead is up; the snapped angle between the player's facing and the wall's inward
## normal turns it left or right in the wall plane (a player facing a wall head-on stamps an
## up-arrow; a quarter turn to the right stamps a right-arrow).
static func arrow_basis(normal: Vector3, facing: Vector3) -> Basis:
	var n := normal.normalized()
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		f = Vector3(0.0, 0.0, -1.0)
	f = f.normalized()
	var snap := deg_to_rad(Tuning.CHALK_YAW_SNAP)
	var yaw := snappedf(atan2(-f.x, -f.z), snap)
	var snapped_f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var d: Vector3
	if absf(n.y) >= 0.7:
		d = snapped_f
	else:
		var into := Vector3(-n.x, 0.0, -n.z).normalized()
		var right := into.cross(Vector3.UP)
		var theta := snappedf(atan2(snapped_f.dot(right), snapped_f.dot(into)), snap)
		theta = clampf(theta, -PI * 0.5, PI * 0.5)
		d = Vector3.UP * cos(theta) + right * sin(theta)
	var z := (-d - n * (-d).dot(n)).normalized()
	var x := n.cross(z).normalized()
	return Basis(x, n, z)


## The facing direction the arrow tip points to, world space (-Z of the basis).
func tip_direction() -> Vector3:
	return -global_transform.basis.z
