extends Control

const WORLD_MAP_SCRIPT := preload("res://UIScenesAndScript/Shared/world_map_overlay.gd")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

@onready var hud: GameHUD = %GameHUD

var _map_button: Button = null
var _world_map: Control = null


func _ready() -> void:
	_build_world_map_bar()
	move_child(hud, -1)
	move_child(_world_map, -1)
	if hud.has_signal(&"menu_opened"):
		hud.connect(&"menu_opened", _on_hud_menu_opened)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal(&"world_time_changed"):
		gm.connect(&"world_time_changed", _on_world_time_changed)
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_signal(&"menu_action"):
		im.connect(&"menu_action", _on_phone_menu_action)
	_refresh_clock_button()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode != KEY_M and event.keycode != KEY_M:
		return
	var story := get_node_or_null("/root/StoryManager")
	if story != null and story.has_method(&"is_playing") and story.call(&"is_playing"):
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	get_viewport().set_input_as_handled()
	toggle_world_map()


func open_menu(menu_id: String) -> void:
	if _world_map != null and _world_map.visible:
		_world_map.call(&"close")
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()
	if _world_map != null and _world_map.visible:
		_world_map.call(&"close")


func open_world_map() -> void:
	if _world_map != null:
		hud.close_all_menus()
		_world_map.call(&"open")


func toggle_world_map() -> void:
	if _world_map == null:
		return
	if _world_map.visible:
		_world_map.call(&"close")
	else:
		open_world_map()


func _on_hud_menu_opened(_menu_id: String) -> void:
	if _world_map != null and _world_map.visible:
		_world_map.call(&"close")


func _on_phone_menu_action(_player_id: int, action: String) -> void:
	var story := get_node_or_null("/root/StoryManager")
	if story != null and story.has_method(&"is_playing") and story.call(&"is_playing"):
		return
	if action == "map":
		toggle_world_map()
		return
	if _world_map != null and _world_map.visible and _world_map.has_method(&"handle_mobile_action"):
		if not GameHUD.PHONE_MENU_NAMES.has(action) and action != "inventory":
			_world_map.call(&"handle_mobile_action", action)


func _on_world_map_visibility_changed() -> void:
	var im := get_node_or_null("/root/InputManager")
	if im != null and im.has_method(&"set_context"):
		if _world_map != null and _world_map.visible:
			im.call(&"set_context", InputManager.InputContext.MENU)
		elif hud == null or not hud.is_any_menu_open():
			im.call(&"set_context", InputManager.InputContext.OVERWORLD)
	var cm := get_node_or_null("/root/ConnectionManager")
	if _world_map != null and _world_map.visible:
		if cm != null and cm.has_method(&"send_to_all"):
			cm.call(&"send_to_all", {"active_menu": "map"})
	elif hud != null and hud.has_method(&"_sync_active_menu_to_phone"):
		hud.call(&"_sync_active_menu_to_phone")


func _build_world_map_bar() -> void:
	_map_button = Button.new()
	_map_button.name = "WorldMapButton"
	_map_button.anchor_left = 0.5
	_map_button.anchor_right = 0.5
	_map_button.anchor_top = 0.0
	_map_button.anchor_bottom = 0.0
	_map_button.offset_left = -220.0
	_map_button.offset_right = 220.0
	_map_button.offset_top = 18.0
	_map_button.offset_bottom = 64.0
	_map_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_map_button.add_theme_font_override("font", UI_FONT)
	_map_button.add_theme_font_size_override("font_size", 18)
	_map_button.pressed.connect(toggle_world_map)
	add_child(_map_button)

	_world_map = WORLD_MAP_SCRIPT.new()
	_world_map.name = "WorldMapOverlay"
	_world_map.visibility_changed.connect(_on_world_map_visibility_changed)
	add_child(_world_map)


func _on_world_time_changed(_state: Dictionary) -> void:
	_refresh_clock_button()


func _refresh_clock_button() -> void:
	if _map_button == null:
		return
	var gm := get_node_or_null("/root/GameManager")
	var txt := String(gm.call(&"get_world_clock_text")) if (gm != null and gm.has_method(&"get_world_clock_text")) else "Map & Time"
	_map_button.text = "Map [M]  •  %s" % txt


func _on_jeep_body_entered(body: Node2D) -> void:
	pass # Replace with function body.
