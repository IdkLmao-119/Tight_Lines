extends Control

## Toggle this to show or hide the on-screen mobile controls overlay in Godot.
@export var show_on_screen_controls: bool = false:
	set(val):
		show_on_screen_controls = val
		visible = show_on_screen_controls

func _ready() -> void:
	visible = show_on_screen_controls

func _on_dpad_up_pressed() -> void:
	_inject_action("Up", true)

func _on_dpad_up_released() -> void:
	_inject_action("Up", false)

func _on_dpad_down_pressed() -> void:
	_inject_action("Down", true)

func _on_dpad_down_released() -> void:
	_inject_action("Down", false)

func _on_dpad_left_pressed() -> void:
	_inject_action("Left", true)

func _on_dpad_left_released() -> void:
	_inject_action("Left", false)

func _on_dpad_right_pressed() -> void:
	_inject_action("Right", true)

func _on_dpad_right_released() -> void:
	_inject_action("Right", false)

func _inject_action(action_name: StringName, is_pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = is_pressed
	ev.strength = 1.0 if is_pressed else 0.0
	Input.parse_input_event(ev)
