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
	get_tree().change_scene_to_file("res://UIScenesAndScript/MainMenu/save_slot_menu.tscn")

func _on_options_button_pressed() -> void:
	main_menu_buttons.visible = false
	options.visible = true
	
func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_button_pressed() -> void:
	main_menu_buttons.visible = true
	options.visible = false
