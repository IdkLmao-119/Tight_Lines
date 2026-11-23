extends Control

const MIN_DURATION_SEC := 30
const MAX_DURATION_SEC := 900
const STEP_DURATION_SEC := 30
const DEFAULT_DURATION_SEC := 120
const PRESET_DURATIONS := [60, 120, 180, 300]
const ACTIVITY_FLASH_SEC := 1.8

const WIN_MODES: Array[Dictionary] = [
	{"id": "total_weight", "label": "Total Weight"},
	{"id": "biggest_fish", "label": "Biggest Fish"},
	{"id": "most_fish", "label": "Most Fish"},
]

const ARENA_SPOTS: Array[Dictionary] = [
	{"id": "location_marikina", "label": "Marikina River", "rod_id": "rod_medium_heavy", "bait_id": "bait_2"},
	{"id": "location_imus", "label": "Imus Fields", "rod_id": "rod_medium_heavy", "bait_id": "bait_1"},
	{"id": "location_kawit", "label": "Kawit Seaside", "rod_id": "rod_medium_heavy", "bait_id": "bait_1"},
	{"id": "location_fish_pens", "label": "Noveleta Pens", "rod_id": "rod_medium_heavy", "bait_id": "bait_1"},
	{"id": "location_salt_farm", "label": "Noveleta Salt Farm", "rod_id": "rod_medium_heavy", "bait_id": "bait_1"},
	{"id": "location_calatagan", "label": "Calatagan Mangroves", "rod_id": "rod_medium_heavy", "bait_id": "bait_5"},
	{"id": "location_fortune_island", "label": "Fortune Island", "rod_id": "rod_medium_heavy", "bait_id": "bait_3"},
]

const COLOR_CONNECTED := Color(0.45, 0.95, 0.56, 1.0)
const COLOR_WAITING := Color(1.0, 0.72, 0.42, 1.0)
const COLOR_SCREEN_ACTIVE := Color(0.68, 0.92, 1.0, 1.0)
const COLOR_SCREEN_MENU := Color(1.0, 0.88, 0.52, 1.0)
const COLOR_SCREEN_OFF := Color(0.66, 0.66, 0.68, 1.0)
const COLOR_ACTIVITY_FLASH := Color(1.0, 0.88, 0.36, 1.0)
const COLOR_ACTIVITY_IDLE := Color(0.84, 0.82, 0.78, 1.0)

@onready var _back_button: Button = %BackButton
@onready var _server_info_label: Label = %ServerInfoLabel
@onready var _connection_count_label: Label = %ConnectionCountLabel

@onready var _left_card: PanelContainer = %LeftPlayerCard
@onready var _left_slot_tag_label: Label = %LeftSlotTagLabel
@onready var _left_conn_status_label: Label = %LeftConnStatusLabel
@onready var _left_phone_screen_label: Label = %LeftPhoneScreenLabel
@onready var _left_name_input: LineEdit = %LeftNameInput
@onready var _left_ping_button: Button = %LeftPingButton
@onready var _left_activity_label: Label = %LeftActivityLabel

@onready var _right_card: PanelContainer = %RightPlayerCard
@onready var _right_slot_tag_label: Label = %RightSlotTagLabel
@onready var _right_conn_status_label: Label = %RightConnStatusLabel
@onready var _right_phone_screen_label: Label = %RightPhoneScreenLabel
@onready var _right_name_input: LineEdit = %RightNameInput
@onready var _right_ping_button: Button = %RightPingButton
@onready var _right_activity_label: Label = %RightActivityLabel

@onready var _swap_sides_button: Button = %SwapSidesButton

@onready var _duration_60_button: Button = %Duration60Button
@onready var _duration_120_button: Button = %Duration120Button
@onready var _duration_180_button: Button = %Duration180Button
@onready var _duration_300_button: Button = %Duration300Button
@onready var _duration_minus_button: Button = %DurationMinusButton
@onready var _duration_value_label: Label = %DurationValueLabel
@onready var _duration_plus_button: Button = %DurationPlusButton

