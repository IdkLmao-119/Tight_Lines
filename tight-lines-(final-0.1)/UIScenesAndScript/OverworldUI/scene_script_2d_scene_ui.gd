extends Control

@onready var hud: GameHUD = %GameHUD


func open_menu(menu_id: String) -> void:
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()
