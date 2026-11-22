extends Control

signal switch_to_bait_requested
signal back_requested
signal rod_purchased(rod_name: String, cost: int)
signal purchase_failed(reason: String)

const ITEM_CARD_SCENE := preload("res://UIScenesAndScript/RodShopUI/ShopItemCard.tscn")

const ROD_CATALOG: Array[Dictionary] = [
	{"id": "rod_light", "fallback_price": 0, "fallback_name": "Ultralight Rod"},
	{"id": "rod_medium_light", "fallback_price": 75, "fallback_name": "Medium Light Rod"},
	{"id": "rod_medium", "fallback_price": 150, "fallback_name": "Medium Rod"},
	{"id": "rod_medium_heavy", "fallback_price": 300, "fallback_name": "Medium Heavy Rod"},
	{"id": "rod_heavy", "fallback_price": 500, "fallback_name": "Heavy Rod"},
]

@onready var _bait_shop_button: Button = %BaitShopButton
@onready var _item_grid: GridContainer = %ItemGrid
@onready var _back_button: Button = %BackButton

var _cards: Dictionary = {}


func _ready() -> void:
	_build_cards()

	_bait_shop_button.pressed.connect(_on_bait_shop_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)

	if SaveManager.has_signal(&"money_changed"):
		SaveManager.money_changed.connect(_on_money_changed)
	if SaveManager.has_signal(&"equipment_changed"):
		SaveManager.equipment_changed.connect(refresh_ui)
	visibility_changed.connect(_on_visibility_changed)

	refresh_ui()


func _build_cards() -> void:
	for child in _item_grid.get_children():
		child.queue_free()
	_cards.clear()

	for entry in ROD_CATALOG:
		var rod_id: String = entry["id"]
		var card := ITEM_CARD_SCENE.instantiate() as ShopItemCard
		_item_grid.add_child(card)
		card.action_pressed.connect(_buy_rod)
		_cards[rod_id] = card


func _on_money_changed(_amount: int) -> void:
	refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		refresh_ui()


func _find_entry(rod_id: String) -> Dictionary:
	for entry in ROD_CATALOG:
		if entry["id"] == rod_id:
			return entry
	return {}


func _get_rod_price(rod_id: String, fallback: int) -> int:
	if GameDB.has_rod(rod_id):
		return GameDB.get_rod(rod_id).rod_price
	return fallback


func refresh_ui() -> void:
	var money: int = SaveManager.get_money()

	for entry in ROD_CATALOG:
		var rod_id: String = entry["id"]
		var card: ShopItemCard = _cards.get(rod_id)
		if card == null:
			continue

		var price := _get_rod_price(rod_id, int(entry["fallback_price"]))
		var display_name: String = entry["fallback_name"]
		var tex: Texture2D = null
		if GameDB.has_rod(rod_id):
			var record: RodData = GameDB.get_rod(rod_id)
			display_name = record.display_name
			tex = record.icon

		var owned := SaveManager.has_rod(rod_id)
		var btn_text := "Owned" if owned else "Buy (₱%d)" % price
		var btn_disabled := owned or (money < price)
		card.configure(rod_id, display_name, tex, btn_text, btn_disabled)


func _buy_rod(rod_id: String) -> void:
	var entry := _find_entry(rod_id)
	if entry.is_empty():
		return

	var price := _get_rod_price(rod_id, int(entry["fallback_price"]))
	var display_name: String = GameDB.get_rod(rod_id).display_name if GameDB.has_rod(rod_id) else String(entry["fallback_name"])

	if SaveManager.has_rod(rod_id):
		SaveManager.set_equipped_rod(rod_id)
		refresh_ui()
		return

	if not SaveManager.spend_money(price):
		purchase_failed.emit("Not enough money for %s (₱%d needed)." % [display_name, price])
		refresh_ui()
		return

	SaveManager.add_owned_rod(rod_id)
	SaveManager.set_equipped_rod(rod_id)
	rod_purchased.emit(display_name, price)
	refresh_ui()


func _on_bait_shop_button_pressed() -> void:
	switch_to_bait_requested.emit()


func _on_back_button_pressed() -> void:
	if get_signal_connection_list(&"back_requested").is_empty():
		visible = false
	else:
		back_requested.emit()
