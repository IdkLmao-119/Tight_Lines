extends HSlider

@export var bus_name: String = "Master"  # Default fallback if nothing is set in the Inspector

var bus_index: int

func _ready() -> void:
	# Get the bus index
	bus_index = AudioServer.get_bus_index(bus_name)
	
	# Safety check if the bus name doesn't exist
	if bus_index == -1:
		push_warning("Audio bus '" + bus_name + "' not found! Defaulting to Master.")
		bus_index = AudioServer.get_bus_index("Master")
		
	value_changed.connect(_on_value_changed)
	
func _on_value_changed(value: float) -> void:
	if bus_index != -1:
		AudioServer.set_bus_volume_db(
			bus_index,
			linear_to_db(value)
		)
