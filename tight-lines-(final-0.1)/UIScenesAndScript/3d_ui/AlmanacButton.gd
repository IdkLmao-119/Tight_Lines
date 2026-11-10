const ALMANAC_SCENE := preload("res://UIScenesAndScript/AlmanacUI/FishAlmanacUI.tscn")
var _almanac: Control

func _ready():
	$AlmanacButton.pressed.connect(_open_almanac)

func _unhandled_input(event):
	if event.is_action_pressed("open_almanac"):   # optional keyboard shortcut
		_open_almanac()

func _open_almanac():
	if _almanac:
		return
	_almanac = ALMANAC_SCENE.instantiate()
	_almanac.process_mode = Node.PROCESS_MODE_ALWAYS
	_almanac.back_pressed.connect(_close_almanac)
	add_child(_almanac)          # the HUD CanvasLayer draws it on top
	get_tree().paused = true     # so the player can't walk around behind it

func _close_almanac():
	_almanac.queue_free()
	_almanac = null
	get_tree().paused = false
