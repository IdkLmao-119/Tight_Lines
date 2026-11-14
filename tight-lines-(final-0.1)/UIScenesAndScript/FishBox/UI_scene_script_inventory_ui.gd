extends Control

@onready var TextureButtonGroupNode = $TextureButtonGroup
var TextureButtonGroup: Array[TextureButton] = []

# Stores the uid of the fish assigned to each button index (0 = empty slot)
var _button_uids: Array[int] = []

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

	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	_refresh_fish_buttons()


func _on_inventory_changed(container_id: String) -> void:
	if container_id == InventoryManager.FISH_BOX:
		_refresh_fish_buttons()


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
			btn.tooltip_text = "%s\n%.1f cm | %.2f kg | $%d" % [display_name, size_cm, weight, price]
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
	print("Clicked fish in slot %d -> id: %s, uid: %d, size: %.1f cm" % [
		slot_index,
		fish["item_id"],
		uid,
		float(fish["meta"].get("size_cm", 0.0))
	])


func _on_back_button_pressed() -> void:
	visible = false
