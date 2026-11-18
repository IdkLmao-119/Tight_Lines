extends Control

signal switch_to_bait_requested
signal back_requested
signal rod_purchased(rod_name: String, cost: int)
signal purchase_failed(reason: String)

const ROD_CATALOG := {
	"light": {"id": "rod_light", "fallback_price": 0, "texture_node": "Panel/ULrodTexture", "button_node": "Panel/ULbuyButton", "label_node": "Panel/ULrodLabel"},
	"medium_light": {"id": "rod_medium_light", "fallback_price": 75, "texture_node": "Panel/MLrodTexture", "button_node": "Panel/MLbuyButton", "label_node": "Panel/MLrodLabel"},
	"medium": {"id": "rod_medium", "fallback_price": 150, "texture_node": "Panel/ULrodTexture/MrodTexture", "button_node": "Panel/ULbuyButton/MbuyButton", "label_node": "Panel/ULrodLabel/MrodLabel"},
	"medium_heavy": {"id": "rod_medium_heavy", "fallback_price": 300, "texture_node": "Panel/ULrodTexture/MHrodTexture", "button_node": "Panel/ULbuyButton/MHbuyButton", "label_node": "Panel/ULrodLabel/MHrodLabel"},
	"heavy": {"id": "rod_heavy", "fallback_price": 500, "texture_node": "Panel/ULrodTexture/HrodTexture", "button_node": "Panel/ULbuyButton/HbuyButton", "label_node": "Panel/ULrodLabel/HrodLabel"},
}

@onready var bait_shop_button: Button = get_node_or_null("Panel/BaitShopUIButton")
@onready var back_button: Button = get_node_or_null("Panel/BackButton")


func _ready() -> void:
	if bait_shop_button != null and not bait_shop_button.pressed.is_connected(_on_bait_shop_button_pressed):
		bait_shop_button.pressed.connect(_on_bait_shop_button_pressed)
	if back_button != null and not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	for key: String in ROD_CATALOG:
		var entry: Dictionary = ROD_CATALOG[key]
		var btn: Button = get_node_or_null(entry["button_node"])
		if btn != null:
			var callable := _buy_rod.bind(key)
			if not btn.pressed.is_connected(callable):
				btn.pressed.connect(callable)

	if SaveManager.has_signal("money_changed"):
		SaveManager.money_changed.connect(_on_money_changed)
	if SaveManager.has_signal("equipment_changed"):
		SaveManager.equipment_changed.connect(refresh_ui)
	visibility_changed.connect(_on_visibility_changed)

	refresh_ui()


func _on_money_changed(_amount: int) -> void:
	refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		refresh_ui()


func _get_rod_price(rod_id: String, fallback: int) -> int:
	if GameDB.has_rod(rod_id):
		return GameDB.get_rod(rod_id).rod_price
	return fallback


func refresh_ui() -> void:
	var money: int = SaveManager.get_money() if SaveManager.has_method("get_money") else 0

	for key: String in ROD_CATALOG:
		var entry: Dictionary = ROD_CATALOG[key]
		var rod_id: String = entry["id"]
		var price: int = _get_rod_price(rod_id, int(entry["fallback_price"]))

		var img: TextureRect = get_node_or_null(entry["texture_node"])
		var btn: Button = get_node_or_null(entry["button_node"])
		var lbl: Label = get_node_or_null(entry["label_node"])

		var display_name: String = key.replace("_", " ").capitalize()
		var tex: Texture2D = null
		if GameDB.has_rod(rod_id):
			var record: RodData = GameDB.get_rod(rod_id)
			display_name = record.display_name
			tex = record.icon

		if img != null and tex != null:
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		if lbl != null:
			lbl.text = display_name

		if btn != null:
			if SaveManager.has_rod(rod_id):
				btn.text = "Owned"
				btn.disabled = true
			else:
				btn.text = "Buy (%dG)" % price
				btn.disabled = (money < price)


func _buy_rod(key: String) -> void:
	if not ROD_CATALOG.has(key):
		return
	var entry: Dictionary = ROD_CATALOG[key]
	var rod_id: String = entry["id"]
	var price: int = _get_rod_price(rod_id, int(entry["fallback_price"]))
	var display_name: String = GameDB.get_rod(rod_id).display_name if GameDB.has_rod(rod_id) else rod_id

	if SaveManager.has_rod(rod_id):
		SaveManager.set_equipped_rod(rod_id)
		refresh_ui()
		return

	if not SaveManager.spend_money(price):
		purchase_failed.emit("Not enough money for %s (%d G needed)." % [display_name, price])
		refresh_ui()
		return

	SaveManager.add_owned_rod(rod_id)
	SaveManager.set_equipped_rod(rod_id)
	rod_purchased.emit(display_name, price)
	refresh_ui()


func _on_bait_shop_button_pressed() -> void:
	switch_to_bait_requested.emit()
	var bait_shop := get_node_or_null("../BaitShop")
	if bait_shop != null:
		visible = false
		bait_shop.visible = true


func _on_back_button_pressed() -> void:
	if get_signal_connection_list("back_requested").is_empty():
		visible = false
	else:
		back_requested.emit()
