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

var _sort_button: Button = null
var _lock_button: Button = null
var _compost_button: Button = null

var _slot_buttons: Array[TextureButton] = []
var _slot_lock_badges: Array[Label] = []
var _slot_uids: Array[int] = []
var _focused_index: int = 0
var _selected_uid: int = 0

var _confirm_overlay: ColorRect = null
var _confirm_message_label: Label = null
var _confirm_ok_button: Button = null
var _confirm_cancel_button: Button = null
var _pending_sell_mode: String = ""
var _pending_sell_uid: int = 0


func _ready() -> void:
	_build_action_buttons()
	_build_fish_slots()
	_build_sell_confirm_overlay()
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_back_button.pressed.connect(close)
	InventoryManager.inventory_changed.connect(_on_inventory_changed)
	visibility_changed.connect(_on_visibility_changed)

	_refresh_fish_buttons()
	_update_mode_ui()


func open() -> void:
	var was_visible := visible
	visible = true
	if was_visible:
		_refresh_fish_buttons()
		_update_mode_ui()
		_highlight_focused.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _confirm_overlay != null and _confirm_overlay.visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_hide_sell_confirm()


func close() -> void:
	_hide_sell_confirm()
	_cursor_highlight.clear()
	visible = false
	back_requested.emit()
	close_requested.emit()


func handle_mobile_action(action: String) -> void:
	if _confirm_overlay != null and _confirm_overlay.visible:
		match action:
			"select":
				_on_sell_confirm_pressed()
			"back":
				_hide_sell_confirm()
		return

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


func _build_action_buttons() -> void:
	var header := _sell_all_button.get_parent()
	if header == null:
		return
	var insert_idx := _sell_all_button.get_index()

	_sort_button = Button.new()
	_sort_button.name = "SortButton"
	_sort_button.text = "Sort"
	_sort_button.custom_minimum_size = Vector2(96, 56)
	_sort_button.add_theme_font_size_override("font_size", 20)
	_sort_button.pressed.connect(_on_sort_pressed)
	header.add_child(_sort_button)
	header.move_child(_sort_button, insert_idx)

	_lock_button = Button.new()
	_lock_button.name = "LockButton"
	_lock_button.text = "Lock"
	_lock_button.custom_minimum_size = Vector2(116, 56)
	_lock_button.add_theme_font_size_override("font_size", 20)
	_lock_button.pressed.connect(_on_lock_pressed)
	header.add_child(_lock_button)
	header.move_child(_lock_button, insert_idx + 1)

	_compost_button = Button.new()
	_compost_button.name = "CompostButton"
	_compost_button.text = "Compost"
	_compost_button.custom_minimum_size = Vector2(132, 56)
	_compost_button.add_theme_font_size_override("font_size", 20)
	_compost_button.pressed.connect(_on_compost_pressed)
	header.add_child(_compost_button)
	header.move_child(_compost_button, insert_idx + 2)


func _build_fish_slots() -> void:
	for child in _fish_grid.get_children():
		child.queue_free()
	_slot_buttons.clear()
	_slot_lock_badges.clear()

	var capacity := maxi(InventoryManager.get_container_capacity(InventoryManager.FISH_BOX), 28)
	_slot_uids.resize(capacity)
	_slot_uids.fill(0)

	for i in capacity:
		var btn := TextureButton.new()
		btn.custom_minimum_size = SLOT_SIZE
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.pressed.connect(_on_fish_slot_pressed.bind(i))

		var badge := Label.new()
		badge.text = "★"
		badge.visible = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(6, 2)
		badge.add_theme_font_size_override("font_size", 22)
		badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.24, 1.0))
		badge.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 1.0))
		badge.add_theme_constant_override("outline_size", 4)
		btn.add_child(badge)

		_fish_grid.add_child(btn)
		_slot_buttons.append(btn)
		_slot_lock_badges.append(badge)


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
		_hide_sell_confirm()
		_cursor_highlight.clear()


func _on_inventory_changed(container_id: String) -> void:
	if container_id == InventoryManager.FISH_BOX:
		_refresh_fish_buttons()
		_update_mode_ui()


