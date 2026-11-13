extends Control

@onready var main_menu: Panel = $"../MainMenu"
@onready var options: Panel = $Options
@onready var music_slider: HSlider = $Options/MusicSlider
func _ready() -> void:
	music_slider.value = GameManager.get_bus_volume(GameManager.BUS_MUSIC)
	music_slider.value_changed.connect(_on_music_slider_changed)

func _setup_music_slider() -> void:
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.value = GameManager.get_bus_volume(GameManager.BUS_MUSIC)
	if not music_slider.value_changed.is_connected(_on_music_slider_changed):
		music_slider.value_changed.connect(_on_music_slider_changed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_music_slider_changed(value: float) -> void:
	GameManager.set_bus_volume(GameManager.BUS_MUSIC, value)

func _on_back_button_pressed() -> void:
	visible = false
	main_menu.visible = true
	
func _on_save_button_pressed() -> void:
	pass # Replace with function body.
	
func _on_menu_button_pressed() -> void:
	GameManager.change_scene("main_menu")
