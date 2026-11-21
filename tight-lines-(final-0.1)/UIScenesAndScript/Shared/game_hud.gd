class_name GameHUD
extends Control

signal return_requested

const PHONE_MENU_NAMES := {
	"fish_box": "fish_box",
	"almanac": "almanac",
	"equipment": "equipment",
	"quests": "quests",
}

@export var show_return_button: bool = false:
	set(value):
		show_return_button = value
		if is_node_ready():
			_apply_configuration()

@export var return_button_text: String = "Overworld":
	set(value):
		return_button_text = value
		if is_node_ready():
			_apply_configuration()

@export var show_menu_buttons: bool = true:
	set(value):
		show_menu_buttons = value
		if is_node_ready():
			_apply_configuration()

@export var show_save_in_options: bool = false:
	set(value):
		show_save_in_options = value
		if is_node_ready():
			_apply_configuration()

@export var show_main_menu_in_options: bool = true:
	set(value):
		show_main_menu_in_options = value
		if is_node_ready():
			_apply_configuration()

@onready var _pause_button: Button = %PauseButton
@onready var _return_button: Button = %ReturnButton
@onready var _left_menu_column: VBoxContainer = %LeftMenuColumn
@onready var _right_menu_column: VBoxContainer = %RightMenuColumn
@onready var _quest_button: Button = %QuestButton
@onready var _equipment_button: Button = %EquipmentButton
@onready var _almanac_button: Button = %AlmanacButton
@onready var _fish_box_button: Button = %FishBoxButton

@onready var _fish_box_ui: Control = %FishBoxUI
@onready var _equipment_ui: Control = %EquipmentUI
@onready var _almanac_ui: Control = %AlmanacUI
@onready var _quest_log: Control = %QuestLog
@onready var _options_menu: Control = %OptionsMenu

var _overlays: Dictionary = {}
var _active_menu_id: String = ""
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_queue: Array[String] = []
var _toast_showing := false
var _toast_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlays = {
		"fish_box": _fish_box_ui,
		"equipment": _equipment_ui,
		"almanac": _almanac_ui,
		"quests": _quest_log,
		"options": _options_menu,
	}

	_pause_button.pressed.connect(toggle_menu.bind("options"))
	_return_button.pressed.connect(func() -> void:
		return_requested.emit()
	)
	_quest_button.pressed.connect(toggle_menu.bind("quests"))
	_equipment_button.pressed.connect(toggle_menu.bind("equipment"))
	_almanac_button.pressed.connect(toggle_menu.bind("almanac"))
	_fish_box_button.pressed.connect(toggle_menu.bind("fish_box"))

	for menu_id: String in _overlays:
		var overlay: Control = _overlays[menu_id]
		if overlay.has_signal(&"close_requested"):
			overlay.connect(&"close_requested", _on_overlay_close_requested.bind(menu_id))
		if overlay.has_signal(&"back_requested"):
			overlay.connect(&"back_requested", _on_overlay_close_requested.bind(menu_id))
		if PHONE_MENU_NAMES.has(menu_id):
			overlay.visibility_changed.connect(_sync_active_menu_to_phone)

	if GameManager.has_signal(&"paused_changed"):
		GameManager.paused_changed.connect(_on_paused_changed)

	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_signal(&"menu_action"):
		im.connect(&"menu_action", _on_phone_menu_action)

	var cm := get_node_or_null("/root/ConnectionManager")
	if cm != null and cm.has_signal(&"player_connected"):
		cm.connect(&"player_connected", _on_phone_connected)

	_build_toast_banner()
	var qm := get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_signal(&"quest_completed"):
		qm.connect(&"quest_completed", _on_quest_completed)
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_signal(&"unlock_flag_added"):
		sm.connect(&"unlock_flag_added", _on_unlock_flag_added)

	_apply_configuration()
	close_all_menus()


func _unhandled_input(event: InputEvent) -> void:
	if _active_menu_id == "" or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	close_all_menus()


func open_menu(menu_id: String) -> void:
	if not _overlays.has(menu_id):
		return

	_active_menu_id = menu_id
	for id: String in _overlays:
		var overlay: Control = _overlays[id]
		if id == menu_id:
			if overlay.has_method(&"open"):
				overlay.call(&"open")
			else:
				overlay.visible = true
		else:
			overlay.visible = false

	if menu_id == "options" and not GameManager.is_paused():
		GameManager.set_paused(true)

	_sync_active_menu_to_phone()


func toggle_menu(menu_id: String) -> void:
	if _active_menu_id == menu_id and _overlays.has(menu_id) and (_overlays[menu_id] as Control).visible:
		close_all_menus()
	else:
		open_menu(menu_id)


