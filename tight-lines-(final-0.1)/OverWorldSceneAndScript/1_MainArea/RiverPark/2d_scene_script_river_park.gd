extends Node2D

@onready var player: Node2D = $Player

func get_scene_state() -> Dictionary:
	return {"player_pos": player.global_position}

func _ready() -> void:
	var mem: Dictionary = GameManager.recall("overworld_river_park")
	if mem.has("player_pos"):
		player.global_position = mem["player_pos"]
		$Camera2D.reset_smoothing()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_river_park_to_river_park_fishing_spot_body_entered(body: Node2D) -> void:
	pass # Replace with function body.
