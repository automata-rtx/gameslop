extends SceneTree
## Renders the application icons from the hand-written `noclip` glyph (16 §2, 02 T8: no
## imported art). Writes res://assets/icon.png (256 px: the Linux and window icon) and
## res://assets/icon.ico (16 to 256 px, PNG-compressed entries: the Windows exe icon).
## Deterministic: the same glyph gives the same bytes, so the committed files only change
## when the glyph does. Run by tools/ci/export.sh:
##   $GODOT_BIN --headless --path game --script <repo>/tools/ci/icons.gd

const GLYPH := "res://assets/ui/glyphs/noclip.svg"
const OUT_PNG := "res://assets/icon.png"
const OUT_ICO := "res://assets/icon.ico"
const ICO_SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]
const PNG_SIZE := 256
## 04 §2: ui_fg glyph on ui_bg.
const BG := "#000000"


func _init() -> void:
	var code := 0
	var svg := icon_svg()
	if svg.is_empty():
		code = 1
	else:
		var png := render(svg, PNG_SIZE)
		if png == null or png.save_png(OUT_PNG) != OK:
			push_error("icons: could not write %s" % OUT_PNG)
			code = 1
		var entries: Array[PackedByteArray] = []
		for s in ICO_SIZES:
			var img := render(svg, s)
			if img == null:
				code = 1
				break
			entries.append(img.save_png_to_buffer())
		if code == 0 and not write_ico(OUT_ICO, ICO_SIZES, entries):
			code = 1
	if code == 0:
		print("icons: wrote %s and %s" % [OUT_PNG, OUT_ICO])
	quit(code)


## The glyph's paths over a filled square, as one SVG document.
func icon_svg() -> String:
	var src := FileAccess.get_file_as_string(GLYPH)
	var open := src.find("<svg")
	var body_start := src.find(">", open) + 1
	var body_end := src.rfind("</svg>")
	if open == -1 or body_start <= 0 or body_end <= body_start:
		push_error("icons: cannot read %s" % GLYPH)
		return ""
	var root := src.substr(open, body_start - open - 1)   # "<svg ..." without the ">"
	var body := src.substr(body_start, body_end - body_start)
	return "%s><rect x=\"0\" y=\"0\" width=\"24\" height=\"24\" fill=\"%s\" stroke=\"none\"/>%s</svg>" % [root, BG, body]


func render(svg: String, size: int) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg, float(size) / 24.0) != OK:
		push_error("icons: SVG render failed at %d px" % size)
		return null
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


## ICO container: ICONDIR, one ICONDIRENTRY per size, then the PNG payloads (little endian).
static func write_ico(path: String, sizes: Array[int], pngs: Array[PackedByteArray]) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("icons: could not write %s" % path)
		return false
	f.store_16(0)               # reserved
	f.store_16(1)               # type: icon
	f.store_16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var s := sizes[i]
		f.store_8(0 if s >= 256 else s)   # width (0 means 256)
		f.store_8(0 if s >= 256 else s)   # height
		f.store_8(0)            # palette colours
		f.store_8(0)            # reserved
		f.store_16(1)           # colour planes
		f.store_16(32)          # bits per pixel
		f.store_32(pngs[i].size())
		f.store_32(offset)
		offset += pngs[i].size()
	for png in pngs:
		f.store_buffer(png)
	f.close()
	return true
