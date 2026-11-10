extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	InputManager.set_context(InputManager.InputContext.FISHING)
	InputManager.set_multiplayer_mode(true)
	InputManager.debug_log = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
