class_name LoadoutCards
extends VBoxContainer
## Loadout select inside the DESCEND detail column (04 §7, 05 §7): four cards in a row, only
## unlocked ones selectable (GameState.is_loadout_available). A card is a 1 px top rule (the
## one rule menus may draw), the name, and the starting items as glyphs with counts; the
## selected card's rule and name are ui_accent. The selected loadout's one-line description
## prints beneath the row (locked cards show their unlock condition instead). Left/right
## change the selection; a click selects.

signal selection_changed(id: StringName)

## M3.6: 192 px, so four cards fit the compact title's detail column (832 px).
const CARD_WIDTH := UiTokens.GRID * 24
const GLYPH_PX := UiTokens.GLYPH_SIZE

var ids: Array[StringName] = []
var selected: StringName = &"faller"
var _cards: Dictionary = {}
var _desc: Label


func _init() -> void:
	add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTokens.GRID * 2)
	add_child(row)
	for id in DataRegistry.LOADOUT_ORDER:
		ids.append(id)
		var card := _card(id)
		row.add_child(card)
		_cards[id] = card
	_desc = MenuPage.description_label("")
	_desc.custom_minimum_size.x = CARD_WIDTH * 4 + UiTokens.GRID * 6
	add_child(_desc)
	refresh()


func available(id: StringName) -> bool:
	return GameState.is_loadout_available(id)


## More than Faller is unlocked (04 §7 shows the selector only then).
static func has_choice() -> bool:
	for id in DataRegistry.LOADOUT_ORDER:
		if id != &"faller" and GameState.is_loadout_available(id):
			return true
	return false


func select(id: StringName) -> void:
	if not ids.has(id) or not available(id) or id == selected:
		return
	selected = id
	AudioManager.play_2d(&"ui_move")
	refresh()
	selection_changed.emit(id)


## Steps to the next available card left (-1) or right (+1). True when it moved.
func move(dir: int) -> bool:
	var i := ids.find(selected)
	var j := i + dir
	while j >= 0 and j < ids.size():
		if available(ids[j]):
			select(ids[j])
			return true
		j += dir
	return false


func refresh() -> void:
	if not available(selected):
		selected = &"faller"
	for id: StringName in _cards:
		var card: VBoxContainer = _cards[id]
		var on := id == selected
		var open := available(id)
		(card.get_child(0) as ColorRect).color = UiTokens.accent() if on else (UiTokens.UI_FG if open else UiTokens.UI_DIM)
		var name_label := card.get_child(1) as Label
		name_label.text = String(Strings.LOADOUT_NAMES.get(id, String(id).to_upper())) if open else Strings.LOADOUT_LOCKED
		UiTokens.paint(name_label, UiTokens.accent() if on else (UiTokens.UI_FG if open else UiTokens.UI_DIM))
		(card.get_child(2) as Control).modulate = Color.WHITE if open else Color(1, 1, 1, 0.35)
	_desc.text = String(Strings.LOADOUT_DESCRIPTIONS.get(selected, ""))


func _card(id: StringName) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.add_theme_constant_override(&"separation", UiTokens.GRID)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var rule := ColorRect.new()
	rule.custom_minimum_size.y = UiTokens.hairline()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)
	var name_label := Label.new()
	name_label.theme_type_variation = &"MenuItemLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)
	var glyphs := HBoxContainer.new()
	glyphs.add_theme_constant_override(&"separation", UiTokens.GRID)
	glyphs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kit := DataRegistry.loadout(id)
	if kit != null:
		for kind: StringName in kit.start_items:
			var tex := TextureRect.new()
			tex.texture = UiTokens.glyph(kind)
			tex.custom_minimum_size = Vector2(GLYPH_PX, GLYPH_PX)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyphs.add_child(tex)
			var count := Label.new()
			count.theme_type_variation = &"Description"
			count.text = "×%d" % int(kit.start_items[kind])
			count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyphs.add_child(count)
	card.add_child(glyphs)
	var cond := MenuPage.description_label("" if available(id) else String(Strings.LOADOUT_UNLOCK_CONDITIONS.get(id, "")))
	cond.custom_minimum_size.x = CARD_WIDTH
	cond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cond)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select(id))
	return card
