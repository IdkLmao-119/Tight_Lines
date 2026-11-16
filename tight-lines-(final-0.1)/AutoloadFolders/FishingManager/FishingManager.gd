extends Node3D

# ============================================================================
# FISHING MANAGER (SCENE NODE) - TightLines          Version 0.4.8 (2026-11-16)
# ============================================================================
# Put this script on a Node3D inside FishingMinigame.tscn (or the 2-player
# versus scene). It is NOT an autoload. It runs one fishing session per
# player_id.
# There is deliberately no class_name: Godot refuses a class_name that equals
# an autoload's name ("hides an autoload singleton"). If you see that error,
# delete the FishingManager entry in Project Settings > Autoload.
#
# LOOP:  IDLE -> CASTING -> WAITING -> REELING -> CAUGHT / ESCAPED -> IDLE
#   No hook step: a bite starts the reel fight. interact_pressed (tap / E)
#   recalls the line while WAITING (DECISIONS C7).
#
# FEATURES:
#   - Full GameDB integration (rod/fish records, catch odds, weight).
#   - 50/50 split tension: fish pull (max 50%) + player reeling (max 50%).
#   - Casual vs Angler difficulty.
#   - Camera shake, tension bar HUD, on-screen messages, catch popup.
#
# 0.4.8 FIXES: see PROGRESS_FishingManager.md changelog.
# ============================================================================

# --- Signals (for UI, camera rigs, audio, SaveManager) ---
signal state_changed(player_id: int, new_state: int, old_state: int)
signal cast_started(player_id: int, power: float, target: Vector3)
signal bobber_landed(player_id: int, position: Vector3)
signal fish_bit(player_id: int)
signal fish_caught(player_id: int, fish: Dictionary)
signal fish_released(player_id: int, fish: Dictionary, reason: String)
signal fish_escaped(player_id: int, fish: Dictionary, reason: String)
signal cast_rejected(player_id: int, reason: String)
signal rod_changed(player_id: int, rod_id: String)
signal bait_changed(player_id: int, bait_id: String)
signal difficulty_changed(difficulty: int)
signal session_finished(results: Dictionary)

enum State { IDLE, CASTING, WAITING, REELING, CAUGHT, ESCAPED }
enum Difficulty { CASUAL, ANGLER }

# --- Scene setup ---
@export_group("Scene setup")
@export var player_anchors: Array[Node3D] = []
@export var rod_holders: Array[Node3D] = []
@export var bobber_scene: PackedScene
@export var water_level := 0.0
@export var max_players := 2
@export var weather_system: Node
@export var difficulty: Difficulty = Difficulty.CASUAL

@export_group("Casting")
@export var min_cast_distance := 4.0
@export var look_turn_speed := 1.5
@export var max_look_angle_deg := 75.0

@export_group("Bites")
@export var bite_delay_min := 3.0
@export var bite_delay_max := 9.0
@export var bobber_bite_sink := 0.12
@export var bobber_sink_duration := 1.0

@export_group("Camera Shake")
@export var enable_camera_shake := true
@export var shake_base_intensity := 0.06
@export var shake_frequency := 30.0

@export_group("HUD / UI")
@export var show_tension_bar := true

@export_group("Messages")
@export var show_messages := true
@export var bite_message_seconds := 0.8
@export var message_font_size := 48
@export var send_phone_messages := true
@export var surge_vibrate_interval := 0.35

@export_group("Round rules")
@export var result_display_time := 2.5
@export var time_limit_sec := 0.0             # 0 = no limit
@export var require_bait := false              # D10: bait is always required
@export var store_catches_in_inventory := true  # single player only (D7)

@export_group("Debug / standalone testing")
@export var debug_spot_id := ""
@export var debug_rod_id := ""
@export var debug_bait_id := ""
@export var debug_multiplayer := false
@export var debug_log := true

# --- Day / weather words used when NO WeatherSystem node is in the scene ---
var time_of_day := ""
var weather := ""
var season := ""

# --- Fallback defaults used if GameDB records lack a field ---
const TEMP_ROD_LINE_STRENGTH := 10.0
const TEMP_ROD_MAX_CAST_DISTANCE := 20.0
const TEMP_ROD_CONTROL := 1.0
const TEMP_FISH_PULL_STRENGTH := 4.0
const TEMP_FISH_STAMINA := 20.0
const TEMP_ROD_REEL_SPEED := 1.0

# --- Reel fight tuning ---
const REEL_PROGRESS_RATE := 0.15
const TENSION_RISE_RATE := 0.90
const TENSION_FALL_RATE := 3.0
const FISH_DRAG_RATE := 0.009
const START_PROGRESS := 0.35
const SNAP_GRACE_SEC := 1.2
const PULL_FOR_FULL_SHARE := 6.0    # fish_pull that fills the fish's whole 50% of the bar
const SNAP_RATIO := 0.95            # bar level (0..1) at which the snap timer runs
const SURGE_REEL_PROGRESS_MULT := 0.35  # reeling during a surge wins this much line
const SURGE_PULL_MULT := 1.5
const CALM_PULL_MULT := 0.6
const SURGE_DRAIN := 1.0
const CALM_DRAIN := 0.4
const CAST_ARC_BASE := 2.0
const CAST_ARC_POWER := 3.0
const CATCH_STOP_DISTANCE := 1.5

