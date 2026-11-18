extends Control

const ROD_IDS := {
	"light": "rod_light",
	"medium_light": "rod_medium_light",
	"medium": "rod_medium",
	"medium_heavy": "rod_medium_heavy",
	"heavy": "rod_heavy",
}

const BAIT_IDS := {
	"dough": "bait_1",
	"worm": "bait_2",
	"hardbait": "bait_3",
	"shrimp": "bait_4",
	"softbait": "bait_5",
	"topwater_lure": "bait_6",
}

@onready var _rod_buttons: Dictionary = {
	"rod_light": get_node_or_null("Panel/HBoxContainer/LightRod"),
	"rod_medium_light": get_node_or_null("Panel/HBoxContainer/MediumLightRod"),
	"rod_medium": get_node_or_null("Panel/HBoxContainer/MediumRod"),
	"rod_medium_heavy": get_node_or_null("Panel/HBoxContainer/MediumHeavyRod"),
	"rod_heavy": get_node_or_null("Panel/HBoxContainer/HeavyRod"),
}

@onready var _bait_buttons: Dictionary = {
	"bait_1": get_node_or_null("Panel/VBoxContainer/Dough"),
	"bait_2": get_node_or_null("Panel/VBoxContainer/Worm"),
	"bait_3": get_node_or_null("Panel/VBoxContainer/Hardbait"),
	"bait_4": get_node_or_null("Panel/VBoxContainer/Shrimp"),
	"bait_5": get_node_or_null("Panel/VBoxContainer/Softbait"),
	"bait_6": get_node_or_null("Panel/VBoxContainer/TopwaterLure"),
}

const ROD_ORDER := ["rod_light", "rod_medium_light", "rod_medium", "rod_medium_heavy", "rod_heavy"]
const BAIT_ORDER := ["bait_1", "bait_2", "bait_3", "bait_4", "bait_5", "bait_6"]

enum FocusSection { RODS, BAITS }

var _status_label: Label = null
var _focus_section: FocusSection = FocusSection.RODS
var _focused_rod_idx: int = 0
var _focused_bait_idx: int = 0
var _cursor_highlight: Panel = null


func _ready() -> void:
	_ensure_starter_equipment()
	_build_status_label()
	_build_cursor_highlight()

	if SaveManager.has_signal("equipment_changed"):
		SaveManager.equipment_changed.connect(_refresh_ui)
	if InventoryManager.has_signal("inventory_changed"):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	_refresh_ui()


func _build_cursor_highlight() -> void:
	_cursor_highlight = Panel.new()
	_cursor_highlight.name = "MobileCursorHighlight"
	_cursor_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_highlight.z_index = 10
	_cursor_highlight.visible = false
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color(1.0, 0.85, 0.2, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	_cursor_highlight.add_theme_stylebox_override("panel", style)
	add_child(_cursor_highlight)


func _update_cursor_highlight() -> void:
	if _cursor_highlight == null or not visible:
		return
	var target: Control = null
	if _focus_section == FocusSection.RODS:
		var rod_id: String = ROD_ORDER[clampi(_focused_rod_idx, 0, ROD_ORDER.size() - 1)]
		target = _rod_buttons.get(rod_id)
	else:
		var bait_id: String = BAIT_ORDER[clampi(_focused_bait_idx, 0, BAIT_ORDER.size() - 1)]
		target = _bait_buttons.get(bait_id)

	if target == null:
		_cursor_highlight.visible = false
		return

	var rect := target.get_global_rect()
	_cursor_highlight.visible = true
	_cursor_highlight.global_position = rect.position - Vector2(4, 4)
	_cursor_highlight.size = rect.size + Vector2(8, 8)


func handle_mobile_action(action: String) -> void:
	match action:
		"back":
			_on_back_button_pressed()
			return
		"tab_prev":
			_focus_section = FocusSection.RODS
		"tab_next":
			_focus_section = FocusSection.BAITS
		"select":
			if _focus_section == FocusSection.RODS:
				_equip_rod(ROD_ORDER[_focused_rod_idx])
			else:
				_equip_bait(BAIT_ORDER[_focused_bait_idx])
		_:
			if _focus_section == FocusSection.RODS:
				match action:
					"left":
						_focused_rod_idx = maxi(0, _focused_rod_idx - 1)
					"right":
						if _focused_rod_idx < ROD_ORDER.size() - 1:
							_focused_rod_idx += 1
						else:
							_focus_section = FocusSection.BAITS
					"down":
						_focus_section = FocusSection.BAITS
			else:
				match action:
					"up":
						_focused_bait_idx = maxi(0, _focused_bait_idx - 1)
					"down":
						_focused_bait_idx = mini(BAIT_ORDER.size() - 1, _focused_bait_idx + 1)
					"left":
						_focus_section = FocusSection.RODS

	_update_cursor_highlight.call_deferred()


func _ensure_starter_equipment() -> void:
	if SaveManager.get_owned_rods().is_empty():
		SaveManager.add_owned_rod("rod_light")
	if SaveManager.get_equipped_rod() == "":
		SaveManager.set_equipped_rod("rod_light")
	if SaveManager.get_equipped_bait() == "":
		SaveManager.set_equipped_bait("bait_1")


func _build_status_label() -> void:
	var panel := get_node_or_null("Panel")
	if panel == null:
		return
	_status_label = Label.new()
	_status_label.name = "EquipmentStatusLabel"
	_status_label.offset_left = 80.0
	_status_label.offset_top = 40.0
	_status_label.offset_right = 900.0
	_status_label.offset_bottom = 90.0
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 6)
	panel.add_child(_status_label)


