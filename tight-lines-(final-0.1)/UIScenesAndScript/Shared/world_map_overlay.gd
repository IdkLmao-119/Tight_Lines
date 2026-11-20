extends Control

signal close_requested
signal travel_requested(scene_id: String)

const UI_THEME: Theme = preload("res://UIScenesAndScript/Shared/ui_theme.tres")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

const DESTINATIONS: Array[Dictionary] = [
	{"name": "Marikina City (Home)", "region": "Metro Manila", "scene_id": "overworld_spawn", "location_id": "", "unlock_flag": ""},
	{"name": "Marikina River Park", "region": "Metro Manila", "scene_id": "overworld_river_park", "location_id": "location_marikina", "unlock_flag": ""},
	{"name": "Imus Fields", "region": "Cavite", "scene_id": "overworld_rice_field", "location_id": "location_imus", "unlock_flag": "unlock_imus"},
	{"name": "Kawit Seaside Park", "region": "Cavite", "scene_id": "overworld_fish_market", "location_id": "location_kawit", "unlock_flag": "unlock_kawit"},
	{"name": "Noveleta Fishing Pens", "region": "Cavite", "scene_id": "overworld_fishing_pens", "location_id": "location_fish_pens", "unlock_flag": "unlock_fish_pens"},
	{"name": "Noveleta Salt Farm", "region": "Cavite", "scene_id": "overworld_salt_farm", "location_id": "location_salt_farm", "unlock_flag": "unlock_salt_farm"},
	{"name": "Calatagan Mangroves", "region": "Batangas", "scene_id": "overworld_mangrove", "location_id": "location_calatagan", "unlock_flag": "unlock_calatagan"},
	{"name": "Fortune Island", "region": "Batangas", "scene_id": "overworld_island", "location_id": "location_fortune_island", "unlock_flag": "unlock_fortune_island"},
]

var _clock_label: Label = null
var _dest_grid: GridContainer = null
var _dest_buttons: Dictionary = {} # { scene_id: Button }


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI_THEME
	_build_ui()
	visible = false

	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal(&"world_time_changed"):
		gm.connect(&"world_time_changed", _on_world_time_changed)


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	close_requested.emit()


func refresh() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if _clock_label != null and gm != null and gm.has_method(&"get_world_clock_text"):
		_clock_label.text = String(gm.call(&"get_world_clock_text"))

	var sm := get_node_or_null("/root/SaveManager")
	var db := get_node_or_null("/root/GameDB")
	var unlocked_flags: Array = sm.call(&"get_unlock_flags") if (sm != null and sm.has_method(&"get_unlock_flags")) else []
	var caught_list: Array = sm.call(&"get_caught_fish") if (sm != null and sm.has_method(&"get_caught_fish")) else []

	for dest in DESTINATIONS:
		var sid: String = dest["scene_id"]
		var loc_id: String = dest["location_id"]
		var btn: Button = _dest_buttons.get(sid)
		if btn == null:
			continue

		var is_open := true
		var req_flag := String(dest.get("unlock_flag", ""))
		if req_flag != "" and not unlocked_flags.has(req_flag):
			is_open = false
		var progress_txt := "Safe Haven"
		if loc_id != "" and db != null and bool(db.get("is_loaded")):
			is_open = is_open and bool(db.call(&"is_location_available", loc_id, {"unlocked": unlocked_flags}))
			var pool: Array = db.call(&"get_location_fish_pool", loc_id)
			var total := pool.size()
			var caught := 0
			for entry in pool:
				if entry != null and entry.fish != null and caught_list.has(String(entry.fish.id)):
					caught += 1
			progress_txt = "%d / %d Species" % [caught, total] if is_open else "Locked"

		btn.disabled = not is_open
		btn.text = "%s\n%s  •  %s" % [dest["name"], dest["region"], progress_txt]


func get_destination_snapshot() -> Dictionary:
	var out := {}
	for sid in _dest_buttons:
		var btn: Button = _dest_buttons[sid]
		out[sid] = {"disabled": btn.disabled, "text": btn.text}
	return out


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _on_world_time_changed(_state: Dictionary) -> void:
	if visible:
		refresh()


func _on_rest_pressed(phase: String) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method(&"rest_to_phase"):
		gm.call(&"rest_to_phase", phase)
	refresh()


func _on_destination_pressed(scene_id: String) -> void:
	close()
	travel_requested.emit(scene_id)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method(&"change_scene") and String(gm.get("current_scene_id")) != scene_id:
		gm.call(&"change_scene", scene_id)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.24, 0.17, 0.10, 0.95)
	style.border_color = Color(0.88, 0.74, 0.46, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Philippine Fishing Map & Time"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78, 1.0))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseMapButton"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 44)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Clock + Rest Bar
	_clock_label = Label.new()
	_clock_label.name = "WorldClockLabel"
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_override("font", UI_FONT)
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color(0.75, 0.94, 1.0, 1.0))
	vbox.add_child(_clock_label)

	var rest_row := HBoxContainer.new()
	rest_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rest_row.add_theme_constant_override("separation", 10)
	vbox.add_child(rest_row)

	var rest_lbl := Label.new()
	rest_lbl.text = "Rest until:"
	rest_lbl.add_theme_font_size_override("font_size", 18)
	rest_row.add_child(rest_lbl)

	for entry in [
		{"phase": "dawn", "label": "Dawn (05:30)"},
		{"phase": "day", "label": "Day (09:00)"},
		{"phase": "dusk", "label": "Dusk (17:30)"},
		{"phase": "night", "label": "Night (21:00)"},
	]:
		var btn := Button.new()
		btn.name = "Rest_%s" % entry["phase"]
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(138, 40)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_rest_pressed.bind(entry["phase"]))
		rest_row.add_child(btn)

	# Destinations Grid
	_dest_grid = GridContainer.new()
	_dest_grid.columns = 2
	_dest_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dest_grid.add_theme_constant_override("h_separation", 14)
	_dest_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_dest_grid)

	for dest in DESTINATIONS:
		var sid: String = dest["scene_id"]
		var btn := Button.new()
		btn.name = "Dest_%s" % sid
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(320, 68)
		btn.add_theme_font_size_override("font_size", 17)
		btn.pressed.connect(_on_destination_pressed.bind(sid))
		_dest_grid.add_child(btn)
		_dest_buttons[sid] = btn
