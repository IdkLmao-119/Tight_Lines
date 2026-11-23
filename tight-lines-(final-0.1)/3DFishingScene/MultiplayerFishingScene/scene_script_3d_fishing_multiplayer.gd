extends Node3D

const UI_THEME: Theme = preload("res://UIScenesAndScript/Shared/ui_theme.tres")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

@onready var fishing_manager = $FishingManager   # adjust the path to your node
@onready var _hud: GameHUD = $GameHUDLayer/GameHUD
@onready var _mp_hud: Control = $CanvasLayer/MultiplayerHUD

@onready var _left_name_label: Label = %LeftHudNameLabel
@onready var _left_score_label: Label = %LeftHudScoreLabel
@onready var _right_name_label: Label = %RightHudNameLabel
@onready var _right_score_label: Label = %RightHudScoreLabel
@onready var _timer_title_label: Label = %TimerTitleLabel
@onready var _timer_value_label: Label = %TimerValueLabel

var _left_pid := 1
var _right_pid := 2
var _side_huds: Array[Dictionary] = []
var _status_panel: PanelContainer = null
var _clock_label: Label = null
var _tide_indicator: TideIndicator = null
var _status_label: Label = null
var _pulse_time := 0.0


func _ready() -> void:
	var main_world := get_world_3d()
	var vp1 := get_node_or_null("GridContainer/SubViewportContainer/SubViewport") as SubViewport
	var vp2 := get_node_or_null("GridContainer/SubViewportContainer2/SubViewport") as SubViewport
	if vp1 != null and main_world != null:
		vp1.world_3d = main_world
	if vp2 != null and main_world != null:
		vp2.world_3d = main_world
	_hud.return_requested.connect(_on_return_to_menu)
	if fishing_manager.has_signal(&"fish_caught"):
		fishing_manager.fish_caught.connect(_on_fish_caught)
	_build_fishing_hud()
	# Deferred so FishingManager's own _ready() has finished first.
	_start_two_player_round.call_deferred()


func _process(delta: float) -> void:
	_pulse_time += delta
	_refresh_timer_hud()
	_refresh_status_pill()
	_refresh_side_hud(0, _left_pid)
	_refresh_side_hud(1, _right_pid)


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

	var mode_id := "total_weight"
	if fishing_manager.has_method(&"get_context"):
		mode_id = String(fishing_manager.get_context().get("win_mode", "total_weight"))
	var mode_tag := "WEIGHT"
	match mode_id:
		"biggest_fish":
			mode_tag = "BIGGEST FISH"
		"most_fish":
			mode_tag = "MOST FISH"
	_timer_title_label.text = "TIME LEFT  •  %s" % mode_tag
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


func _build_fishing_hud() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.11, 0.14, 0.18, 0.78)
	card_style.border_color = Color(0.86, 0.74, 0.52, 0.85)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6

	_side_huds = [
		_build_side_hud(0, 0.25, card_style),
		_build_side_hud(1, 0.75, card_style),
	]

	_status_panel = PanelContainer.new()
	_status_panel.name = "FishingStatusPanel"
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.theme = UI_THEME
	_status_panel.add_theme_stylebox_override("panel", card_style)
	_status_panel.anchor_left = 0.5
	_status_panel.anchor_right = 0.5
	_status_panel.anchor_top = 1.0
	_status_panel.anchor_bottom = 1.0
	_status_panel.offset_left = -190.0
	_status_panel.offset_right = 190.0
	_status_panel.offset_top = -46.0
	_status_panel.offset_bottom = -10.0
	_status_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mp_hud.add_child(_status_panel)

	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	_status_panel.add_child(status_row)

	_clock_label = Label.new()
	_clock_label.name = "ClockLabel"
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_override("font", UI_FONT)
	_clock_label.add_theme_font_size_override("font_size", 15)
	_clock_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1.0))
	_clock_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_clock_label.add_theme_constant_override("outline_size", 4)
	status_row.add_child(_clock_label)

	_tide_indicator = TideIndicator.new()
	_tide_indicator.visible = false
	status_row.add_child(_tide_indicator)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", UI_FONT)
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_status_label.add_theme_constant_override("outline_size", 4)
	status_row.add_child(_status_label)


