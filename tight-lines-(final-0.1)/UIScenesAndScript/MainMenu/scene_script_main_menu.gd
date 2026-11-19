extends Control

@onready var _menu_content: Control = %MenuContent
@onready var _start_button: Button = %StartButton
@onready var _options_button: Button = %OptionsButton
@onready var _multi_button: Button = %MultiButton
@onready var _exit_button: Button = %ExitButton
@onready var _options_menu: Control = %OptionsMenu


func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)
	_options_button.pressed.connect(_on_options_button_pressed)
	_multi_button.pressed.connect(_on_multi_button_pressed)
	_exit_button.pressed.connect(_on_exit_button_pressed)
	_options_menu.close_requested.connect(_on_options_closed)

	_menu_content.visible = true
	_options_menu.visible = false
	_start_button.grab_focus()

	var cm := get_node_or_null("/root/ConnectionManager")
	if cm != null and cm.has_method(&"clear_all_player_screen_sides"):
		cm.call(&"clear_all_player_screen_sides")


func _unhandled_input(event: InputEvent) -> void:
	if _options_menu.visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_options_menu.call(&"close")


func _on_start_button_pressed() -> void:
	GameManager.change_scene("save_slots")


func _on_multi_button_pressed() -> void:
	GameManager.change_scene("multiplayer_lobby")


func _on_options_button_pressed() -> void:
	_menu_content.visible = false
	_options_menu.call(&"open")


func _on_options_closed() -> void:
	_options_menu.visible = false
	_menu_content.visible = true
	_start_button.grab_focus()


func _on_exit_button_pressed() -> void:
	get_tree().quit()
