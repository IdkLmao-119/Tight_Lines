extends Control

const UI_THEME: Theme = preload("res://UIScenesAndScript/Shared/ui_theme.tres")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")
const MARIKINA_TUTORIAL_FLAG := "seen_marikina_fishing_tutorial"
const MARIKINA_SPOT_ID := "location_marikina"
const TUTORIAL_COMPLETE_SECONDS := 4.5

@export var fishing_manager: Node

@onready var hud: GameHUD = %GameHUD

var _status_panel: PanelContainer = null
var _clock_label: Label = null
var _tide_indicator: TideIndicator = null
var _status_label: Label = null

var _cast_panel: PanelContainer = null
var _cast_bar: ProgressBar = null

var _fight_panel: PanelContainer = null
var _surge_label: Label = null
var _progress_bar: ProgressBar = null
var _stamina_bar: ProgressBar = null
var _pulse_time := 0.0

var _tutorial_panel: PanelContainer = null
var _tutorial_title_label: Label = null
var _tutorial_body_label: Label = null
var _tutorial_skip_button: Button = null
var _tutorial_complete_timer: float = 0.0


func _ready() -> void:
	hud.return_requested.connect(_on_return_requested)
	_build_fishing_hud()
	move_child(hud, -1)


func _process(delta: float) -> void:
	_pulse_time += delta
	var fm := _resolve_fishing_manager()
	_refresh_status_pill(fm)
	_refresh_fishing_meters(fm)
	_refresh_tutorial_card(fm, delta)


func open_menu(menu_id: String) -> void:
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()


func skip_tutorial() -> void:
	var save := get_node_or_null("/root/SaveManager")
	if save != null and save.has_method(&"add_unlock_flag"):
		save.call(&"add_unlock_flag", MARIKINA_TUTORIAL_FLAG)
	_tutorial_complete_timer = 0.0
	if _tutorial_panel != null:
		_tutorial_panel.visible = false


func get_hud_snapshot() -> Dictionary:
	var status_parts := PackedStringArray()
	if _clock_label != null and _clock_label.visible and _clock_label.text != "":
		status_parts.append(_clock_label.text)
	if _tide_indicator != null and _tide_indicator.visible:
		status_parts.append(_tide_indicator.get_display_text())
	if _status_label != null and _status_label.text != "":
		status_parts.append(_status_label.text)
	return {
		"status_text": "  •  ".join(status_parts),
		"tide_visible": _tide_indicator.visible if _tide_indicator != null else false,
		"tide_state": _tide_indicator.tide_state if _tide_indicator != null else "",
		"cast_visible": _cast_panel.visible if _cast_panel != null else false,
		"cast_value": _cast_bar.value if _cast_bar != null else 0.0,
		"fight_visible": _fight_panel.visible if _fight_panel != null else false,
		"progress_value": _progress_bar.value if _progress_bar != null else 0.0,
		"stamina_value": _stamina_bar.value if _stamina_bar != null else 0.0,
		"surge_text": _surge_label.text if _surge_label != null else "",
		"tutorial_visible": _tutorial_panel.visible if _tutorial_panel != null else false,
		"tutorial_title": _tutorial_title_label.text if _tutorial_title_label != null else "",
		"tutorial_body": _tutorial_body_label.text if _tutorial_body_label != null else "",
	}


func _resolve_fishing_manager() -> Node:
	if fishing_manager != null and is_instance_valid(fishing_manager):
		return fishing_manager
	if get_tree() != null and get_tree().current_scene != null:
		fishing_manager = get_tree().current_scene.find_child("FishingManager", true, false)
	if fishing_manager == null and get_parent() != null and get_parent().get_parent() != null:
		fishing_manager = get_parent().get_parent().find_child("FishingManager", true, false)
	return fishing_manager


func _on_return_requested() -> void:
	var fm := _resolve_fishing_manager()
	if fm != null and fm.has_method(&"finish_session"):
		fm.call(&"finish_session")
	else:
		GameManager.end_fishing({"results": {}})