func _refresh_fish_buttons() -> void:
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)
	var still_has_selected := false

	for i in _slot_buttons.size():
		var btn: TextureButton = _slot_buttons[i]
		var badge: Label = _slot_lock_badges[i]
		if i < fish_list.size():
			var fish: Dictionary = fish_list[i]
			var uid: int = fish["uid"]
			var fish_id: String = fish["item_id"]
			var locked := InventoryManager.is_item_locked(uid)
			if uid == _selected_uid:
				still_has_selected = true

			_slot_uids[i] = uid
			btn.texture_normal = _get_fish_texture(fish_id)
			btn.disabled = false
			badge.visible = locked

			var display_name := _get_fish_display_name(fish_id)
			var size_cm := float(fish["meta"].get("size_cm", 0.0))
			var weight := InventoryManager.get_fish_weight_kg(uid)
			var price := InventoryManager.get_fish_sell_price(uid)
			var lock_tag := " [Locked]" if locked else ""
			btn.tooltip_text = "%s%s\n%.1f cm | %.2f kg | ₱%d" % [display_name, lock_tag, size_cm, weight, price]
		else:
			_slot_uids[i] = 0
			btn.texture_normal = null
			btn.disabled = true
			badge.visible = false
			btn.tooltip_text = ""

	if not still_has_selected:
		_selected_uid = _slot_uids[0] if not _slot_uids.is_empty() else 0


func _update_mode_ui(extra_msg: String = "") -> void:
	var fish_count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX)
	var sellable_value := _get_total_fish_value(true)
	var sellable_count := _get_sellable_fish_count()

	_sell_all_button.visible = sell_mode
	_sell_all_button.text = "Sell All (+₱%d)" % sellable_value
	_sell_all_button.disabled = (sellable_count <= 0)

	if _sort_button != null:
		_sort_button.disabled = (fish_count <= 1)

	if _lock_button != null:
		_lock_button.visible = (not sell_mode)
		_lock_button.disabled = (_selected_uid == 0)
		_lock_button.text = "Unlock ★" if (_selected_uid != 0 and InventoryManager.is_item_locked(_selected_uid)) else "Lock ★"

	if _compost_button != null:
		_compost_button.visible = (not sell_mode)
		_compost_button.disabled = (_selected_uid == 0 or InventoryManager.is_item_locked(_selected_uid))

	if extra_msg != "":
		_info_label.text = extra_msg
	elif sell_mode:
		if sellable_count > 0:
			_info_label.text = "Click any unlocked fish to sell! (%d sellable / %d total)" % [sellable_count, fish_count]
		elif fish_count > 0:
			_info_label.text = "All %d fish are locked (★). Unlock in Fish Box to sell." % fish_count
		else:
			_info_label.text = "Your Fish Box is empty. Catch some fish first!"
	else:
		var capacity := InventoryManager.get_container_capacity(InventoryManager.FISH_BOX)
		_info_label.text = "Fish Box (%d / %d)" % [fish_count, capacity]


func _get_sellable_fish_count() -> int:
	var count := 0
	for fish: Dictionary in InventoryManager.get_items(InventoryManager.FISH_BOX):
		if not InventoryManager.is_item_locked(int(fish["uid"])):
			count += 1
	return count


func _get_total_fish_value(unlocked_only: bool = false) -> int:
	var total := 0
	for fish: Dictionary in InventoryManager.get_items(InventoryManager.FISH_BOX):
		var uid := int(fish["uid"])
		if unlocked_only and InventoryManager.is_item_locked(uid):
			continue
		total += InventoryManager.get_fish_sell_price(uid)
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

	_selected_uid = uid
	var fish_id: String = fish["item_id"]
	var display_name := _get_fish_display_name(fish_id)
	var size_cm := float(fish["meta"].get("size_cm", 0.0))
	var weight := InventoryManager.get_fish_weight_kg(uid)
	var price := InventoryManager.get_fish_sell_price(uid)
	var locked := InventoryManager.is_item_locked(uid)

	if sell_mode:
		if locked:
			_update_mode_ui("%s is locked (★)! Unlock it in Fish Box before selling." % display_name)
			return
		_pending_sell_mode = "single"
		_pending_sell_uid = uid
		_show_sell_confirm("Sell %s (%.1f cm) for ₱%d?" % [display_name, size_cm, price])
	else:
		var lock_note := "  [★ Locked]" if locked else ""
		_update_mode_ui("%s%s — %.1f cm | %.2f kg | Value: ₱%d" % [display_name, lock_note, size_cm, weight, price])


func _on_sell_all_pressed() -> void:
	if not sell_mode:
		return
	var sellable_count := _get_sellable_fish_count()
	if sellable_count <= 0:
		return
	var sellable_value := _get_total_fish_value(true)
	var locked_count := InventoryManager.get_used_slot_count(InventoryManager.FISH_BOX) - sellable_count
	var prompt := "Sell %d fish for ₱%d?" % [sellable_count, sellable_value]
	if locked_count > 0:
		prompt += "\n(%d locked ★ will be kept)" % locked_count
	_pending_sell_mode = "all"
	_pending_sell_uid = 0
	_show_sell_confirm(prompt)


