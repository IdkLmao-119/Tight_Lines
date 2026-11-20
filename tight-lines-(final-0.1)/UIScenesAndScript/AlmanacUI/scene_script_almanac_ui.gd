extends Control

signal close_requested

const GRID_COLUMNS := 4
const FISH_BUTTON_SIZE := Vector2(96, 96)

const LOCATION_IDS: Array[String] = [
	"location_marikina",
	"location_kawit",
	"location_imus",
	"location_fish_pens",
	"location_salt_farm",
	"location_calatagan",
	"location_fortune_island",
]

enum FocusArea { LOCATIONS, FISH_GRID }

@onready var _location_list: VBoxContainer = %LocationList
@onready var _fish_scroll: ScrollContainer = %FishScroll
@onready var _fish_grid: GridContainer = %FishGrid
@onready var _fish_picture: TextureRect = %FishPicture
@onready var _fish_name: Label = %FishName
@onready var _fish_scientific_name: Label = %FishScientificName
@onready var _fish_description: RichTextLabel = %FishDescription
@onready var _back_button: Button = %BackButton
@onready var _cursor_highlight: MobileCursorHighlight = %CursorHighlight

var _location_buttons: Array[Button] = []
var _fish_buttons: Array[TextureButton] = []
var _current_location_fish: Array[FishData] = []
var _current_location_id: String = ""

var _focus_area: FocusArea = FocusArea.FISH_GRID
var _focused_location_idx: int = 0
var _focused_fish_idx: int = 0


func _ready() -> void:
	_connect_location_buttons()
	_back_button.pressed.connect(close)
	visibility_changed.connect(_on_visibility_changed)
	_clear_entry_display()

	if not LOCATION_IDS.is_empty():
		_select_location(LOCATION_IDS[0])


func open() -> void:
	visible = true
	if _current_location_id != "":
		_select_location(_current_location_id)
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
			_cycle_location(-1)
			return
		"tab_next":
			_cycle_location(1)
			return
		"select":
			if _focus_area == FocusArea.LOCATIONS:
				_activate_focused_location()
				if not _current_location_fish.is_empty():
					_focus_area = FocusArea.FISH_GRID
			elif not _current_location_fish.is_empty():
				_on_fish_button_pressed(_focused_fish_idx)
			_highlight_focused.call_deferred()
			return

	if _focus_area == FocusArea.LOCATIONS:
		_handle_location_nav(action)
	else:
		_handle_grid_nav(action)
	_highlight_focused.call_deferred()


func _connect_location_buttons() -> void:
	_location_buttons.clear()
	var idx := 0
	for child in _location_list.get_children():
		if child is Button and idx < LOCATION_IDS.size():
			var btn := child as Button
			var loc_id := LOCATION_IDS[idx]
			btn.pressed.connect(_on_location_button_pressed.bind(idx, loc_id))
			_location_buttons.append(btn)
			idx += 1


func _on_location_button_pressed(idx: int, loc_id: String) -> void:
	_focused_location_idx = idx
	_select_location(loc_id)


func _on_visibility_changed() -> void:
	if visible:
		if _current_location_id != "":
			_select_location(_current_location_id)
		_highlight_focused.call_deferred()
	else:
		_cursor_highlight.clear()


func _highlight_focused() -> void:
	if not visible:
		_cursor_highlight.clear()
		return
	var target: Control = null
	if _focus_area == FocusArea.LOCATIONS:
		if _focused_location_idx >= 0 and _focused_location_idx < _location_buttons.size():
			target = _location_buttons[_focused_location_idx]
	else:
		if not _current_location_fish.is_empty() and _focused_fish_idx >= 0 and _focused_fish_idx < _fish_buttons.size():
			target = _fish_buttons[_focused_fish_idx]
		elif _focused_location_idx >= 0 and _focused_location_idx < _location_buttons.size():
			target = _location_buttons[_focused_location_idx]
	_cursor_highlight.highlight(target)


func _cycle_location(delta: int) -> void:
	if _location_buttons.is_empty():
		return
	_focused_location_idx = posmod(_focused_location_idx + delta, _location_buttons.size())
	_activate_focused_location()
	if not _current_location_fish.is_empty():
		_focus_area = FocusArea.FISH_GRID
	_highlight_focused.call_deferred()


func _activate_focused_location() -> void:
	if _focused_location_idx >= 0 and _focused_location_idx < LOCATION_IDS.size():
		_select_location(LOCATION_IDS[_focused_location_idx])


