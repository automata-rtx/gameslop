class_name GlitchTransition
extends CanvasLayer
## The 120 ms glitch between screens (04 §4, GLOSSARY): the previous frame is held, sliced
## horizontally into 8 to 14 bands offset by ±12 px with CA 0.02, then cut. SceneRouter calls
## play(&"out") before the swap and play(&"in") after it (its `transition` hook); main.gd
## assigns it. Cosmetic: band layout from a hash of the frame count, never gameplay RNG.

const LAYER := 100

var _view: _Bands


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = _Bands.new()
	add_child(_view)


## &"out": hold the frame and glitch it for 120 ms. &"in": cut to the new scene.
func play(phase: StringName) -> void:
	if phase == &"out":
		_view.capture(get_viewport())
		AudioManager.play_2d(&"ui_glitch_transition")
		await Clock.wall_timer(UiTokens.GLITCH_S).timeout
	else:
		_view.release()


func is_holding() -> bool:
	return _view.visible


class _Bands extends Control:
	var tex: Texture2D
	var seed_value: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false

	func capture(vp: Viewport) -> void:
		tex = null
		if vp != null and DisplayServer.get_name() != "headless":
			var img := vp.get_texture().get_image()
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		seed_value = Engine.get_process_frames()
		visible = true
		queue_redraw()

	func release() -> void:
		visible = false
		tex = null

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		if tex == null:
			return
		var bands := UiTokens.GLITCH_BANDS_MIN + absi(hash(seed_value)) % (UiTokens.GLITCH_BANDS_MAX - UiTokens.GLITCH_BANDS_MIN + 1)
		var h := size.y / bands
		var th := float(tex.get_height()) / bands
		var ca := UiTokens.GLITCH_CA * size.x * 0.1
		for b in bands:
			var off := float(absi(hash(seed_value * 31 + b)) % (UiTokens.GLITCH_OFFSET_PX * 2 + 1) - UiTokens.GLITCH_OFFSET_PX)
			var dst := Rect2(Vector2(off, b * h), Vector2(size.x, h))
			var src := Rect2(Vector2(0, b * th), Vector2(tex.get_width(), th))
			draw_texture_rect_region(tex, Rect2(dst.position + Vector2(ca, 0), dst.size), src, Color(1, 0, 0, 0.5))
			draw_texture_rect_region(tex, Rect2(dst.position - Vector2(ca, 0), dst.size), src, Color(0, 0.5, 1, 0.5))
			draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 0.6))
