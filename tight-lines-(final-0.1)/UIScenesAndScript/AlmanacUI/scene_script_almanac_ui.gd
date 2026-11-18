extends Control

@onready var FishName: Label = $FishEntry/FishName
@onready var Description: RichTextLabel = $FishEntry/FishDescription
@onready var FishPicture: TextureRect = $FishEntry/FishPicture
@onready var FishScientificName: Label = $FishEntry/FishScientificName
@onready var grid_vbox: VBoxContainer = $ScrollContainer/VBoxContainer

# Replace these string values with your actual LocationData IDs from GameDB
@onready var LOCATION_BUTTONS: Dictionary = {
	$VBoxContainer/PasigButton: "location_marikina",
	$VBoxContainer/KawitButton: "location_kawit",
	$VBoxContainer/ImusButton: "location_imus",
	$VBoxContainer/FishPensButton: "location_fish_pens",
	$VBoxContainer/SaltFarmButton: "location_salt_farm",
	$VBoxContainer/CalataganButton: "location_calatagan",
	$VBoxContainer/FortuneIsButton: "location_fortune_island",
}

const GRID_COLUMNS := 4

enum FocusArea { LOCATIONS, FISH_GRID }

var fish_buttons: Array[TextureButton] = []
var location_buttons: Array[Button] = []
var current_location_fish: Array[FishData] = []

var _focus_area: FocusArea = FocusArea.FISH_GRID
var _focused_location_idx: int = 0
var _focused_fish_idx: int = 0
var _cursor_highlight: Panel = null


func _ready() -> void:
	_collect_fish_buttons()
	_connect_location_buttons()
	_build_cursor_highlight()
	_clear_entry_display()
	visibility_changed.connect(_on_visibility_changed)

	if not LOCATION_BUTTONS.is_empty():
		var first_location_id: String = LOCATION_BUTTONS.values()[0]
		_select_location(first_location_id)


func _on_visibility_changed() -> void:
	if visible and not LOCATION_BUTTONS.is_empty():
		# Re-populate the grid so newly caught fish appear immediately
		_populate_fish_grid()
		_update_cursor_highlight.call_deferred()
	elif _cursor_highlight != null:
		_cursor_highlight.visible = false


func _collect_fish_buttons() -> void:
	fish_buttons.clear()
	for hbox in grid_vbox.get_children():
		for child in hbox.get_children():
			if child is TextureButton:
				var btn := child as TextureButton
				var index := fish_buttons.size()
				btn.pressed.connect(_on_fish_button_pressed.bind(index))
				fish_buttons.append(btn)


func _connect_location_buttons() -> void:
	location_buttons.clear()
	for button: Button in LOCATION_BUTTONS:
		var idx := location_buttons.size()
		var loc_id: String = LOCATION_BUTTONS[button]
		button.pressed.connect(_on_location_button_pressed.bind(idx, loc_id))
		location_buttons.append(button)


func _on_location_button_pressed(idx: int, loc_id: String) -> void:
	_focused_location_idx = idx
	_select_location(loc_id)


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
	style.set_corner_radius_all(6)
	_cursor_highlight.add_theme_stylebox_override("panel", style)
	add_child(_cursor_highlight)


func _update_cursor_highlight() -> void:
	if _cursor_highlight == null or not visible:
		return
	var target: Control = null
	if _focus_area == FocusArea.LOCATIONS:
		if _focused_location_idx >= 0 and _focused_location_idx < location_buttons.size():
			target = location_buttons[_focused_location_idx]
	else:
		if not current_location_fish.is_empty() and _focused_fish_idx >= 0 and _focused_fish_idx < fish_buttons.size():
			target = fish_buttons[_focused_fish_idx]
		elif _focused_location_idx >= 0 and _focused_location_idx < location_buttons.size():
			target = location_buttons[_focused_location_idx]

	if target == null:
		_cursor_highlight.visible = false
		return

	_cursor_highlight.visible = true
	_cursor_highlight.global_position = target.global_position - Vector2(3, 3)
	_cursor_highlight.size = target.size + Vector2(6, 6)


func handle_mobile_action(action: String) -> void:
	match action:
		"back":
			_on_back_button_pressed()
			return
		"tab_prev":
			_cycle_location(-1)
			return
		"tab_next":
			_cycle_location(1)
			return
		"select":
			if _focus_area == FocusArea.LOCATIONS:
				_activate_focused_location()
				if not current_location_fish.is_empty():
					_focus_area = FocusArea.FISH_GRID
			elif not current_location_fish.is_empty():
				_on_fish_button_pressed(_focused_fish_idx)
			_update_cursor_highlight.call_deferred()
			return

	if _focus_area == FocusArea.LOCATIONS:
		_handle_location_nav(action)
	else:
		_handle_grid_nav(action)
	_update_cursor_highlight.call_deferred()


