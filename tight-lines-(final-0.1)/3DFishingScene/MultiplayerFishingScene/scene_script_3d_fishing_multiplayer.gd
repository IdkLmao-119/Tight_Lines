extends Node3D

@onready var fishing_manager = $FishingManager   # adjust the path to your node
@onready var _hud: GameHUD = $CanvasLayer/GameHUD

@onready var _left_name_label: Label = %LeftHudNameLabel
@onready var _left_score_label: Label = %LeftHudScoreLabel
@onready var _right_name_label: Label = %RightHudNameLabel
@onready var _right_score_label: Label = %RightHudScoreLabel
@onready var _timer_title_label: Label = %TimerTitleLabel
@onready var _timer_value_label: Label = %TimerValueLabel

var _left_pid := 1
var _right_pid := 2


func _ready() -> void:
	_hud.return_requested.connect(_on_return_to_menu)
	if fishing_manager.has_signal(&"fish_caught"):
		fishing_manager.fish_caught.connect(_on_fish_caught)
	# Deferred so FishingManager's own _ready() has finished first.
	_start_two_player_round.call_deferred()


func _process(_delta: float) -> void:
	_refresh_timer_hud()


func _start_two_player_round() -> void:
	var ids: Array[int] = [1, 2]
	if fishing_manager.has_method(&"get_context"):
		var ctx: Dictionary = fishing_manager.get_context()
		var ctx_ids: Variant = ctx.get("player_ids", [])
		if ctx_ids is Array and ctx_ids.size() >= 2:
			ids.assign([int(ctx_ids[0]), int(ctx_ids[1])])

	if not fishing_manager.has_method(&"get_player_order") or fishing_manager.get_player_order() != ids:
		fishing_manager.start_session(ids)

	_left_pid = ids[0]
	_right_pid = ids[1]

	_left_name_label.text = _player_display_name(_left_pid)
	_right_name_label.text = _player_display_name(_right_pid)
	_refresh_scores()
	_refresh_timer_hud()


func _player_display_name(pid: int) -> String:
	if fishing_manager.has_method(&"get_player_name"):
		return String(fishing_manager.get_player_name(pid))
	return "Player %d" % pid


func _on_fish_caught(_player_id: int, _fish: Dictionary) -> void:
	_refresh_scores()


func _refresh_scores() -> void:
	_left_score_label.text = _format_player_score(_left_pid)
	_right_score_label.text = _format_player_score(_right_pid)


func _format_player_score(pid: int) -> String:
	if not fishing_manager.has_method(&"get_session_info"):
		return "0 fish  •  0.00 kg"
	var info: Dictionary = fishing_manager.get_session_info(pid)
	if info.is_empty():
		return "0 fish  •  0.00 kg"
	var catches := int(info.get("catch_count", 0))
	var weight := float(info.get("total_weight", 0.0))
	return "%d fish  •  %.2f kg" % [catches, weight]


func _refresh_timer_hud() -> void:
	if not fishing_manager.has_method(&"get_time_left"):
		return
	var time_left: float = float(fishing_manager.get_time_left())
	if time_left < 0.0:
		_timer_title_label.text = "MODE"
		_timer_value_label.text = "FREE PLAY"
		_timer_value_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.94, 1.0))
		return

	var is_up := fishing_manager.has_method(&"is_time_up") and bool(fishing_manager.is_time_up())
	if is_up or time_left <= 0.0:
		_timer_title_label.text = "FINISHING..."
		_timer_value_label.text = "00:00"
		_timer_value_label.add_theme_color_override("font_color", Color(1.0, 0.36, 0.32, 1.0))
		return

	_timer_title_label.text = "TIME LEFT"
	var whole_sec := ceili(time_left)
	var mins := whole_sec / 60
	var secs := whole_sec % 60
	_timer_value_label.text = "%02d:%02d" % [mins, secs]

	if whole_sec <= 10:
		_timer_value_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.34, 1.0))
	elif whole_sec <= 30:
		_timer_value_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.32, 1.0))
	else:
		_timer_value_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.94, 1.0))


func _on_return_to_menu() -> void:
	GameManager.change_scene("multiplayer_lobby")
