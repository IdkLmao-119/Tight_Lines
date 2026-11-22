extends Control

signal close_requested

@export var show_save_button: bool = true:
	set(value):
		show_save_button = value
		if is_node_ready():
			_apply_button_visibility()

@export var show_main_menu_button: bool = true:
	set(value):
		show_main_menu_button = value
		if is_node_ready():
			_apply_button_visibility()

@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _difficulty_button: Button = %DifficultyButton
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_input: LineEdit = %SensitivityInput
@onready var _save_button: Button = %SaveButton
@onready var _back_button: Button = %BackButton
@onready var _menu_button: Button = %MenuButton
@onready var _save_slot_menu: Control = %SaveSlotMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_slider.value_changed.connect(_on_music_slider_changed)
	_music_slider.drag_ended.connect(_on_slider_drag_ended)

	_sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	_sfx_slider.drag_ended.connect(_on_slider_drag_ended)

	_difficulty_button.pressed.connect(_on_difficulty_button_pressed)

	_sensitivity_slider.value_changed.connect(_on_sensitivity_slider_changed)
	_sensitivity_slider.drag_ended.connect(_on_slider_drag_ended)
	_sensitivity_input.text_submitted.connect(_on_sensitivity_input_submitted)
	_sensitivity_input.focus_exited.connect(func() -> void:
		_on_sensitivity_input_submitted(_sensitivity_input.text)
	)

	_save_button.pressed.connect(_on_save_button_pressed)
	_back_button.pressed.connect(close)
	_menu_button.pressed.connect(_on_menu_button_pressed)
	_save_slot_menu.add_to_group(&"pause_submodal")
	_save_slot_menu.close_requested.connect(_on_save_slot_menu_closed)
	visibility_changed.connect(_on_visibility_changed)

	_apply_button_visibility()
	_sync_values()


func open() -> void:
	var was_visible := visible
	_save_slot_menu.visible = false
	visible = true
	if was_visible:
		_apply_button_visibility()
		_sync_values()
	_back_button.grab_focus()


func close() -> void:
	_save_slot_menu.visible = false
	_save_settings()
	visible = false
	close_requested.emit()


func handle_mobile_action(action: String) -> void:
	match action:
		"back":
			if _save_slot_menu.visible:
				_on_save_slot_menu_closed()
			else:
				close()


func _on_visibility_changed() -> void:
	if visible:
		_save_slot_menu.visible = false
		_apply_button_visibility()
		_sync_values()


func _apply_button_visibility() -> void:
	_save_button.visible = show_save_button
	_menu_button.visible = show_main_menu_button


func _sync_values() -> void:
	_music_slider.set_value_no_signal(GameManager.get_bus_volume(GameManager.BUS_MUSIC))
	_sfx_slider.set_value_no_signal(GameManager.get_bus_volume(GameManager.BUS_SFX))

	var sm := get_node_or_null("/root/SaveManager")
	var diff := String(sm.call(&"get_difficulty")) if (sm != null and sm.has_method(&"get_difficulty")) else "casual"
	_difficulty_button.text = "Angler" if diff.to_lower() == "angler" else "Casual"

	var im := get_node_or_null("/root/InputManager")
	var sens: float = float(im.get("cast_sensitivity")) if im != null else 0.5
	_sensitivity_slider.set_value_no_signal(sens)
	if not _sensitivity_input.has_focus():
		_sensitivity_input.text = "%.2f" % sens


func _on_music_slider_changed(value: float) -> void:
	GameManager.set_bus_volume(GameManager.BUS_MUSIC, value)


func _on_sfx_slider_changed(value: float) -> void:
	GameManager.set_bus_volume(GameManager.BUS_SFX, value)


func _on_difficulty_button_pressed() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	var cur := String(sm.call(&"get_difficulty")) if (sm != null and sm.has_method(&"get_difficulty")) else "casual"
	var next := "angler" if cur.to_lower() == "casual" else "casual"
	if sm != null and sm.has_method(&"set_difficulty"):
		sm.call(&"set_difficulty", next)
	_difficulty_button.text = "Angler" if next == "angler" else "Casual"
	if get_tree() != null and get_tree().current_scene != null:
		var fm := get_tree().current_scene.find_child("FishingManager", true, false)
		if fm != null and fm.has_method(&"set_difficulty_string"):
			fm.call(&"set_difficulty_string", next)


func _on_sensitivity_slider_changed(value: float) -> void:
	var im := get_node_or_null("/root/InputManager")
	if im != null:
		im.set("cast_sensitivity", value)
	if not _sensitivity_input.has_focus():
		_sensitivity_input.text = "%.2f" % value


func _on_slider_drag_ended(_changed: bool) -> void:
	_save_settings()


func _on_sensitivity_input_submitted(new_text: String) -> void:
	var val := clampf(new_text.to_float(), 0.0, 1.0)
	_sensitivity_slider.set_value_no_signal(val)
	_on_sensitivity_slider_changed(val)
	_sensitivity_input.text = "%.2f" % val
	_save_settings()


func _on_save_button_pressed() -> void:
	if _save_slot_menu.has_method(&"open"):
		_save_slot_menu.call(&"open")
	else:
		_save_slot_menu.visible = true


func _on_save_slot_menu_closed() -> void:
	_save_slot_menu.visible = false
	_back_button.grab_focus()


func _on_menu_button_pressed() -> void:
	_save_slot_menu.visible = false
	_save_settings()
	visible = false
	GameManager.change_scene("main_menu")


func _save_settings() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method(&"save_settings"):
		sm.call(&"save_settings")
