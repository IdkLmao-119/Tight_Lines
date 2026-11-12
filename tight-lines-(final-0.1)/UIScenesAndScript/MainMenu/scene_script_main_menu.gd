extends Control

@onready var main_menu_buttons: VBoxContainer = $MainMenuButtons
@onready var options: Panel = $Options
@onready var music_slider: HSlider = $Options/MusicSlider

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set the starting value FIRST, then connect, so it doesn't fire a change.
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
func _process(_delta: float) -> void:
	pass

func _on_start_button_pressed() -> void:
	GameManager.change_scene("save_slots")

func _on_options_button_pressed() -> void:
	main_menu_buttons.visible = false
	options.visible = true
	
func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _on_button_pressed() -> void:
	main_menu_buttons.visible = true
	options.visible = false
	_ready()

func _on_multi_button_pressed() -> void:
	GameManager.change_scene("multiplayer")

func _on_music_slider_changed(value: float) -> void:
	GameManager.set_bus_volume(GameManager.BUS_MUSIC, value)