const MSG_BITE := "There's a bite"
const MSG_REEL := "Reel now"
const MSG_ESCAPE := "Fish escaped"

const CATCH_POPUP_SECONDS := 5.0
const FISH_IMAGE_PROPERTIES := ["jpg", "image", "icon", "texture"]

# ----------------------------------------------------------------------------
# Per-player session data
# ----------------------------------------------------------------------------
class FishingSession extends RefCounted:
	var player_id := 0
	var anchor: Node3D = null
	var holder: Node3D = null
	var state := 0
	var state_time := 0.0

	var base_yaw := 0.0
	var look_offset := 0.0

	var rod_id := ""
	var bait_id := ""
	var rod: Dictionary = {}
	var rod_model: Node3D = null
	var line_tip: Node3D = null

	var bobber: Node3D = null
	var fish: Dictionary = {}

	var cast_start := Vector3.ZERO
	var cast_target := Vector3.ZERO
	var cast_duration := 1.0
	var cast_arc := 2.0
	var cast_time := 0.0

	var bite_timer := 0.0

	var tension := 0.0
	var progress := 0.0
	var stamina := 0.0
	var max_stamina := 1.0
	var surging := false
	var surge_timer := 0.0
	var surge_vibrate_timer := 0.0
	var snap_timer := 0.0

	var msg_token := 0
	var shake_time := 0.0

	var catches: Array = []
	var total_weight := 0.0

# --- Internals ---
var _sessions: Dictionary = {}
var _order: Array[int] = []
var _input: Node = null
var _game_manager: Node = null
var _db: Node = null
var _save: Node = null
var _inventory: Node = null
var _connection: Node = null
var _context: Dictionary = {}
var _multiplayer := false
var _elapsed := 0.0
var _time_up := false
var _finished := false
var _warned: Dictionary = {}
var _fish_layout: Node = null
var _fish_layout_token := 0
var _popup: CanvasLayer = null
var _msg_layer: CanvasLayer = null
var _msg_labels: Dictionary = {}
var _tension_layer: CanvasLayer = null
var _tension_bars: Dictionary = {}


func _ready() -> void:
	_input = get_node_or_null("/root/InputManager")
	_game_manager = get_node_or_null("/root/GameManager")
	_db = get_node_or_null("/root/GameDB")
	_save = get_node_or_null("/root/SaveManager")
	_inventory = get_node_or_null("/root/InventoryManager")
	_connection = get_node_or_null("/root/ConnectionManager")

	if _input == null:
		push_error("FishingManager: InputManager autoload not found - no input will work.")
	if _db == null:
		push_error("FishingManager: GameDB autoload not found - no fish can bite.")

	if _game_manager != null and _game_manager.has_method("consume_context"):
		_context = _game_manager.consume_context().duplicate(true)

	_fill_debug_defaults()

	if _context.has("difficulty"):
		var ctx_diff: Variant = _context.get("difficulty")
		if ctx_diff is int:
			set_difficulty(ctx_diff)
		elif ctx_diff is String:
			set_difficulty_string(ctx_diff)
	elif _save != null and _save.has_method("get_difficulty"):
		var save_diff: Variant = _save.get_difficulty()
		if save_diff is String:
			set_difficulty_string(save_diff)
		elif save_diff is int:
			set_difficulty(save_diff)

	_multiplayer = bool(_context.get("multiplayer", false)) or debug_multiplayer
	if _multiplayer and time_limit_sec <= 0.0:
		push_warning("FishingManager: multiplayer round has no time_limit_sec - Cancel is disabled in multiplayer.")

	if _input != null:
		_connect_input()
	if _connection != null and _connection.has_signal("player_connected"):
		_connection.player_connected.connect(_on_phone_connected)

	start_session(_pick_player_ids())


func _exit_tree() -> void:
	if _connection != null and _connection.has_signal("player_connected") \
			and _connection.player_connected.is_connected(_on_phone_connected):
		_connection.player_connected.disconnect(_on_phone_connected)
	if _input == null:
		return
	if _input.cast_triggered.is_connected(_on_cast):
		_input.cast_triggered.disconnect(_on_cast)
	if _input.interact_pressed.is_connected(_on_interact):
		_input.interact_pressed.disconnect(_on_interact)
	if _input.cancel_pressed.is_connected(_on_cancel):
		_input.cancel_pressed.disconnect(_on_cancel)


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

func set_difficulty(new_difficulty: int) -> void:
	if new_difficulty >= Difficulty.CASUAL and new_difficulty <= Difficulty.ANGLER:
		if difficulty != new_difficulty:
			difficulty = new_difficulty as Difficulty
			difficulty_changed.emit(difficulty)


func set_difficulty_string(diff_str: String) -> void:
	match diff_str.to_lower():
		"casual", "0":
			set_difficulty(Difficulty.CASUAL)
		"angler", "1":
			set_difficulty(Difficulty.ANGLER)


func get_difficulty() -> int:
	return difficulty


func get_difficulty_string() -> String:
	return "angler" if difficulty == Difficulty.ANGLER else "casual"


