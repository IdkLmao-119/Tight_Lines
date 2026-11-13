extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options
@onready var Map: Control = $Map
@onready var map_picture: TextureRect = $Map/MapPicture
@onready var Almanac: Control = $AlmanacUi
# Called when the node enters the sne tree for the first time.

const MAP_TEXTURES := {
	"overworld_rice_field": preload("res://Assets/2D/Maps/RiceFieldMap.png"),
	"overworld_river_park": preload("res://Assets/2D/Maps/RiverParkMap.png"),
	"overworld_fish_market": preload("res://Assets/2D/Maps/SeasideParkMap.png"),
	"overworld_fishing_pens": preload("res://Assets/2D/Maps/FishPensMap.png"),
	"overworld_salt_farm": preload("res://Assets/2D/Maps/SaltFarmMap.png"),
	"overworld_mangrove": preload("res://Assets/2D/Maps/MangroveMap.png"),
	"overworld_island": preload("res://Assets/2D/Maps/IslandMap.png")
}

func _ready() -> void:
	pass
	
func _update_map_picture() -> void:
	match GameManager.current_scene_id:
		"overworld_river_park":
			map_picture.texture = MAP_TEXTURES["overworld_river_park"]
		"overworld_rice_field":
			map_picture.texture = MAP_TEXTURES["overworld_rice_field"]
		"overworld_fish_market":
			map_picture.texture = MAP_TEXTURES["overworld_fish_market"]
		"overworld_fishing_pens":
			map_picture.texture = MAP_TEXTURES["overworld_fishing_pens"]
		"overworld_salt_farm":
			map_picture.texture = MAP_TEXTURES["overworld_salt_farm"]
		"overworld_mangrove":
			map_picture.texture = MAP_TEXTURES["overworld_mangrove"]
		"overworld_island":
			map_picture.texture = MAP_TEXTURES["overworld_island"]
		_:
			push_warning("Map: no picture for scene '%s'" % GameManager.current_scene_id)
# Called every frame. 'delta' is the elapsed time since the previous frame.

func _process(delta: float) -> void:
	pass

func _on_Pause_button_pressed() -> void:
	Options.visible = true

func _on_overworld_button_pressed() -> void:
	_update_map_picture()
	Map.visible = true

func _on_map_back_button_pressed() -> void:
	Map.visible = false

func _on_almanac_button_pressed() -> void:
	Almanac.visible = true
