extends Control

## Toggle this to show or hide the on-screen mobile controls overlay in Godot.
@export var show_on_screen_controls: bool = false:
	set(val):
		show_on_screen_controls = val
		visible = show_on_screen_controls

@onready var _up_button: Button = %UpButton
@onready var _down_button: Button = %DownButton
@onready var _left_button: Button = %LeftButton
@onready var _right_button: Button = %RightButton


func _ready() -> void:
	visible = show_on_screen_controls

	var dpad_map := {
		_up_button: &"Up",
		_down_button: &"Down",
		_left_button: &"Left",
		_right_button: &"Right",
	}
	for btn: Button in dpad_map:
		var action_name: StringName = dpad_map[btn]
		btn.button_down.connect(_inject_action.bind(action_name, true))
		btn.button_up.connect(_inject_action.bind(action_name, false))


func _inject_action(action_name: StringName, is_pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = is_pressed
	ev.strength = 1.0 if is_pressed else 0.0
	Input.parse_input_event(ev)
