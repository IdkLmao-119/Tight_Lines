extends Control

@onready var FishName: Label = $FishEntry/FishName
@onready var Description: RichTextLabel = $FishEntry/FishDescription
@onready var FishPicture: TextureRect = $FishEntry/FishPicture
@onready var FishScientificName: Label = $FishEntry/FishName/FishScientificName
@onready var grid_vbox: VBoxContainer = $ScrollContainer/VBoxContainer

# Replace these string values with your actual LocationData IDs from GameDB
@onready var LOCATION_BUTTONS: Dictionary = {
	$VBoxContainer/PasigButton: "location_marikina",
	$VBoxContainer/KawitButton: "location_kawit",
	$VBoxContainer/ImusButton: "location_imus",
	$VBoxContainer/FishPensButton: "location_fish_pens",
	$VBoxContainer/SaltFarmButton: "location_salt_farm",
	$VBoxContainer/CalataganButton: "location_calatagan",
	$VBoxContainer/FortuneIsButton: "location_fortune_island",
}

var fish_buttons: Array[TextureButton] = []
var current_location_fish: Array[FishData] = []


func _ready() -> void:
	_collect_fish_buttons()
	_connect_location_buttons()
	_clear_entry_display()
	visibility_changed.connect(_on_visibility_changed)

	if not LOCATION_BUTTONS.is_empty():
		var first_location_id: String = LOCATION_BUTTONS.values()[0]
		_select_location(first_location_id)


func _on_visibility_changed() -> void:
	if visible and not LOCATION_BUTTONS.is_empty():
		# Re-populate the grid so newly caught fish appear immediately
		_populate_fish_grid()


func _collect_fish_buttons() -> void:
	fish_buttons.clear()
	for hbox in grid_vbox.get_children():
		for child in hbox.get_children():
			if child is TextureButton:
				var btn := child as TextureButton
				var index := fish_buttons.size()
				btn.pressed.connect(_on_fish_button_pressed.bind(index))
				fish_buttons.append(btn)


func _connect_location_buttons() -> void:
	for button: Button in LOCATION_BUTTONS:
		var loc_id: String = LOCATION_BUTTONS[button]
		button.pressed.connect(_select_location.bind(loc_id))


func _select_location(location_id: String) -> void:
	current_location_fish.clear()

	var pool: Array[PoolEntry] = GameDB.get_location_fish_pool(location_id)
	for entry in pool:
		if entry != null and entry.fish != null:
			current_location_fish.append(entry.fish)

	_populate_fish_grid()

	if not current_location_fish.is_empty():
		_show_fish(0)
	else:
		_clear_entry_display()


func _populate_fish_grid() -> void:
	for i in range(fish_buttons.size()):
		var btn: TextureButton = fish_buttons[i]

		if i < current_location_fish.size():
			var fish: FishData = current_location_fish[i]
			var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

			btn.texture_normal = tex
			btn.disabled = false

			if SaveManager.has_caught_fish(fish.id):
				btn.modulate = Color.WHITE
			else:
				btn.modulate = Color(0.15, 0.15, 0.15, 1.0)
		else:
			btn.texture_normal = null
			btn.disabled = true
			btn.modulate = Color.WHITE


func _on_fish_button_pressed(index: int) -> void:
	if index >= 0 and index < current_location_fish.size():
		_show_fish(index)


func _show_fish(index: int) -> void:
	var fish: FishData = current_location_fish[index]
	var caught: bool = SaveManager.has_caught_fish(fish.id)
	var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

	FishPicture.texture = tex

	if caught:
		FishPicture.modulate = Color.WHITE
		FishName.text = fish.display_name
		FishScientificName.text = fish.scientific_name
		Description.text = "%s\n\n[b]Size Class:[/b] %s\n[b]Avg Size:[/b] %.1f cm\n[b]Avg Weight:[/b] %.2f kg\n[b]Base Value:[/b] %d G" % [
			fish.description,
			fish.size_class.capitalize(),
			fish.avg_size,
			fish.avg_weight,
			fish.base_price
		]
	else:
		FishPicture.modulate = Color(0.15, 0.15, 0.15, 1.0)
		FishName.text = "???"
		FishScientificName.text = "Unknown Species"
		Description.text = "Catch this fish to unlock its Almanac entry."


func _clear_entry_display() -> void:
	FishPicture.texture = null
	FishName.text = ""
	FishScientificName.text = ""
	Description.text = ""


func _on_back_button_pressed() -> void:
	visible = false