@onready var _readiness_label: Label = %ReadinessLabel
@onready var _start_match_button: Button = %StartMatchButton

@onready var _results_overlay: Control = %ResultsOverlay
@onready var _results_winner_label: Label = %ResultsWinnerLabel
@onready var _results_left_title: Label = %ResultsLeftTitle
@onready var _results_left_stats: Label = %ResultsLeftStats
@onready var _results_right_title: Label = %ResultsRightTitle
@onready var _results_right_stats: Label = %ResultsRightStats
@onready var _results_close_button: Button = %ResultsCloseButton
@onready var _results_rematch_button: Button = %ResultsRematchButton

var _duration_sec: int = DEFAULT_DURATION_SEC
var _win_mode_idx: int = 0
var _arena_idx: int = 0
var _slot_player_ids: Array[int] = [1, 2]
var _win_mode_button: Button = null
var _arena_button: Button = null
var _is_syncing_ui := false
var _activity_timers: Array[float] = [0.0, 0.0]

var _default_card_style: StyleBoxFlat
var _highlight_card_style: StyleBoxFlat
var _preset_buttons: Dictionary = {}
var _cm_connections: Array = []


func _ready() -> void:
	var base_style: StyleBox = _left_card.get_theme_stylebox("panel")
	if base_style is StyleBoxFlat:
		_default_card_style = base_style.duplicate() as StyleBoxFlat
		_highlight_card_style = base_style.duplicate() as StyleBoxFlat
		_highlight_card_style.border_color = Color(1.0, 0.86, 0.32, 1.0)
		_highlight_card_style.set_border_width_all(4)

	_preset_buttons = {
		60: _duration_60_button,
		120: _duration_120_button,
		180: _duration_180_button,
		300: _duration_300_button,
	}

	_restore_lobby_memory()
	_build_match_options_bar()
	_connect_ui_signals()
	_connect_connection_manager()
	_reconcile_connected_slots()
	_update_server_info()
	_refresh_all_ui()
	_sync_all_phone_identities()

	var ctx: Dictionary = GameManager.consume_context()
	if ctx.has("result") and ctx["result"] is Dictionary:
		_show_results_overlay(ctx["result"])
	else:
		_start_match_button.grab_focus()


func _exit_tree() -> void:
	_disconnect_connection_manager()


func _process(delta: float) -> void:
	for i in range(2):
		if _activity_timers[i] > 0.0:
			_activity_timers[i] = maxf(_activity_timers[i] - delta, 0.0)
			if _activity_timers[i] <= 0.0:
				_clear_card_activity(i)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return

	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit:
		focused.release_focus()
		get_viewport().set_input_as_handled()
		return

	if _results_overlay.visible:
		_close_results_overlay()
		get_viewport().set_input_as_handled()
		return

	_on_back_pressed()
	get_viewport().set_input_as_handled()


func get_scene_state() -> Dictionary:
	return {
		"duration_sec": _duration_sec,
		"slot_player_ids": _slot_player_ids.duplicate(),
		"win_mode_idx": _win_mode_idx,
		"arena_idx": _arena_idx,
	}


func _restore_lobby_memory() -> void:
	var mem: Dictionary = GameManager.recall("multiplayer_lobby")
	if mem.is_empty():
		return
	if mem.has("duration_sec"):
		_duration_sec = clampi(int(mem["duration_sec"]), MIN_DURATION_SEC, MAX_DURATION_SEC)
	if mem.has("win_mode_idx"):
		_win_mode_idx = clampi(int(mem["win_mode_idx"]), 0, WIN_MODES.size() - 1)
	if mem.has("arena_idx"):
		_arena_idx = clampi(int(mem["arena_idx"]), 0, ARENA_SPOTS.size() - 1)
	var saved_ids: Variant = mem.get("slot_player_ids", [])
	if saved_ids is Array and saved_ids.size() >= 2:
		var p0 := int(saved_ids[0])
		var p1 := int(saved_ids[1])
		if p0 > 0 and p1 > 0 and p0 != p1:
			_slot_player_ids.assign([p0, p1])


