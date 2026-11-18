extends Control

signal back_requested
signal fish_sold(fish_name: String, price: int)

@export var sell_mode: bool = false:
	set(val):
		sell_mode = val
		_update_mode_ui()

@onready var TextureButtonGroupNode = $TextureButtonGroup
var TextureButtonGroup: Array[TextureButton] = []

# Stores the uid of the fish assigned to each button index (0 = empty slot)
var _button_uids: Array[int] = []

var _sell_all_button: Button = null
var _info_label: Label = null

# Matches the image property lookup used in FishingManager
const FISH_IMAGE_PROPERTIES := ["jpg", "image", "icon", "texture"]
const FISH_NAME_PROPERTIES := ["display_name", "name", "title"]


func _ready() -> void:
	if TextureButtonGroupNode == null:
		push_error("Could not find TextureButtonGroup! Check the node path or Unique Name.")
		return

	TextureButtonGroup.assign(TextureButtonGroupNode.get_children())
	_button_uids.resize(TextureButtonGroup.size())
	_button_uids.fill(0)

	for i in TextureButtonGroup.size():
		var btn: TextureButton = TextureButtonGroup[i]
		# Center and scale the fish image proportionally inside the button
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.pressed.connect(_on_fish_button_pressed.bind(i))

	_build_extra_ui()
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_fish_buttons()
	_update_mode_ui()


func _build_extra_ui() -> void:
	_info_label = Label.new()
	_info_label.name = "FishBoxInfoLabel"
	_info_label.offset_left = 180.0
	_info_label.offset_top = 42.0
	_info_label.offset_right = 760.0
	_info_label.offset_bottom = 95.0
	_info_label.add_theme_font_size_override("font_size", 28)
	_info_label.add_theme_color_override("font_color", Color.WHITE)
	_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_info_label.add_theme_constant_override("outline_size", 6)
	add_child(_info_label)

	_sell_all_button = Button.new()
	_sell_all_button.name = "SellAllButton"
	_sell_all_button.offset_left = 770.0
	_sell_all_button.offset_top = 42.0
	_sell_all_button.offset_right = 955.0
	_sell_all_button.offset_bottom = 105.0
	_sell_all_button.add_theme_font_size_override("font_size", 24)
	_sell_all_button.text = "Sell All"
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	add_child(_sell_all_button)


func _on_visibility_changed() -> void:
	if visible:
		_refresh_fish_buttons()
		_update_mode_ui()


func _update_mode_ui(extra_msg: String = "") -> void:
	if _sell_all_button != null:
		_sell_all_button.visible = sell_mode
		var total_value := _get_total_fish_value()
		var fish_count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX)
		_sell_all_button.text = "Sell All (+%dG)" % total_value
		_sell_all_button.disabled = (fish_count <= 0)

	if _info_label != null:
		if extra_msg != "":
			_info_label.text = extra_msg
		elif sell_mode:
			var count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX)
			if count > 0:
				_info_label.text = "Click any fish to sell it! (%d fish in box)" % count
			else:
				_info_label.text = "Your Fish Box is empty. Catch some fish first!"
		else:
			var count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX)
			_info_label.text = "Fish Box (%d / %d)" % [count, InventoryManager.get_container_capacity(InventoryManager.FISH_BOX)]


func _get_total_fish_value() -> int:
	var total := 0
	for fish: Dictionary in InventoryManager.get_items(InventoryManager.FISH_BOX):
		var uid: int = fish["uid"]
		total += InventoryManager.get_fish_sell_price(uid)
	return total


func _on_inventory_changed(container_id: String) -> void:
	if container_id == InventoryManager.FISH_BOX:
		_refresh_fish_buttons()
		_update_mode_ui()


