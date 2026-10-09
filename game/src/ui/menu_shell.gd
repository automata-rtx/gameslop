class_name MenuShell
extends Control
## The one menu frame every menu shares (04 §7, 04 Interfaces `MenuShell`): black background
## (or the pause overlay's 70% black over the frozen frame), a title line at the top-left
## (28 px Bold), a 1 px rule under it, and the open page's left column list and right column
## detail. Pages are MenuPage children registered by id; open() pushes, Esc goes back one
## page (unless the page used it), back past the first page emits `closed`. Pages appear with
## the shutter (04 §4), never a fade. Runs while the tree is paused (the pause menu).

signal opened(id: StringName)
## Esc on the first page, or close().
signal closed

## Margin of the frame at 1080p (8 px grid, outside the 32 px safe area).
const MARGIN := UiTokens.GRID * 8
## M3.6: below COMPACT_HEIGHT logical pixels (UI scale above 1.0 at 1080p, any scale at
## 720p) the frame keeps only the 32 px safe area (04 §4).
const MARGIN_COMPACT := UiTokens.SAFE_MARGIN
const COMPACT_HEIGHT := UiTokens.COMPACT_HEIGHT
const HEADER_GAP := UiTokens.GRID * 3
## The pause overlay starts below the HUD's top readouts (Coherence, depth) it dims.
const OVERLAY_TOP := UiTokens.GRID * 16
## Compact: the HUD's top readouts end 82 px down (32 px margin, two lines).
const OVERLAY_TOP_COMPACT := UiTokens.GRID * 12

## Pause: the frozen frame shows through a 70% black (04 §7). Otherwise full black.
var overlay: bool = false:
	set(v):
		overlay = v
		if _bg != null:
			_bg.color = UiTokens.PAUSE_OVERLAY if v else UiTokens.UI_BG
		_apply_margins()
var pages: Dictionary = {}
var stack: Array[StringName] = []

var _bg: ColorRect
var _frame: MarginContainer
var _header: VBoxContainer
var _title: Label
var _body: Control
var _shutters: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.color = UiTokens.UI_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var frame := MarginContainer.new()
	_frame = frame
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_apply_margins()
	resized.connect(_apply_margins)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", HEADER_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)
	_header = VBoxContainer.new()
	_header.add_theme_constant_override(&"separation", UiTokens.GRID)
	col.add_child(_header)
	_title = Label.new()
	_title.theme_type_variation = &"MenuHeading"
	_header.add_child(_title)
	var rule := ColorRect.new()
	rule.color = UiTokens.UI_FG
	rule.custom_minimum_size.y = UiTokens.hairline()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(rule)
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)
	visible = false


## M3.6: the colour of the shell's background (UI_BG; the title's live corridor shows through
## MENU_TITLE_BACKDROP_ALPHA black). `overlay` sets it too.
func set_backdrop(color: Color) -> void:
	if _bg != null:
		_bg.color = color


## True while the logical viewport is short enough for the compact frame (M3.6).
func is_compact() -> bool:
	return size.y > 0.0 and size.y < COMPACT_HEIGHT


func _apply_margins() -> void:
	if _frame == null:
		return
	if size.y > 0.0 and is_compact() != UiTokens.compact:
		UiTokens.compact = is_compact()
		for id: StringName in pages:
			(pages[id] as MenuPage).apply_compact()
	var m := MARGIN_COMPACT if is_compact() else MARGIN
	for side in [&"margin_left", &"margin_right", &"margin_bottom"]:
		_frame.add_theme_constant_override(side, m)
	var top := m
	if overlay:
		top = OVERLAY_TOP_COMPACT if is_compact() else OVERLAY_TOP
	_frame.add_theme_constant_override(&"margin_top", top)


## Registers `page` under `id` (it becomes a hidden child of the body).
func register(id: StringName, page: MenuPage) -> void:
	var sh := UiShutter.new()
	sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_child(sh)
	# M3.6: a page wider or taller than the frame (UI scale 1.5 on a 5:4 screen) scales down.
	var fit := UiFitBox.new()
	sh.add_child(fit)
	fit.add_child(page)
	pages[id] = page
	_shutters[id] = sh
	page.open_requested.connect(open)
	page.back_requested.connect(back)


func page(id: StringName) -> MenuPage:
	return pages.get(id)


func current_id() -> StringName:
	return stack[-1] if not stack.is_empty() else &""


func current() -> MenuPage:
	return pages.get(current_id())


func is_open() -> bool:
	return visible and not stack.is_empty()


## Opens page `id` on top of the current one (the title line follows it).
func open(id: StringName) -> void:
	if not pages.has(id):
		push_error("MenuShell: no page %s" % id)
		return
	if not stack.is_empty() and stack[-1] == id:
		return
	stack.append(id)
	_show_top()


## Replaces the whole stack with `id` (a menu opened from outside).
func open_root(id: StringName) -> void:
	stack.clear()
	open(id)


## One page back; past the first page the shell closes.
func back() -> void:
	if stack.is_empty():
		return
	AudioManager.play_2d(&"ui_back")
	stack.pop_back()
	if stack.is_empty():
		close()
	else:
		_show_top()


## Shows the shell again on its current page with the shutter (after the boot line).
func reveal() -> void:
	if stack.is_empty():
		return
	_show_top()


func close() -> void:
	stack.clear()
	for id: StringName in _shutters:
		(_shutters[id] as UiShutter).show_now(false)
	visible = false
	closed.emit()


func _show_top() -> void:
	visible = true
	var id := stack[-1]
	var p: MenuPage = pages[id]
	p.ensure_built()
	for other: StringName in _shutters:
		if other != id:
			(_shutters[other] as UiShutter).show_now(false)
	_title.text = p.title
	_header.visible = p.show_header
	p.on_open()
	(_shutters[id] as UiShutter).shutter_in()
	opened.emit(id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	var p := current()
	if p != null and p.handle_cancel():
		return
	back()
