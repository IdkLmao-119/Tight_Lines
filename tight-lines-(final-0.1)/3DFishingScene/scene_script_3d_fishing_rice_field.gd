extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	InputManager.set_context(InputManager.InputContext.FISHING)
	InputManager.debug_log = true
	print(get_node_or_null("/root/GameDB"))
	print(get_node("/root/GameDB").get_summary())

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
