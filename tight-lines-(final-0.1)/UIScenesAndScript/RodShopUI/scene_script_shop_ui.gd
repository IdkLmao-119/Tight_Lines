extends Control

signal close_requested

@onready var _money_label: Label = %MoneyLabel
@onready var _status_label: Label = %StatusLabel
@onready var _choice_center: Control = %ChoiceCenter
@onready var _sell_fish_button: Button = %SellFishButton
@onready var _buy_button: Button = %BuyButton
@onready var _close_button: Button = %CloseButton
@onready var _rod_shop: Control = %RodShop
@onready var _bait_shop: Control = %BaitShop
@onready var _sell_fish_ui: Control = %SellFishUI


func _ready() -> void:
	_sell_fish_button.pressed.connect(_on_sell_fish_pressed)
	_buy_button.pressed.connect(_show_rod_shop)
	_close_button.pressed.connect(close_shop)

	_rod_shop.switch_to_bait_requested.connect(_show_bait_shop)
	_rod_shop.back_requested.connect(show_choices)
	_rod_shop.rod_purchased.connect(_on_rod_purchased)
	_rod_shop.purchase_failed.connect(_set_status)

	_bait_shop.switch_to_rods_requested.connect(_show_rod_shop)
	_bait_shop.back_requested.connect(show_choices)
	_bait_shop.item_purchased.connect(_on_bait_purchased)
	_bait_shop.purchase_failed.connect(_set_status)

	_sell_fish_ui.set(&"sell_mode", true)
	_sell_fish_ui.back_requested.connect(show_choices)
	_sell_fish_ui.fish_sold.connect(_on_fish_sold)

	if SaveManager.has_signal(&"money_changed"):
		SaveManager.money_changed.connect(_update_money_label)
	visibility_changed.connect(_on_visibility_changed)

	_update_money_label(SaveManager.get_money())
	show_choices()


func _on_visibility_changed() -> void:
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_method(&"set_context"):
		im.call(&"set_context", InputManager.InputContext.MENU if visible else InputManager.InputContext.OVERWORLD)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if _choice_center.visible:
		close_shop()
	else:
		show_choices()


func open_shop() -> void:
	visible = true
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_method(&"set_context"):
		im.call(&"set_context", InputManager.InputContext.MENU)
	_update_money_label(SaveManager.get_money())
	show_choices()
	_sell_fish_button.grab_focus()


func close_shop() -> void:
	visible = false
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_method(&"set_context"):
		im.call(&"set_context", InputManager.InputContext.OVERWORLD)
	close_requested.emit()


func show_choices() -> void:
	_set_active_view(_choice_center, "Welcome! Would you like to sell fish or buy gear?")


func _set_active_view(active_view: Control, status_msg: String) -> void:
	for view: Control in [_choice_center, _rod_shop, _bait_shop, _sell_fish_ui]:
		view.visible = (view == active_view)
	_set_status(status_msg)


func _on_sell_fish_pressed() -> void:
	_sell_fish_ui.set(&"sell_mode", true)
	_set_active_view(_sell_fish_ui, "Select fish to sell for currency.")


func _show_rod_shop() -> void:
	_set_active_view(_rod_shop, "Browse rods or click 'Bait' at the top to switch to the Bait Shop.")


func _show_bait_shop() -> void:
	_set_active_view(_bait_shop, "Browse bait or click 'Rods' at the top to switch to the Rod Shop.")


func _update_money_label(amount: int) -> void:
	_money_label.text = "Pesos: ₱%d" % amount


func _set_status(msg: String) -> void:
	_status_label.text = msg


func _on_rod_purchased(rod_name: String, cost: int) -> void:
	_set_status("Bought & equipped %s for ₱%d!" % [rod_name, cost])


func _on_bait_purchased(item_name: String, count: int, cost: int) -> void:
	_set_status("Bought & equipped %s x%d for ₱%d!" % [item_name, count, cost])


func _on_fish_sold(fish_name: String, price: int) -> void:
	_set_status("Sold %s for +₱%d!" % [fish_name, price])
