extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options
# Called when the node enters the sne tree for the first time.
func _ready() -> void:
	var im = get_node_or_null("/root/InputManager")
	if im != null and im.has_signal("menu_action"):
		im.menu_action.connect(_on_phone_menu_action)

func _on_phone_menu_action(_player_id: int, action: String) -> void:
	match action:
		"fish_box":
			_on_fish_box_button_pressed()
		"almanac":
			_on_almanac_button_pressed()
		"equipment":
			_on_rod_button_pressed()

# Called every frame. 'delta' is the elapsed time since the previous frame.
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
		$InventoryUi.visible = not $InventoryUi.visible

func _on_almanac_button_pressed() -> void:
	if has_node("AlmanacUi"):
		$AlmanacUi.visible = not $AlmanacUi.visible

func _on_rod_button_pressed() -> void:
	if has_node("Rod_Inventory"):
		$Rod_Inventory.visible = not $Rod_Inventory.visible

func _on_quest_button_pressed() -> void:
	if has_node("QuestLog"):
		$QuestLog.visible = not $QuestLog.visible
