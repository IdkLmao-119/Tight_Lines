extends Control

@onready var main_menu: Panel = $MainMenu
@onready var main_menu_buttons: VBoxContainer = $MainMenu/MainMenuButtons
@onready var options: Control = $Options
@onready var start_button: Button = $MainMenu/MainMenuButtons/StartButton # Adjust path if needed


func _ready() -> void:
	main_menu.visible = true
	options.visible = false
	
	# Ensures keyboard/controller navigation works right away
	if start_button:
		start_button.grab_focus()


func _on_start_button_pressed() -> void:
	GameManager.change_scene("save_slots")


func _on_multi_button_pressed() -> void:
	GameManager.change_scene("multiplayer")


func _on_options_button_pressed() -> void:
	main_menu.visible = false
	options.visible = true


# Connect a signal from your Options menu to this function when closing it
func _on_options_closed() -> void:
	options.visible = false
	main_menu.visible = true
	if start_button:
		start_button.grab_focus()


func _on_exit_button_pressed() -> void:
	get_tree().quit()
