extends Node3D

@onready var fishing_manager = $FishingManager   # adjust the path to your node
@onready var _hud: GameHUD = $CanvasLayer/GameHUD


func _ready() -> void:
	_hud.return_requested.connect(_on_return_to_menu)
	# Deferred so FishingManager's own _ready() has finished first.
	_start_two_player_round.call_deferred()


func _start_two_player_round() -> void:
	var ids: Array[int] = [1, 2]
	fishing_manager.start_session(ids)


func _on_return_to_menu() -> void:
	GameManager.change_scene("main_menu")
