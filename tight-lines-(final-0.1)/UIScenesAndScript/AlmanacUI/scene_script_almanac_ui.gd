extends Control

signal close_requested

const GRID_COLUMNS := 4
const FISH_BUTTON_SIZE := Vector2(96, 96)
const TROPHY_TEXTURE_PATHS := {
	"Gold": "res://Assets/2D/trophy_gold.png",
	"Silver": "res://Assets/2D/trophy_silver.png",
	"Bronze": "res://Assets/2D/trophy_bronze.png",
}

const LOCATION_IDS: Array[String] = [
	"location_marikina",
	"location_kawit",
	"location_imus",
	"location_fish_pens",
	"location_salt_farm",
	"location_calatagan",
	"location_fortune_island",
]

const LOCATION_UNLOCK_FLAGS: Dictionary = {
	"location_marikina": "",
	"location_kawit": "unlock_kawit",
	"location_imus": "unlock_imus",
	"location_fish_pens": "unlock_fish_pens",
	"location_salt_farm": "unlock_salt_farm",
	"location_calatagan": "unlock_calatagan",
	"location_fortune_island": "unlock_fortune_island",
}

const REGULAR_ROD_IDS: Array[String] = [
	"rod_light",
	"rod_medium_light",
	"rod_medium",
	"rod_medium_heavy",
	"rod_heavy",
]

