extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options
# Called when the node enters the sne tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_Pause_button_pressed() -> void:
	Options.visible = true

func _on_back_button_pressed() -> void:
	Options.visible = false

func _on_overworld_button_pressed() -> void:
	if fishing_manager != null:
		fishing_manager.finish_session()
	else:
		GameManager.end_fishing({"results": {}})