func close_all_menus() -> void:
	var was_options := (_active_menu_id == "options")
	_active_menu_id = ""
	for overlay: Control in _overlays.values():
		overlay.visible = false

	if was_options and GameManager.is_paused():
		GameManager.set_paused(false)

	_sync_active_menu_to_phone()


func _apply_configuration() -> void:
	_return_button.visible = show_return_button
	_return_button.text = return_button_text
	_left_menu_column.visible = show_menu_buttons
	_right_menu_column.visible = show_menu_buttons
	_options_menu.set(&"show_save_button", show_save_in_options)
	_options_menu.set(&"show_main_menu_button", show_main_menu_in_options)


func _on_overlay_close_requested(menu_id: String) -> void:
	if _overlays.has(menu_id):
		(_overlays[menu_id] as Control).visible = false
	if _active_menu_id == menu_id:
		_active_menu_id = ""
	if menu_id == "options" and GameManager.is_paused():
		GameManager.set_paused(false)
	_sync_active_menu_to_phone()


func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		if _active_menu_id != "options":
			open_menu("options")
	elif _active_menu_id == "options":
		_active_menu_id = ""
		_options_menu.call(&"close")
		_sync_active_menu_to_phone()


func _on_phone_connected(_player_id: int) -> void:
	_sync_active_menu_to_phone()


func _on_phone_menu_action(_player_id: int, action: String) -> void:
	if show_menu_buttons:
		match action:
			"fish_box":
				toggle_menu("fish_box")
				return
			"almanac":
				toggle_menu("almanac")
				return
			"equipment", "inventory":
				toggle_menu("equipment")
				return
			"quests":
				toggle_menu("quests")
				return

	var story := get_node_or_null("/root/StoryManager")
	if story != null and story.has_method(&"is_playing") and story.call(&"is_playing"):
		return

	if _active_menu_id != "" and _overlays.has(_active_menu_id):
		var active: Control = _overlays[_active_menu_id]
		if active.visible and active.has_method(&"handle_mobile_action"):
			active.call(&"handle_mobile_action", action)


func _get_active_phone_menu_name() -> String:
	for menu_id: String in PHONE_MENU_NAMES:
		var overlay: Control = _overlays.get(menu_id)
		if overlay != null and overlay.visible:
			return PHONE_MENU_NAMES[menu_id]
	return "none"


func _sync_active_menu_to_phone() -> void:
	var cm := get_node_or_null("/root/ConnectionManager")
	if cm != null and cm.has_method(&"send_to_all"):
		cm.call(&"send_to_all", {"active_menu": _get_active_phone_menu_name()})


func show_toast(message: String) -> void:
	if message.strip_edges() == "":
		return
	_toast_queue.append(message)
	if not _toast_showing:
		_pop_next_toast()


func get_active_toast_text() -> String:
	return _toast_label.text if (_toast_label != null and _toast_panel != null and _toast_panel.visible) else ""


func _build_toast_banner() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.24, 0.18, 0.92)
	style.border_color = Color(1.0, 0.86, 0.36, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastBanner"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", style)
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.anchor_bottom = 0.0
	_toast_panel.offset_left = -260.0
	_toast_panel.offset_right = 260.0
	_toast_panel.offset_top = 72.0
	_toast_panel.offset_bottom = 128.0
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.visible = false
	add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82, 1.0))
	_toast_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 1.0))
	_toast_label.add_theme_constant_override("outline_size", 4)
	_toast_panel.add_child(_toast_label)


func _pop_next_toast() -> void:
	if _toast_queue.is_empty() or _toast_panel == null or _toast_label == null:
		_toast_showing = false
		if _toast_panel != null:
			_toast_panel.visible = false
		return
	_toast_showing = true
	_toast_label.text = _toast_queue.pop_front()
	_toast_panel.modulate.a = 0.0
	_toast_panel.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(_pop_next_toast)


func _on_quest_completed(quest_id: String) -> void:
	var qm := get_node_or_null("/root/QuestManager")
	var title := quest_id
	if qm != null and qm.has_method(&"get_quest_info"):
		var info: Dictionary = qm.call(&"get_quest_info", quest_id)
		if info.has("title"):
			title = String(info["title"])
	show_toast("Quest Complete: %s!" % title)


func _on_unlock_flag_added(flag: String) -> void:
	if flag.begins_with("seen_"):
		return
	var pretty := flag.trim_prefix("unlock_").replace("_", " ").capitalize()
	show_toast("Unlocked: %s!" % pretty)