const REGULAR_BAIT_IDS: Array[String] = [
	"bait_1",
	"bait_2",
	"bait_3",
	"bait_4",
	"bait_5",
	"bait_6",
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
var _location_labels: Array[String] = []
var _fish_buttons: Array[TextureButton] = []
var _current_location_fish: Array[FishData] = []
var _current_location_id: String = ""
var _trophy_textures: Dictionary = {}

var _focus_area: FocusArea = FocusArea.FISH_GRID
var _focused_location_idx: int = 0
var _focused_fish_idx: int = 0


func _ready() -> void:
	_connect_location_buttons()
	_back_button.pressed.connect(close)
	visibility_changed.connect(_on_visibility_changed)
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_signal(&"unlock_flag_added"):
		sm.connect(&"unlock_flag_added", _on_unlock_flag_added)
	_clear_entry_display()
	_refresh_location_buttons()

	var first_idx := _get_first_unlocked_location_index()
	if first_idx >= 0:
		_focused_location_idx = first_idx
		_select_location(LOCATION_IDS[first_idx])


func open() -> void:
	var was_visible := visible
	visible = true
	if was_visible:
		_on_visibility_changed()


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
	_location_labels.clear()
	var idx := 0
	for child in _location_list.get_children():
		if child is Button and idx < LOCATION_IDS.size():
			var btn := child as Button
			var loc_id := LOCATION_IDS[idx]
			btn.pressed.connect(_on_location_button_pressed.bind(idx, loc_id))
			_location_buttons.append(btn)
			_location_labels.append(btn.text)
			idx += 1


func _is_location_unlocked(location_id: String) -> bool:
	var sm := get_node_or_null("/root/SaveManager")
	var unlocked_flags: Array = sm.call(&"get_unlock_flags") if (sm != null and sm.has_method(&"get_unlock_flags")) else []
	var req_flag := String(LOCATION_UNLOCK_FLAGS.get(location_id, ""))
	if req_flag != "" and not unlocked_flags.has(req_flag):
		return false
	var db := get_node_or_null("/root/GameDB")
	if db != null and bool(db.get("is_loaded")) and db.has_method(&"is_location_available"):
		return bool(db.call(&"is_location_available", location_id, {"unlocked": unlocked_flags}))
	return true


func _get_first_unlocked_location_index() -> int:
	for i in mini(_location_buttons.size(), LOCATION_IDS.size()):
		if _is_location_unlocked(LOCATION_IDS[i]):
			return i
	return -1


func _refresh_location_buttons() -> void:
	for i in mini(_location_buttons.size(), LOCATION_IDS.size()):
		var btn := _location_buttons[i]
		var loc_id := LOCATION_IDS[i]
		var unlocked := _is_location_unlocked(loc_id)
		btn.disabled = not unlocked
		btn.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
		btn.text = _location_labels[i] if unlocked else "???"


func _on_unlock_flag_added(_flag: String) -> void:
	_refresh_location_buttons()


func _on_location_button_pressed(idx: int, loc_id: String) -> void:
	if not _is_location_unlocked(loc_id):
		return
	_focused_location_idx = idx
	_select_location(loc_id)


func _on_visibility_changed() -> void:
	if visible:
		_refresh_location_buttons()
		if _current_location_id == "" or not _is_location_unlocked(_current_location_id):
			var first_idx := _get_first_unlocked_location_index()
			if first_idx >= 0:
				_focused_location_idx = first_idx
				_current_location_id = LOCATION_IDS[first_idx]
			else:
				_current_location_id = ""
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
	var count := mini(_location_buttons.size(), LOCATION_IDS.size())
	if count == 0:
		return
	var candidate := _focused_location_idx
	for _step in count:
		candidate = posmod(candidate + delta, count)
		if _is_location_unlocked(LOCATION_IDS[candidate]):
			_focused_location_idx = candidate
			_activate_focused_location()
			if not _current_location_fish.is_empty():
				_focus_area = FocusArea.FISH_GRID
			_highlight_focused.call_deferred()
			return


func _activate_focused_location() -> void:
	if _focused_location_idx >= 0 and _focused_location_idx < LOCATION_IDS.size():
		if _is_location_unlocked(LOCATION_IDS[_focused_location_idx]):
			_select_location(LOCATION_IDS[_focused_location_idx])


func _handle_location_nav(action: String) -> void:
	var count := mini(_location_buttons.size(), LOCATION_IDS.size())
	if count == 0:
		return
	match action:
		"up":
			for i in range(_focused_location_idx - 1, -1, -1):
				if _is_location_unlocked(LOCATION_IDS[i]):
					_focused_location_idx = i
					_activate_focused_location()
					break
		"down":
			for i in range(_focused_location_idx + 1, count):
				if _is_location_unlocked(LOCATION_IDS[i]):
					_focused_location_idx = i
					_activate_focused_location()
					break
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
	if not _is_location_unlocked(location_id):
		return
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
		var caught := SaveManager.has_caught_fish(fish.id)
		btn.modulate = Color.WHITE if caught else Color(0.15, 0.15, 0.15, 1.0)
		if caught:
			var trophy_tex := _get_trophy_texture(_get_fish_trophy_tier(fish.id))
			if trophy_tex != null:
				var trophy_bg := TextureRect.new()
				trophy_bg.name = "TrophyBackground"
				trophy_bg.show_behind_parent = true
				trophy_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
				trophy_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				trophy_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				trophy_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				trophy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				trophy_bg.texture = trophy_tex
				btn.add_child(trophy_bg)
		btn.pressed.connect(_on_fish_button_pressed.bind(i))
		_fish_grid.add_child(btn)
		_fish_buttons.append(btn)


func _get_fish_trophy_tier(fish_id: String) -> String:
	if not SaveManager.has_caught_fish(fish_id) or not SaveManager.has_method(&"get_fish_record") or not SaveManager.has_method(&"get_trophy_tier"):
		return ""
	var rec: Dictionary = SaveManager.get_fish_record(fish_id)
	var best_size := float(rec.get("best_size_cm", 0.0))
	if best_size <= 0.0:
		return ""
	return String(SaveManager.get_trophy_tier(fish_id, best_size))


func _get_trophy_texture(tier: String) -> Texture2D:
	if tier == "" or not TROPHY_TEXTURE_PATHS.has(tier):
		return null
	if _trophy_textures.has(tier):
		return _trophy_textures[tier] as Texture2D
	var path := String(TROPHY_TEXTURE_PATHS[tier])
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			tex = res
	if tex == null:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_trophy_textures[tier] = tex
	return tex


func _on_fish_button_pressed(index: int) -> void:
	if index >= 0 and index < _current_location_fish.size():
		_focused_fish_idx = index
		_show_fish(index)


func _show_fish(index: int) -> void:
	var fish: FishData = _current_location_fish[index]
	var caught := SaveManager.has_caught_fish(fish.id)
	var tex: Texture2D = fish.icon_3d if fish.icon_3d != null else fish.icon

	var rec_rod := _get_recommended_rod_text(fish)
	var rec_bait := _get_recommended_baits_text(fish)

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
		_fish_description.text = "%s\n\n[b]Size Class:[/b] %s\n[b]Avg Size:[/b] %.1f cm\n[b]Avg Weight:[/b] %.2f kg\n[b]Base Value:[/b] ₱%d\n[b]Recommended Rod:[/b] %s\n[b]Recommended Bait:[/b] %s%s" % [
			fish.description,
			fish.size_class.capitalize(),
			fish.avg_size,
			fish.avg_weight,
			fish.base_price,
			rec_rod,
			rec_bait,
			record_line,
		]
	else:
		_fish_picture.modulate = Color(0.15, 0.15, 0.15, 1.0)
		_fish_name.text = "???"
		_fish_scientific_name.text = "Unknown Species"
		_fish_description.text = "Catch this fish to unlock its Almanac entry.\n\n[b]Recommended Rod:[/b] %s\n[b]Recommended Bait:[/b] %s" % [
			rec_rod,
			rec_bait,
		]


func _get_recommended_rod_text(fish: FishData) -> String:
	var best_strong: RodData = null
	var best_strong_chance := -1.0
	var fallback_rod: RodData = null
	var fallback_strength := -1.0
	var fallback_chance := -1.0

	for rod_id in REGULAR_ROD_IDS:
		var rod: RodData = GameDB.get_rod(rod_id)
		if rod == null:
			continue
		var chance := rod.get_chance(fish.size_class)
		if chance <= 0.0:
			continue
		if rod.line_strength >= fish.pull_strength:
			if chance > best_strong_chance:
				best_strong_chance = chance
				best_strong = rod
		if rod.line_strength > fallback_strength or (is_equal_approx(rod.line_strength, fallback_strength) and chance > fallback_chance):
			fallback_strength = rod.line_strength
			fallback_chance = chance
			fallback_rod = rod

	var chosen := best_strong if best_strong != null else fallback_rod
	return chosen.display_name if chosen != null else "Any Rod"


func _get_recommended_baits_text(fish: FishData) -> String:
	var names: PackedStringArray = []
	for bait_id in REGULAR_BAIT_IDS:
		if GameDB.bait_enables_fish(bait_id, fish.id):
			var bait: BaitData = GameDB.get_bait(bait_id)
			if bait != null:
				names.append(bait.display_name)
	return ", ".join(names) if not names.is_empty() else "None"


func _clear_entry_display() -> void:
	_fish_picture.texture = null
	_fish_name.text = ""
	_fish_scientific_name.text = ""
	_fish_description.text = ""
