extends Control

@onready var choice_panel: Panel = $ChoicePanel
@onready var sell_fish_button: Button = $ChoicePanel/VBoxContainer/SellFishButton
@onready var buy_button: Button = $ChoicePanel/VBoxContainer/BuyButton
@onready var close_button: Button = $ChoicePanel/VBoxContainer/CloseButton

@onready var rod_shop: Control = $RodShop
@onready var bait_shop: Control = $BaitShop
@onready var sell_fish_ui: Control = $SellFishUI

@onready var money_label: Label = $TopBar/MoneyLabel
@onready var status_label: Label = $TopBar/StatusLabel


func _ready() -> void:
	sell_fish_button.pressed.connect(_on_sell_fish_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	close_button.pressed.connect(close_shop)

	if rod_shop != null:
		if rod_shop.has_signal("switch_to_bait_requested"):
			rod_shop.connect("switch_to_bait_requested", _show_bait_shop)
		if rod_shop.has_signal("back_requested"):
			rod_shop.connect("back_requested", show_choices)
		if rod_shop.has_signal("rod_purchased"):
			rod_shop.connect("rod_purchased", _on_rod_purchased)
		if rod_shop.has_signal("purchase_failed"):
			rod_shop.connect("purchase_failed", _set_status)

	if bait_shop != null:
		if bait_shop.has_signal("switch_to_rods_requested"):
			bait_shop.connect("switch_to_rods_requested", _show_rod_shop)
		if bait_shop.has_signal("back_requested"):
			bait_shop.connect("back_requested", show_choices)
		if bait_shop.has_signal("item_purchased"):
			bait_shop.connect("item_purchased", _on_bait_purchased)
		if bait_shop.has_signal("purchase_failed"):
			bait_shop.connect("purchase_failed", _set_status)

	if sell_fish_ui != null:
		sell_fish_ui.set("sell_mode", true)
		if sell_fish_ui.has_signal("back_requested"):
			sell_fish_ui.connect("back_requested", show_choices)
		if sell_fish_ui.has_signal("fish_sold"):
			sell_fish_ui.connect("fish_sold", _on_fish_sold)

	if SaveManager.has_signal("money_changed"):
		SaveManager.money_changed.connect(_update_money_label)

	_update_money_label(SaveManager.get_money() if SaveManager.has_method("get_money") else 0)
	show_choices()


func open_shop() -> void:
	visible = true
	_update_money_label(SaveManager.get_money() if SaveManager.has_method("get_money") else 0)
	show_choices()


func close_shop() -> void:
	visible = false


func show_choices() -> void:
	choice_panel.visible = true
	rod_shop.visible = false
	bait_shop.visible = false
	sell_fish_ui.visible = false
	_set_status("Welcome! Would you like to sell fish or buy gear?")


func _on_sell_fish_pressed() -> void:
	choice_panel.visible = false
	rod_shop.visible = false
	bait_shop.visible = false
	sell_fish_ui.set("sell_mode", true)
	sell_fish_ui.visible = true
	_set_status("Select fish to sell for currency.")


func _on_buy_pressed() -> void:
	_show_rod_shop()


func _show_rod_shop() -> void:
	choice_panel.visible = false
	sell_fish_ui.visible = false
	bait_shop.visible = false
	rod_shop.visible = true
	_set_status("Browse rods or click 'Bait' at the top to switch to the Bait Shop.")


func _show_bait_shop() -> void:
	choice_panel.visible = false
	sell_fish_ui.visible = false
	rod_shop.visible = false
	bait_shop.visible = true
	_set_status("Browse bait or click 'Rods' at the top to switch to the Rod Shop.")


func _update_money_label(amount: int) -> void:
	if money_label != null:
		money_label.text = "Money: %d G" % amount


func _set_status(msg: String) -> void:
	if status_label != null:
		status_label.text = msg


func _on_rod_purchased(rod_name: String, cost: int) -> void:
	_set_status("Bought & equipped %s for %d G!" % [rod_name, cost])


func _on_bait_purchased(item_name: String, count: int, cost: int) -> void:
	_set_status("Bought & equipped %s x%d for %d G!" % [item_name, count, cost])


func _on_fish_sold(fish_name: String, price: int) -> void:
	_set_status("Sold %s for +%d G!" % [fish_name, price])
