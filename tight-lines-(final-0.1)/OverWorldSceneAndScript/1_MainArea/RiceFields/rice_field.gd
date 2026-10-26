extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var ctx := GameManager.consume_context()
	var mem :Dictionary = GameManager.recall("RiceFields")
	if ctx.has("spawn"):
		$Player.global_position = $SpawnPoints.get_node(ctx["spawn"]).global_position
	elif mem.has("player_pos"):
		$Player.global_position = mem["player_pos"]
	$Player/Camera2D.reset_smoothing()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func get_scene_state() -> Dictionary:
	return {"player_pos": $Player.global_position}