func _build_fishing_hud() -> void:
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.11, 0.14, 0.18, 0.78)
	card_style.border_color = Color(0.86, 0.74, 0.52, 0.85)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8

	# --- Top-Center Status Pill (Weather / Time / Rod / Bait) ---
	_status_panel = PanelContainer.new()
	_status_panel.name = "FishingStatusPanel"
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.theme = UI_THEME
	_status_panel.add_theme_stylebox_override("panel", card_style)
	_status_panel.anchor_left = 0.5
	_status_panel.anchor_right = 0.5
	_status_panel.anchor_top = 0.0
	_status_panel.anchor_bottom = 0.0
	_status_panel.offset_left = -260.0
	_status_panel.offset_right = 260.0
	_status_panel.offset_top = 18.0
	_status_panel.offset_bottom = 64.0
	_status_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_status_panel)

	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 10)
	_status_panel.add_child(status_row)

	_clock_label = Label.new()
	_clock_label.name = "ClockLabel"
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_override("font", UI_FONT)
	_clock_label.add_theme_font_size_override("font_size", 18)
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
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_status_label.add_theme_constant_override("outline_size", 4)
	status_row.add_child(_status_label)

	# --- Cast Power Meter (bottom-center while charging cast) ---
	_cast_panel = PanelContainer.new()
	_cast_panel.name = "CastPowerPanel"
	_cast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_panel.theme = UI_THEME
	_cast_panel.add_theme_stylebox_override("panel", card_style)
	_cast_panel.anchor_left = 0.5
	_cast_panel.anchor_right = 0.5
	_cast_panel.anchor_top = 1.0
	_cast_panel.anchor_bottom = 1.0
	_cast_panel.offset_left = -160.0
	_cast_panel.offset_right = 160.0
	_cast_panel.offset_top = -124.0
	_cast_panel.offset_bottom = -64.0
	_cast_panel.visible = false
	add_child(_cast_panel)

	var cast_vbox := VBoxContainer.new()
	cast_vbox.add_theme_constant_override("separation", 4)
	_cast_panel.add_child(cast_vbox)

	var cast_title := Label.new()
	cast_title.text = "CAST POWER"
	cast_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_title.add_theme_font_override("font", UI_FONT)
	cast_title.add_theme_font_size_override("font_size", 16)
	cast_vbox.add_child(cast_title)

	_cast_bar = ProgressBar.new()
	_cast_bar.min_value = 0.0
	_cast_bar.max_value = 1.0
	_cast_bar.show_percentage = false
	_cast_bar.custom_minimum_size = Vector2(260, 18)
	cast_vbox.add_child(_cast_bar)

	# --- Fight HUD (Progress + Stamina + Surge Warning while REELING) ---
	_fight_panel = PanelContainer.new()
	_fight_panel.name = "FightMetersPanel"
	_fight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fight_panel.theme = UI_THEME
	_fight_panel.add_theme_stylebox_override("panel", card_style)
	_fight_panel.anchor_left = 0.5
	_fight_panel.anchor_right = 0.5
	_fight_panel.anchor_top = 0.0
	_fight_panel.anchor_bottom = 0.0
	_fight_panel.offset_left = -210.0
	_fight_panel.offset_right = 210.0
	_fight_panel.offset_top = 74.0
	_fight_panel.offset_bottom = 178.0
	_fight_panel.visible = false
	add_child(_fight_panel)

	var fight_vbox := VBoxContainer.new()
	fight_vbox.add_theme_constant_override("separation", 6)
	_fight_panel.add_child(fight_vbox)

	_surge_label = Label.new()
	_surge_label.name = "SurgeWarningLabel"
	_surge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_surge_label.add_theme_font_override("font", UI_FONT)
	_surge_label.add_theme_font_size_override("font_size", 18)
	_surge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_surge_label.add_theme_constant_override("outline_size", 4)
	fight_vbox.add_child(_surge_label)

	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	fight_vbox.add_child(prog_row)

	var prog_lbl := Label.new()
	prog_lbl.text = "Catch"
	prog_lbl.custom_minimum_size = Vector2(76, 0)
	prog_lbl.add_theme_font_override("font", UI_FONT)
	prog_lbl.add_theme_font_size_override("font_size", 15)
	prog_row.add_child(prog_lbl)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size = Vector2(0, 16)
	_progress_bar.modulate = Color(0.35, 0.92, 0.52, 1.0)
	prog_row.add_child(_progress_bar)

	var stam_row := HBoxContainer.new()
	stam_row.add_theme_constant_override("separation", 8)
	fight_vbox.add_child(stam_row)

	var stam_lbl := Label.new()
	stam_lbl.text = "Stamina"
	stam_lbl.custom_minimum_size = Vector2(76, 0)
	stam_lbl.add_theme_font_override("font", UI_FONT)
	stam_lbl.add_theme_font_size_override("font_size", 15)
	stam_row.add_child(stam_lbl)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.min_value = 0.0
	_stamina_bar.max_value = 1.0
	_stamina_bar.show_percentage = false
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_bar.custom_minimum_size = Vector2(0, 14)
	_stamina_bar.modulate = Color(1.0, 0.78, 0.30, 1.0)
	stam_row.add_child(_stamina_bar)

	# --- First-Time Marikina Fishing Tutorial Card ---
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.name = "MarikinaTutorialPanel"
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_panel.theme = UI_THEME
	_tutorial_panel.add_theme_stylebox_override("panel", card_style)
	_tutorial_panel.anchor_left = 0.5
	_tutorial_panel.anchor_right = 0.5
	_tutorial_panel.anchor_top = 0.0
	_tutorial_panel.anchor_bottom = 0.0
	_tutorial_panel.offset_left = -260.0
	_tutorial_panel.offset_right = 260.0
	_tutorial_panel.offset_top = 74.0
	_tutorial_panel.offset_bottom = 152.0
	_tutorial_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tutorial_panel.visible = false
	add_child(_tutorial_panel)

	var tut_vbox := VBoxContainer.new()
	tut_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_vbox.add_theme_constant_override("separation", 4)
	_tutorial_panel.add_child(tut_vbox)

	var tut_header := HBoxContainer.new()
	tut_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_header.add_theme_constant_override("separation", 8)
	tut_vbox.add_child(tut_header)

	_tutorial_title_label = Label.new()
	_tutorial_title_label.name = "TutorialTitleLabel"
	_tutorial_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_title_label.add_theme_font_override("font", UI_FONT)
	_tutorial_title_label.add_theme_font_size_override("font_size", 16)
	_tutorial_title_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.48, 1.0))
	_tutorial_title_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_tutorial_title_label.add_theme_constant_override("outline_size", 4)
	tut_header.add_child(_tutorial_title_label)

	_tutorial_skip_button = Button.new()
	_tutorial_skip_button.name = "TutorialSkipButton"
	_tutorial_skip_button.text = "Skip"
	_tutorial_skip_button.flat = true
	_tutorial_skip_button.focus_mode = Control.FOCUS_NONE
	_tutorial_skip_button.add_theme_font_override("font", UI_FONT)
	_tutorial_skip_button.add_theme_font_size_override("font_size", 14)
	_tutorial_skip_button.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94, 0.9))
	_tutorial_skip_button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.72, 1.0))
	_tutorial_skip_button.pressed.connect(skip_tutorial)
	tut_header.add_child(_tutorial_skip_button)

	_tutorial_body_label = Label.new()
	_tutorial_body_label.name = "TutorialBodyLabel"
	_tutorial_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_body_label.add_theme_font_override("font", UI_FONT)
	_tutorial_body_label.add_theme_font_size_override("font_size", 15)
	_tutorial_body_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))
	_tutorial_body_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_tutorial_body_label.add_theme_constant_override("outline_size", 3)
	tut_vbox.add_child(_tutorial_body_label)


