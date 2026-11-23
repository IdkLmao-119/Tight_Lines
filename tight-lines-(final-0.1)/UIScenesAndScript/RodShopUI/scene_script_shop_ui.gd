extends Control

signal close_requested

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
	_rod_shop.purchase_failed.connect(_notify_transaction)

	_bait_shop.switch_to_rods_requested.connect(_show_rod_shop)
	_bait_shop.back_requested.connect(show_choices)
	_bait_shop.item_purchased.connect(_on_bait_purchased)
	_bait_shop.purchase_failed.connect(_notify_transaction)

	_sell_fish_ui.set(&"sell_mode", true)
	_sell_fish_ui.back_requested.connect(show_choices)
	_sell_fish_ui.fish_sold.connect(_on_fish_sold)

	visibility_changed.connect(_on_visibility_changed)

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
	_add_wallet_icon()
	_sell_fish_button.grab_focus()


func close_shop() -> void:
	visible = false
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_method(&"set_context"):
		im.call(&"set_context", InputManager.InputContext.OVERWORLD)
	close_requested.emit()


func show_choices() -> void:
	_set_active_view(_choice_center)


func _set_active_view(active_view: Control) -> void:
	for view: Control in [_choice_center, _rod_shop, _bait_shop, _sell_fish_ui]:
		view.visible = (view == active_view)


func _on_sell_fish_pressed() -> void:
	_sell_fish_ui.set(&"sell_mode", true)
	_set_active_view(_sell_fish_ui)


func _show_rod_shop() -> void:
	_set_active_view(_rod_shop)


func _show_bait_shop() -> void:
	_set_active_view(_bait_shop)


func _notify_transaction(msg: String) -> void:
	var hud: Node = null
	if get_parent() != null:
		hud = get_parent().find_child("GameHUD", true, false)
	if hud == null and get_tree() != null and get_tree().current_scene != null:
		hud = get_tree().current_scene.find_child("GameHUD", true, false)
	if hud != null and hud.has_method(&"show_toast"):
		hud.call(&"show_toast", msg)


func _on_rod_purchased(rod_name: String, cost: int) -> void:
	_notify_transaction("Bought %s (-₱%d)" % [rod_name, cost])


func _on_bait_purchased(item_name: String, count: int, cost: int) -> void:
	_notify_transaction("Bought %s x%d (-₱%d)" % [item_name, count, cost])


func _on_fish_sold(fish_name: String, price: int) -> void:
	_notify_transaction("Sold %s (+₱%d)" % [fish_name, price])
