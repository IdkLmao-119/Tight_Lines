extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options
@onready var Map: Control = $Map
@onready var map_picture: TextureRect = $Map/MapPicture
# Called when the node enters the sne tree for the first time.

const MAP_TEXTURES := {
	"overworld_spawn": preload("res://assets/Water.jpg"),
	"overworld_rice_field": preload("res://Assets/2D/Maps/RiceFieldMap.png"),
	"overworld_river_park": preload("res://Assets/2D/Maps/RiverParkMap.png")
}

func _ready() -> void:
	pass
	
func _update_map_picture() -> void:
	match GameManager.current_scene_id:
		"overworld_spawn":
			map_picture.texture = MAP_TEXTURES["overworld_spawn"]
		"overworld_river_park":
			map_picture.texture = MAP_TEXTURES["overworld_river_park"]
		_:
			push_warning("Map: no picture for scene '%s'" % GameManager.current_scene_id)
# Called every frame. 'delta' is the elapsed time since the previous frame.

func _process(delta: float) -> void:
	pass

func _on_Pause_button_pressed() -> void:
	Options.visible = true

func _on_back_button_pressed() -> void:
	Options.visible = false

func _on_overworld_button_pressed() -> void:
	_update_map_picture()
	Map.visible = true

func _on_map_back_button_pressed() -> void:
	Map.visible = false
	
