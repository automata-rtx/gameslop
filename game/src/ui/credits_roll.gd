class_name CreditsRoll
extends Control
## The credits rolling over the ending corridor (01 §8 step 4, 16 §6): one centred column
## on a ui_backing band (04 §2, the readout's backing, so white text reads over daylight),
## scrolling up at ENDING_CREDITS_SPEED from below the screen until "Thank you for looking."
## stands at the centre; it holds there ENDING_THANKS_HOLD, then `finished`. Typography (04
## §2): the disclosure and section lines at menu size in ui_fg, headings in ui_dim, notices
## and the component list (two wrapped columns) at HUD size in ui_dim. Driven by advance(dt) from the
## Ending so tests can step it; it never processes on its own.

signal finished

const COLUMN_WIDTH := UiTokens.GRID * 120
const GAP_UNITS := 6
const THANKS_GAP_UNITS := 24
## The 1080p layout (04 §2) when the roll has no size yet (headless, before the first frame).
const REFERENCE_SIZE := Vector2(1920.0, 1080.0)

var column: VBoxContainer
var band: ColorRect
var thanks: Label
## Pixels the column has risen since start().
var scrolled: float = 0.0
var running: bool = false
var holding: float = -1.0
var done: bool = false
var speed: float = Tuning.ENDING_CREDITS_SPEED
var _grid: GridContainer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	band = ColorRect.new()
	band.color = UiTokens.UI_BACKING
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", UiTokens.GRID)
	column.custom_minimum_size.x = COLUMN_WIDTH
	add_child(column)
	for e in Credits.entries():
		_add_entry(e)
	visible = false


func _add_entry(e: Dictionary) -> void:
	var style: StringName = e["style"]
	if style != Credits.STYLE_COMPONENT:
		_grid = null
	match style:
		Credits.STYLE_GAP:
			var c := Control.new()
			c.custom_minimum_size.y = UiTokens.GRID * GAP_UNITS
			column.add_child(c)
		Credits.STYLE_COMPONENT:
			if _grid == null:
				_grid = GridContainer.new()
				_grid.columns = 2
				_grid.add_theme_constant_override(&"h_separation", UiTokens.GRID * 4)
				_grid.add_theme_constant_override(&"v_separation", 0)
				column.add_child(_grid)
			var l := _label(String(e["text"]), &"TitleSubline", true)
			l.custom_minimum_size.x = (COLUMN_WIDTH - UiTokens.GRID * 4) * 0.5
			_grid.add_child(l)
		Credits.STYLE_HEADING:
			column.add_child(_label(String(e["text"]), &"DimLabel", true))
		Credits.STYLE_SMALL:
			column.add_child(_label(String(e["text"]), &"TitleSubline", true))
		Credits.STYLE_THANKS:
			var c := Control.new()
			c.custom_minimum_size.y = UiTokens.GRID * THANKS_GAP_UNITS
			column.add_child(c)
			thanks = _label(String(e["text"]), &"MenuItemLabel", true)
			thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(thanks)
		_:
			column.add_child(_label(String(e["text"]), &"MenuItemLabel", true))


func _label(t: String, variation: StringName, wrap: bool) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = COLUMN_WIDTH
	return l


## Begins the roll from just below the screen.
func start() -> void:
	visible = true
	running = true
	scrolled = 0.0
	holding = -1.0
	done = false
	_layout()


func is_finished() -> bool:
	return done


## Every label the roll prints (tests).
func printed_text() -> String:
	var out := PackedStringArray()
	for n in column.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return "\n".join(out)


## Where the column has to rise to for the last line to stand at the screen's centre.
func stop_scroll() -> float:
	var h := size.y if size.y > 0.0 else REFERENCE_SIZE.y
	var thanks_mid := thanks.position.y + thanks.size.y * 0.5 if thanks != null else column.size.y
	return h * 0.5 + thanks_mid


func advance(dt: float) -> void:
	if not running or done:
		return
	if holding >= 0.0:
		holding += dt
		if holding >= Tuning.ENDING_THANKS_HOLD:
			done = true
			running = false
			finished.emit()
		return
	scrolled += speed * dt
	var stop := stop_scroll()
	if scrolled >= stop:
		scrolled = stop
		holding = 0.0
	_layout()


func _layout() -> void:
	var w := size.x if size.x > 0.0 else REFERENCE_SIZE.x
	var h := size.y if size.y > 0.0 else REFERENCE_SIZE.y
	column.size.x = COLUMN_WIDTH
	column.position = Vector2(roundf((w - COLUMN_WIDTH) * 0.5), roundf(h - scrolled))
	var pad := UiTokens.GRID * 4
	band.position = Vector2(column.position.x - pad, 0.0)
	band.size = Vector2(COLUMN_WIDTH + pad * 2.0, h)
