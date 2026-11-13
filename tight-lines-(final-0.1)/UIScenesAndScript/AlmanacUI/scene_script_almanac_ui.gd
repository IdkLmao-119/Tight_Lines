extends Control

@onready var FishName: Label = $AlmanacPanel/Entry/FishName
@onready var Description: RichTextLabel = $AlmanacPanel/Entry/FishDescription
@onready var FishPicture: TextureRect = $AlmanacPanel/Entry/FishPicture
@onready var FishScientificName: Label = $AlmanacPanel/Entry/FishName/FishScientificName
var fish_array: Array[FishData] = []
var fish_array_pointer: int = 0


func _ready() -> void:
	fish_array = GameDB.get_all_fish()
	if fish_array.is_empty():
		push_warning("Almanac: GameDB has no fish.")
		return
	_show_fish()


func _show_fish() -> void:
	var fish: FishData = fish_array[fish_array_pointer]
	FishName.text = fish.display_name
	Description.text = fish.description
	FishScientificName.text = fish.scientific_name
	# icon_3d is empty in your .tres files, so fall back to the 2D icon.
	FishPicture.texture = fish.icon_3d if fish.icon_3d != null else fish.icon


func _on_previous_button_pressed() -> void:
	if fish_array.is_empty():
		return
	fish_array_pointer = (fish_array_pointer - 1 + fish_array.size()) % fish_array.size()
	_show_fish()


func _on_next_button_pressed() -> void:
	if fish_array.is_empty():
		return
	fish_array_pointer = (fish_array_pointer + 1) % fish_array.size()
	_show_fish()

func _on_back_button_pressed() -> void:
	visible = false