func _build_side_hud(slot_idx: int, center_anchor: float, card_style: StyleBoxFlat) -> Dictionary:
	var cast_panel := PanelContainer.new()
	cast_panel.name = "CastPowerPanel_%d" % slot_idx
	cast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_panel.theme = UI_THEME
	cast_panel.add_theme_stylebox_override("panel", card_style)
	cast_panel.anchor_left = center_anchor
	cast_panel.anchor_right = center_anchor
	cast_panel.anchor_top = 1.0
	cast_panel.anchor_bottom = 1.0
	cast_panel.offset_left = -140.0
	cast_panel.offset_right = 140.0
	cast_panel.offset_top = -124.0
	cast_panel.offset_bottom = -64.0
	cast_panel.visible = false
	_mp_hud.add_child(cast_panel)

	var cast_vbox := VBoxContainer.new()
	cast_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_vbox.add_theme_constant_override("separation", 4)
	cast_panel.add_child(cast_vbox)

	var cast_title := Label.new()
	cast_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_title.text = "CAST POWER"
	cast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_title.add_theme_font_override("font", UI_FONT)
	cast_title.add_theme_font_size_override("font_size", 15)
	cast_vbox.add_child(cast_title)

	var cast_bar := ProgressBar.new()
	cast_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_bar.min_value = 0.0
	cast_bar.max_value = 1.0
	cast_bar.show_percentage = false
	cast_bar.custom_minimum_size = Vector2(240, 16)
	cast_vbox.add_child(cast_bar)

	var fight_panel := PanelContainer.new()
	fight_panel.name = "FightMetersPanel_%d" % slot_idx
	fight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight_panel.theme = UI_THEME
	fight_panel.add_theme_stylebox_override("panel", card_style)
	fight_panel.anchor_left = center_anchor
	fight_panel.anchor_right = center_anchor
	fight_panel.anchor_top = 0.0
	fight_panel.anchor_bottom = 0.0
	fight_panel.offset_left = -165.0
	fight_panel.offset_right = 165.0
	fight_panel.offset_top = 114.0
	fight_panel.offset_bottom = 216.0
	fight_panel.visible = false
	_mp_hud.add_child(fight_panel)

	var fight_vbox := VBoxContainer.new()
	fight_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight_vbox.add_theme_constant_override("separation", 6)
	fight_panel.add_child(fight_vbox)

	var surge_label := Label.new()
	surge_label.name = "SurgeWarningLabel_%d" % slot_idx
	surge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	surge_label.add_theme_font_override("font", UI_FONT)
	surge_label.add_theme_font_size_override("font_size", 16)
	surge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	surge_label.add_theme_constant_override("outline_size", 4)
	fight_vbox.add_child(surge_label)

	var prog_row := HBoxContainer.new()
	prog_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog_row.add_theme_constant_override("separation", 8)
	fight_vbox.add_child(prog_row)

	var prog_lbl := Label.new()
	prog_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog_lbl.text = "Catch"
	prog_lbl.custom_minimum_size = Vector2(68, 0)
	prog_lbl.add_theme_font_override("font", UI_FONT)
	prog_lbl.add_theme_font_size_override("font_size", 14)
	prog_row.add_child(prog_lbl)

	var progress_bar := ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.custom_minimum_size = Vector2(0, 15)
	progress_bar.modulate = Color(0.35, 0.92, 0.52, 1.0)
	prog_row.add_child(progress_bar)

	var stam_row := HBoxContainer.new()
	stam_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stam_row.add_theme_constant_override("separation", 8)
	fight_vbox.add_child(stam_row)

	var stam_lbl := Label.new()
	stam_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stam_lbl.text = "Stamina"
	stam_lbl.custom_minimum_size = Vector2(68, 0)
	stam_lbl.add_theme_font_override("font", UI_FONT)
	stam_lbl.add_theme_font_size_override("font_size", 14)
	stam_row.add_child(stam_lbl)

	var stamina_bar := ProgressBar.new()
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 1.0
	stamina_bar.show_percentage = false
	stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stamina_bar.custom_minimum_size = Vector2(0, 13)
	stamina_bar.modulate = Color(1.0, 0.78, 0.30, 1.0)
	stam_row.add_child(stamina_bar)

	return {
		"cast_panel": cast_panel,
		"cast_bar": cast_bar,
		"fight_panel": fight_panel,
		"surge_label": surge_label,
		"progress_bar": progress_bar,
		"stamina_bar": stamina_bar,
	}