func _handle_location_nav(action: String) -> void:
	if _location_buttons.is_empty():
		return
	match action:
		"up":
			_focused_location_idx = maxi(0, _focused_location_idx - 1)
			_activate_focused_location()
		"down":
			_focused_location_idx = mini(_location_buttons.size() - 1, _focused_location_idx + 1)
			_activate_focused_location()
		"right":
			if not _current_location_fish.is_empty():
				_focus_area = FocusArea.FISH_GRID
				_focused_fish_idx = clampi(_focused_fish_idx, 0, _current_location_fish.size() - 1)
				_show_fish(_focused_fish_idx)


func _handle_grid_nav(action: String) -> void:
	var count := mini(_current_location_fish.size(), _fish_buttons.size())
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
	if _focused_fish_idx < _fish_buttons.size():
		_fish_scroll.ensure_control_visible(_fish_buttons[_focused_fish_idx])


func _select_location(location_id: String) -> void:
	var changed := (location_id != _current_location_id)
	_current_location_id = location_id
	_current_location_fish.clear()

	var pool: Array[PoolEntry] = GameDB.get_location_fish_pool(location_id)
	for entry in pool:
		if entry != null and entry.fish != null:
			_current_location_fish.append(entry.fish)

	_rebuild_fish_grid()

	if not _current_location_fish.is_empty():
		_focused_fish_idx = 0 if changed else clampi(_focused_fish_idx, 0, _current_location_fish.size() - 1)
		_show_fish(_focused_fish_idx)
	else:
		_focused_fish_idx = 0
		_clear_entry_display()


func _rebuild_fish_grid() -> void:
	for child in _fish_grid.get_children():
		child.queue_free()
	_fish_buttons.clear()

	for i in _current_location_fish.size():
		var fish: FishData = _current_location_fish[i]
		var btn := TextureButton.new()
		btn.custom_minimum_size = FISH_BUTTON_SIZE
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.texture_normal = fish.icon_3d if fish.icon_3d != null else fish.icon
		btn.modulate = Color.WHITE if SaveManager.has_caught_fish(fish.id) else Color(0.15, 0.15, 0.15, 1.0)
		btn.pressed.connect(_on_fish_button_pressed.bind(i))
		_fish_grid.add_child(btn)
		_fish_buttons.append(btn)


func _on_fish_button_pressed(index: int) -> void:
	if index >= 0 and index < _current_location_fish.size():
		_focused_fish_idx = index
		_show_fish(index)


func _show_fish(index: int) -> void:
	var fish: FishData = _current_location_fish[index]
	var caught := SaveManager.has_caught_fish(fish.id)
	var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

	_fish_picture.texture = tex
	if caught:
		_fish_picture.modulate = Color.WHITE
		_fish_name.text = fish.display_name
		_fish_scientific_name.text = fish.scientific_name
		var rec: Dictionary = SaveManager.get_fish_record(fish.id) if SaveManager.has_method(&"get_fish_record") else {}
		var caught_count := int(rec.get("count", 1))
		var best_size := float(rec.get("best_size_cm", 0.0))
		var best_weight := float(rec.get("best_weight_kg", 0.0))
		var tier := String(SaveManager.get_trophy_tier(fish.id, best_size)) if (best_size > 0.0 and SaveManager.has_method(&"get_trophy_tier")) else ""
		var record_line := ""
		if best_size > 0.0:
			var tier_tag := " (%s Trophy)" % tier if tier != "" else ""
			record_line = "\n[b]Caught:[/b] %d  |  [b]Best:[/b] %.1f cm / %.2f kg%s" % [caught_count, best_size, best_weight, tier_tag]
		else:
			record_line = "\n[b]Caught:[/b] %d" % caught_count
		_fish_description.text = "%s\n\n[b]Size Class:[/b] %s\n[b]Avg Size:[/b] %.1f cm\n[b]Avg Weight:[/b] %.2f kg\n[b]Base Value:[/b] ₱%d%s" % [
			fish.description,
			fish.size_class.capitalize(),
			fish.avg_size,
			fish.avg_weight,
			fish.base_price,
			record_line,
		]
	else:
		_fish_picture.modulate = Color(0.15, 0.15, 0.15, 1.0)
		_fish_name.text = "???"
		_fish_scientific_name.text = "Unknown Species"
		_fish_description.text = "Catch this fish to unlock its Almanac entry."


func _clear_entry_display() -> void:
	_fish_picture.texture = null
	_fish_name.text = ""
	_fish_scientific_name.text = ""
	_fish_description.text = ""