func _build_sell_confirm_overlay() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.name = "SellConfirmOverlay"
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 200)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "SellConfirmTitle"
	title.text = "Confirm Sale"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_confirm_message_label = Label.new()
	_confirm_message_label.name = "SellConfirmMessage"
	_confirm_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_message_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_confirm_message_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_confirm_ok_button = Button.new()
	_confirm_ok_button.name = "SellConfirmButton"
	_confirm_ok_button.text = "Sell"
	_confirm_ok_button.custom_minimum_size = Vector2(130, 44)
	_confirm_ok_button.add_theme_font_size_override("font_size", 20)
	_confirm_ok_button.pressed.connect(_on_sell_confirm_pressed)
	btn_row.add_child(_confirm_ok_button)

	_confirm_cancel_button = Button.new()
	_confirm_cancel_button.name = "SellCancelButton"
	_confirm_cancel_button.text = "Cancel"
	_confirm_cancel_button.custom_minimum_size = Vector2(130, 44)
	_confirm_cancel_button.add_theme_font_size_override("font_size", 20)
	_confirm_cancel_button.pressed.connect(_hide_sell_confirm)
	btn_row.add_child(_confirm_cancel_button)


func _show_sell_confirm(message: String) -> void:
	if _confirm_overlay == null or _confirm_message_label == null:
		return
	_confirm_message_label.text = message
	_confirm_overlay.visible = true
	if _confirm_ok_button != null:
		_confirm_ok_button.grab_focus()


func _hide_sell_confirm() -> void:
	_pending_sell_mode = ""
	_pending_sell_uid = 0
	if _confirm_overlay != null:
		_confirm_overlay.visible = false


func _on_sell_confirm_pressed() -> void:
	var mode := _pending_sell_mode
	var uid := _pending_sell_uid
	_hide_sell_confirm()
	if mode == "single":
		_execute_sell_single(uid)
	elif mode == "all":
		_execute_sell_all()


func _execute_sell_single(uid: int) -> void:
	if uid == 0:
		return
	var fish: Dictionary = InventoryManager.get_item(uid)
	if fish.is_empty() or InventoryManager.is_item_locked(uid):
		return
	var fish_id: String = fish["item_id"]
	var display_name := _get_fish_display_name(fish_id)
	var size_cm := float(fish["meta"].get("size_cm", 0.0))
	var price := InventoryManager.get_fish_sell_price(uid)
	if InventoryManager.remove_item(uid) > 0:
		SaveManager.add_money(price)
		fish_sold.emit(display_name, price)
		_update_mode_ui("Sold %s (%.1f cm) for +₱%d!" % [display_name, size_cm, price])


func _execute_sell_all() -> void:
	var fish_list: Array = InventoryManager.get_items(InventoryManager.FISH_BOX)
	if fish_list.is_empty():
		return

	var total_earned := 0
	var count_sold := 0
	var skipped_locked := 0
	for fish: Dictionary in fish_list:
		var uid: int = fish["uid"]
		if InventoryManager.is_item_locked(uid):
			skipped_locked += 1
			continue
		var price := InventoryManager.get_fish_sell_price(uid)
		if InventoryManager.remove_item(uid) > 0:
			total_earned += price
			count_sold += 1

	if total_earned > 0:
		SaveManager.add_money(total_earned)
	if count_sold > 0:
		fish_sold.emit("%d fish" % count_sold, total_earned)
	var msg := "Sold %d fish for +₱%d!" % [count_sold, total_earned]
	if skipped_locked > 0:
		msg += " (Kept %d locked ★)" % skipped_locked
	_update_mode_ui(msg)


func _on_sort_pressed() -> void:
	InventoryManager.auto_arrange(InventoryManager.FISH_BOX)
	_update_mode_ui("Fish Box sorted by species and size!")


func _on_lock_pressed() -> void:
	if _selected_uid == 0:
		return
	var now_locked := InventoryManager.toggle_item_locked(_selected_uid)
	_update_mode_ui("Fish locked (★ protected from selling)." if now_locked else "Fish unlocked.")


func _on_compost_pressed() -> void:
	if _selected_uid == 0:
		return
	var res: Dictionary = InventoryManager.compost_fish(_selected_uid)
	if bool(res.get("ok", false)):
		_update_mode_ui("Composted into %s x%d!" % [String(res["bait_name"]), int(res["count"])])
	else:
		match String(res.get("reason", "")):
			"locked":
				_update_mode_ui("Unlock this fish before composting.")
			"tackle_box_full":
				_update_mode_ui("Tackle Box is full — cannot store composted bait.")
			_:
				_update_mode_ui("Could not compost selected fish.")
