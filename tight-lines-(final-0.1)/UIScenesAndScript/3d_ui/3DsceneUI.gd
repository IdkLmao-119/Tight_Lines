extends Node

var _player_ids
var _catches
var _total_weight
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_Pause_button_pressed() -> void:
	pass # Replace with function body.

func _on_back_button_pressed() -> void:
	pass # Replace with function body.

func _on_overworld_button_pressed() -> void:
	var result: Dictionary = {"results": {}}
	for pid in _player_ids:   # use your own list of players
		result["results"][pid] = {
		"catches": _catches[pid],
		"total_weight": _total_weight[pid]
	}
	GameManager.end_fishing(result)