func start_session(player_ids: Array[int]) -> void:
	for s in _sessions.values():
		_remove_bobber(s)
		_remove_rod_model(s)
	_sessions.clear()
	_order.clear()
	_clear_messages()
	_clear_tension_bars()
	_elapsed = 0.0
	_time_up = false
	_finished = false

	var rod_id := String(_context.get("rod_id", ""))
	var bait_id := String(_context.get("bait_id", ""))
	var spot_id := String(_context.get("spot_id", ""))

	if _db != null and _db.is_loaded and spot_id != "":
		if not _db.is_location_available(spot_id, _build_odds_context()):
			push_warning("FishingManager: Location '%s' is not available or locked in current context." % spot_id)

	for i in player_ids.size():
		var pid := player_ids[i]
		var s := FishingSession.new()
		s.player_id = pid
		s.anchor = _anchor_for_index(i)
		s.holder = _holder_for_index(i)
		s.base_yaw = s.anchor.rotation.y if s.anchor != null else 0.0
		s.rod_id = rod_id
		s.bait_id = bait_id
		_load_rod(s)
		_sessions[pid] = s
		_order.append(pid)
		_send_game_state(pid, "casting")

	if debug_log:
		print("[FishingManager] sessions %s | difficulty=%s | multiplayer=%s | spot='%s' rod='%s' bait='%s' require_bait=%s" % [
				str(_order), get_difficulty_string(), str(_multiplayer), spot_id, rod_id, bait_id, str(require_bait)])


func set_rod(player_id: int, rod_id: String) -> bool:
	var s := _sessions.get(player_id) as FishingSession
	if s == null or s.state != State.IDLE:
		return false
	if _db == null or not _db.has_rod(rod_id):
		push_warning("FishingManager: set_rod() unknown rod '%s'." % rod_id)
		return false
	s.rod_id = rod_id
	_load_rod(s)
	rod_changed.emit(player_id, rod_id)
	return true


func set_bait(player_id: int, bait_id: String) -> bool:
	var s := _sessions.get(player_id) as FishingSession
	if s == null or s.state != State.IDLE:
		return false
	if _db == null or not _db.has_bait(bait_id):
		push_warning("FishingManager: set_bait() unknown bait '%s'." % bait_id)
		return false
	s.bait_id = bait_id
	bait_changed.emit(player_id, bait_id)
	return true


func get_session_info(player_id: int) -> Dictionary:
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		return {}
	var line_strength := maxf(float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH)), 0.001)
	return {
		"state": s.state,
		"tension_ratio": s.tension / line_strength,
		"progress": s.progress,
		"stamina_ratio": s.stamina / maxf(s.max_stamina, 0.001),
		"surging": s.surging,
		"cast_charge": _input.get_cast_charge() if _input != null else 0.0,
		"catch_count": s.catches.size(),
		"total_weight": s.total_weight,
		"rod_id": s.rod_id,
		"bait_id": s.bait_id,
		"look_degrees": rad_to_deg(s.look_offset),
		"difficulty": difficulty,
	}


func get_state(player_id: int) -> int:
	var s := _sessions.get(player_id) as FishingSession
	return s.state if s != null else State.IDLE


func get_time_left() -> float:
	if time_limit_sec <= 0.0:
		return -1.0
	return maxf(time_limit_sec - _elapsed, 0.0)


func finish_session() -> void:
	if _finished:
		return
	_finished = true
	var results := {}
	for pid in _order:
		var s: FishingSession = _sessions[pid]
		_remove_bobber(s)
		results[pid] = {"catches": s.catches.duplicate(true), "total_weight": s.total_weight}
		_send_game_state(pid, "overworld")
	_clear_tension_bars()
	session_finished.emit(results)

	var payload := {"results": results}
	if _multiplayer:
		payload["winner"] = _winner_id(results)
	if _game_manager == null:
		return
	if _game_manager.has_method("end_fishing"):
		_game_manager.end_fishing(payload)
	elif _game_manager.has_method("change_scene"):
		_warn_once("end_fishing", "GameManager.end_fishing() missing - using change_scene() fallback.")
		var back := String(_context.get("return_to", ""))
		_game_manager.change_scene(back if back != "" else "overworld", {"result": payload})


func _winner_id(results: Dictionary) -> int:
	var best := -1
	var best_w := -1.0
	var tie := false
	for pid in results:
		var w := float(results[pid]["total_weight"])
		if w > best_w + 0.0001:
			best_w = w
			best = int(pid)
			tie = false
		elif absf(w - best_w) <= 0.0001:
			tie = true
	return -1 if tie else best


# ----------------------------------------------------------------------------
# Frame update
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _finished:
		return

	if time_limit_sec > 0.0 and not _time_up:
		_elapsed += delta
		if _elapsed >= time_limit_sec:
			_time_up = true

	var all_idle := true
	for pid in _order:
		var s: FishingSession = _sessions[pid]
		s.state_time += delta
		_update_session(s, delta)
		if s.state != State.IDLE:
			all_idle = false

	if _time_up and all_idle:
		finish_session()


func _update_session(s: FishingSession, delta: float) -> void:
	if s.state == State.IDLE and _input != null and s.anchor != null:
		var look: float = _input.get_look(s.player_id)
		if look != 0.0:
			var limit := deg_to_rad(max_look_angle_deg)
			s.look_offset = clampf(s.look_offset - look * look_turn_speed * delta, -limit, limit)
			s.anchor.rotation.y = s.base_yaw + s.look_offset

	match s.state:
		State.CASTING:
			_update_casting(s, delta)
		State.WAITING:
			_update_waiting(s, delta)
		State.REELING:
			_update_reeling(s, delta)
		State.CAUGHT, State.ESCAPED:
			if s.state_time >= result_display_time:
				_remove_bobber(s)
				_set_state(s, State.IDLE)