func _on_inventory_changed(_container_id: String) -> void:
	_refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		_ensure_starter_equipment()
		_refresh_ui()
		_update_cursor_highlight.call_deferred()
	elif _cursor_highlight != null:
		_cursor_highlight.visible = false


func _refresh_ui(extra_msg: String = "") -> void:
	var eq_rod := SaveManager.get_equipped_rod()
	var eq_bait := SaveManager.get_equipped_bait()

	for rod_id: String in _rod_buttons:
		var btn: TextureButton = _rod_buttons[rod_id]
		if btn == null:
			continue
		var owned := SaveManager.has_rod(rod_id)
		var is_eq := (rod_id == eq_rod)
		var rod_name := rod_id
		if GameDB.has_rod(rod_id):
			rod_name = GameDB.get_rod(rod_id).display_name
		if is_eq:
			btn.modulate = Color(1.2, 1.2, 0.8, 1.0)
			btn.tooltip_text = "%s (Equipped)" % rod_name
		elif owned:
			btn.modulate = Color(0.85, 0.85, 0.85, 1.0)
			btn.tooltip_text = "%s (Click to Equip)" % rod_name
		else:
			btn.modulate = Color(0.25, 0.25, 0.25, 0.85)
			btn.tooltip_text = "%s (Not Owned - Buy at Shop)" % rod_name

	for bait_id: String in _bait_buttons:
		var btn: TextureButton = _bait_buttons[bait_id]
		if btn == null:
			continue
		var count := InventoryManager.count_of(bait_id)
		var is_unlim := false
		var bait_name := bait_id
		if GameDB.has_bait(bait_id):
			var b := GameDB.get_bait(bait_id)
			bait_name = b.display_name
			is_unlim = b.unlimited
		var available := is_unlim or count > 0
		var is_eq := (bait_id == eq_bait)
		if is_eq:
			btn.modulate = Color(1.2, 1.2, 0.75, 1.0)
			btn.tooltip_text = "%s (Equipped%s)" % [bait_name, " - x%d" % count if count > 0 else ""]
		elif available:
			btn.modulate = Color(0.9, 0.9, 0.9, 1.0)
			btn.tooltip_text = "%s (Click to Equip%s)" % [bait_name, " - x%d" % count if count > 0 else ""]
		else:
			btn.modulate = Color(0.35, 0.35, 0.35, 0.85)
			btn.tooltip_text = "%s (0 in Tackle Box)" % bait_name

	if _status_label != null:
		var rod_disp := GameDB.get_rod(eq_rod).display_name if GameDB.has_rod(eq_rod) else eq_rod
		var bait_disp := GameDB.get_bait(eq_bait).display_name if GameDB.has_bait(eq_bait) else eq_bait
		var base_text := "Equipped Rod: %s   |   Equipped Bait: %s" % [rod_disp, bait_disp]
		if extra_msg != "":
			base_text += "\n" + extra_msg
		_status_label.text = base_text


# ============================================================================
# EQUIP HELPERS
# ============================================================================

func _equip_rod(rod_id: String) -> void:
	if not SaveManager.has_rod(rod_id):
		var rname := GameDB.get_rod(rod_id).display_name if GameDB.has_rod(rod_id) else rod_id
		push_warning("InventoryUI: Cannot equip '%s' (rod not owned)." % rod_id)
		_refresh_ui("You don't own %s yet! Buy it at the Shop." % rname)
		return

	if SaveManager.set_equipped_rod(rod_id):
		print("Equipped rod: ", rod_id)
		_refresh_ui()


func _equip_bait(bait_id: String) -> void:
	var is_unlim := false
	if GameDB.has_bait(bait_id):
		is_unlim = GameDB.get_bait(bait_id).unlimited

	if not is_unlim and not InventoryManager.has_item(bait_id, 1):
		var bname := GameDB.get_bait(bait_id).display_name if GameDB.has_bait(bait_id) else bait_id
		push_warning("InventoryUI: Not enough '%s' in Tackle Box to equip." % bait_id)
		_refresh_ui("No %s in Tackle Box! Buy some at the Shop." % bname)
		return

	if SaveManager.set_equipped_bait(bait_id):
		print("Equipped bait: ", bait_id)
		_refresh_ui()


# ============================================================================
# ROD BUTTON SIGNALS
# ============================================================================

func _on_light_rod_pressed() -> void:
	_equip_rod(ROD_IDS["light"])


func _on_medium_light_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium_light"])


func _on_medium_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium"])


func _on_medium_heavy_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium_heavy"])


func _on_heavy_rod_pressed() -> void:
	_equip_rod(ROD_IDS["heavy"])


# ============================================================================
# BAIT BUTTON SIGNALS
# ============================================================================

func _on_dough_pressed() -> void:
	_equip_bait(BAIT_IDS["dough"])


func _on_worm_pressed() -> void:
	_equip_bait(BAIT_IDS["worm"])


func _on_hardbait_pressed() -> void:
	_equip_bait(BAIT_IDS["hardbait"])


func _on_shrimp_pressed() -> void:
	_equip_bait(BAIT_IDS["shrimp"])


func _on_softbait_pressed() -> void:
	_equip_bait(BAIT_IDS["softbait"])


func _on_topwater_lure_pressed() -> void:
	_equip_bait(BAIT_IDS["topwater_lure"])


# ============================================================================
# UI NAVIGATION
# ============================================================================

func _on_back_button_pressed() -> void:
	visible = false
