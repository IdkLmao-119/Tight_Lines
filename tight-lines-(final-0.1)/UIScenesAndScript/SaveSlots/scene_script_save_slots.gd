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
@onready var _name_prompt_overlay: ColorRect = %NamePromptOverlay
@onready var _player_name_input: LineEdit = %PlayerNameInput
@onready var _cancel_name_button: Button = %CancelNameButton
@onready var _confirm_name_button: Button = %ConfirmNameButton

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
	_cancel_name_button.pressed.connect(_close_name_prompt)
	_confirm_name_button.pressed.connect(_confirm_new_game)
	_player_name_input.text_submitted.connect(_on_name_submitted)
	_player_name_input.max_length = SaveManager.MAX_PLAYER_NAME_LENGTH
	_player_name_input.placeholder_text = SaveManager.DEFAULT_PLAYER_NAME
	_name_prompt_overlay.visible = false
	visibility_changed.connect(_on_visibility_changed)

	if not GameDB.is_loaded:
		GameDB.reload()

	refresh_slot_labels()
	_update_action_buttons()

	if visible and not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


func open() -> void:
	_name_prompt_overlay.visible = false
	var was_visible := visible
	visible = true
	if was_visible:
		refresh_slot_labels()
		_update_action_buttons()
	if not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


func close() -> void:
	_name_prompt_overlay.visible = false
	if not get_signal_connection_list(&"close_requested").is_empty():
		visible = false
		close_requested.emit()
	else:
		GameManager.go_back()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _name_prompt_overlay.visible:
			_close_name_prompt()
		else:
			close()


func _on_visibility_changed() -> void:
	if visible:
		_name_prompt_overlay.visible = false
		refresh_slot_labels()
		_update_action_buttons()


func refresh_slot_labels() -> void:
	for i in range(_slot_buttons.size()):
		var info: Dictionary = SaveManager.get_slot_info(i)
		if info["exists"]:
			var player_name := String(info.get("player_name", SaveManager.DEFAULT_PLAYER_NAME))
			var line1 := "Slot %d (%s) — %s  •  Day %d (%s)" % [
				i + 1,
				player_name,
				String(info.get("scene_name", "Unknown")),
				int(info.get("day_count", 1)),
				String(info.get("clock_text", "08:00")),
			]
			var line2 := "₱%d  •  Almanac %d%% (%d/%d)  •  %s" % [
				int(info.get("money", 0)),
				int(info.get("almanac_percent", 0)),
				int(info.get("caught_count", 0)),
				int(info.get("total_fish", 0)),
				String(info.get("difficulty", "Casual")),
			]
			var ts := String(info.get("timestamp", ""))
			_slot_buttons[i].text = "%s\n%s\n%s" % [line1, line2, ts]
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
		_open_name_prompt()
		return

	if SaveManager.load_slot(_selected_slot):
		GameManager.change_scene(SaveManager.get_saved_scene())


func _open_name_prompt() -> void:
	_player_name_input.text = ""
	_name_prompt_overlay.visible = true
	_player_name_input.grab_focus()


func _close_name_prompt() -> void:
	_name_prompt_overlay.visible = false
	if _selected_slot != -1:
		_load_save_button.grab_focus()
	elif not _slot_buttons.is_empty():
		_slot_buttons[0].grab_focus()


func _on_name_submitted(_text: String) -> void:
	_confirm_new_game()


func _confirm_new_game() -> void:
	if _selected_slot == -1 or not _name_prompt_overlay.visible or SaveManager.slot_exists(_selected_slot):
		return
	_name_prompt_overlay.visible = false
	SaveManager.new_game(_player_name_input.text)
	SaveManager.save_slot(_selected_slot)
	GameManager.change_scene(SaveManager.get_saved_scene())


func _on_delete_save_button_pressed() -> void:
	if _selected_slot == -1:
		return
	SaveManager.delete_save(_selected_slot)
	refresh_slot_labels()
	_update_action_buttons()
