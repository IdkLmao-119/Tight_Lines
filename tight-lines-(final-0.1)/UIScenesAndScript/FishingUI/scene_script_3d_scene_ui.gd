extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options


func _ready() -> void:
	var im = get_node_or_null("/root/InputManager")
	if im != null and im.has_signal("menu_action"):
		im.menu_action.connect(_on_phone_menu_action)

	var cm = get_node_or_null("/root/ConnectionManager")
	if cm != null and cm.has_signal("player_connected"):
		cm.player_connected.connect(_on_phone_connected)

	for node_name in ["InventoryUi", "AlmanacUi", "Rod_Inventory"]:
		if has_node(node_name):
			get_node(node_name).visibility_changed.connect(_sync_active_menu_to_phone)


func _on_phone_connected(_player_id: int) -> void:
	_sync_active_menu_to_phone()


func _on_phone_menu_action(_player_id: int, action: String) -> void:
	match action:
		"fish_box":
			_on_fish_box_button_pressed()
			return
		"almanac":
			_on_almanac_button_pressed()
			return
		"equipment", "inventory":
			_on_rod_button_pressed()
			return

	var story = get_node_or_null("/root/StoryManager")
	if story != null and story.has_method("is_playing") and story.is_playing():
		return

	var active_node := _get_active_menu_node()
	if active_node != null and active_node.has_method("handle_mobile_action"):
		active_node.handle_mobile_action(action)


func _get_active_menu_name() -> String:
	if has_node("InventoryUi") and $InventoryUi.visible:
		return "fish_box"
	if has_node("AlmanacUi") and $AlmanacUi.visible:
		return "almanac"
	if has_node("Rod_Inventory") and $Rod_Inventory.visible:
		return "equipment"
	return "none"


func _get_active_menu_node() -> Control:
	if has_node("InventoryUi") and $InventoryUi.visible:
		return $InventoryUi
	if has_node("AlmanacUi") and $AlmanacUi.visible:
		return $AlmanacUi
	if has_node("Rod_Inventory") and $Rod_Inventory.visible:
		return $Rod_Inventory
	return null


func _sync_active_menu_to_phone() -> void:
	var cm = get_node_or_null("/root/ConnectionManager")
	if cm != null and cm.has_method("send_to_all"):
		cm.send_to_all({"active_menu": _get_active_menu_name()})


func _close_other_menus(except_name: String) -> void:
	for node_name in ["InventoryUi", "AlmanacUi", "Rod_Inventory", "QuestLog"]:
		if node_name != except_name and has_node(node_name):
			get_node(node_name).visible = false


func _process(_delta: float) -> void:
	pass


func _on_Pause_button_pressed() -> void:
	Options.visible = true


func _on_overworld_button_pressed() -> void:
	if fishing_manager != null:
		fishing_manager.finish_session()
	else:
		GameManager.end_fishing({"results": {}})


func _on_fish_box_button_pressed() -> void:
	if has_node("InventoryUi"):
		var opening: bool = not $InventoryUi.visible
		if opening:
			_close_other_menus("InventoryUi")
		$InventoryUi.visible = opening


func _on_almanac_button_pressed() -> void:
	if has_node("AlmanacUi"):
		var opening: bool = not $AlmanacUi.visible
		if opening:
			_close_other_menus("AlmanacUi")
		$AlmanacUi.visible = opening


func _on_rod_button_pressed() -> void:
	if has_node("Rod_Inventory"):
		var opening: bool = not $Rod_Inventory.visible
		if opening:
			_close_other_menus("Rod_Inventory")
		$Rod_Inventory.visible = opening


func _on_quest_button_pressed() -> void:
	if has_node("QuestLog"):
		var opening: bool = not $QuestLog.visible
		if opening:
			_close_other_menus("QuestLog")
		$QuestLog.visible = opening
