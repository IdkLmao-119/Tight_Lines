extends Control

const UI_THEME: Theme = preload("res://UIScenesAndScript/Shared/ui_theme.tres")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

@export var fishing_manager: Node

@onready var hud: GameHUD = %GameHUD

var _status_panel: PanelContainer = null
var _status_label: Label = null

var _cast_panel: PanelContainer = null
var _cast_bar: ProgressBar = null

var _fight_panel: PanelContainer = null
var _surge_label: Label = null
var _progress_bar: ProgressBar = null
var _stamina_bar: ProgressBar = null
var _pulse_time := 0.0


func _ready() -> void:
	hud.return_requested.connect(_on_return_requested)
	_build_fishing_hud()


func _process(delta: float) -> void:
	_pulse_time += delta
	var fm := _resolve_fishing_manager()
	_refresh_status_pill(fm)
	_refresh_fishing_meters(fm)


func open_menu(menu_id: String) -> void:
	hud.open_menu(menu_id)


func close_all_menus() -> void:
	hud.close_all_menus()


func get_hud_snapshot() -> Dictionary:
	return {
		"status_text": _status_label.text if _status_label != null else "",
		"cast_visible": _cast_panel.visible if _cast_panel != null else false,
		"cast_value": _cast_bar.value if _cast_bar != null else 0.0,
		"fight_visible": _fight_panel.visible if _fight_panel != null else false,
		"progress_value": _progress_bar.value if _progress_bar != null else 0.0,
		"stamina_value": _stamina_bar.value if _stamina_bar != null else 0.0,
		"surge_text": _surge_label.text if _surge_label != null else "",
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

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", UI_FONT)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_panel.add_child(_status_label)

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


func _refresh_status_pill(fm: Node) -> void:
	if _status_label == null:
		return
	var parts := PackedStringArray()

	var ws := get_tree().get_first_node_in_group("weather_system") if get_tree() != null else null
	if ws != null:
		var clock_str: String = String(ws.call("get_clock_text")) if ws.has_method("get_clock_text") else ""
		var tod: String = String(ws.get("time_of_day")).capitalize()
		var wx: String = String(ws.get("weather")).capitalize()
		if clock_str != "" and tod != "":
			parts.append("%s (%s)" % [clock_str, tod])
		if wx != "":
			parts.append(wx)

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

	_status_label.text = "  •  ".join(parts) if not parts.is_empty() else "Ready to Fish"


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