# --- CASTING ---
func _update_casting(s: FishingSession, delta: float) -> void:
	s.cast_time += delta
	var t := clampf(s.cast_time / s.cast_duration, 0.0, 1.0)
	if s.bobber != null:
		var pos := s.cast_start.lerp(s.cast_target, t)
		pos.y += s.cast_arc * 4.0 * t * (1.0 - t)
		s.bobber.global_position = pos
	if t >= 1.0:
		s.bite_timer = _roll_bite_delay()
		_set_state(s, State.WAITING)
		bobber_landed.emit(s.player_id, s.cast_target)


# --- WAITING ---
func _update_waiting(s: FishingSession, delta: float) -> void:
	if s.bobber != null:
		var pos := s.cast_target
		pos.y += sin(s.state_time * 3.0) * 0.03
		s.bobber.global_position = pos

	s.bite_timer -= delta
	if s.bite_timer <= 0.0:
		_try_bite(s)


func _roll_bite_delay() -> float:
	var mult := maxf(float(_context.get("bite_multiplier", 1.0)), 0.1)
	return randf_range(bite_delay_min, bite_delay_max) / mult


func _try_bite(s: FishingSession) -> void:
	var fish := _roll_fish(s)
	if fish.is_empty():
		s.bite_timer = _roll_bite_delay()
		return
	s.fish = fish

	s.tension = 0.0
	s.progress = START_PROGRESS
	s.max_stamina = maxf(float(fish["stamina"]), 1.0)
	s.stamina = s.max_stamina
	s.surging = false
	s.surge_timer = randf_range(1.0, 2.0)
	s.surge_vibrate_timer = 0.0
	s.snap_timer = 0.0

	_set_state(s, State.REELING)
	fish_bit.emit(s.player_id)
	on_bite(s)


# --- EVENT HOOKS ---
func on_bite(s: FishingSession) -> void:
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "bite"})
	_show_message(s.player_id, MSG_BITE, 0.0)

	s.msg_token += 1
	var token := s.msg_token
	if bite_message_seconds <= 0.0:
		on_reeling(s)
	else:
		get_tree().create_timer(bite_message_seconds).timeout.connect(func() -> void:
			if token == s.msg_token and s.state == State.REELING:
				on_reeling(s))


func on_reeling(s: FishingSession) -> void:
	_show_message(s.player_id, MSG_REEL, 0.0)


func on_escape(s: FishingSession) -> void:
	s.msg_token += 1
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "escape"})
	_show_message(s.player_id, MSG_ESCAPE, result_display_time)


func on_fight_won(s: FishingSession) -> void:
	s.msg_token += 1
	_hide_message(s.player_id)


# --- Phone messages ---
func _notify_phone(player_id: int, data: Dictionary) -> void:
	if not send_phone_messages:
		return
	var msg := data.duplicate()
	msg["player_id"] = player_id
	_send_to_phones(player_id, msg)


func _send_game_state(player_id: int, game_state: String) -> void:
	if not send_phone_messages:
		return
	_send_to_phones(player_id, {"game_state": game_state})


func _send_to_phones(player_id: int, msg: Dictionary) -> void:
	if _connection == null:
		_warn_once("no_connection", "ConnectionManager autoload not found - phone messages are not sent.")
		return
	if debug_log:
		print("[FishingManager] -> phone (player %d): %s" % [player_id, str(msg)])
	if _multiplayer:
		if _connection.has_method("send_to_player"):
			_connection.send_to_player(player_id, msg)
	elif _connection.has_method("send_to_all"):
		_connection.send_to_all(msg)


# --- On-screen messages ---
func _show_message(player_id: int, text: String, seconds: float) -> void:
	if not show_messages:
		return
	var label := _get_message_label(player_id)
	if label == null:
		return
	label.text = text
	label.visible = true
	if seconds > 0.0:
		var s := _sessions.get(player_id) as FishingSession
		if s == null:
			return
		var token := s.msg_token
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if token == s.msg_token and is_instance_valid(label):
				label.visible = false)


func _hide_message(player_id: int) -> void:
	var label := _msg_labels.get(player_id) as Label
	if label != null and is_instance_valid(label):
		label.visible = false


func _get_message_label(player_id: int) -> Label:
	if _msg_labels.has(player_id) and is_instance_valid(_msg_labels[player_id]):
		return _msg_labels[player_id]
	if _msg_layer == null or not is_instance_valid(_msg_layer):
		_msg_layer = CanvasLayer.new()
		_msg_layer.layer = 15
		add_child(_msg_layer)

	var index := maxi(_order.find(player_id), 0)
	var count := maxi(_order.size(), 1)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", message_font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.anchor_left = float(index) / count
	label.anchor_right = float(index + 1) / count
	label.anchor_top = 0.62
	label.anchor_bottom = 0.78
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = 0.0
	label.offset_bottom = 0.0
	label.visible = false
	_msg_layer.add_child(label)
	_msg_labels[player_id] = label
	return label


