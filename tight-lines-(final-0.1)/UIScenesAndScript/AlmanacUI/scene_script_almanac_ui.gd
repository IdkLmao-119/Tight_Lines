extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print(GameDB.get_all_fish())
	var fish_array: Array[FishData] = GameDB.get_all_fish()
	var fish_array_pointer: int = 0
	var fish: FishData = fish_array[fish_array_pointer]

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_previous_button_pressed() -> void:
	pass # Replace with function body.
func _on_next_button_pressed() -> void:
	pass # Replace with function body.
