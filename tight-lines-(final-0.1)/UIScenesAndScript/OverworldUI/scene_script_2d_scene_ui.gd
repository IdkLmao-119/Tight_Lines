extends Control

const WORLD_MAP_SCRIPT := preload("res://UIScenesAndScript/Shared/world_map_overlay.gd")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

@onready var hud: GameHUD = %GameHUD

var _map_button: Button = null
var _world_map: Control = null


func _ready() -> void:
	_build_world_map_bar()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal(&"world_time_changed"):
		gm.connect(&"world_time_changed", _on_world_time_changed)
	_refresh_clock_button()


func open_menu(menu_id: String) -> void:
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()
	if _world_map != null and _world_map.visible:
		_world_map.call(&"close")


func open_world_map() -> void:
	if _world_map != null:
		hud.close_all_menus()
		_world_map.call(&"open")


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
	_map_button.pressed.connect(open_world_map)
	add_child(_map_button)

	_world_map = WORLD_MAP_SCRIPT.new()
	_world_map.name = "WorldMapOverlay"
	add_child(_world_map)


func _on_world_time_changed(_state: Dictionary) -> void:
	_refresh_clock_button()


func _refresh_clock_button() -> void:
	if _map_button == null:
		return
	var gm := get_node_or_null("/root/GameManager")
	var txt := String(gm.call(&"get_world_clock_text")) if (gm != null and gm.has_method(&"get_world_clock_text")) else "Map & Time"
	_map_button.text = "Map  •  %s" % txt