func _clear_messages() -> void:
	for label in _msg_labels.values():
		if is_instance_valid(label):
			label.queue_free()
	_msg_labels.clear()


# --- On-screen Tension Bar HUD ---
func _update_tension_ui(s: FishingSession) -> void:
	if not show_tension_bar:
		return
	var bar := _get_tension_bar(s.player_id)
	if bar == null:
		return

	if s.state == State.REELING:
		bar.visible = true
		var line_strength := maxf(float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH)), 0.001)
		var ratio := s.tension / line_strength
		bar.value = clampf(ratio, 0.0, 1.2)

		if ratio >= 1.0:
			bar.modulate = Color(1.0, 0.2, 0.2)
		elif ratio > 0.75:
			bar.modulate = Color(1.0, 0.8, 0.2)
		else:
			bar.modulate = Color(0.2, 0.8, 1.0)
	else:
		bar.visible = false


func _get_tension_bar(player_id: int) -> ProgressBar:
	if _tension_bars.has(player_id) and is_instance_valid(_tension_bars[player_id]):
		return _tension_bars[player_id]
	if _tension_layer == null or not is_instance_valid(_tension_layer):
		_tension_layer = CanvasLayer.new()
		_tension_layer.layer = 16
		add_child(_tension_layer)

	var index := maxi(_order.find(player_id), 0)
	var count := maxi(_order.size(), 1)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	bar.anchor_left = (float(index) / count) + 0.1
	bar.anchor_right = (float(index + 1) / count) - 0.1
	bar.anchor_top = 0.82
	bar.anchor_bottom = 0.86
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	bar.visible = false

	_tension_layer.add_child(bar)
	_tension_bars[player_id] = bar
	return bar


func _clear_tension_bars() -> void:
	for bar in _tension_bars.values():
		if is_instance_valid(bar):
			bar.queue_free()
	_tension_bars.clear()


# --- THE CATCH ROLL VIA GameDB ---
func _roll_fish(s: FishingSession) -> Dictionary:
	if _db == null or not _db.is_loaded:
		_warn_once("db_not_loaded", "GameDB missing or not loaded - nothing can bite.")
		return {}

	var spot_id := String(_context.get("spot_id", ""))
	var odds: Dictionary = _db.get_catch_odds(spot_id, s.bait_id, s.rod_id, _build_odds_context())
	if odds.is_empty():
		_warn_once("empty_odds", "get_catch_odds() returned nothing for spot '%s', bait '%s', rod '%s'." % [spot_id, s.bait_id, s.rod_id])
		return {}

	var fish_id := _pick_weighted(odds)
	if fish_id == "" or not _db.has_fish(fish_id):
		return {}

	var record: FishData = _db.get_fish(fish_id)
	if record == null:
		return {}

	var lo := record.min_size
	var hi := maxf(record.max_size, lo)
	var avg := clampf(record.avg_size, lo, hi)
	var size_cm := snappedf(_triangular(lo, avg, hi), 0.1)
	var weight_kg: float = _db.get_weight_for_size_kg(fish_id, size_cm)

	return {
		"id": fish_id,
		"display_name": record.display_name,
		"size_cm": size_cm,
		"weight": snappedf(weight_kg, 0.01),
		"pull_strength": _record_float(record, "pull_strength", TEMP_FISH_PULL_STRENGTH),
		"stamina": _record_float(record, "stamina", TEMP_FISH_STAMINA),
	}


# Reads a float property from a record, using a fallback when it is missing or <= 0.
func _record_float(record: Object, prop: String, fallback: float) -> float:
	if record == null:
		return fallback
	var value: Variant = record.get(prop)
	if value == null:
		return fallback
	var f := float(value)
	return f if f > 0.0 else fallback


func _pick_weighted(odds: Dictionary) -> String:
	var total := 0.0
	for id in odds:
		total += maxf(float(odds[id]), 0.0)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	var acc := 0.0
	var last := ""
	for id in odds:
		var w := float(odds[id])
		if w <= 0.0:
			continue
		acc += w
		last = String(id)
		if roll <= acc:
			return last
	return last


func _triangular(lo: float, mode: float, hi: float) -> float:
	if hi <= lo:
		return lo
	var u := randf()
	var f := (mode - lo) / (hi - lo)
	if u < f:
		return lo + sqrt(u * (hi - lo) * (mode - lo))
	return hi - sqrt((1.0 - u) * (hi - lo) * (hi - mode))


func _build_odds_context() -> Dictionary:
	var ctx := {"unlocked": _get_unlock_flags()}
	var tod := time_of_day
	var wx := weather
	var ws := _get_weather_system()
	if ws != null:
		var ws_tod := String(ws.get("time_of_day"))
		var ws_wx := String(ws.get("weather"))
		if ws_tod != "":
			tod = ws_tod
		if ws_wx != "":
			wx = ws_wx
	if tod != "":
		ctx["time_of_day"] = tod
	if wx != "":
		ctx["weather"] = wx
	if season != "":
		ctx["season"] = season
	return ctx


func _get_weather_system() -> Node:
	if weather_system == null or not is_instance_valid(weather_system):
		weather_system = get_tree().get_first_node_in_group("weather_system")
	return weather_system