func _refresh_status_pill(fm: Node) -> void:
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
		var show_tide := fm != null and fm.has_method(&"is_current_spot_tidal") and bool(fm.call(&"is_current_spot_tidal"))
		_tide_indicator.visible = show_tide
		if show_tide and fm.has_method(&"get_tide_state"):
			_tide_indicator.set_tide(fm.call(&"get_tide_state"))

	var info: Dictionary = _get_primary_session_info(fm)
	var rod_id := String(info.get("rod_id", ""))
	var bait_id := String(info.get("bait_id", ""))

	var db := get_node_or_null("/root/GameDB")
	var inv := get_node_or_null("/root/InventoryManager")

	if rod_id != "":
		var rod_name := rod_id
		if db != null and db.has_method("has_rod") and db.call("has_rod", rod_id):
			rod_name = String(db.call("get_rod", rod_id).display_name)
		parts.append(rod_name)

	if bait_id != "":
		var bait_name := bait_id
		var is_unlimited := false
		if db != null and db.has_method("has_bait") and db.call("has_bait", bait_id):
			var bait_rec: Variant = db.call("get_bait", bait_id)
			bait_name = String(bait_rec.display_name)
			is_unlimited = bool(bait_rec.unlimited)
		if is_unlimited:
			parts.append("%s (∞)" % bait_name)
		elif inv != null and inv.has_method("count_of"):
			parts.append("%s x%d" % [bait_name, int(inv.call("count_of", bait_id))])
		else:
			parts.append(bait_name)

	if not parts.is_empty():
		var joined := "  •  ".join(parts)
		_status_label.text = ("•  " + joined) if clock_txt != "" else joined
	elif clock_txt != "":
		_status_label.text = ""
	else:
		_status_label.text = "Ready to Fish"


