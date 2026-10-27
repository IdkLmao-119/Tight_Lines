extends Node2D

@onready var player: Node2D = $Player

func get_scene_state() -> Dictionary:
	return {"player_pos": player.global_position}

func _ready() -> void:
	var mem: Dictionary = GameManager.recall("overworld_rice_field")
	if mem.has("player_pos"):
		player.global_position = mem["player_pos"]
		$Camera2D.reset_smoothing()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