func _build_match_options_bar() -> void:
	var duration_row := _duration_value_label.get_parent() as Control
	if duration_row == null:
		return
	var margin_box := duration_row.get_parent()
	if margin_box == null:
		return
	var vbox := margin_box as VBoxContainer
	if vbox == null:
		vbox = VBoxContainer.new()
		vbox.name = "DurationVBox"
		vbox.add_theme_constant_override("separation", 8)
		margin_box.remove_child(duration_row)
		margin_box.add_child(vbox)
		vbox.add_child(duration_row)

	var row := HBoxContainer.new()
	row.name = "MatchOptionsRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	_win_mode_button = Button.new()
	_win_mode_button.name = "WinModeButton"
	_win_mode_button.custom_minimum_size = Vector2(240, 42)
	_win_mode_button.add_theme_font_size_override("font_size", 18)
	_win_mode_button.pressed.connect(_cycle_win_mode)
	row.add_child(_win_mode_button)

	_arena_button = Button.new()
	_arena_button.name = "ArenaButton"
	_arena_button.custom_minimum_size = Vector2(260, 42)
	_arena_button.add_theme_font_size_override("font_size", 18)
	_arena_button.pressed.connect(_cycle_arena)
	row.add_child(_arena_button)

	vbox.add_child(row)
	_refresh_match_options_ui()


func _cycle_win_mode() -> void:
	_win_mode_idx = (_win_mode_idx + 1) % WIN_MODES.size()
	_refresh_match_options_ui()


func _cycle_arena() -> void:
	_arena_idx = (_arena_idx + 1) % ARENA_SPOTS.size()
	_refresh_match_options_ui()


func _refresh_match_options_ui() -> void:
	if _win_mode_button != null:
		_win_mode_button.text = "Mode: %s" % WIN_MODES[_win_mode_idx]["label"]
	if _arena_button != null:
		_arena_button.text = "Arena: %s" % ARENA_SPOTS[_arena_idx]["label"]


func get_selected_win_mode() -> String:
	return String(WIN_MODES[_win_mode_idx]["id"])


func get_selected_arena_id() -> String:
	return String(ARENA_SPOTS[_arena_idx]["id"])


func get_selected_arena_rod_id() -> String:
	return String(ARENA_SPOTS[_arena_idx].get("rod_id", "rod_medium_heavy"))


func get_selected_arena_bait_id() -> String:
	return String(ARENA_SPOTS[_arena_idx].get("bait_id", "bait_1"))


func _connect_ui_signals() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_swap_sides_button.pressed.connect(_on_swap_sides_pressed)
	_start_match_button.pressed.connect(_start_match)

	_left_ping_button.pressed.connect(_on_ping_pressed.bind(0))
	_right_ping_button.pressed.connect(_on_ping_pressed.bind(1))

	_left_name_input.text_changed.connect(_on_name_text_changed.bind(0))
	_right_name_input.text_changed.connect(_on_name_text_changed.bind(1))
	_left_name_input.text_submitted.connect(_on_name_text_submitted.bind(0))
	_right_name_input.text_submitted.connect(_on_name_text_submitted.bind(1))

	for key in _preset_buttons:
		var sec: int = int(key)
		var btn: Button = _preset_buttons[key]
		btn.pressed.connect(_on_duration_preset_pressed.bind(sec))

	_duration_minus_button.pressed.connect(_adjust_duration.bind(-STEP_DURATION_SEC))
	_duration_plus_button.pressed.connect(_adjust_duration.bind(STEP_DURATION_SEC))

	_results_close_button.pressed.connect(_close_results_overlay)
	_results_rematch_button.pressed.connect(_on_rematch_pressed)