func _refresh_fishing_meters(fm: Node) -> void:
	var info := _get_primary_session_info(fm)
	if info.is_empty():
		if _cast_panel != null:
			_cast_panel.visible = false
		if _fight_panel != null:
			_fight_panel.visible = false
		return

	var state := int(info.get("state", 0))
	var charge := float(info.get("cast_charge", 0.0))

	if _cast_panel != null and _cast_bar != null:
		var show_cast := (state == 0 and charge > 0.01) # State.IDLE
		_cast_panel.visible = show_cast
		if show_cast:
			_cast_bar.value = clampf(charge, 0.0, 1.0)
			_cast_bar.modulate = Color(0.35, 0.88, 1.0).lerp(Color(1.0, 0.78, 0.25), charge)

	if _fight_panel != null:
		var is_reeling := (state == 3) # State.REELING
		_fight_panel.visible = is_reeling
		if is_reeling:
			_progress_bar.value = clampf(float(info.get("progress", 0.0)), 0.0, 1.0)
			_stamina_bar.value = clampf(float(info.get("stamina_ratio", 0.0)), 0.0, 1.0)
			var surging := bool(info.get("surging", false))
			if surging:
				_surge_label.text = "SURGE! Release Line [F / Spin CCW]"
				var pulse := 0.65 + 0.35 * sin(_pulse_time * 14.0)
				_surge_label.add_theme_color_override("font_color", Color(1.0, 0.32 * pulse, 0.22 * pulse, 1.0))
			else:
				_surge_label.text = "REEL IN! [R / Spin CW]"
				_surge_label.add_theme_color_override("font_color", Color(0.55, 0.96, 0.82, 1.0))


func _get_primary_session_info(fm: Node) -> Dictionary:
	if fm == null or not fm.has_method(&"get_session_info"):
		return {}
	var pid := 1
	if fm.has_method(&"get_player_order"):
		var order: Array = fm.call(&"get_player_order")
		if not order.is_empty():
			pid = int(order[0])
	return fm.call(&"get_session_info", pid)


func _is_marikina_tutorial_spot(fm: Node) -> bool:
	if fm == null or bool(fm.get(&"_multiplayer")):
		return false
	var spot_id := ""
	if fm.has_method(&"get_context"):
		var ctx: Variant = fm.call(&"get_context")
		if ctx is Dictionary:
			spot_id = String((ctx as Dictionary).get("spot_id", ""))
	if spot_id == "":
		var gm := get_node_or_null("/root/GameManager")
		if gm != null and String(gm.get(&"current_scene_id")) == "fishing_river_park":
			return true
	return spot_id == MARIKINA_SPOT_ID


func _position_tutorial_panel(bottom_mode: bool) -> void:
	if _tutorial_panel == null:
		return
	if bottom_mode:
		_tutorial_panel.anchor_top = 1.0
		_tutorial_panel.anchor_bottom = 1.0
		_tutorial_panel.offset_top = -108.0
		_tutorial_panel.offset_bottom = -20.0
	elif _fight_panel != null and _fight_panel.visible:
		_tutorial_panel.anchor_top = 0.0
		_tutorial_panel.anchor_bottom = 0.0
		_tutorial_panel.offset_top = 188.0
		_tutorial_panel.offset_bottom = 266.0
	else:
		_tutorial_panel.anchor_top = 0.0
		_tutorial_panel.anchor_bottom = 0.0
		_tutorial_panel.offset_top = 74.0
		_tutorial_panel.offset_bottom = 152.0


