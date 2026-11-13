extends Control

@onready var main_menu_buttons: VBoxContainer = $MainMenuButtons
@onready var options: Control = $Options
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_start_button_pressed() -> void:
	GameManager.change_scene("save_slots")

func _on_options_button_pressed() -> void:
	options.visible = true
	
func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _on_multi_button_pressed() -> void:
	GameManager.change_scene("multiplayer")