func _connect_connection_manager() -> void:
	var cm := _cm()
	if cm == null:
		return

	_bind_cm(cm, &"player_connected", _on_player_connected)
	_bind_cm(cm, &"player_disconnected", _on_player_disconnected)
	_bind_cm(cm, &"player_screen_changed", _on_player_screen_changed)
	_bind_cm(cm, &"player_name_changed", _on_player_name_changed)

	_bind_cm(cm, &"swipe_input", _on_phone_swipe)
	_bind_cm(cm, &"tap_input", _on_phone_tap)
	_bind_cm(cm, &"swing_input", _on_phone_swing)
	_bind_cm(cm, &"cancel_input", _on_phone_cancel)
	_bind_cm(cm, &"reel_input", _on_phone_reel)
	_bind_cm(cm, &"move_input", _on_phone_move)
	_bind_cm(cm, &"menu_action_input", _on_phone_menu_action)
	_bind_cm(cm, &"interact_input", _on_phone_interact)


func _bind_cm(cm: Node, sig_name: StringName, callable: Callable) -> void:
	if not cm.has_signal(sig_name):
		return
	if not cm.is_connected(sig_name, callable):
		cm.connect(sig_name, callable)
		_cm_connections.append({"signal": sig_name, "callable": callable})


func _disconnect_connection_manager() -> void:
	var cm := _cm()
	if cm == null:
		_cm_connections.clear()
		return
	for entry in _cm_connections:
		var sig_name: StringName = entry["signal"]
		var callable: Callable = entry["callable"]
		if cm.is_connected(sig_name, callable):
			cm.disconnect(sig_name, callable)
	_cm_connections.clear()


func _cm() -> Node:
	return get_node_or_null("/root/ConnectionManager")


func _reconcile_connected_slots() -> void:
	var cm := _cm()
	if cm == null or not cm.has_method(&"get_connected_players"):
		return
	var connected: Array = cm.call(&"get_connected_players")
	for raw_pid in connected:
		var pid := int(raw_pid)
		if _slot_player_ids.has(pid):
			continue
		for i in range(_slot_player_ids.size()):
			var current_pid := _slot_player_ids[i]
			if not bool(cm.call(&"is_player_connected", current_pid)):
				_slot_player_ids[i] = pid
				break


func _update_server_info() -> void:
	var cm := _cm()
	if cm == null:
		_server_info_label.text = "ConnectionManager unavailable"
		return
	var local_ip: String = String(cm.call(&"get_local_ip")) if cm.has_method(&"get_local_ip") else "unknown"
	var port: int = int(cm.call(&"get_port")) if cm.has_method(&"get_port") else 9080
	if local_ip == "" or local_ip == "unknown":
		_server_info_label.text = "Connect both phones on the same Wi-Fi / PC Hotspot (Port %d)" % port
	else:
		_server_info_label.text = "Same Wi-Fi / PC Hotspot  •  PC Server: ws://%s:%d" % [local_ip, port]


func _refresh_all_ui() -> void:
	_refresh_duration_ui()
	_sync_player_card(0)
	_sync_player_card(1)
	_refresh_readiness_ui()