func _get_unlock_flags() -> Array:
	if _save != null and _save.has_method("get_unlock_flags"):
		var flags: Variant = _save.get_unlock_flags()
		if flags is Array:
			return flags
		if flags is PackedStringArray:
			return Array(flags)
	return []


# --- REELING (50/50 split tension system) ---
func _update_reeling(s: FishingSession, delta: float) -> void:
	var reel_speed := float(s.rod.get("reel_speed", TEMP_ROD_REEL_SPEED))
	var line_strength := float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH))
	var control := float(s.rod.get("control", TEMP_ROD_CONTROL))
	var reeling: float = _input.get_reel_strength(s.player_id) if _input != null else 0.0

	s.surge_timer -= delta
	if s.surge_timer <= 0.0:
		s.surging = not s.surging
		s.surge_timer = randf_range(0.8, 1.6) if s.surging else randf_range(1.5, 3.0)
		if s.surging:
			s.surge_vibrate_timer = surge_vibrate_interval
			_notify_phone(s.player_id, {"type": "vibrate", "reason": "surge"})

	if s.surging:
		s.surge_vibrate_timer -= delta
		if s.surge_vibrate_timer <= 0.0:
			s.surge_vibrate_timer = surge_vibrate_interval
			_notify_phone(s.player_id, {"type": "vibrate", "reason": "surge"})

	var stamina_ratio := s.stamina / s.max_stamina
	var pull_mult := SURGE_PULL_MULT if s.surging else CALM_PULL_MULT
	var fish_pull := float(s.fish.get("pull_strength", TEMP_FISH_PULL_STRENGTH)) * pull_mult * (0.4 + 0.6 * stamina_ratio)

	# TENSION BAR = fish share (0..0.5) + reel share (0..0.5), as a ratio of the bar.
	# Fish share: a fresh fish surging at PULL_FOR_FULL_SHARE fills its whole half;
	# a calm or tired fish fills much less.
	var fish_share := clampf(fish_pull / PULL_FOR_FULL_SHARE, 0.0, 1.0) * 0.5
	# Reel share: reeling at full strength fills the other half (reel_speed does
	# not change the bar, only how fast progress is gained).
	var reel_share := clampf(reeling, 0.0, 1.0) * 0.75
	var target_ratio := fish_share + reel_share
	var target := target_ratio * line_strength

	var rate := TENSION_RISE_RATE if target > s.tension else TENSION_FALL_RATE
	s.tension = move_toward(s.tension, target, rate * delta)

	# Reeling against a surge wins far less line AND fills the bar: discourages it.
	var reel_gain := reeling * reel_speed * REEL_PROGRESS_RATE
	if s.surging:
		reel_gain *= SURGE_REEL_PROGRESS_MULT
	s.progress += reel_gain * delta
	s.progress -= fish_pull * FISH_DRAG_RATE * delta
	s.progress = clampf(s.progress, 0.0, 1.0)

	s.stamina = maxf(s.stamina - (SURGE_DRAIN if s.surging else CALM_DRAIN) * delta, 0.0)

	if s.tension >= line_strength * SNAP_RATIO:
		s.snap_timer += delta
	else:
		s.snap_timer = maxf(s.snap_timer - delta * 2.0, 0.0)

	# Camera shake
	if s.anchor != null:
		var base_yaw := s.base_yaw + s.look_offset
		if enable_camera_shake and s.surging and s.tension > 0.0:
			s.shake_time += delta * shake_frequency
			var tension_ratio := clampf(s.tension / maxf(line_strength, 0.001), 0.2, 2.0)
			var intensity := shake_base_intensity * tension_ratio
			s.anchor.rotation.x = sin(s.shake_time * 1.4) * intensity * 0.7
			s.anchor.rotation.y = base_yaw + (cos(s.shake_time * 1.7) * intensity)
		else:
			s.shake_time = 0.0
			s.anchor.rotation.x = move_toward(s.anchor.rotation.x, 0.0, delta * 5.0)
			s.anchor.rotation.y = move_toward(s.anchor.rotation.y, base_yaw, delta * 5.0)

	_update_tension_ui(s)

	if s.bobber != null:
		var origin := _anchor_water_pos(s)
		var to_target := s.cast_target - origin
		var away := clampf((1.0 - s.progress) / maxf(1.0 - START_PROGRESS, 0.01), 0.0, 2.0)
		var wanted := origin + to_target.normalized() * maxf(to_target.length() * away, CATCH_STOP_DISTANCE)

		var sink_t := clampf(s.state_time / maxf(bobber_sink_duration, 0.01), 0.0, 1.0)
		var sink_depth := bobber_bite_sink * sink_t * (1.2 if s.surging else 1.0)
		wanted.y = water_level - sink_depth

		s.bobber.global_position = s.bobber.global_position.lerp(wanted, 1.0 - exp(-10.0 * delta))

	var diff_grace_mult := 2.5 if difficulty == Difficulty.CASUAL else 1.0
	if s.snap_timer >= SNAP_GRACE_SEC * maxf(control, 0.1) * diff_grace_mult:
		_fish_escapes(s, "line_snapped")
	elif s.progress <= 0.0:
		_fish_escapes(s, "got_away")
	elif s.progress >= 1.0:
		_fish_won(s)