func _refresh_fish_buttons() -> void:
	# Get all fish currently stored in the Fish Box
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)

	for i in TextureButtonGroup.size():
		var btn: TextureButton = TextureButtonGroup[i]

		if i < fish_list.size():
			var fish: Dictionary = fish_list[i]
			var uid: int = fish["uid"]
			var fish_id: String = fish["item_id"]

			_button_uids[i] = uid
			btn.texture_normal = _get_fish_texture(fish_id)
			btn.disabled = false
			btn.visible = true

			var display_name: String = _get_fish_display_name(fish_id)
			var size_cm := float(fish["meta"].get("size_cm", 0.0))
			var weight: float = InventoryManager.get_fish_weight_kg(uid)
			var price: int = InventoryManager.get_fish_sell_price(uid)
			btn.tooltip_text = "%s\n%.1f cm | %.2f kg | %d G" % [display_name, size_cm, weight, price]
		else:
			# Clear unused button slots
			_button_uids[i] = 0
			btn.texture_normal = null
			btn.disabled = true
			btn.tooltip_text = ""


# Looks up the fish's record in GameDB and returns its display name (falls back to fish_id)
func _get_fish_display_name(fish_id: String) -> String:
	var db := get_node_or_null("/root/GameDB")
	if db == null or not db.has_fish(fish_id):
		return fish_id

	var record: Object = db.get_fish(fish_id)
	if record == null:
		return fish_id

	for prop in FISH_NAME_PROPERTIES:
		var value: Variant = record.get(prop)
		if (value is String or value is StringName) and String(value) != "":
			return String(value)

	return fish_id


# Looks up the fish's record in GameDB and returns its Texture2D
func _get_fish_texture(fish_id: String) -> Texture2D:
	var db := get_node_or_null("/root/GameDB")
	if db == null or not db.has_fish(fish_id):
		return null

	var record: Object = db.get_fish(fish_id)
	if record == null:
		return null

	for prop in FISH_IMAGE_PROPERTIES:
		var value: Variant = record.get(prop)
		if value is Texture2D:
			return value
		if (value is String or value is StringName) and String(value) != "":
			return load(String(value)) as Texture2D

	return null


# Runs when the player clicks one of the fish buttons
func _on_fish_button_pressed(slot_index: int) -> void:
	var uid: int = _button_uids[slot_index]
	if uid == 0:
		return

	var fish: Dictionary = InventoryManager.get_item(uid)
	if fish.is_empty():
		return
	var fish_id: String = fish["item_id"]
	var display_name: String = _get_fish_display_name(fish_id)
	var size_cm := float(fish["meta"].get("size_cm", 0.0))
	var weight: float = InventoryManager.get_fish_weight_kg(uid)
	var price: int = InventoryManager.get_fish_sell_price(uid)

	if sell_mode:
		InventoryManager.remove_item(uid)
		SaveManager.add_money(price)
		fish_sold.emit(display_name, price)
		_update_mode_ui("Sold %s (%.1f cm) for +%d G!" % [display_name, size_cm, price])
	else:
		_update_mode_ui("%s — %.1f cm | %.2f kg | Value: %d G" % [display_name, size_cm, weight, price])
		print("Clicked fish in slot %d -> id: %s, uid: %d, size: %.1f cm" % [
			slot_index,
			fish_id,
			uid,
			size_cm
		])


func _on_sell_all_pressed() -> void:
	if not sell_mode:
		return
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)
	if fish_list.is_empty():
		return
	var total_earned := 0
	var count_sold := 0
	for fish: Dictionary in fish_list:
		var uid: int = fish["uid"]
		var price: int = InventoryManager.get_fish_sell_price(uid)
		if InventoryManager.remove_item(uid) > 0:
			total_earned += price
			count_sold += 1
	if total_earned > 0:
		SaveManager.add_money(total_earned)
	fish_sold.emit("%d fish" % count_sold, total_earned)
	_update_mode_ui("Sold %d fish for +%d G!" % [count_sold, total_earned])


func _on_back_button_pressed() -> void:
	if get_signal_connection_list("back_requested").is_empty():
		visible = false
	else:
		back_requested.emit()