func _sync_player_card(slot_index: int) -> void:
	var pid := _slot_player_ids[slot_index]
	var is_left := (slot_index == 0)
	var slot_tag_label := _left_slot_tag_label if is_left else _right_slot_tag_label
	var conn_label := _left_conn_status_label if is_left else _right_conn_status_label
	var screen_label := _left_phone_screen_label if is_left else _right_phone_screen_label
	var name_input := _left_name_input if is_left else _right_name_input
	var ping_button := _left_ping_button if is_left else _right_ping_button
	var activity_label := _left_activity_label if is_left else _right_activity_label

	slot_tag_label.text = "Controller Slot #%d" % pid

	var cm: Node = _cm()
	var connected: bool = cm != null and cm.has_method(&"is_player_connected") and bool(cm.call(&"is_player_connected", pid))
	var screen_display: String = String(cm.call(&"get_player_screen_display", pid)) if (cm != null and cm.has_method(&"get_player_screen_display")) else ("Overworld" if connected else "Disconnected")
	var raw_screen: String = String(cm.call(&"get_player_screen", pid)) if (cm != null and cm.has_method(&"get_player_screen")) else ""
	var has_custom: bool = cm != null and cm.has_method(&"has_custom_player_name") and bool(cm.call(&"has_custom_player_name", pid))
	var display_name: String = String(cm.call(&"get_player_name", pid)) if (cm != null and cm.has_method(&"get_player_name")) else ("Player %d" % pid)

	if connected:
		conn_label.text = "Connected"
		conn_label.add_theme_color_override("font_color", COLOR_CONNECTED)
		screen_label.text = "Phone Screen: %s" % screen_display
		if raw_screen.begins_with("menu"):
			screen_label.add_theme_color_override("font_color", COLOR_SCREEN_MENU)
		else:
			screen_label.add_theme_color_override("font_color", COLOR_SCREEN_ACTIVE)
		ping_button.disabled = false
	else:
		conn_label.text = "Waiting for Phone..."
		conn_label.add_theme_color_override("font_color", COLOR_WAITING)
		screen_label.text = "Phone Screen: Disconnected"
		screen_label.add_theme_color_override("font_color", COLOR_SCREEN_OFF)
		ping_button.disabled = true

	name_input.placeholder_text = "Player %d" % pid
	if not name_input.has_focus():
		_is_syncing_ui = true
		name_input.text = display_name if has_custom else ""
		_is_syncing_ui = false

	if _activity_timers[slot_index] <= 0.0:
		activity_label.text = "Tap / move phone to verify side" if connected else "Connect phone to test"
		activity_label.add_theme_color_override("font_color", COLOR_ACTIVITY_IDLE)
		_set_card_highlighted(slot_index, false)


func _refresh_readiness_ui() -> void:
	var cm := _cm()
	var left_connected := cm != null and cm.has_method(&"is_player_connected") and bool(cm.call(&"is_player_connected", _slot_player_ids[0]))
	var right_connected := cm != null and cm.has_method(&"is_player_connected") and bool(cm.call(&"is_player_connected", _slot_player_ids[1]))
	var connected_count := int(left_connected) + int(right_connected)

	_connection_count_label.text = "%d / 2 Connected" % connected_count

	var im := get_node_or_null("/root/InputManager")
	var debug_kb_allowed := im != null and bool(im.get("debug_keyboard_p2"))

	if connected_count == 2:
		_start_match_button.disabled = false
		_start_match_button.text = "Start Fishing!"
		_readiness_label.text = "Both phones connected and ready! Check your screen sides above."
		_readiness_label.add_theme_color_override("font_color", COLOR_CONNECTED)
	elif debug_kb_allowed:
		_start_match_button.disabled = false
		_start_match_button.text = "Start Fishing (Debug Keys)"
		_readiness_label.text = "%d / 2 phones connected — Debug keyboard active (P1: WASD/Space, P2: IJKL/U)" % connected_count
		_readiness_label.add_theme_color_override("font_color", COLOR_ACTIVITY_FLASH)
	else:
		_start_match_button.disabled = true
		_start_match_button.text = "Waiting for Players (%d/2)" % connected_count
		_readiness_label.text = "Connect both mobile controllers on the same network to start."
		_readiness_label.add_theme_color_override("font_color", COLOR_WAITING)


func _refresh_duration_ui() -> void:
	_duration_value_label.text = _format_duration(_duration_sec)
	_duration_minus_button.disabled = (_duration_sec <= MIN_DURATION_SEC)
	_duration_plus_button.disabled = (_duration_sec >= MAX_DURATION_SEC)

	for key in _preset_buttons:
		var sec: int = int(key)
		var btn: Button = _preset_buttons[key]
		btn.set_pressed_no_signal(sec == _duration_sec)