func _fish_won(s: FishingSession) -> void:
	var fish := s.fish.duplicate(true)
	var kept := true
	if store_catches_in_inventory and not _multiplayer:
		kept = _store_fish(fish)
		_record_caught_fish(String(fish["id"]))

	if kept:
		s.catches.append(fish)
		s.total_weight += float(fish["weight"])

	_set_state(s, State.CAUGHT)
	on_fight_won(s)
	if kept:
		fish_caught.emit(s.player_id, fish)
	else:
		fish_released.emit(s.player_id, fish, "fish_box_full")
	_show_catch_popup(s.player_id, fish, kept)


func _record_caught_fish(fish_id: String) -> void:
	if _save == null or not _save.has_method("record_caught_fish"):
		_warn_once("record_caught_fish", "SaveManager.record_caught_fish() not found - Bestiary will not unlock.")
		return
	var is_new := bool(_save.record_caught_fish(fish_id))
	if is_new and debug_log:
		print("[FishingManager] New Bestiary entry unlocked: '%s'" % fish_id)


func _store_fish(fish: Dictionary) -> bool:
	if _inventory == null or not _inventory.has_method("add_fish"):
		_warn_once("add_fish", "InventoryManager.add_fish() not found - catch is counted but NOT stored.")
		return true
	return bool(_inventory.add_fish(String(fish["id"]), float(fish["size_cm"])))


# Shows the catch: text popup always, plus the fish picture on 'FishLayout' when the scene has one.
func _show_catch_popup(player_id: int, fish: Dictionary, kept: bool) -> void:
	_show_catch_picture(fish)

	if is_instance_valid(_popup):
		_popup.queue_free()
	var text := ""
	if _multiplayer:
		text += "Player %d caught\n" % player_id
	text += "%s\n%.1f cm   %.2f kg" % [String(fish["display_name"]), float(fish["size_cm"]), float(fish["weight"])]
	if not kept:
		text += "\nFish Box full: released"
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 40)
	_popup = layer
	get_tree().create_timer(CATCH_POPUP_SECONDS).timeout.connect(layer.queue_free)


func _show_catch_picture(fish: Dictionary) -> void:
	if not is_instance_valid(_fish_layout):
		_fish_layout = get_tree().root.find_child("FishLayout", true, false)
	if _fish_layout == null:
		_warn_once("fish_layout", "no node named 'FishLayout' in the scene - catch picture not shown.")
		return

	var record: FishData = _db.get_fish(String(fish["id"])) if _db != null else null
	var path := ""
	var texture: Texture2D = null
	if record != null:
		for prop in FISH_IMAGE_PROPERTIES:
			var value: Variant = record.get(prop)
			if value is Texture2D:
				texture = value
				path = texture.resource_path
				break
			if (value is String or value is StringName) and String(value) != "":
				path = String(value)
				texture = load(path) as Texture2D
				break
	if texture == null:
		_warn_once("fish_image", "fish '%s' has no picture." % String(fish["id"]))
		return

	var jpg_type := -1
	for p in _fish_layout.get_property_list():
		if p["name"] == "jpg":
			jpg_type = int(p["type"])
			break
	if jpg_type == TYPE_STRING:
		_fish_layout.set("jpg", path)
	elif jpg_type != -1:
		_fish_layout.set("jpg", texture)
	elif _fish_layout is TextureRect:
		(_fish_layout as TextureRect).texture = texture
	else:
		_warn_once("fish_layout_prop", "FishLayout has no 'jpg' property and is not a TextureRect.")
		return

	_fish_layout.set("visible", true)
	_fish_layout_token += 1
	var token := _fish_layout_token
	get_tree().create_timer(CATCH_POPUP_SECONDS).timeout.connect(func() -> void:
		if token == _fish_layout_token and is_instance_valid(_fish_layout):
			_fish_layout.set("visible", false))


func _fish_escapes(s: FishingSession, reason: String) -> void:
	_set_state(s, State.ESCAPED)
	fish_escaped.emit(s.player_id, s.fish.duplicate(true), reason)
	on_escape(s)


# --- Input handlers ---
func _connect_input() -> void:
	_input.cast_triggered.connect(_on_cast)
	_input.interact_pressed.connect(_on_interact)
	_input.cancel_pressed.connect(_on_cancel)


func _on_cast(player_id: int, power: float) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		return
	if s.state != State.IDLE or _finished:
		return
	if _time_up:
		_reject_cast(player_id, "time_up")
		return

	if require_bait:
		if s.bait_id == "":
			_reject_cast(player_id, "no_bait", "no bait_id set")
			return
		if not _spend_bait(s):
			_reject_cast(player_id, "no_bait", "none left in inventory")
			return

	power = clampf(power, 0.0, 1.0)
	var max_dist := float(s.rod.get("max_cast_distance", TEMP_ROD_MAX_CAST_DISTANCE))
	var distance := lerpf(min_cast_distance, maxf(max_dist, min_cast_distance), power)

	var origin := _anchor_water_pos(s)
	var forward := Vector3.FORWARD
	if s.anchor != null:
		forward = -s.anchor.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD

	if s.line_tip != null and is_instance_valid(s.line_tip):
		s.cast_start = s.line_tip.global_position
	else:
		s.cast_start = origin + Vector3.UP * 1.0
	s.cast_target = Vector3(origin.x + forward.x * distance, water_level, origin.z + forward.z * distance)
	s.cast_duration = 0.6 + 0.6 * power
	s.cast_arc = CAST_ARC_BASE + CAST_ARC_POWER * power
	s.cast_time = 0.0

	_spawn_bobber(s)
	_set_state(s, State.CASTING)
	cast_started.emit(player_id, power, s.cast_target)


