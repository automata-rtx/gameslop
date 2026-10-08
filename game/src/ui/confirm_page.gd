class_name ConfirmPage
extends MenuPage
## A yes/no page (04 §7 pause: `This ends the run. Depth and notes found are kept.` with
## `ABANDON` / `BACK`). BACK is selected first, so a stray Enter never ends a run. BACK and
## Esc return to the previous page; the yes item emits `confirmed`.

signal confirmed

const ITEM_YES := &"yes"
const ITEM_NO := &"no"

var message: String = ""
var yes_text: String = ""
var no_text: String = Strings.PAUSE_ABANDON_NO
var _message_label: Label


func _init(page_title: String = "", text: String = "", yes: String = "") -> void:
	super()
	title = page_title
	message = text
	yes_text = yes


func build() -> void:
	list.add_item(ITEM_YES, yes_text)
	list.add_item(ITEM_NO, no_text)
	list.activated.connect(func(id: StringName) -> void:
		if id == ITEM_YES:
			confirmed.emit()
		else:
			back_requested.emit())
	_message_label = MenuPage.description_label(message)
	_message_label.theme_type_variation = &"MenuItemLabel"
	detail.add_child(_message_label)


func on_open() -> void:
	list.active = true
	list.selected = list.ids.find(ITEM_NO)
	list.active = true
