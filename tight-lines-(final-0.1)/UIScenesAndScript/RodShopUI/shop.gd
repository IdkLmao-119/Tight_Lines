extends Control
## Simple shop UI (Godot 4.x). Attach to a Control node (shop.tscn does this).
## 5 items only, and each item can be bought just once.

var gold: int = 0
var owned: Array[String] = []

var items: Array[Dictionary] = [
	{"name": "MediumLight Rod",  "price": 0},
	{"name": "UltraLight Rod",  "price": 500},
	{"name": "Medium Rod",  "price": 2500},
	{"name": "MediumHeavy Rod",  "price": 5000},
	{"name": "Heavy Rod",  "price": 10000},
]

var gold_label: Label
var message_label: Label
var inventory_label: Label
var buy_buttons: Array[Button] = []


func _ready() -> void:
	# Fill the screen even if the parent isn't a Control
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not (get_parent() is Control):
		position = Vector2.ZERO
		size = get_viewport_rect().size
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.14)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Item Shop"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 18)
	header.add_child(gold_label)

	vbox.add_child(HSeparator.new())

	# The 5 item rows
	for i in items.size():
		vbox.add_child(_make_item_row(i))

	vbox.add_child(HSeparator.new())

	message_label = Label.new()
	message_label.text = "Welcome! Each item can only be bought once."
	vbox.add_child(message_label)

	inventory_label = Label.new()
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(inventory_label)


func _make_item_row(index: int) -> HBoxContainer:
	var item: Dictionary = items[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = item["name"]
	name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d G" % item["price"]
	row.add_child(price_label)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(90, 0)
	buy.pressed.connect(_on_buy_pressed.bind(index))
	row.add_child(buy)
	buy_buttons.append(buy)

	return row


func _on_buy_pressed(index: int) -> void:
	var item: Dictionary = items[index]
	var item_name: String = item["name"]
	var price: int = item["price"]

	if owned.has(item_name):
		message_label.text = "You already own %s." % item_name
		return
	if gold < price:
		message_label.text = "Not enough gold for %s!" % item_name
		return

	gold -= price
	owned.append(item_name)
	message_label.text = "Bought %s!" % item_name
	_refresh()


func _refresh() -> void:
	gold_label.text = "Gold: %d" % gold

	for i in items.size():
		var item: Dictionary = items[i]
		var btn := buy_buttons[i]
		if owned.has(item["name"]):
			btn.text = "Owned"
			btn.disabled = true
		else:
			btn.text = "Buy"
			btn.disabled = gold < int(item["price"])

	if owned.is_empty():
		inventory_label.text = "Inventory: (empty)"
	else:
		inventory_label.text = "Inventory: " + ", ".join(owned)
