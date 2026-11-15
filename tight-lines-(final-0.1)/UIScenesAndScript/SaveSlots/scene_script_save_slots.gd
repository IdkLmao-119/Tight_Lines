extends Control

@onready var slot_buttons: Array[Button] = [
	$VBoxContainer/SaveSlot1,
	$VBoxContainer/SaveSlot2,
	$VBoxContainer/SaveSlot3
]

# Update these node paths to match your exact Scene Tree
@onready var make_save_button: Button = $HBoxContainer/MakeSaveButton
@onready var load_save_button: Button = $HBoxContainer/LoadSaveButton

var selected_slot: int = -1  # -1 = nothing selected


func _ready() -> void:
	refresh_slot_labels()
	_update_action_buttons()
	GameDB.reload()


func refresh_slot_labels() -> void:
	for i in range(slot_buttons.size()):
		var info: Dictionary = SaveManager.get_slot_info(i)
		if info["exists"]:
			slot_buttons[i].text = "Slot %d\n%s" % [i + 1, info["timestamp"]]
		else:
			slot_buttons[i].text = "Slot %d\nEmpty" % (i + 1)


func _select_slot(slot: int) -> void:
	selected_slot = slot
	for i in range(slot_buttons.size()):
		slot_buttons[i].button_pressed = (i == slot)
	_update_action_buttons()


func _update_action_buttons() -> void:
	# Disable both action buttons if no slot is selected yet
	if selected_slot == -1:
		make_save_button.disabled = true
		load_save_button.disabled = true
		return

	load_save_button.disabled = false
	var is_taken: bool = SaveManager.slot_exists(selected_slot)
	var is_main_menu: bool = (GameManager.previous_scene_id == "main_menu")

	if is_taken:
		load_save_button.text = "Load Save"
		make_save_button.text = "Save"
		make_save_button.disabled = is_main_menu
	else:
		make_save_button.text = "Make Save"
		make_save_button.disabled = is_main_menu
		load_save_button.text = "New Game"


func _on_back_button_pressed() -> void:
	if GameManager.previous_scene_id == "main_menu":
		GameManager.go_back()
	else:
		visible = false


func _on_save_slot_1_pressed() -> void:
	_select_slot(0)


func _on_save_slot_2_pressed() -> void:
	_select_slot(1)


func _on_save_slot_3_pressed() -> void:
	_select_slot(2)


func _on_make_save_button_pressed() -> void:
	if selected_slot == -1:
		return
	if not SaveManager.slot_exists(selected_slot) and GameManager.previous_scene_id == "main_menu":
		SaveManager.new_game()
	
	if SaveManager.save_slot(selected_slot):
		refresh_slot_labels()
		_update_action_buttons()


func _on_load_save_button_pressed() -> void:
	if selected_slot == -1:
		return

	if not SaveManager.slot_exists(selected_slot):
		SaveManager.new_game()
		SaveManager.save_slot(selected_slot)
		GameManager.change_scene(SaveManager.get_saved_scene())
		return

	if SaveManager.load_slot(selected_slot):
		GameManager.change_scene(SaveManager.get_saved_scene())


func _on_delete_save_button_pressed() -> void:
	if selected_slot == -1:
		return
	SaveManager.delete_save(selected_slot)
	refresh_slot_labels()
	_update_action_buttons()