func _cycle_location(delta: int) -> void:
	if location_buttons.is_empty():
		return
	_focused_location_idx = posmod(_focused_location_idx + delta, location_buttons.size())
	_activate_focused_location()
	if not current_location_fish.is_empty():
		_focus_area = FocusArea.FISH_GRID
	_update_cursor_highlight.call_deferred()


func _activate_focused_location() -> void:
	if _focused_location_idx < 0 or _focused_location_idx >= location_buttons.size():
		return
	var btn := location_buttons[_focused_location_idx]
	_select_location(LOCATION_BUTTONS[btn])


func _handle_location_nav(action: String) -> void:
	if location_buttons.is_empty():
		return
	match action:
		"up":
			_focused_location_idx = maxi(0, _focused_location_idx - 1)
			_activate_focused_location()
		"down":
			_focused_location_idx = mini(location_buttons.size() - 1, _focused_location_idx + 1)
			_activate_focused_location()
		"right":
			if not current_location_fish.is_empty():
				_focus_area = FocusArea.FISH_GRID
				_focused_fish_idx = clampi(_focused_fish_idx, 0, current_location_fish.size() - 1)
				_show_fish(_focused_fish_idx)


func _handle_grid_nav(action: String) -> void:
	var count := mini(current_location_fish.size(), fish_buttons.size())
	if count == 0:
		_focus_area = FocusArea.LOCATIONS
		return
	_focused_fish_idx = clampi(_focused_fish_idx, 0, count - 1)
	var col := _focused_fish_idx % GRID_COLUMNS
	match action:
		"left":
			if col > 0:
				_focused_fish_idx -= 1
			else:
				_focus_area = FocusArea.LOCATIONS
				return
		"right":
			if col < GRID_COLUMNS - 1 and _focused_fish_idx + 1 < count:
				_focused_fish_idx += 1
		"up":
			if _focused_fish_idx - GRID_COLUMNS >= 0:
				_focused_fish_idx -= GRID_COLUMNS
		"down":
			if _focused_fish_idx + GRID_COLUMNS < count:
				_focused_fish_idx += GRID_COLUMNS

	_show_fish(_focused_fish_idx)
	var scroll := get_node_or_null("ScrollContainer") as ScrollContainer
	if scroll != null and _focused_fish_idx < fish_buttons.size():
		scroll.ensure_control_visible(fish_buttons[_focused_fish_idx])


func _select_location(location_id: String) -> void:
	current_location_fish.clear()

	var pool: Array[PoolEntry] = GameDB.get_location_fish_pool(location_id)
	for entry in pool:
		if entry != null and entry.fish != null:
			current_location_fish.append(entry.fish)

	_populate_fish_grid()

	if not current_location_fish.is_empty():
		_focused_fish_idx = 0
		_show_fish(0)
	else:
		_focused_fish_idx = 0
		_clear_entry_display()


func _populate_fish_grid() -> void:
	for i in range(fish_buttons.size()):
		var btn: TextureButton = fish_buttons[i]

		if i < current_location_fish.size():
			var fish: FishData = current_location_fish[i]
			var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

			btn.texture_normal = tex
			btn.disabled = false

			if SaveManager.has_caught_fish(fish.id):
				btn.modulate = Color.WHITE
			else:
				btn.modulate = Color(0.15, 0.15, 0.15, 1.0)
		else:
			btn.texture_normal = null
			btn.disabled = true
			btn.modulate = Color.WHITE


func _on_fish_button_pressed(index: int) -> void:
	if index >= 0 and index < current_location_fish.size():
		_show_fish(index)


func _show_fish(index: int) -> void:
	var fish: FishData = current_location_fish[index]
	var caught: bool = SaveManager.has_caught_fish(fish.id)
	var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

	FishPicture.texture = tex

	if caught:
		FishPicture.modulate = Color.WHITE
		FishName.text = fish.display_name
		FishScientificName.text = fish.scientific_name
		Description.text = "%s\n\n[b]Size Class:[/b] %s\n[b]Avg Size:[/b] %.1f cm\n[b]Avg Weight:[/b] %.2f kg\n[b]Base Value:[/b] %d G" % [
			fish.description,
			fish.size_class.capitalize(),
			fish.avg_size,
			fish.avg_weight,
			fish.base_price
		]
	else:
		FishPicture.modulate = Color(0.15, 0.15, 0.15, 1.0)
		FishName.text = "???"
		FishScientificName.text = "Unknown Species"
		Description.text = "Catch this fish to unlock its Almanac entry."


func _clear_entry_display() -> void:
	FishPicture.texture = null
	FishName.text = ""
	FishScientificName.text = ""
	Description.text = ""


func _on_back_button_pressed() -> void:
	visible = false