func _format_duration(total_seconds: int) -> String:
	var mins := total_seconds / 60
	var secs := total_seconds % 60
	return "%02d:%02d" % [mins, secs]


func _on_duration_preset_pressed(seconds: int) -> void:
	_duration_sec = clampi(seconds, MIN_DURATION_SEC, MAX_DURATION_SEC)
	_refresh_duration_ui()


func _adjust_duration(delta_sec: int) -> void:
	_duration_sec = clampi(_duration_sec + delta_sec, MIN_DURATION_SEC, MAX_DURATION_SEC)
	_refresh_duration_ui()


func _on_swap_sides_pressed() -> void:
	if _left_name_input.has_focus():
		_left_name_input.release_focus()
	if _right_name_input.has_focus():
		_right_name_input.release_focus()

	var tmp_pid := _slot_player_ids[0]
	_slot_player_ids[0] = _slot_player_ids[1]
	_slot_player_ids[1] = tmp_pid

	var tmp_timer := _activity_timers[0]
	_activity_timers[0] = _activity_timers[1]
	_activity_timers[1] = tmp_timer

	var tmp_act_text := _left_activity_label.text
	_left_activity_label.text = _right_activity_label.text
	_right_activity_label.text = tmp_act_text

	_refresh_all_ui()
	if _activity_timers[0] > 0.0:
		_set_card_highlighted(0, true)
	if _activity_timers[1] > 0.0:
		_set_card_highlighted(1, true)
	_sync_all_phone_identities()


func _on_name_text_changed(new_text: String, slot_index: int) -> void:
	if _is_syncing_ui:
		return
	var cm := _cm()
	if cm == null or not cm.has_method(&"set_player_name"):
		return
	var pid := _slot_player_ids[slot_index]
	cm.call(&"set_player_name", pid, new_text)
	_sync_phone_identity_for_slot(slot_index)


func _on_name_text_submitted(_new_text: String, slot_index: int) -> void:
	var input := _left_name_input if slot_index == 0 else _right_name_input
	input.release_focus()
	_sync_player_card(slot_index)


func _on_ping_pressed(slot_index: int) -> void:
	var cm := _cm()
	if cm == null or not cm.has_method(&"ping_player"):
		return
	var pid := _slot_player_ids[slot_index]
	if bool(cm.call(&"ping_player", pid)):
		_flash_slot_activity(slot_index, "Ping sent! Phone vibrated")


func _sync_all_phone_identities() -> void:
	_sync_phone_identity_for_slot(0)
	_sync_phone_identity_for_slot(1)


func _sync_phone_identity_for_slot(slot_index: int) -> void:
	var cm := _cm()
	if cm == null or not cm.has_method(&"sync_player_identity"):
		return
	var pid := _slot_player_ids[slot_index]
	var side := "left" if slot_index == 0 else "right"
	var display_name: String = String(cm.call(&"get_player_name", pid)) if cm.has_method(&"get_player_name") else ("Player %d" % pid)
	cm.call(&"sync_player_identity", pid, display_name, side)


func _slot_index_for_player(player_id: int) -> int:
	return _slot_player_ids.find(player_id)


func _on_player_connected(player_id: int) -> void:
	if not _slot_player_ids.has(player_id):
		_reconcile_connected_slots()
	_refresh_all_ui()
	_sync_all_phone_identities()
	var idx := _slot_index_for_player(player_id)
	if idx >= 0:
		_flash_slot_activity(idx, "Phone connected!")


func _on_player_disconnected(player_id: int) -> void:
	var idx := _slot_index_for_player(player_id)
	if idx >= 0:
		_activity_timers[idx] = 0.0
	_refresh_all_ui()


func _on_player_screen_changed(player_id: int, _screen_name: String) -> void:
	var idx := _slot_index_for_player(player_id)
	if idx >= 0:
		_sync_player_card(idx)


