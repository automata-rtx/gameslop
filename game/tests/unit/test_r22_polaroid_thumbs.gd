extends TestCase
## R22: the Archive's Polaroid thumbnails (13 §5, 09 §4): the photos seen show as small
## pictures in the Statistics page, the unseen as empty outlined squares; the image comes
## from the game's own runtime source (`PolaroidPainter`), swappable by `PolaroidThumbs.capture`.

var _meta: MetaState
var _compact: bool


func before_all() -> void:
	_meta = GameState.meta
	_compact = UiTokens.compact


func after_all() -> void:
	GameState.meta = _meta
	UiTokens.compact = _compact
	PolaroidThumbs.capture = Callable()
	PolaroidThumbs.clear_cache()


func before_each() -> void:
	GameState.meta = MetaState.new()
	UiTokens.compact = false
	PolaroidThumbs.capture = Callable()
	PolaroidThumbs.clear_cache()


## A flat 40 x 40 "capture" of one colour per index, so a thumbnail's source is checkable.
static func _fake(index: int) -> Image:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1 * (index + 1), 0.5, 0.25, 1.0))
	return img


func test_thumbnail_comes_from_the_capture_source() -> void:
	var calls: Array[int] = []
	PolaroidThumbs.capture = func(i: int) -> Image:
		calls.append(i)
		return _fake(i)
	var t := PolaroidThumbs.texture_for(2)
	assert_not_null(t)
	assert_eq(t.get_width(), PolaroidThumbs.STORE_PX)
	var px := t.get_image().get_pixel(10, 10)
	assert_approx(px.r, 0.3, 0.02)
	assert_approx(px.g, 0.5, 0.02)
	# Cached: asking again does not capture again; an index wraps like the painter's.
	PolaroidThumbs.texture_for(2)
	PolaroidThumbs.texture_for(2 + PolaroidPainter.COUNT)
	assert_eq(calls, [2] as Array[int])
	# A source with nothing to give leaves the slot empty.
	PolaroidThumbs.clear_cache()
	PolaroidThumbs.capture = func(_i: int) -> Image: return null
	assert_null(PolaroidThumbs.texture_for(0))


func test_default_source_is_the_painted_photographs() -> void:
	var t := PolaroidThumbs.texture_for(5)
	assert_not_null(t)
	var want := PolaroidPainter.image(5).duplicate() as Image
	want.resize(PolaroidThumbs.STORE_PX, PolaroidThumbs.STORE_PX, Image.INTERPOLATE_LANCZOS)
	assert_eq(t.get_image().get_pixel(48, 48), want.get_pixel(48, 48))


func test_seen_photos_show_and_the_rest_are_empty_frames() -> void:
	PolaroidThumbs.capture = _fake
	var row := PolaroidThumbs.new()
	add_child(row)
	row.setup([1, 6] as Array[int])
	assert_eq(row.slots.size(), PolaroidPainter.COUNT)
	for i in row.slots.size():
		var seen := i == 1 or i == 6
		assert_eq(row.slots[i].texture != null, seen, "photo %d" % i)
		assert_eq(row.slots[i].get_child_count(), 0 if seen else 1, "photo %d outline" % i)
		assert_eq(row.slots[i].custom_minimum_size, Vector2(48, 48))
	row.queue_free()
	await await_frames(1)


func test_compact_menus_shrink_the_thumbnails() -> void:
	UiTokens.compact = true
	assert_eq(PolaroidThumbs.thumb_px(), 32)
	var row := PolaroidThumbs.new()
	add_child(row)
	row.setup([0] as Array[int])
	assert_eq(row.slots[0].custom_minimum_size, Vector2(32, 32))
	assert_eq(row.get_theme_constant(&"separation"), PolaroidThumbs.GAP_PX_COMPACT)
	row.queue_free()
	await await_frames(1)


func test_statistics_page_lists_the_seen_photographs() -> void:
	PolaroidThumbs.capture = _fake
	GameState.meta.polaroids_seen.assign([0, 3, 7])
	var page := ArchiveMenu.new()
	add_child(page)
	page.show_section(ArchiveMenu.SECTION_STATISTICS)
	var thumbs := page.body.get_node_or_null(^"PolaroidThumbs") as PolaroidThumbs
	assert_not_null(thumbs, "the Statistics page carries the thumbnails")
	var shown: Array[int] = []
	for s in thumbs.slots:
		if s.texture != null:
			shown.append(int(s.get_meta(&"photo")))
	assert_eq(shown, [0, 3, 7] as Array[int])
	# The other sections do not.
	page.show_section(ArchiveMenu.SECTION_ERRORS)
	assert_null(page.body.get_node_or_null(^"PolaroidThumbs"))
	page.queue_free()
	await await_frames(1)