func _refresh_tutorial_card(fm: Node, delta: float) -> void:
	if _tutorial_panel == null:
		return

	var gm := get_node_or_null("/root/GameManager")
	var story := get_node_or_null("/root/StoryManager")
	var blocked_by_ui := (
		(gm != null and bool(gm.get(&"is_changing_scene")))
		or (story != null and story.has_method(&"is_playing") and bool(story.call(&"is_playing")))
		or (hud != null and hud.is_any_menu_open())
	)

	if _tutorial_complete_timer > 0.0:
		_tutorial_complete_timer = maxf(_tutorial_complete_timer - delta, 0.0)
		if _tutorial_complete_timer <= 0.0:
			_tutorial_panel.visible = false
			return
		_position_tutorial_panel(true)
		_tutorial_panel.visible = not blocked_by_ui
		return

	var save := get_node_or_null("/root/SaveManager")
	if save == null or not save.has_method(&"has_unlock_flag") or bool(save.call(&"has_unlock_flag", MARIKINA_TUTORIAL_FLAG)):
		_tutorial_panel.visible = false
		return

	if blocked_by_ui or not _is_marikina_tutorial_spot(fm):
		_tutorial_panel.visible = false
		return

	var info := _get_primary_session_info(fm)
	if info.is_empty():
		_tutorial_panel.visible = false
		return

	var state := int(info.get("state", 0))
	var title_color := Color(1.0, 0.90, 0.48, 1.0)
	var title_text := ""
	var body_text := ""
	var show_skip := true

	match state:
		0: # State.IDLE
			title_text = "FISHING TUTORIAL (1/4)  —  AIM & CAST"
			body_text = "Aim with [A]/[D] (or Tilt Phone). Hold & release [Space] (or Swing Phone) to cast."
		1, 2: # State.CASTING, State.WAITING
			title_text = "FISHING TUTORIAL (2/4)  —  WAIT FOR A BITE"
			body_text = "Watch the bobber for a bite! Press [E] or [X] anytime to reel back early."
		3: # State.REELING
			var surging := bool(info.get("surging", false))
			var tension := float(info.get("tension_ratio", 0.0))
			if surging or tension >= 0.75:
				title_text = "FISHING TUTORIAL (3/4)  —  EASE THE TENSION!"
				title_color = Color(1.0, 0.38, 0.28, 1.0)
				body_text = "Fish is surging! Hold [F] / [Up] (or Spin Phone CCW) so the line won't snap."
			else:
				title_text = "FISHING TUTORIAL (3/4)  —  REEL IT IN!"
				title_color = Color(0.55, 0.96, 0.82, 1.0)
				body_text = "Fish is calm — hold [R] / [Down] (or Spin Phone CW) to fill the Catch bar!"
		6: # State.KNOTTING
			title_text = "FISHING TUTORIAL  —  TIE A KNOT"
			title_color = Color(1.0, 0.72, 0.35, 1.0)
			body_text = "Line snapped! Trace the knot on your phone (or press [E] on PC) to repair it."
		5: # State.ESCAPED
			title_text = "FISHING TUTORIAL  —  TRY AGAIN"
			title_color = Color(1.0, 0.65, 0.45, 1.0)
			body_text = "It got away! Cast again and hold [F] / [Up] whenever the fish surges."
		4: # State.CAUGHT
			save.call(&"add_unlock_flag", MARIKINA_TUTORIAL_FLAG)
			_tutorial_complete_timer = TUTORIAL_COMPLETE_SECONDS
			show_skip = false
			title_text = "TUTORIAL COMPLETE! (4/4)"
			title_color = Color(1.0, 0.90, 0.48, 1.0)
			body_text = "Nice catch! Catch every small fish in Marikina River — check Almanac & Quests anytime."
		_:
			_tutorial_panel.visible = false
			return

	_tutorial_title_label.text = title_text
	_tutorial_title_label.add_theme_color_override("font_color", title_color)
	_tutorial_body_label.text = body_text
	_tutorial_skip_button.visible = show_skip
	_position_tutorial_panel(_tutorial_complete_timer > 0.0)
	_tutorial_panel.visible = true
