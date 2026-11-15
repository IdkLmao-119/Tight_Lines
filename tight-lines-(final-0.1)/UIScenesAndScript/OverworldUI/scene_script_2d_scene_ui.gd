extends Node

@export var fishing_manager: Node
@onready var Options: Control = $Options
@onready var Almanac: Control = $AlmanacUi
# Called when the node enters the sne tree for the first time.

func _ready() -> void:
	pass
	
func _process(delta: float) -> void:
	pass

func _on_Pause_button_pressed() -> void:
	Options.visible = true

func _on_almanac_button_pressed() -> void:
	Almanac.visible = true