func _on_player_name_changed(player_id: int, _player_name: String) -> void:
	var idx := _slot_index_for_player(player_id)
	if idx >= 0:
		_sync_player_card(idx)
		_sync_phone_identity_for_slot(idx)


func _on_phone_swipe(player_id: int, _direction: String, _dx: float, _dy: float) -> void:
	_flash_player_activity(player_id, "Input Detected (Swipe)")


func _on_phone_tap(player_id: int, _x: float, _y: float) -> void:
	_flash_player_activity(player_id, "Input Detected (Tap)")


func _on_phone_swing(player_id: int, _magnitude: float) -> void:
	_flash_player_activity(player_id, "Input Detected (Swing)")


func _on_phone_cancel(player_id: int) -> void:
	_flash_player_activity(player_id, "Input Detected (Tap)")


func _on_phone_reel(player_id: int, _delta: float) -> void:
	_flash_player_activity(player_id, "Input Detected (Reel)")


func _on_phone_move(player_id: int, x: float, y: float) -> void:
	if absf(x) > 0.05 or absf(y) > 0.05:
		_flash_player_activity(player_id, "Input Detected (D-Pad)")


func _on_phone_menu_action(player_id: int, _action: String) -> void:
	_flash_player_activity(player_id, "Input Detected (Menu)")


func _on_phone_interact(player_id: int) -> void:
	_flash_player_activity(player_id, "Input Detected (Interact)")


func _flash_player_activity(player_id: int, label_text: String) -> void:
	var idx := _slot_index_for_player(player_id)
	if idx >= 0:
		_flash_slot_activity(idx, label_text)


func _flash_slot_activity(slot_index: int, label_text: String) -> void:
	_activity_timers[slot_index] = ACTIVITY_FLASH_SEC
	var activity_label := _left_activity_label if slot_index == 0 else _right_activity_label
	activity_label.text = label_text
	activity_label.add_theme_color_override("font_color", COLOR_ACTIVITY_FLASH)
	_set_card_highlighted(slot_index, true)


func _clear_card_activity(slot_index: int) -> void:
	var pid := _slot_player_ids[slot_index]
	var cm := _cm()
	var connected := cm != null and cm.has_method(&"is_player_connected") and bool(cm.call(&"is_player_connected", pid))
	var activity_label := _left_activity_label if slot_index == 0 else _right_activity_label
	activity_label.text = "Tap / move phone to verify side" if connected else "Connect phone to test"
	activity_label.add_theme_color_override("font_color", COLOR_ACTIVITY_IDLE)
	_set_card_highlighted(slot_index, false)


func _set_card_highlighted(slot_index: int, highlighted: bool) -> void:
	var card := _left_card if slot_index == 0 else _right_card
	var style := _highlight_card_style if highlighted else _default_card_style
	if style != null:
		card.add_theme_stylebox_override("panel", style)


func _start_match() -> void:
	var cm := _cm()
	var left_pid := _slot_player_ids[0]
	var right_pid := _slot_player_ids[1]

	if cm != null and cm.has_method(&"set_player_name"):
		cm.call(&"set_player_name", left_pid, _left_name_input.text)
		cm.call(&"set_player_name", right_pid, _right_name_input.text)

	var left_name := _resolve_name(left_pid, _left_name_input.text)
	var right_name := _resolve_name(right_pid, _right_name_input.text)

	if cm != null and cm.has_method(&"sync_player_identity"):
		cm.call(&"sync_player_identity", left_pid, left_name, "left")
		cm.call(&"sync_player_identity", right_pid, right_name, "right")

	GameManager.change_scene("multiplayer", {
		"multiplayer": true,
		"return_to": "multiplayer_lobby",
		"time_limit_sec": float(_duration_sec),
		"win_mode": get_selected_win_mode(),
		"spot_id": get_selected_arena_id(),
		"rod_id": get_selected_arena_rod_id(),
		"bait_id": get_selected_arena_bait_id(),
		"player_ids": [left_pid, right_pid],
		"player_names": {
			left_pid: left_name,
			right_pid: right_name,
		},
	})


