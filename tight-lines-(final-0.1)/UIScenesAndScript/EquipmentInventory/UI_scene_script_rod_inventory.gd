extends Control

signal close_requested

const ROD_BUTTON_MAP := {
	"LightRod": "rod_light",
	"MediumLightRod": "rod_medium_light",
	"MediumRod": "rod_medium",
	"MediumHeavyRod": "rod_medium_heavy",
	"HeavyRod": "rod_heavy",
}

const BAIT_BUTTON_MAP := {
	"Dough": "bait_1",
	"Worm": "bait_2",
	"Hardbait": "bait_3",
	"Shrimp": "bait_4",
	"Softbait": "bait_5",
	"TopwaterLure": "bait_6",
}

const ROD_ORDER := ["rod_light", "rod_medium_light", "rod_medium", "rod_medium_heavy", "rod_heavy"]
const BAIT_ORDER := ["bait_1", "bait_2", "bait_3", "bait_4", "bait_5", "bait_6"]

enum FocusSection { RODS, BAITS }

@onready var _status_label: Label = %StatusLabel
@onready var _back_button: Button = %BackButton
@onready var _rod_container: HBoxContainer = %RodContainer
@onready var _bait_container: VBoxContainer = %BaitContainer
@onready var _cursor_highlight: MobileCursorHighlight = %CursorHighlight

var _rod_buttons: Dictionary = {}
var _bait_buttons: Dictionary = {}
var _focus_section: FocusSection = FocusSection.RODS
var _focused_rod_idx: int = 0
var _focused_bait_idx: int = 0


func _ready() -> void:
	_bind_equipment_buttons()
	_back_button.pressed.connect(close)

	_ensure_starter_equipment()

	if SaveManager.has_signal(&"equipment_changed"):
		SaveManager.equipment_changed.connect(_refresh_ui)
	if InventoryManager.has_signal(&"inventory_changed"):
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	_refresh_ui()


func open() -> void:
	visible = true
	_ensure_starter_equipment()
	_refresh_ui()
	_highlight_focused.call_deferred()


func close() -> void:
	_cursor_highlight.clear()
	visible = false
	close_requested.emit()


func handle_mobile_action(action: String) -> void:
	match action:
		"back":
			close()
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

	_highlight_focused.call_deferred()


func _bind_equipment_buttons() -> void:
	for child in _rod_container.get_children():
		if child is TextureButton and ROD_BUTTON_MAP.has(child.name):
			var rod_id: String = ROD_BUTTON_MAP[child.name]
			var btn := child as TextureButton
			_rod_buttons[rod_id] = btn
			btn.pressed.connect(_equip_rod.bind(rod_id))

	for child in _bait_container.get_children():
		if child is TextureButton and BAIT_BUTTON_MAP.has(child.name):
			var bait_id: String = BAIT_BUTTON_MAP[child.name]
			var btn := child as TextureButton
			_bait_buttons[bait_id] = btn
			btn.pressed.connect(_equip_bait.bind(bait_id))


func _highlight_focused() -> void:
	if not visible:
		_cursor_highlight.clear()
		return
	var target: Control = null
	if _focus_section == FocusSection.RODS:
		var rod_id: String = ROD_ORDER[clampi(_focused_rod_idx, 0, ROD_ORDER.size() - 1)]
		target = _rod_buttons.get(rod_id)
	else:
		var bait_id: String = BAIT_ORDER[clampi(_focused_bait_idx, 0, BAIT_ORDER.size() - 1)]
		target = _bait_buttons.get(bait_id)
	_cursor_highlight.highlight(target)


func _ensure_starter_equipment() -> void:
	if SaveManager.get_owned_rods().is_empty():
		SaveManager.add_owned_rod("rod_light")
	if SaveManager.get_equipped_rod() == "":
		SaveManager.set_equipped_rod("rod_light")
	if SaveManager.get_equipped_bait() == "":
		SaveManager.set_equipped_bait("bait_1")


func _on_inventory_changed(_container_id: String) -> void:
	_refresh_ui()


func _on_visibility_changed() -> void:
	if visible:
		_ensure_starter_equipment()
		_refresh_ui()
		_highlight_focused.call_deferred()
	else:
		_cursor_highlight.clear()


func _refresh_ui(extra_msg: String = "") -> void:
	var eq_rod := SaveManager.get_equipped_rod()
	var eq_bait := SaveManager.get_equipped_bait()

	for rod_id: String in _rod_buttons:
		var btn: TextureButton = _rod_buttons[rod_id]
		var owned := SaveManager.has_rod(rod_id)
		var is_eq := (rod_id == eq_rod)
		var rod_name := GameDB.get_rod(rod_id).display_name if GameDB.has_rod(rod_id) else rod_id

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
		var count := InventoryManager.count_of(bait_id)
		var is_unlim := false
		var bait_name := bait_id
		if GameDB.has_bait(bait_id):
			var bait := GameDB.get_bait(bait_id)
			bait_name = bait.display_name
			is_unlim = bait.unlimited
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

	var rod_disp := GameDB.get_rod(eq_rod).display_name if GameDB.has_rod(eq_rod) else eq_rod
	var bait_disp := GameDB.get_bait(eq_bait).display_name if GameDB.has_bait(eq_bait) else eq_bait
	var base_text := "Equipped Rod: %s   |   Equipped Bait: %s" % [rod_disp, bait_disp]
	if extra_msg != "":
		base_text += "\n" + extra_msg
	_status_label.text = base_text


func _equip_rod(rod_id: String) -> void:
	if not SaveManager.has_rod(rod_id):
		var rname := GameDB.get_rod(rod_id).display_name if GameDB.has_rod(rod_id) else rod_id
		push_warning("EquipmentInventory: Cannot equip '%s' (rod not owned)." % rod_id)
		_refresh_ui("You don't own %s yet! Buy it at the Shop." % rname)
		return

	if SaveManager.set_equipped_rod(rod_id):
		_refresh_ui()


func _equip_bait(bait_id: String) -> void:
	var is_unlim := GameDB.has_bait(bait_id) and GameDB.get_bait(bait_id).unlimited
	if not is_unlim and not InventoryManager.has_item(bait_id, 1):
		var bname := GameDB.get_bait(bait_id).display_name if GameDB.has_bait(bait_id) else bait_id
		push_warning("EquipmentInventory: Not enough '%s' in Tackle Box to equip." % bait_id)
		_refresh_ui("No %s in Tackle Box! Buy some at the Shop." % bname)
		return

	if SaveManager.set_equipped_bait(bait_id):
		_refresh_ui()
