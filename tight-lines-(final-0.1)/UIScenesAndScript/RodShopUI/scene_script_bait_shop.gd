extends Control

signal switch_to_rods_requested
signal back_requested
signal item_purchased(item_name: String, count: int, cost: int)
signal purchase_failed(reason: String)

const ITEM_CARD_SCENE := preload("res://UIScenesAndScript/RodShopUI/ShopItemCard.tscn")

const BAIT_CATALOG: Array[Dictionary] = [
	{"id": "bait_1", "price": 10, "pack_count": 5, "fallback_name": "Dough"},
	{"id": "bait_2", "price": 20, "pack_count": 5, "fallback_name": "Worm"},
	{"id": "bait_4", "price": 35, "pack_count": 5, "fallback_name": "Shrimp"},
	{"id": "bait_5", "price": 50, "pack_count": 5, "fallback_name": "Softbait"},
	{"id": "bait_3", "price": 65, "pack_count": 5, "fallback_name": "Hardbait"},
	{"id": "bait_6", "price": 80, "pack_count": 5, "fallback_name": "Topwater"},
]

@onready var _rod_shop_button: Button = %RodShopButton
@onready var _item_grid: GridContainer = %ItemGrid
@onready var _back_button: Button = %BackButton

var _cards: Dictionary = {}


func _ready() -> void:
	_build_cards()

	_rod_shop_button.pressed.connect(_on_rod_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)

	if SaveManager.has_signal(&"money_changed"):
		SaveManager.money_changed.connect(_on_money_changed)
	if InventoryManager.has_signal(&"inventory_changed"):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	refresh_ui()


func _build_cards() -> void:
	for child in _item_grid.get_children():
		child.queue_free()
	_cards.clear()

	for entry in BAIT_CATALOG:
		var bait_id: String = entry["id"]
		var card := ITEM_CARD_SCENE.instantiate() as ShopItemCard
		_item_grid.add_child(card)
		card.action_pressed.connect(_buy_bait)
		_cards[bait_id] = card


func _on_money_changed(_amount: int) -> void:
	refresh_ui()


func _on_inventory_changed(_container_id: String) -> void:
	refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		refresh_ui()


func _find_entry(bait_id: String) -> Dictionary:
	for entry in BAIT_CATALOG:
		if entry["id"] == bait_id:
			return entry
	return {}


func refresh_ui() -> void:
	var money: int = SaveManager.get_money()

	for entry in BAIT_CATALOG:
		var bait_id: String = entry["id"]
		var card: ShopItemCard = _cards.get(bait_id)
		if card == null:
			continue

		var price: int = entry["price"]
		var pack_count: int = entry["pack_count"]

		var display_name: String = entry["fallback_name"]
		var tex: Texture2D = null
		var is_unlimited: bool = (bait_id == "bait_1")
		if GameDB.has_bait(bait_id):
			var record: BaitData = GameDB.get_bait(bait_id)
			display_name = record.display_name
			tex = record.icon
			is_unlimited = record.unlimited

		if is_unlimited:
			card.configure(bait_id, "%s (∞)" % display_name, tex, "Owned (∞)", true)
			continue

		var owned_count := InventoryManager.count_of(bait_id)
		var title := "%s (x%d)" % [display_name, owned_count]
		var has_room := InventoryManager.can_add(bait_id, pack_count)
		var btn_text := "Full" if not has_room else "Buy x%d (₱%d)" % [pack_count, price]
		var btn_disabled := (not has_room) or (money < price)
		card.configure(bait_id, title, tex, btn_text, btn_disabled)


func _buy_bait(bait_id: String) -> void:
	var entry := _find_entry(bait_id)
	if entry.is_empty():
		return

	if (GameDB.has_bait(bait_id) and GameDB.get_bait(bait_id).unlimited) or bait_id == "bait_1":
		refresh_ui()
		return

	var price: int = entry["price"]
	var pack_count: int = entry["pack_count"]
	var display_name: String = GameDB.get_bait(bait_id).display_name if GameDB.has_bait(bait_id) else String(entry["fallback_name"])

	if not InventoryManager.can_add(bait_id, pack_count):
		purchase_failed.emit("Tackle Box is full!")
		refresh_ui()
		return

	if not SaveManager.spend_money(price):
		purchase_failed.emit("Not enough money for %s (₱%d needed)." % [display_name, price])
		refresh_ui()
		return

	InventoryManager.add_item(bait_id, pack_count)
	SaveManager.set_equipped_bait(bait_id)
	item_purchased.emit(display_name, pack_count, price)
	refresh_ui()


func _on_rod_button_pressed() -> void:
	switch_to_rods_requested.emit()


func _on_back_button_pressed() -> void:
	if get_signal_connection_list(&"back_requested").is_empty():
		visible = false
	else:
		back_requested.emit()
