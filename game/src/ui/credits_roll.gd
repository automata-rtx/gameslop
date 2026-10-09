class_name CreditsRoll
extends Control
## The credits rolling over the ending corridor (01 §8 step 4, 16 §6): one centred column of
## 16 §6's lines (Credits.roll_entries(); the full license texts live on the LICENSES page,
## R17) over the corridor, with no panel: each line sits on its own 60% black backing, tight
## to the text, as captions do (04 §2: backing only where the world makes text unreadable;
## the ending's white walls and window do), so the corridor shows between and around the
## lines. It scrolls up at ENDING_CREDITS_SPEED from below the screen until "Thank you for
## looking." stands at the centre, holds there ENDING_THANKS_HOLD, then `finished`.
## Typography (04 §2): lines at menu size, the copyright and the LICENSES.txt line at HUD size,
## all ui_fg (ui_dim does not read on a backing over white). Driven by advance(dt) from the
## Ending so tests can step it; it never processes on its own.

signal finished

const COLUMN_WIDTH := UiTokens.GRID * 120
const GAP_UNITS := 6
const THANKS_GAP_UNITS := 24
## The 1080p layout (04 §2) when the roll has no size yet (headless, before the first frame).
const REFERENCE_SIZE := Vector2(1920.0, 1080.0)

var column: VBoxContainer
var thanks: Label
## The last line's backing (the line that stops at the centre).
var thanks_box: PanelContainer
## Pixels the column has risen since start().
var scrolled: float = 0.0
var running: bool = false
var holding: float = -1.0
var done: bool = false
var speed: float = Tuning.ENDING_CREDITS_SPEED


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", UiTokens.GRID)
	column.custom_minimum_size.x = COLUMN_WIDTH
	add_child(column)
	for e in Credits.roll_entries():
		_add_entry(e)
	visible = false


func _add_entry(e: Dictionary) -> void:
	var style: StringName = e["style"]
	match style:
		Credits.STYLE_GAP:
			var c := Control.new()
			c.custom_minimum_size.y = UiTokens.GRID * GAP_UNITS
			column.add_child(c)
		Credits.STYLE_SMALL:
			column.add_child(_line(String(e["text"]), &"HudBody"))
		Credits.STYLE_THANKS:
			var c := Control.new()
			c.custom_minimum_size.y = UiTokens.GRID * THANKS_GAP_UNITS
			column.add_child(c)
			thanks_box = _line(String(e["text"]), &"MenuItemLabel")
			thanks = thanks_box.get_child(0) as Label
			column.add_child(thanks_box)
		_:
			column.add_child(_line(String(e["text"]), &"MenuItemLabel"))


## One line on its own backing, centred in the column.
static func _line(t: String, variation: StringName) -> PanelContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = &"Backing"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return box


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
	var thanks_mid := thanks_box.position.y + thanks_box.size.y * 0.5 if thanks_box != null else column.size.y
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
	var cw := maxf(COLUMN_WIDTH, column.get_combined_minimum_size().x)
	column.size.x = cw
	column.position = Vector2(roundf((w - cw) * 0.5), roundf(h - scrolled))
