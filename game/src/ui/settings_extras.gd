class_name SettingsExtras
extends RefCounted
## The two live helpers of the settings detail column: the brightness test strip (12 §2:
## 8 greys and "the darkest bar should be barely visible") and the mouse sensitivity TEST
## square (04 §7: a 200 px square with a dot that moves with the mouse at the chosen
## sensitivity). Both read SettingsManager each frame they draw.


static func brightness_strip() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTokens.GRID)
	box.add_child(BrightnessBars.new())
	box.add_child(MenuPage.description_label(Strings.SETTINGS_BRIGHTNESS_TEST))
	return box


static func sensitivity_test() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTokens.GRID)
	var l := Label.new()
	l.theme_type_variation = &"DimLabel"
	l.text = Strings.SETTINGS_SENS_TEST
	box.add_child(l)
	box.add_child(SensitivitySquare.new())
	return box


## Eight dark greys, scaled by the brightness setting as the Environment's
## adjustment_brightness scales the world.
class BrightnessBars extends Control:
	const BARS := Tuning.SETTINGS_BRIGHTNESS_TEST_BARS
	const BAR := Vector2(UiTokens.GRID * 8, UiTokens.GRID * 4)
	## Linear grey of the brightest bar at brightness 1.0; the darkest is 1/8 of it.
	const TOP_GREY := 0.16

	func _init() -> void:
		custom_minimum_size = Vector2(BAR.x * BARS + UiTokens.GRID * (BARS - 1), BAR.y)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		SettingsManager.changed.connect(_on_changed)

	func _on_changed(k: StringName, _v: Variant) -> void:
		if k == &"brightness":
			queue_redraw()

	static func grey(i: int, brightness: float) -> float:
		return clampf(TOP_GREY * float(i + 1) / BARS * brightness, 0.0, 1.0)

	func _draw() -> void:
		var b := float(SettingsManager.get_value(&"brightness"))
		for i in BARS:
			var g := grey(i, b)
			var c := Color(g, g, g).linear_to_srgb()
			draw_rect(Rect2(Vector2(i * (BAR.x + UiTokens.GRID), 0), BAR), c)


## The dot moves by the mouse motion over the square times the sensitivity and wraps.
class SensitivitySquare extends Control:
	const SIZE := Tuning.SETTINGS_SENS_TEST_SIZE
	const DOT := UiTokens.GRID / 2
	var dot: Vector2 = Vector2(SIZE, SIZE) * 0.5

	func _init() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS

	func move_by(relative: Vector2) -> void:
		var s := float(SettingsManager.get_value(&"mouse_sensitivity"))
		var inv := -1.0 if bool(SettingsManager.get_value(&"invert_y")) else 1.0
		dot += Vector2(relative.x, relative.y * inv) * s
		dot = Vector2(fposmod(dot.x, SIZE), fposmod(dot.y, SIZE))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			move_by((event as InputEventMouseMotion).relative)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
		draw_rect(r, UiTokens.UI_DIM, false, UiTokens.LINE)
		draw_line(Vector2(SIZE * 0.5, 0), Vector2(SIZE * 0.5, SIZE), Color(UiTokens.UI_DIM, 0.35), UiTokens.LINE)
		draw_line(Vector2(0, SIZE * 0.5), Vector2(SIZE, SIZE * 0.5), Color(UiTokens.UI_DIM, 0.35), UiTokens.LINE)
		draw_rect(Rect2(dot - Vector2(DOT, DOT) * 0.5, Vector2(DOT, DOT)), UiTokens.UI_FG)
