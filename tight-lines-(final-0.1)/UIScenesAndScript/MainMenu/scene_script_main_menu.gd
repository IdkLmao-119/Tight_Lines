extends Control

@onready var main_menu_buttons: VBoxContainer = $MainMenuButtons
@onready var options: Panel = $Options


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_start_button_pressed() -> void:
	GameManager.change_scene("save_slots")

func _on_options_button_pressed() -> void:
	main_menu_buttons.visible = false
	options.visible = true
	
func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _on_button_pressed() -> void:
	main_menu_buttons.visible = true
	options.visible = false
	_ready()

<<<<<<< HEAD:tight-lines-(final-0.1)/UIScenesAndScript/MainMenu/main_menu_tightlines.gd
func _on_multiplayer_button_pressed() -> void:
	pass # Replace with function body.
=======
func _on_multi_button_pressed() -> void:
	GameManager.change_scene("multiplayer")
>>>>>>> 08daacc983fe56999bfeb85903325aa68671b8fe:tight-lines-(final-0.1)/UIScenesAndScript/MainMenu/scene_script_main_menu.gd