func _resolve_name(pid: int, raw_input: String) -> String:
	var clean := raw_input.strip_edges()
	if clean != "":
		return clean
	var cm := _cm()
	if cm != null and cm.has_method(&"get_player_name"):
		return String(cm.call(&"get_player_name", pid))
	return "Player %d" % pid


func _on_back_pressed() -> void:
	var cm := _cm()
	if cm != null and cm.has_method(&"clear_all_player_screen_sides"):
		cm.call(&"clear_all_player_screen_sides")
	GameManager.change_scene("main_menu")


func _show_results_overlay(payload: Dictionary) -> void:
	var results: Dictionary = payload.get("results", {})
	var names: Dictionary = payload.get("player_names", {})
	var order_var: Variant = payload.get("player_order", [])
	var order: Array[int] = []
	if order_var is Array and order_var.size() >= 2:
		order.assign([int(order_var[0]), int(order_var[1])])
	else:
		order.assign(_slot_player_ids)

	var left_pid := order[0]
	var right_pid := order[1]
	var left_name := _result_player_name(left_pid, names)
	var right_name := _result_player_name(right_pid, names)

	_results_left_title.text = left_name
	_results_right_title.text = right_name
	_results_left_stats.text = _format_player_stats(results.get(left_pid, {}))
	_results_right_stats.text = _format_player_stats(results.get(right_pid, {}))

	var winner_id := int(payload.get("winner", -1))
	var mode_id := String(payload.get("win_mode", "total_weight"))
	var mode_label := "Total Weight"
	for m in WIN_MODES:
		if String(m["id"]) == mode_id:
			mode_label = String(m["label"])
			break
	if winner_id == -1:
		_results_winner_label.text = "It's a Tie! (%s)" % mode_label
	else:
		_results_winner_label.text = "%s Wins! (%s)" % [_result_player_name(winner_id, names), mode_label]

	_results_overlay.visible = true
	_results_close_button.grab_focus()


func _result_player_name(pid: int, names: Dictionary) -> String:
	if names.has(pid) and String(names[pid]).strip_edges() != "":
		return String(names[pid]).strip_edges()
	if names.has(str(pid)) and String(names[str(pid)]).strip_edges() != "":
		return String(names[str(pid)]).strip_edges()
	var cm := _cm()
	if cm != null and cm.has_method(&"get_player_name"):
		return String(cm.call(&"get_player_name", pid))
	return "Player %d" % pid


func _format_player_stats(entry: Variant) -> String:
	if not (entry is Dictionary):
		return "Fish Caught: 0\nTotal Weight: 0.00 kg\nBest Catch: None"
	var dict := entry as Dictionary
	var catches_raw: Variant = dict.get("catches", [])
	var catches: Array = catches_raw if catches_raw is Array else []
	var count: int = catches.size()
	var total_weight: float = float(dict.get("total_weight", 0.0))

	var best_text := "None"
	if not catches.is_empty():
		var best_weight := -1.0
		var best_name := ""
		var best_size := 0.0
		for fish in catches:
			if fish is Dictionary:
				var w := float(fish.get("weight", 0.0))
				if w > best_weight:
					best_weight = w
					best_name = String(fish.get("display_name", "Fish"))
					best_size = float(fish.get("size_cm", 0.0))
		if best_weight >= 0.0:
			best_text = "%s\n(%.1f cm, %.2f kg)" % [best_name, best_size, best_weight]

	return "Fish Caught: %d\nTotal Weight: %.2f kg\n\nBest Catch:\n%s" % [count, total_weight, best_text]


func _close_results_overlay() -> void:
	_results_overlay.visible = false
	_start_match_button.grab_focus()


func _on_rematch_pressed() -> void:
	_results_overlay.visible = false
	if not _start_match_button.disabled:
		_start_match()
	else:
		_start_match_button.grab_focus()
