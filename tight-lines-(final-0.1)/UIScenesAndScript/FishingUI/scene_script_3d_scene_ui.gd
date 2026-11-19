extends Control

@export var fishing_manager: Node

@onready var hud: GameHUD = %GameHUD


func _ready() -> void:
	hud.return_requested.connect(_on_return_requested)


func open_menu(menu_id: String) -> void:
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()


func _on_return_requested() -> void:
	var fm := fishing_manager
	if fm == null and get_tree().current_scene != null:
		fm = get_tree().current_scene.find_child("FishingManager", true, false)

	if fm != null and fm.has_method(&"finish_session"):
		fm.call(&"finish_session")
	else:
		GameManager.end_fishing({"results": {}})
