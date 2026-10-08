class_name HudBelt
extends HBoxContainer
## The item belt, bottom-right (04 §6): four slots as `N GLYPH ×count`; empty slots show
## `—`. The selected slot has a 1 px ui_accent underline. Selecting pulses the glyph 1.15x
## for 100 ms; a count that decrements blinks ui_accent for 100 ms (11 §2).
## Reads slots duck-typed (09 Interfaces ItemSlot: `kind`, `count`; a Dictionary with the
## same keys also works) and each kind's ItemData glyph, falling back to the 04 §5 glyph
## of the same name while ItemData.glyph is unset.
## A slot whose item is live shows it after the count (M2.12): a burning flare its seconds
## of burn left (`40S`, FlareItem state `burn`), a radio switched on `ON` (RadioItem state
## `on`). The state is read every frame from the slot entry, so it needs no extra signal.

const SLOT_COUNT := 4
## Space between slots (three grid units).
const SLOT_GAP := UiTokens.GRID * 3
## The underline sits on the slot's bottom pixel row (the font's descent gap), inside the
## slot so the belt's shutter does not clip it.
const UNDERLINE_INSET := 1.0

var selected: int = -1
var _slots: Array[Slot] = []


class Slot extends HBoxContainer:
	var index: int = 0
	var kind: StringName = &""
	var count: int = 0
	var selected: bool = false
	var number: Label
	var glyph: TextureRect
	var count_label: Label
	## The item is live: a burning flare (seconds left) or a radio switched on.
	var status_label: Label
	var entry: Variant = null
	var pulse_t: float = INF
	var blink_t: float = INF

	func _init(i: int) -> void:
		index = i
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override(&"separation", UiTokens.GRID)
		number = Label.new()
		number.theme_type_variation = &"HudLabel"
		number.text = _split()[0].replace("{slot}", str(i + 1)).strip_edges()
		add_child(number)
		glyph = TextureRect.new()
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		glyph.custom_minimum_size = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE)
		glyph.pivot_offset = Vector2(UiTokens.GLYPH_SIZE, UiTokens.GLYPH_SIZE) * 0.5
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(glyph)
		count_label = Label.new()
		count_label.theme_type_variation = &"HudBody"
		add_child(count_label)
		status_label = Label.new()
		status_label.theme_type_variation = &"HudBody"
		status_label.visible = false
		add_child(status_label)

	## HUD_BELT_SLOT around its {glyph}: ["{slot} ", " ×{count}"].
	static func _split() -> PackedStringArray:
		var parts := Strings.HUD_BELT_SLOT.split("{glyph}")
		return parts if parts.size() == 2 else PackedStringArray(["{slot}", "×{count}"])

	func is_empty() -> bool:
		return kind == &"" or count <= 0

	func set_item(k: StringName, n: int) -> void:
		var decremented := k == kind and n < count and n > 0
		kind = k
		count = n
		if is_empty():
			glyph.texture = null
			glyph.visible = false
			count_label.text = Strings.HUD_BELT_EMPTY
		else:
			glyph.visible = true
			glyph.texture = HudBelt.glyph_for(k)
			count_label.text = _split()[1].replace("{count}", str(n)).strip_edges()
		if decremented:
			blink_t = 0.0
		_colour()
		refresh_status()

	## The live-item marker from the entry's state (FlareItem.BURN, RadioItem.ON).
	func status_text() -> String:
		if is_empty():
			return ""
		var st: Variant = HudBelt._field(entry, &"state", {})
		if not (st is Dictionary):
			return ""
		var burn := float((st as Dictionary).get(&"burn", 0.0))
		if burn > 0.0:
			return Strings.HUD_BELT_BURNING.replace("{seconds}", str(ceili(burn - 0.0001)))
		if bool((st as Dictionary).get(&"on", false)):
			return Strings.HUD_BELT_ON
		return ""

	func refresh_status() -> void:
		var t := status_text()
		if t != status_label.text:
			status_label.text = t
		status_label.visible = not t.is_empty()

	func select(on: bool) -> void:
		if on and not selected:
			pulse_t = 0.0
			glyph.scale = Vector2.ONE * UiMotion.PULSE_SCALE
		selected = on
		queue_redraw()

	func step(dt: float) -> void:
		var pulsing := pulse_t < UiMotion.BLINK_S
		var blinking := blink_t < UiMotion.BLINK_S
		pulse_t += dt
		blink_t += dt
		refresh_status()
		if pulsing:
			glyph.scale = Vector2.ONE * UiMotion.pulse(pulse_t)
		if blinking:
			_colour()

	func _colour() -> void:
		var c := UiTokens.UI_DIM if is_empty() else UiTokens.UI_FG
		if blink_t < UiMotion.BLINK_S:
			c = UiTokens.accent()
		count_label.add_theme_color_override(&"font_color", c)

	func _draw() -> void:
		if selected:
			draw_rect(Rect2(0.0, size.y - UNDERLINE_INSET, size.x, UiTokens.LINE), UiTokens.accent())


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", SLOT_GAP)
	for i in SLOT_COUNT:
		var s := Slot.new(i)
		s.name = "Slot%d" % (i + 1)
		_slots.append(s)
		add_child(s)
		s.set_item(&"", 0)


## The 04 Interfaces call: `slots` holds up to four ItemSlot-likes (null = empty).
func set_items(slots: Array, sel: int) -> void:
	for i in SLOT_COUNT:
		var entry: Variant = slots[i] if i < slots.size() else null
		_slots[i].entry = entry
		_slots[i].set_item(StringName(str(_field(entry, &"kind", ""))), int(_field(entry, &"count", 0)))
	selected = sel
	for i in SLOT_COUNT:
		_slots[i].select(i == sel)


## Redraws every slot (the underline after a 12 §6 accent change).
func queue_redraw_all() -> void:
	for s in _slots:
		s.queue_redraw()
		s._colour()


func slot(i: int) -> Slot:
	return _slots[i]


static func glyph_for(kind: StringName) -> Texture2D:
	var data := DataRegistry.item(kind)
	if data != null and data.glyph != null:
		return data.glyph
	if ResourceLoader.exists(UiTokens.glyph_path(kind)):
		return UiTokens.glyph(kind)
	return null


static func _field(entry: Variant, key: StringName, fallback: Variant) -> Variant:
	if entry == null:
		return fallback
	if entry is Dictionary:
		return (entry as Dictionary).get(key, (entry as Dictionary).get(String(key), fallback))
	if entry is Object:
		var v: Variant = (entry as Object).get(key)
		return fallback if v == null else v
	return fallback


func advance(dt: float) -> void:
	for s in _slots:
		s.step(dt)


func _process(delta: float) -> void:
	if not UiMotion.manual_clock:
		advance(delta)
