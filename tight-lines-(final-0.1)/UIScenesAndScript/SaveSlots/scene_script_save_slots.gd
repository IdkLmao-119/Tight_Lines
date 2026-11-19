extends Control

signal close_requested

@export var allow_saving: bool = false:
	set(value):
		allow_saving = value
		if is_node_ready():
			_update_action_buttons()

@onready var _slot_list: VBoxContainer = %SlotList
@onready var _back_button: Button = %BackButton
@onready var _make_save_button: Button = %MakeSaveButton
@onready var _load_save_button: Button = %LoadSaveButton
@onready var _delete_save_button: Button = %DeleteSaveButton

var _slot_buttons: Array[Button] = []
var _selected_slot: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	for child in _slot_list.get_children():
		if child is Button:
			var btn := child as Button
			var slot_idx := _slot_buttons.size()
			btn.pressed.connect(_select_slot.bind(slot_idx))
			_slot_buttons.append(btn)

	_back_button.pressed.connect(close)
	_make_save_button.pressed.connect(_on_make_save_button_pressed)
	_load_save_button.pressed.connect(_on_load_save_button_pressed)
	_delete_save_button.pressed.connect(_on_delete_save_button_pressed)
	visibility_changed.connect(_on_visibility_changed)

	if not GameDB.is_loaded:
		GameDB.reload()

	refresh_slot_labels()
	_update_action_buttons()

	if visible and not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


func open() -> void:
	visible = true
	refresh_slot_labels()
	_update_action_buttons()
	if not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


func close() -> void:
	if not get_signal_connection_list(&"close_requested").is_empty():
		visible = false
		close_requested.emit()
	else:
		GameManager.go_back()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _on_visibility_changed() -> void:
	if visible:
		refresh_slot_labels()
		_update_action_buttons()


func refresh_slot_labels() -> void:
	for i in range(_slot_buttons.size()):
		var info: Dictionary = SaveManager.get_slot_info(i)
		if info["exists"]:
			_slot_buttons[i].text = "Slot %d\n%s" % [i + 1, info["timestamp"]]
		else:
			_slot_buttons[i].text = "Slot %d\nEmpty" % (i + 1)


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	for i in range(_slot_buttons.size()):
		_slot_buttons[i].button_pressed = (i == slot)
	_update_action_buttons()


func _update_action_buttons() -> void:
	if _selected_slot == -1:
		_make_save_button.disabled = true
		_load_save_button.disabled = true
		_delete_save_button.disabled = true
		return

	var is_taken: bool = SaveManager.slot_exists(_selected_slot)
	_load_save_button.disabled = false
	_load_save_button.text = "Load Save" if is_taken else "New Game"

	_make_save_button.text = "Save" if is_taken else "Make Save"
	_make_save_button.disabled = not allow_saving

	_delete_save_button.disabled = not is_taken


func _on_make_save_button_pressed() -> void:
	if _selected_slot == -1 or not allow_saving:
		return
	if SaveManager.save_slot(_selected_slot):
		refresh_slot_labels()
		_update_action_buttons()


func _on_load_save_button_pressed() -> void:
	if _selected_slot == -1:
		return

	if not SaveManager.slot_exists(_selected_slot):
		SaveManager.new_game()
		SaveManager.save_slot(_selected_slot)
		GameManager.change_scene(SaveManager.get_saved_scene())
		return

	if SaveManager.load_slot(_selected_slot):
		GameManager.change_scene(SaveManager.get_saved_scene())


func _on_delete_save_button_pressed() -> void:
	if _selected_slot == -1:
		return
	SaveManager.delete_save(_selected_slot)
	refresh_slot_labels()
	_update_action_buttons()
