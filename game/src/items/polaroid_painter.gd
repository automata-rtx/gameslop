class_name PolaroidPainter
extends RefCounted
## The eight Polaroid photographs (09 §4): "real world" images drawn procedurally as flat
## warm-colour shapes with a thin white border, deliberately naive. They are the only warm,
## saturated images in the game until the ending. 256 x 256, drawn straight into an Image
## (no viewport, so it also works headless), cached on first use.

const SIZE := Tuning.POLAROID_IMAGE_SIZE
const COUNT := Tuning.POLAROID_IMAGE_COUNT
const BORDER := 7

const NAMES: Array[StringName] = [
	&"kitchen_window", &"street_lamp", &"bedroom_lamp", &"yard_tree",
	&"bicycle", &"kettle", &"dog_on_sofa", &"hand_mug",
]

# Warm palette (flat colours).
const CREAM := Color("F4E3B8")
const BUTTER := Color("FFD66B")
const PEACH := Color("F2A672")
const RUST := Color("C8553D")
const BRICK := Color("A8442F")
const BROWN := Color("7A4A2A")
const DARK_BROWN := Color("3E2418")
const SAGE := Color("8FB36B")
const GRASS := Color("6FA04A")
const LEAF := Color("4F8A3A")
const SKY := Color("8EC9E8")
const GOLDEN_SKY := Color("F7C98B")
const DUSK := Color("F28F5C")
const NIGHT := Color("5A4A6E")
const TEAL := Color("4F9A94")
const SKIN := Color("E8A87C")
const WHITE := Color("FFFDF5")

static var _images: Dictionary = {}
static var _textures: Dictionary = {}


## Index 0..COUNT-1 for any integer (a seed).
static func index_for(seed_value: int) -> int:
	return posmod(seed_value, COUNT)


static func name_of(index: int) -> StringName:
	return NAMES[posmod(index, COUNT)]


## Paints every image now (a loading-time call; images are otherwise painted on first use).
static func warm() -> void:
	for i in COUNT:
		image(i)


static func image(index: int) -> Image:
	var i := posmod(index, COUNT)
	if not _images.has(i):
		_images[i] = _paint(i)
	return _images[i]


static func texture(index: int) -> ImageTexture:
	var i := posmod(index, COUNT)
	if not _textures.has(i):
		_textures[i] = ImageTexture.create_from_image(image(i))
	return _textures[i]


## Forgets the cache (tests).
static func clear_cache() -> void:
	_images.clear()
	_textures.clear()