func _refresh_side_hud(slot_idx: int, pid: int) -> void:
	if slot_idx < 0 or slot_idx >= _side_huds.size():
		return
	var h: Dictionary = _side_huds[slot_idx]
	var cast_panel := h["cast_panel"] as PanelContainer
	var cast_bar := h["cast_bar"] as ProgressBar
	var fight_panel := h["fight_panel"] as PanelContainer
	var surge_label := h["surge_label"] as Label
	var progress_bar := h["progress_bar"] as ProgressBar
	var stamina_bar := h["stamina_bar"] as ProgressBar

	var info: Dictionary = fishing_manager.get_session_info(pid) if fishing_manager.has_method(&"get_session_info") else {}
	if info.is_empty():
		cast_panel.visible = false
		fight_panel.visible = false
		return

	var state := int(info.get("state", 0))
	var charge := float(info.get("cast_charge", 0.0))

	var show_cast := (state == 0 and charge > 0.01)
	cast_panel.visible = show_cast
	if show_cast:
		cast_bar.value = clampf(charge, 0.0, 1.0)
		cast_bar.modulate = Color(0.35, 0.88, 1.0).lerp(Color(1.0, 0.78, 0.25), charge)

	var is_reeling := (state == 3)
	fight_panel.visible = is_reeling
	if is_reeling:
		progress_bar.value = clampf(float(info.get("progress", 0.0)), 0.0, 1.0)
		stamina_bar.value = clampf(float(info.get("stamina_ratio", 0.0)), 0.0, 1.0)
		var surging := bool(info.get("surging", false))
		var release_hint := "[F / Spin CCW]" if pid == 1 else ("[O / Spin CCW]" if pid == 2 else "[Spin CCW]")
		var reel_hint := "[R / Spin CW]" if pid == 1 else ("[K / Spin CW]" if pid == 2 else "[Spin CW]")
		if surging:
			surge_label.text = "SURGE! Release %s" % release_hint
			var pulse := 0.65 + 0.35 * sin(_pulse_time * 14.0)
			surge_label.add_theme_color_override("font_color", Color(1.0, 0.32 * pulse, 0.22 * pulse, 1.0))
		else:
			surge_label.text = "REEL IN! %s" % reel_hint
			surge_label.add_theme_color_override("font_color", Color(0.55, 0.96, 0.82, 1.0))


func _refresh_status_pill() -> void:
	if _status_label == null:
		return
	var parts := PackedStringArray()
	var clock_txt := ""

	var ws := get_tree().get_first_node_in_group("weather_system") if get_tree() != null else null
	if ws != null:
		var clock_str: String = String(ws.call("get_clock_text")) if ws.has_method("get_clock_text") else ""
		var tod: String = String(ws.get("time_of_day")).capitalize()
		var wx: String = String(ws.get("weather")).capitalize()
		if clock_str != "" and tod != "":
			clock_txt = "%s (%s)" % [clock_str, tod]
		if wx != "":
			parts.append(wx)

	if _clock_label != null:
		_clock_label.text = clock_txt
		_clock_label.visible = (clock_txt != "")

	if _tide_indicator != null:
		var show_tide := fishing_manager != null and fishing_manager.has_method(&"is_current_spot_tidal") and bool(fishing_manager.call(&"is_current_spot_tidal"))
		_tide_indicator.visible = show_tide
		if show_tide and fishing_manager.has_method(&"get_tide_state"):
			_tide_indicator.set_tide(fishing_manager.call(&"get_tide_state"))

	var info: Dictionary = fishing_manager.get_session_info(_left_pid) if fishing_manager.has_method(&"get_session_info") else {}
	var rod_id := String(info.get("rod_id", ""))
	var bait_id := String(info.get("bait_id", ""))
	var db := get_node_or_null("/root/GameDB")

	if rod_id != "":
		var rod_name := rod_id
		if db != null and db.has_method("has_rod") and db.call("has_rod", rod_id):
			rod_name = String(db.call("get_rod", rod_id).display_name)
		parts.append(rod_name)

	if bait_id != "":
		var bait_name := bait_id
		if db != null and db.has_method("has_bait") and db.call("has_bait", bait_id):
			bait_name = String(db.call("get_bait", bait_id).display_name)
		parts.append("%s (∞)" % bait_name)

	if not parts.is_empty():
		var joined := "  •  ".join(parts)
		_status_label.text = ("•  " + joined) if clock_txt != "" else joined
	elif clock_txt != "":
		_status_label.text = ""
	else:
		_status_label.text = "Ready to Fish"