func _on_interact(player_id: int) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s != null and s.state == State.WAITING:
		_remove_bobber(s)
		_set_state(s, State.IDLE)


func _on_cancel(player_id: int) -> void:
	if _multiplayer:
		return
	var s := _sessions.get(player_id) as FishingSession
	if s != null and s.state == State.IDLE:
		finish_session()


# --- Helpers ---
func _fill_debug_defaults() -> void:
	var fallbacks := {"spot_id": debug_spot_id, "rod_id": debug_rod_id, "bait_id": debug_bait_id}
	for key in fallbacks:
		if String(_context.get(key, "")) == "" and String(fallbacks[key]) != "":
			_context[key] = fallbacks[key]


func _pick_player_ids() -> Array[int]:
	var ids: Array[int] = []
	if _multiplayer and _input != null:
		ids.assign(_input.get_connected_phone_ids())
		ids.sort()
		if ids.size() > max_players:
			ids.resize(max_players)
	if ids.is_empty():
		ids.append(1)
	return ids


func _anchor_for_index(i: int) -> Node3D:
	return player_anchors[i] if i < player_anchors.size() else null


func _holder_for_index(i: int) -> Node3D:
	if i < rod_holders.size() and rod_holders[i] != null:
		return rod_holders[i]
	if i < player_anchors.size() and player_anchors[i] != null:
		return player_anchors[i]
	return self


func _reject_cast(player_id: int, reason: String, detail: String = "") -> void:
	if debug_log:
		print("[FishingManager] cast rejected for player %d: %s %s" % [player_id, reason, detail])
	cast_rejected.emit(player_id, reason)


func _set_state(s: FishingSession, new_state: int) -> void:
	var old := s.state
	s.state = new_state
	s.state_time = 0.0

	if old == State.REELING:
		if s.anchor != null:
			s.anchor.rotation.x = 0.0
			s.anchor.rotation.y = s.base_yaw + s.look_offset
		# Fix: the tension bar used to stay on screen after a catch or escape.
		_update_tension_ui(s)

	if debug_log:
		print("[FishingManager] player %d: %s -> %s" % [s.player_id, State.keys()[old], State.keys()[new_state]])
	var screen := _phone_screen_for(new_state)
	if screen != _phone_screen_for(old):
		_send_game_state(s.player_id, screen)
	state_changed.emit(s.player_id, new_state, old)


func _phone_screen_for(state: int) -> String:
	return "reeling" if state == State.REELING else "casting"


func _on_phone_connected(phone_id: int) -> void:
	if _finished:
		return
	for pid in _order:
		if _multiplayer and pid != phone_id:
			continue
		var s: FishingSession = _sessions[pid]
		_send_game_state(pid, _phone_screen_for(s.state))


func _anchor_water_pos(s: FishingSession) -> Vector3:
	var p := s.anchor.global_position if s.anchor != null else global_position
	return Vector3(p.x, water_level, p.z)


func _spend_bait(s: FishingSession) -> bool:
	if _multiplayer:
		return true
	if _inventory == null or not _inventory.has_method("consume_item"):
		return true
	return bool(_inventory.consume_item(s.bait_id, 1))


func _load_rod(s: FishingSession) -> void:
	var record: RodData = null
	if _db != null and s.rod_id != "" and _db.has_rod(s.rod_id):
		record = _db.get_rod(s.rod_id)

	s.rod = {
		"line_strength": _record_float(record, "line_strength", TEMP_ROD_LINE_STRENGTH),
		"reel_speed": _record_float(record, "reel_speed", TEMP_ROD_REEL_SPEED),
		"max_cast_distance": _record_float(record, "max_cast_distance", TEMP_ROD_MAX_CAST_DISTANCE),
		"control": _record_float(record, "control", TEMP_ROD_CONTROL),
	}

	_remove_rod_model(s)
	if record == null or s.holder == null or _db == null:
		return
	var model: Node3D = _db.instantiate_rod_model(s.rod_id)
	if model == null:
		return
	s.holder.add_child(model)
	s.rod_model = model
	s.line_tip = _db.find_line_tip(model)


func _remove_rod_model(s: FishingSession) -> void:
	if s.rod_model != null and is_instance_valid(s.rod_model):
		s.rod_model.queue_free()
	s.rod_model = null
	s.line_tip = null


func _spawn_bobber(s: FishingSession) -> void:
	_remove_bobber(s)
	if bobber_scene != null:
		s.bobber = bobber_scene.instantiate() as Node3D
	if s.bobber == null:
		# Fix: the fallback bobber never assigned its mesh (and set a property
		# MeshInstance3D does not have), so it was invisible / a script error.
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.15, 0.1)
		sphere.material = mat
		mesh.mesh = sphere
		s.bobber = mesh
	add_child(s.bobber)
	s.bobber.global_position = s.cast_start


func _remove_bobber(s: FishingSession) -> void:
	if s.bobber != null and is_instance_valid(s.bobber):
		s.bobber.queue_free()
	s.bobber = null


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("FishingManager: " + message)
