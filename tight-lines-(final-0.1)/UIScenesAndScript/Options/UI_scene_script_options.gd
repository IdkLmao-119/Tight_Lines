extends Control

@onready var main_menu: Panel = get_node_or_null("../MainMenu")
@onready var options: Panel = get_node_or_null("Options")
@onready var music_slider: HSlider = get_node_or_null("Options/MusicSlider")
@onready var sensitivity_slider: HSlider = get_node_or_null("Options/SensitivitySlider")
@onready var sensitivity_input: LineEdit = get_node_or_null("Options/SensitivityInput")

func _ready() -> void:
	if music_slider != null:
		music_slider.value = GameManager.get_bus_volume(GameManager.BUS_MUSIC)
		if not music_slider.value_changed.is_connected(_on_music_slider_changed):
			music_slider.value_changed.connect(_on_music_slider_changed)

	_setup_sensitivity_controls()

func _setup_sensitivity_controls() -> void:
	var im = get_node_or_null("/root/InputManager")
	var initial_sens: float = im.cast_sensitivity if im != null else 1.0

	if sensitivity_slider != null:
		sensitivity_slider.min_value = 0.2
		sensitivity_slider.max_value = 2.0
		sensitivity_slider.step = 0.05
		sensitivity_slider.value = initial_sens
		if not sensitivity_slider.value_changed.is_connected(_on_sensitivity_slider_changed):
			sensitivity_slider.value_changed.connect(_on_sensitivity_slider_changed)

	if sensitivity_input != null:
		sensitivity_input.text = "%.2f" % initial_sens
		if not sensitivity_input.text_submitted.is_connected(_on_sensitivity_input_submitted):
			sensitivity_input.text_submitted.connect(_on_sensitivity_input_submitted)

func _on_music_slider_changed(value: float) -> void:
	GameManager.set_bus_volume(GameManager.BUS_MUSIC, value)

func _on_sensitivity_slider_changed(value: float) -> void:
	var im = get_node_or_null("/root/InputManager")
	if im != null:
		im.cast_sensitivity = value
	if sensitivity_input != null and not sensitivity_input.has_focus():
		sensitivity_input.text = "%.2f" % value
	var sm = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("save_settings"):
		sm.save_settings()

func _on_sensitivity_input_submitted(new_text: String) -> void:
	var val := new_text.to_float()
	if val > 0.0:
		val = clampf(val, 0.2, 2.0)
		if sensitivity_slider != null:
			sensitivity_slider.value = val
		_on_sensitivity_slider_changed(val)

func _on_back_button_pressed() -> void:
	if main_menu != null and GameManager.current_scene_id == "main_menu":
		main_menu.visible = true
	visible = false
	
func _on_save_button_pressed() -> void:
	if has_node("SaveSlotMenu"):
		$SaveSlotMenu.visible = true
	
func _on_menu_button_pressed() -> void:
	GameManager.change_scene("main_menu")
