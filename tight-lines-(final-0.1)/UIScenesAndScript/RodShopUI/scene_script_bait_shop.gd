extends Control

signal switch_to_rods_requested
signal back_requested
signal item_purchased(item_name: String, count: int, cost: int)
signal purchase_failed(reason: String)

const BAIT_CATALOG := {
	"dough": {"id": "bait_1", "price": 10, "pack_count": 5, "image_node": "DoughImage", "button_node": "DoughImage/DoughButton", "label_node": "DoughImage/DoughLabel"},
	"worm": {"id": "bait_2", "price": 20, "pack_count": 5, "image_node": "WormImage", "button_node": "WormImage/WormButton", "label_node": "WormImage/WormLabel"},
	"shrimp": {"id": "bait_4", "price": 35, "pack_count": 5, "image_node": "ShrimpImage", "button_node": "ShrimpImage/ShrimpButton", "label_node": "ShrimpImage/ShrimpLabel"},
	"softbait": {"id": "bait_5", "price": 50, "pack_count": 5, "image_node": "SoftbaitImage", "button_node": "SoftbaitImage/SoftbaitButton", "label_node": "SoftbaitImage/SoftbaitLabel"},
	"hardbait": {"id": "bait_3", "price": 65, "pack_count": 5, "image_node": "HardbaitImage", "button_node": "HardbaitImage/HardbaitButton", "label_node": "HardbaitImage/HardbaitLabel"},
	"topwater": {"id": "bait_6", "price": 80, "pack_count": 5, "image_node": "TopwaterImage", "button_node": "TopwaterImage/TopwaterButton", "label_node": "TopwaterImage/TopwaterLabel"},
}

@onready var rod_button: Button = get_node_or_null("Panel/RodButton")
@onready var back_button: Button = get_node_or_null("Panel/BackButton")


func _ready() -> void:
	if rod_button != null and not rod_button.pressed.is_connected(_on_rod_button_pressed):
		rod_button.pressed.connect(_on_rod_button_pressed)
	if back_button != null and not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	for key: String in BAIT_CATALOG:
		var entry: Dictionary = BAIT_CATALOG[key]
		var btn: Button = get_node_or_null(entry["button_node"])
		if btn != null:
			var callable := _buy_bait.bind(key)
			if not btn.pressed.is_connected(callable):
				btn.pressed.connect(callable)

	if SaveManager.has_signal("money_changed"):
		SaveManager.money_changed.connect(_on_money_changed)
	if InventoryManager.has_signal("inventory_changed"):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	refresh_ui()


func _on_money_changed(_amount: int) -> void:
	refresh_ui()


func _on_inventory_changed(_container_id: String) -> void:
	refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		refresh_ui()


func refresh_ui() -> void:
	var money: int = SaveManager.get_money() if SaveManager.has_method("get_money") else 0

	for key: String in BAIT_CATALOG:
		var entry: Dictionary = BAIT_CATALOG[key]
		var bait_id: String = entry["id"]
		var price: int = entry["price"]
		var pack_count: int = entry["pack_count"]

		var img: TextureRect = get_node_or_null(entry["image_node"])
		var btn: Button = get_node_or_null(entry["button_node"])
		var lbl: Label = get_node_or_null(entry["label_node"])

		var display_name: String = key.capitalize()
		var tex: Texture2D = null
		if GameDB.has_bait(bait_id):
			var record: BaitData = GameDB.get_bait(bait_id)
			display_name = record.display_name
			tex = record.icon

		if img != null and tex != null:
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var owned_count: int = InventoryManager.count_of(bait_id)
		if lbl != null:
			lbl.text = "%s (x%d)" % [display_name, owned_count]

		if btn != null:
			var has_room: bool = InventoryManager.can_add(bait_id, pack_count)
			if not has_room:
				btn.text = "Full"
				btn.disabled = true
			else:
				btn.text = "Buy x%d (%dG)" % [pack_count, price]
				btn.disabled = (money < price)


func _buy_bait(key: String) -> void:
	if not BAIT_CATALOG.has(key):
		return
	var entry: Dictionary = BAIT_CATALOG[key]
	var bait_id: String = entry["id"]
	var price: int = entry["price"]
	var pack_count: int = entry["pack_count"]
	var display_name: String = GameDB.get_bait(bait_id).display_name if GameDB.has_bait(bait_id) else bait_id

	if not InventoryManager.can_add(bait_id, pack_count):
		purchase_failed.emit("Tackle Box is full!")
		refresh_ui()
		return

	if not SaveManager.spend_money(price):
		purchase_failed.emit("Not enough money for %s (%d G needed)." % [display_name, price])
		refresh_ui()
		return

	InventoryManager.add_item(bait_id, pack_count)
	SaveManager.set_equipped_bait(bait_id)
	item_purchased.emit(display_name, pack_count, price)
	refresh_ui()


func _on_rod_button_pressed() -> void:
	switch_to_rods_requested.emit()
	var rod_shop := get_node_or_null("../RodShop")
	if rod_shop != null:
		visible = false
		rod_shop.visible = true


func _on_back_button_pressed() -> void:
	if get_signal_connection_list("back_requested").is_empty():
		visible = false
	else:
		back_requested.emit()
