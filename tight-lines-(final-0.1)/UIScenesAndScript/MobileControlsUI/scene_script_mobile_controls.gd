extends Control

const DPAD_ACTIONS: Array[StringName] = [&"Up", &"Down", &"Left", &"Right"]

## Toggle this to show or hide the on-screen mobile controls overlay in Godot.
@export var show_on_screen_controls: bool = false:
	set(val):
		show_on_screen_controls = val
		visible = show_on_screen_controls
		if not visible:
			_release_all_actions()

@onready var _up_button: Button = %UpButton
@onready var _down_button: Button = %DownButton
@onready var _left_button: Button = %LeftButton
@onready var _right_button: Button = %RightButton

var _pressed_actions: Dictionary = {}


func _ready() -> void:
	visible = show_on_screen_controls
	visibility_changed.connect(_on_visibility_changed)

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


func _exit_tree() -> void:
	_release_all_actions()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_release_all_actions()


func _release_all_actions() -> void:
	for action_name: StringName in DPAD_ACTIONS:
		if _pressed_actions.get(action_name, false) or Input.is_action_pressed(action_name):
			_inject_action(action_name, false)
	_pressed_actions.clear()


func _inject_action(action_name: StringName, is_pressed: bool) -> void:
	_pressed_actions[action_name] = is_pressed
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = is_pressed
	ev.strength = 1.0 if is_pressed else 0.0
	Input.parse_input_event(ev)
