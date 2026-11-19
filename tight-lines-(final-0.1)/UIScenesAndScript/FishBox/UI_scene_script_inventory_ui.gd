extends Control

signal close_requested
signal back_requested
signal fish_sold(fish_name: String, price: int)

const GRID_COLS := 7
const SLOT_SIZE := Vector2(96, 96)

@export var sell_mode: bool = false:
	set(val):
		sell_mode = val
		if is_node_ready():
			_update_mode_ui()

@onready var _info_label: Label = %InfoLabel
@onready var _sell_all_button: Button = %SellAllButton
@onready var _back_button: Button = %BackButton
@onready var _fish_scroll: ScrollContainer = %FishScroll
@onready var _fish_grid: GridContainer = %FishGrid
@onready var _cursor_highlight: MobileCursorHighlight = %CursorHighlight

var _slot_buttons: Array[TextureButton] = []
var _slot_uids: Array[int] = []
var _focused_index: int = 0


func _ready() -> void:
	_build_fish_slots()
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_back_button.pressed.connect(close)
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	_refresh_fish_buttons()
	_update_mode_ui()


func open() -> void:
	visible = true
	_refresh_fish_buttons()
	_update_mode_ui()
	_highlight_focused.call_deferred()


func close() -> void:
	_cursor_highlight.clear()
	visible = false
	back_requested.emit()
	close_requested.emit()


func handle_mobile_action(action: String) -> void:
	if _slot_buttons.is_empty():
		return

	var col := _focused_index % GRID_COLS
	match action:
		"up":
			if _focused_index - GRID_COLS >= 0:
				_focused_index -= GRID_COLS
		"down":
			if _focused_index + GRID_COLS < _slot_buttons.size():
				_focused_index += GRID_COLS
		"left":
			if col > 0:
				_focused_index -= 1
		"right":
			if col < GRID_COLS - 1 and _focused_index + 1 < _slot_buttons.size():
				_focused_index += 1
		"select":
			_on_fish_slot_pressed(_focused_index)
		"back":
			close()
			return

	_fish_scroll.ensure_control_visible(_slot_buttons[_focused_index])
	_highlight_focused.call_deferred()


func _build_fish_slots() -> void:
	for child in _fish_grid.get_children():
		child.queue_free()
	_slot_buttons.clear()

	var capacity := maxi(InventoryManager.get_container_capacity(InventoryManager.FISH_BOX), 28)
	_slot_uids.resize(capacity)
	_slot_uids.fill(0)

	for i in capacity:
		var btn := TextureButton.new()
		btn.custom_minimum_size = SLOT_SIZE
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.pressed.connect(_on_fish_slot_pressed.bind(i))
		_fish_grid.add_child(btn)
		_slot_buttons.append(btn)


func _highlight_focused() -> void:
	if not visible or _slot_buttons.is_empty():
		_cursor_highlight.clear()
		return
	_focused_index = clampi(_focused_index, 0, _slot_buttons.size() - 1)
	_cursor_highlight.highlight(_slot_buttons[_focused_index])


func _on_visibility_changed() -> void:
	if visible:
		_refresh_fish_buttons()
		_update_mode_ui()
		_highlight_focused.call_deferred()
	else:
		_cursor_highlight.clear()


func _on_inventory_changed(container_id: String) -> void:
	if container_id == InventoryManager.FISH_BOX:
		_refresh_fish_buttons()
		_update_mode_ui()


func _refresh_fish_buttons() -> void:
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)

	for i in _slot_buttons.size():
		var btn: TextureButton = _slot_buttons[i]
		if i < fish_list.size():
			var fish: Dictionary = fish_list[i]
			var uid: int = fish["uid"]
			var fish_id: String = fish["item_id"]

			_slot_uids[i] = uid
			btn.texture_normal = _get_fish_texture(fish_id)
			btn.disabled = false

			var display_name := _get_fish_display_name(fish_id)
			var size_cm := float(fish["meta"].get("size_cm", 0.0))
			var weight := InventoryManager.get_fish_weight_kg(uid)
			var price := InventoryManager.get_fish_sell_price(uid)
			btn.tooltip_text = "%s\n%.1f cm | %.2f kg | %d G" % [display_name, size_cm, weight, price]
		else:
			_slot_uids[i] = 0
			btn.texture_normal = null
			btn.disabled = true
			btn.tooltip_text = ""


func _update_mode_ui(extra_msg: String = "") -> void:
	var fish_count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX)
	var total_value := _get_total_fish_value()

	_sell_all_button.visible = sell_mode
	_sell_all_button.text = "Sell All (+%dG)" % total_value
	_sell_all_button.disabled = (fish_count <= 0)

	if extra_msg != "":
		_info_label.text = extra_msg
	elif sell_mode:
		if fish_count > 0:
			_info_label.text = "Click any fish to sell it! (%d fish in box)" % fish_count
		else:
			_info_label.text = "Your Fish Box is empty. Catch some fish first!"
	else:
		var capacity := InventoryManager.get_container_capacity(InventoryManager.FISH_BOX)
		_info_label.text = "Fish Box (%d / %d)" % [fish_count, capacity]


func _get_total_fish_value() -> int:
	var total := 0
	for fish: Dictionary in InventoryManager.get_items(InventoryManager.FISH_BOX):
		total += InventoryManager.get_fish_sell_price(int(fish["uid"]))
	return total


func _get_fish_display_name(fish_id: String) -> String:
	if GameDB.has_fish(fish_id):
		var record: FishData = GameDB.get_fish(fish_id)
		if record != null and record.display_name != "":
			return record.display_name
	return fish_id


func _get_fish_texture(fish_id: String) -> Texture2D:
	if GameDB.has_fish(fish_id):
		var record: FishData = GameDB.get_fish(fish_id)
		if record != null:
			return record.icon_3d if record.icon_3d != null else record.icon
	return null


func _on_fish_slot_pressed(slot_index: int) -> void:
	var uid: int = _slot_uids[slot_index]
	if uid == 0:
		return

	var fish: Dictionary = InventoryManager.get_item(uid)
	if fish.is_empty():
		return

	var fish_id: String = fish["item_id"]
	var display_name := _get_fish_display_name(fish_id)
	var size_cm := float(fish["meta"].get("size_cm", 0.0))
	var weight := InventoryManager.get_fish_weight_kg(uid)
	var price := InventoryManager.get_fish_sell_price(uid)

	if sell_mode:
		InventoryManager.remove_item(uid)
		SaveManager.add_money(price)
		fish_sold.emit(display_name, price)
		_update_mode_ui("Sold %s (%.1f cm) for +%d G!" % [display_name, size_cm, price])
	else:
		_update_mode_ui("%s — %.1f cm | %.2f kg | Value: %d G" % [display_name, size_cm, weight, price])


func _on_sell_all_pressed() -> void:
	if not sell_mode:
		return
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)
	if fish_list.is_empty():
		return

	var total_earned := 0
	var count_sold := 0
	for fish: Dictionary in fish_list:
		var uid: int = fish["uid"]
		var price := InventoryManager.get_fish_sell_price(uid)
		if InventoryManager.remove_item(uid) > 0:
			total_earned += price
			count_sold += 1

	if total_earned > 0:
		SaveManager.add_money(total_earned)
	fish_sold.emit("%d fish" % count_sold, total_earned)
	_update_mode_ui("Sold %d fish for +%d G!" % [count_sold, total_earned])
