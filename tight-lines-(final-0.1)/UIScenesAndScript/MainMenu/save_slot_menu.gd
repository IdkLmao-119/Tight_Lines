extends Control

@onready var slot_buttons: Array[Button] = [
	$VBoxContainer/SaveSlot1,
	$VBoxContainer/SaveSlot2,
	$VBoxContainer/SaveSlot3
]

var selected_slot: int = -1  # -1 = nothing selected

func _ready() -> void:
	refresh_slot_labels()

func refresh_slot_labels() -> void:
	for i in range(slot_buttons.size()):
		if SaveManager.slot_exists(i):
			var data = SaveManager.load_game(i)
			slot_buttons[i].text = "Slot %d\n%s" % [i + 1, data.get("timestamp", "")]
		else:
			slot_buttons[i].text = "Slot %d\nEmpty" % (i + 1)

func _select_slot(slot: int) -> void:
	selected_slot = slot
	for i in range(slot_buttons.size()):
		slot_buttons[i].button_pressed = (i == slot)  # only the picked one stays toggled

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://UIScenesAndScript/MainMenu/main_menu_tightlines.tscn")

func _on_save_slot_1_pressed() -> void:
	_select_slot(0)

func _on_save_slot_2_pressed() -> void:
	_select_slot(1)

func _on_save_slot_3_pressed() -> void:
	_select_slot(2)

func _on_make_save_button_pressed() -> void:
	if selected_slot == -1:
		return
	var data = {
		"level": 1,      # replace with real game data
		"xp": 0
	}
	SaveManager.save_game(selected_slot, data)
	refresh_slot_labels()

func _on_load_save_button_pressed() -> void:
	get_tree().change_scene_to_file("res://home_base_area.tscn")
	if selected_slot == -1:
		return
	var data = SaveManager.load_game(selected_slot)
	if data.is_empty():
		return
	print("Loaded: ", data)
	# apply data to your game state here, then change scene if needed

func _on_delete_save_button_pressed() -> void:
	if selected_slot == -1:
		return
	SaveManager.delete_save(selected_slot)
	refresh_slot_labels()