static func _paint(i: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(CREAM)
	match i:
		0: _kitchen_window(img)
		1: _street_lamp(img)
		2: _bedroom_lamp(img)
		3: _yard_tree(img)
		4: _bicycle(img)
		5: _kettle(img)
		6: _dog_on_sofa(img)
		7: _hand_mug(img)
	# The thin white border.
	img.fill_rect(Rect2i(0, 0, SIZE, BORDER), WHITE)
	img.fill_rect(Rect2i(0, SIZE - BORDER, SIZE, BORDER), WHITE)
	img.fill_rect(Rect2i(0, 0, BORDER, SIZE), WHITE)
	img.fill_rect(Rect2i(SIZE - BORDER, 0, BORDER, SIZE), WHITE)
	return img


# --- scenes ------------------------------------------------------------------------------

static func _kitchen_window(img: Image) -> void:
	img.fill(PEACH.lightened(0.35))
	_rect(img, 0, 190, 256, 66, BROWN)                     # counter
	_rect(img, 0, 184, 256, 8, BROWN.lightened(0.25))
	_poly(img, [Vector2(78, 190), Vector2(178, 190), Vector2(236, 256), Vector2(30, 256)], BUTTER.lightened(0.2))
	_rect(img, 66, 40, 124, 132, WHITE)                    # frame
	for c in 2:
		for r in 2:
			_rect(img, 74 + c * 58, 48 + r * 62, 52, 56, BUTTER)
	_ellipse(img, 128, 100, 26, 26, WHITE.darkened(0.02))  # the sun
	_rect(img, 100, 150, 56, 4, WHITE)
	_rect(img, 196, 150, 30, 40, RUST)                     # a jar
	_rect(img, 192, 144, 38, 8, BRICK)
	_ellipse(img, 40, 172, 18, 14, SAGE)                   # a plant
	_rect(img, 28, 176, 24, 16, RUST)


static func _street_lamp(img: Image) -> void:
	img.fill(DUSK)
	_rect(img, 0, 0, 256, 70, DUSK.lightened(0.15))
	_rect(img, 0, 190, 256, 66, NIGHT.darkened(0.3))       # road
	_rect(img, 0, 176, 256, 16, NIGHT)                     # pavement
	_rect(img, 10, 80, 70, 100, NIGHT.darkened(0.2))       # houses
	_rect(img, 176, 60, 70, 120, NIGHT.darkened(0.35))
	for c in 2:
		for r in 3:
			_rect(img, 20 + c * 30, 92 + r * 28, 14, 16, BUTTER)
			_rect(img, 186 + c * 32, 76 + r * 34, 16, 18, BUTTER if (c + r) % 2 == 0 else NIGHT)
	_ellipse(img, 118, 66, 40, 40, BUTTER.lightened(0.3))  # the glow
	_rect(img, 114, 70, 8, 112, DARK_BROWN)                # pole
	_rect(img, 100, 62, 36, 8, DARK_BROWN)
	_ellipse(img, 118, 62, 12, 8, WHITE)
	_poly(img, [Vector2(114, 190), Vector2(122, 190), Vector2(150, 256), Vector2(86, 256)], BUTTER.darkened(0.15))


static func _bedroom_lamp(img: Image) -> void:
	img.fill(PEACH)
	_rect(img, 0, 196, 256, 60, BROWN)
	_rect(img, 0, 120, 190, 80, RUST)                      # bed
	_rect(img, 0, 100, 60, 40, WHITE)                      # pillow
	_rect(img, 0, 150, 190, 12, RUST.darkened(0.2))
	_rect(img, 200, 140, 46, 80, BROWN.lightened(0.15))    # nightstand
	_ellipse(img, 223, 80, 70, 64, BUTTER.lightened(0.2))  # the glow
	_poly(img, [Vector2(205, 112), Vector2(241, 112), Vector2(250, 84), Vector2(196, 84)], BUTTER)  # shade
	_rect(img, 220, 112, 6, 28, DARK_BROWN)
	_rect(img, 0, 30, 90, 60, SKY.darkened(0.35))          # a dark window
	_rect(img, 0, 30, 90, 4, WHITE)


static func _yard_tree(img: Image) -> void:
	img.fill(GOLDEN_SKY)
	_ellipse(img, 214, 44, 22, 22, BUTTER.lightened(0.3))
	_rect(img, 0, 170, 256, 86, GRASS)
	for k in 7:                                            # a fence
		_rect(img, 8 + k * 38, 142, 14, 56, WHITE)
	_rect(img, 0, 158, 256, 8, WHITE)
	_rect(img, 118, 100, 22, 110, BROWN)                   # trunk
	_ellipse(img, 128, 78, 66, 52, LEAF)
	_ellipse(img, 90, 98, 40, 32, LEAF.lightened(0.1))
	_ellipse(img, 166, 98, 42, 34, RUST.lightened(0.1))      # one turning leaf
	_ellipse(img, 128, 56, 36, 30, GRASS)
	_ellipse(img, 120, 218, 36, 8, GRASS.darkened(0.2))


static func _bicycle(img: Image) -> void:
	img.fill(BRICK.lightened(0.1))
	for r in 8:                                            # brick courses
		_rect(img, 0, r * 24, 256, 3, BRICK.darkened(0.15))
	_rect(img, 0, 196, 256, 60, CREAM.darkened(0.2))
	for w in [Vector2(78, 168), Vector2(184, 168)]:
		_ring(img, w, 40, 6, DARK_BROWN)
		_ellipse(img, int(w.x), int(w.y), 5, 5, DARK_BROWN)
	var crank := Vector2(128, 168)
	_line(img, Vector2(78, 168), Vector2(110, 118), 6, TEAL)
	_line(img, Vector2(110, 118), Vector2(160, 118), 6, TEAL)
	_line(img, Vector2(160, 118), Vector2(184, 168), 6, TEAL)
	_line(img, Vector2(110, 118), crank, 6, TEAL)
	_line(img, crank, Vector2(160, 118), 6, TEAL)
	_line(img, Vector2(78, 168), crank, 5, TEAL)
	_line(img, Vector2(160, 118), Vector2(154, 92), 6, TEAL)
	_line(img, Vector2(142, 92), Vector2(172, 92), 6, DARK_BROWN)
	_line(img, Vector2(110, 118), Vector2(106, 100), 5, DARK_BROWN)
	_ellipse(img, 106, 96, 18, 6, DARK_BROWN)
	_ellipse(img, 128, 222, 70, 6, DARK_BROWN.lightened(0.1))


static func _kettle(img: Image) -> void:
	img.fill(TEAL.lightened(0.15))
	_rect(img, 0, 176, 256, 80, BROWN)
	_rect(img, 0, 170, 256, 10, BROWN.lightened(0.25))
	_ellipse(img, 120, 128, 62, 52, RUST)                  # body
	_rect(img, 70, 126, 100, 46, RUST)
	_ellipse(img, 120, 172, 62, 8, RUST.darkened(0.25))
	_poly(img, [Vector2(168, 120), Vector2(214, 78), Vector2(224, 88), Vector2(176, 150)], RUST)  # spout
	_ring(img, Vector2(62, 118), 34, 8, DARK_BROWN)        # handle
	_ellipse(img, 120, 78, 28, 14, RUST.darkened(0.15))    # lid
	_ellipse(img, 120, 62, 8, 8, DARK_BROWN)
	_ellipse(img, 96, 118, 16, 26, PEACH.lightened(0.3))   # highlight
	for k in 3:                                            # steam
		_ellipse(img, 226 + k * 4, 62 - k * 18, 12 - k * 2, 8, WHITE)


static func _dog_on_sofa(img: Image) -> void:
	img.fill(PEACH.lightened(0.2))
	_rect(img, 0, 190, 256, 66, BROWN.darkened(0.2))
	_rect(img, 20, 100, 216, 100, RUST.darkened(0.15))     # back
	_rect(img, 10, 150, 236, 56, RUST)                     # seat
	_rect(img, 0, 120, 30, 90, RUST.darkened(0.3))         # arms
	_rect(img, 226, 120, 30, 90, RUST.darkened(0.3))
	_ellipse(img, 128, 142, 52, 28, DARK_BROWN)            # dog: body
	_ellipse(img, 70, 114, 26, 22, DARK_BROWN)             # head
	_poly(img, [Vector2(56, 100), Vector2(46, 70), Vector2(72, 94)], DARK_BROWN)
	_poly(img, [Vector2(78, 96), Vector2(92, 68), Vector2(94, 100)], DARK_BROWN)
	_ellipse(img, 46, 122, 10, 7, DARK_BROWN)              # snout
	_line(img, Vector2(172, 138), Vector2(208, 110), 10, DARK_BROWN)  # tail
	_rect(img, 96, 156, 12, 26, DARK_BROWN)
	_rect(img, 146, 156, 12, 26, DARK_BROWN)
	_rect(img, 150, 20, 70, 50, BUTTER.lightened(0.1))     # a frame on the wall
	_rect(img, 156, 26, 58, 38, SAGE)


static func _hand_mug(img: Image) -> void:
	img.fill(BUTTER.darkened(0.05))
	_rect(img, 0, 200, 256, 56, PEACH)
	_rect(img, 84, 90, 88, 100, TEAL)                      # mug
	_ellipse(img, 128, 92, 44, 12, TEAL.darkened(0.3))
	_ellipse(img, 128, 94, 38, 8, BROWN)
	_ring(img, Vector2(178, 140), 26, 9, TEAL)             # mug handle
	_ellipse(img, 88, 168, 30, 46, SKIN)                   # the hand: palm
	_rect(img, 20, 150, 74, 40, SKIN)                      # wrist and forearm
	for k in 4:                                            # fingers around the mug
		_ellipse(img, 150, 110 + k * 22, 28, 9, SKIN.darkened(0.04 * k))
	_ellipse(img, 98, 120, 12, 28, SKIN.lightened(0.05))   # thumb
	for k in 3:                                            # steam
		_ellipse(img, 112 + k * 16, 56 - (k % 2) * 14, 8, 14, WHITE)


# --- drawing primitives (flat fills) -------------------------------------------------------

static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


static func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(maxi(cy - ry, 0), mini(cy + ry + 1, SIZE)):
		var t := float(y - cy) / float(ry)
		var half := int(round(float(rx) * sqrt(maxf(1.0 - t * t, 0.0))))
		img.fill_rect(Rect2i(cx - half, y, half * 2 + 1, 1), c)


## A ring: outer radius `r`, line width `w`, centre `p`.
static func _ring(img: Image, p: Vector2, r: float, w: float, c: Color) -> void:
	var ri := r - w
	for y in range(maxi(int(p.y - r), 0), mini(int(p.y + r) + 1, SIZE)):
		var dy := float(y) - p.y
		if absf(dy) > r:
			continue
		var outer := sqrt(r * r - dy * dy)
		if absf(dy) >= ri:
			img.fill_rect(Rect2i(int(p.x - outer), y, int(outer * 2.0) + 1, 1), c)
		else:
			var inner := sqrt(ri * ri - dy * dy)
			img.fill_rect(Rect2i(int(p.x - outer), y, int(outer - inner) + 1, 1), c)
			img.fill_rect(Rect2i(int(p.x + inner), y, int(outer - inner) + 1, 1), c)


## Scanline fill of a simple polygon (even-odd).
static func _poly(img: Image, pts: Array, c: Color) -> void:
	var min_y := SIZE
	var max_y := 0
	for p: Vector2 in pts:
		min_y = mini(min_y, int(floor(p.y)))
		max_y = maxi(max_y, int(ceil(p.y)))
	for y in range(maxi(min_y, 0), mini(max_y + 1, SIZE)):
		var xs: Array[float] = []
		var n := pts.size()
		for k in n:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % n]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (float(y) - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := maxi(int(round(xs[k])), 0)
			var x1 := mini(int(round(xs[k + 1])), SIZE)
			if x1 > x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0, 1), c)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var d := (b - a)
	if d.length() < 0.001:
		return
	var n := d.orthogonal().normalized() * (width * 0.5)
	_poly(img, [a + n, b + n, b - n, a - n], c)
	_ellipse(img, int(a.x), int(a.y), int(width * 0.5), int(width * 0.5), c)
	_ellipse(img, int(b.x), int(b.y), int(width * 0.5), int(width * 0.5), c)
