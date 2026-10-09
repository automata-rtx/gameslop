class_name PolaroidThumbs
extends HBoxContainer
## The Archive's Polaroid thumbnails (13 §5, 09 §4, 04 §7): one small square per photograph, the
## ones the player has held up drawn as the photo itself, the rest an empty outlined square
## (the Archive's `··` for what is not found yet). The photos are the images the game paints
## at runtime (`PolaroidPainter`, 09 §4), shrunk to `STORE_PX` once and cached; no file is
## imported (02 T8). `capture` swaps the image source (tests, a future real capture path).
## Sizes (R22 ruling, 04 §7 gives none): 48 px, 32 px when menus are compact, 8 px apart.

const STORE_PX := 96
const GAP_PX := 8
const GAP_PX_COMPACT := 4

## Image source: Callable(index: int) -> Image. Empty means `PolaroidPainter.image`.
static var capture: Callable = Callable()
static var _cache: Dictionary = {}

var slots: Array[TextureRect] = []


## Thumbnail size now: UiTokens.row_height() is 40 or 32; a thumbnail is 48 or 32.
static func thumb_px() -> int:
	return UiTokens.GRID * 6 if not UiTokens.compact else UiTokens.MENU_ROW_HEIGHT_COMPACT


## The thumbnail texture of photo `index` (cached; null if the source gives no image).
static func texture_for(index: int) -> Texture2D:
	var i := posmod(index, PolaroidPainter.COUNT)
	if not _cache.has(i):
		var src: Image = capture.call(i) if capture.is_valid() else PolaroidPainter.image(i)
		if src == null or src.is_empty():
			return null
		var img := src.duplicate() as Image
		img.resize(STORE_PX, STORE_PX, Image.INTERPOLATE_LANCZOS)
		_cache[i] = ImageTexture.create_from_image(img)
	return _cache[i]


static func clear_cache() -> void:
	_cache.clear()


## One slot per photograph; `seen` holds the photo indices found (`meta.polaroids_seen`).
func setup(seen: Array) -> void:
	for s in slots:
		s.queue_free()
	slots.clear()
	add_theme_constant_override(&"separation", GAP_PX_COMPACT if UiTokens.compact else GAP_PX)
	var px := thumb_px()
	for i in PolaroidPainter.COUNT:
		var slot := TextureRect.new()
		slot.name = "Photo%d" % i
		slot.custom_minimum_size = Vector2(px, px)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		slot.set_meta(&"photo", i)
		if seen.has(i):
			slot.texture = texture_for(i)
		slot.set_meta(&"seen", slot.texture != null)
		if slot.texture == null:
			slot.add_child(_empty_frame())
		add_child(slot)
		slots.append(slot)


## The 1 px `ui_dim` outline of a photograph not yet seen.
static func _empty_frame() -> Panel:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(1)
	sb.border_color = UiTokens.UI_DIM
	p.add_theme_stylebox_override(&"panel", sb)
	return p
