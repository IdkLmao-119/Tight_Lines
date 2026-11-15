extends Node3D

# ============================================================================
# FISHING MANAGER (SCENE NODE) - TightLines          Version 0.4.2 (2026-11-01)
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
# NEW IN 0.4.0
#   1. Phone messages (through ConnectionManager) on bite / reeling / escape.
#   2. On-screen messages: "There's a bite", "Reel now", "Fish escaped".
#   3. View rotation limited to +/- max_look_angle_deg (75) around the
#      anchor's starting direction.
#   4. View rotation is locked from the SWING (cast), not from the bite:
#      the player can only turn while IDLE.
#   5. Reeling speed tweak points are marked with  >>> TWEAK REELING SPEED <<<
#      (search for "TWEAK").
#
# WHO OWNS WHAT (DECISIONS.md)
#   GameManager  : input context, multiplayer flag, pause (C4, C6), overlay
#   FishingManager (this): the catch roll, bait spending, rod model, catches
#   FishingManager NEVER calls set_context(), set_multiplayer_mode() or
#   toggle_pause(), and never reads input in _ready().
#
# INPUT (through InputManager only):
#   cast_triggered(player_id, power)  cast (phone swing / keyboard hold+release)
#   get_reel_strength(player_id)      polled every frame while REELING
#   get_look(player_id)               polled, rotates the player's anchor (IDLE only)
#   interact_pressed(player_id)       recall the line while WAITING
#   cancel_pressed(player_id)         leave the scene (single player, IDLE only)
#
# MESSAGES TO THE PHONE (ConnectionManager.send_to_player / send_to_all):
#   Screen changes (the phone swaps its view; see MainActivity.switchToState):
#   {"game_state": "casting"}   fishing screen: ready to cast / cast / waiting for a bite
#                               (sent when the session starts and whenever the
#                               player is back to IDLE after a catch or escape)
#   {"game_state": "reeling"}   a fish bit: show the reeling screen
#   {"game_state": "overworld"} fishing was exited: back to the overworld screen
#   Vibration (handled in MainActivity.onMessage):
#   {"type": "vibrate", "reason": "bite",   "player_id": n}   a fish bit
#   {"type": "vibrate", "reason": "surge",  "player_id": n}   fish is surging
#   {"type": "vibrate", "reason": "escape", "player_id": n}   the fish escaped
#   A phone that (re)connects during a session is sent the current screen again.
#   Single player: sent to every connected phone (any phone is Player 1).
#   Multiplayer: sent only to that player's phone.
#
# CONTEXT IN (read once in _ready() with GameManager.consume_context()):
#   { spot_id, rod_id, bait_id, multiplayer, return_to, bite_multiplier? }
#   This is the STARTING rod and bait. Change them later with set_rod() and
#   set_bait() (IDLE state only).
# RESULT OUT (GameManager.end_fishing):
#   { results = { player_id: { catches = [fish], total_weight = kg } } }
#
# THE CATCH ROLL (GameDB never rolls dice; this script does):
#   1. odds = GameDB.get_catch_odds(spot, bait, rod, context)
#   2. weighted random pick of one fish id ("odds weight", not kg).
#      Empty odds = nothing can bite: the bite timer restarts.
#   3. size_cm rolled between min_size and max_size, leaning toward avg_size
#   4. weight (kg) = GameDB.get_weight_for_size_kg(fish_id, size_cm)
#
# TEMPORARY DEFAULTS: GameDB has no rod or fish fight stats yet. Every value
# named TEMP_* below is used until RodData / FishData get the real fields
# (line_strength, reel_speed, max_cast_distance, control; pull_strength,
# stamina). The script reads those fields by name when they appear.
#
# SCENE SETUP
#   player_anchors : one Node3D per player, in seat order. Put each player's
#                    camera under its anchor; tilt / A,D rotate the anchor and
#                    the cast goes along the anchor's forward (-Z).
#                    The anchor's rotation when the session starts is "straight
#                    ahead"; the player can turn 75 degrees either way from it.
#   rod_holders    : optional Node3D per player that the rod model is added
#                    under. If empty, the player's anchor is used, so the rod
#                    turns with the camera.
#   The rod model scene needs a Marker3D named "LineTip" (GameDB.find_line_tip).
#   F6 testing without GameManager: set the InputManager context to FISHING
#   from a test script, and fill the debug_* exports below.
# ============================================================================

# --- Signals (for UI, camera rigs, audio, SaveManager) ---
signal state_changed(player_id: int, new_state: int, old_state: int)
signal cast_started(player_id: int, power: float, target: Vector3)
signal bobber_landed(player_id: int, position: Vector3)
signal fish_bit(player_id: int)                        # a bite just started the fight
signal fish_caught(player_id: int, fish: Dictionary)   # won AND kept
signal fish_released(player_id: int, fish: Dictionary, reason: String)  # won, not kept: "fish_box_full"
signal fish_escaped(player_id: int, fish: Dictionary, reason: String)   # "line_snapped" | "got_away"
signal cast_rejected(player_id: int, reason: String)   # "no_bait" | "time_up"
signal rod_changed(player_id: int, rod_id: String)     # SaveManager listens: equipped_rod
signal bait_changed(player_id: int, bait_id: String)   # SaveManager listens: equipped_bait
signal session_finished(results: Dictionary)

enum State { IDLE, CASTING, WAITING, REELING, CAUGHT, ESCAPED }

# --- Scene setup ---
@export_group("Scene setup")
@export var player_anchors: Array[Node3D] = []
@export var rod_holders: Array[Node3D] = []
@export var bobber_scene: PackedScene
@export var water_level := 0.0
@export var max_players := 2                  # versus scene = 2
@export var weather_system: Node              # optional: WeatherSystem.gd node; found by itself if empty

@export_group("Casting")
@export var min_cast_distance := 4.0
@export var look_turn_speed := 1.5            # radians/sec at full tilt / key
@export var max_look_angle_deg := 75.0        # view can turn this far left AND right of straight ahead

@export_group("Bites")
@export var bite_delay_min := 3.0             # seconds
@export var bite_delay_max := 9.0
@export var bobber_bite_sink := 0.12          # meters the bobber sinks below water_level on a bite
@export var bobber_sink_duration := 1.0       # seconds it takes for the bobber to sink down

@export_group("Messages")
@export var show_messages := true             # on-screen "There's a bite" / "Reel now" / "Fish escaped"
@export var bite_message_seconds := 0.8       # how long "There's a bite" shows before "Reel now" replaces it
@export var message_font_size := 48
@export var send_phone_messages := true       # game_state + vibrate packets to the Android app
@export var surge_vibrate_interval := 0.35    # seconds between vibrate pulses while the fish is surging

@export_group("Round rules")
@export var result_display_time := 2.5        # seconds shown in CAUGHT / ESCAPED
@export var time_limit_sec := 0.0             # 0 = no limit
@export var require_bait := false              # D10: bait is always required
@export var store_catches_in_inventory := true  # single player only (D7)

@export_group("Debug / standalone testing")
# Used only when the context from GameManager lacks that key (F6 testing).
@export var debug_spot_id := ""
@export var debug_rod_id := ""
@export var debug_bait_id := ""
@export var debug_multiplayer := false        # F6 test of the 2-player scene without GameManager context
@export var debug_log := true

# --- Day / weather words (FishingTerms) used when NO WeatherSystem node is in the scene ---
# With a WeatherSystem node its time_of_day and weather win over these two.
# Empty = "not provided": modifiers that look at the key simply do not apply.
var time_of_day := ""     # e.g. "dawn"
var weather := ""         # e.g. "rain"
var season := ""          # e.g. "wet"

# --- TEMPORARY defaults until GameDB has the real fields ---
const TEMP_ROD_LINE_STRENGTH := 10.0     # real range 5-20
const TEMP_ROD_MAX_CAST_DISTANCE := 50.0 # real range 10-40 m
const TEMP_ROD_CONTROL := 1.0            # real range 0.5-2.0
const TEMP_FISH_PULL_STRENGTH := 4.0     # real range 2-8
const TEMP_FISH_STAMINA := 20.0          # real range 10-30 s

# ============================================================================
# >>> TWEAK REELING SPEED <<<   (1 of 3: the rod's reel speed)
# ============================================================================
# This is the main knob. It multiplies BOTH how fast reeling wins distance
# (REEL_PROGRESS_RATE) AND how much tension reeling adds (REEL_TENSION_FORCE).
#   Higher = faster catches, but the line snaps sooner when you reel during a surge.
#   Lower  = slower, calmer fight.
# Real range 0.5 to 2.0. Once RodData has a `reel_speed` field, THAT value is
# used instead and this default no longer matters, so change it on the rod record.
const TEMP_ROD_REEL_SPEED := 2.0         # <<< TWEAK

# ============================================================================
# Reel fight tuning (guesses, tune after playtest)
# tension is in the same units as a rod's line_strength.
# ============================================================================
# >>> TWEAK REELING SPEED <<<   (2 of 3: how fast reeling pulls the fish in)
const REEL_PROGRESS_RATE := 0.50    # <<< TWEAK  progress/sec while reeling (x reel_speed)
# >>> TWEAK REELING SPEED <<<   (3 of 3: how much stress reeling puts on the line)
const REEL_TENSION_FORCE := 3.0     # <<< TWEAK  tension added while reeling (x reel_speed)
# Rule of thumb: speed up reeling by raising REEL_PROGRESS_RATE; if the line
# then snaps too often, lower REEL_TENSION_FORCE a little.
# Phone only: each swipe reels for PHONE_REEL_PULSE_SEC (0.30 s) in InputManager.gd.
# Raising that to ~0.5 makes phone reeling feel faster without touching this file.

const TENSION_RISE_RATE := 12.0     # units/sec toward a higher target
const TENSION_FALL_RATE := 6.0      # units/sec toward a lower target
const FISH_DRAG_RATE := 0.009       # progress lost/sec per unit of fish pull
const START_PROGRESS := 0.35        # 0 = fish gets away, 1 = landed
const SNAP_GRACE_SEC := 1.2         # seconds over the limit before snapping (x control)
const SURGE_PULL_MULT := 1.5
const CALM_PULL_MULT := 0.6
const SURGE_DRAIN := 1.0            # stamina/sec while surging
const CALM_DRAIN := 0.4
const CAST_ARC_BASE := 2.0
const CAST_ARC_POWER := 3.0
const CATCH_STOP_DISTANCE := 1.5    # bobber never gets closer than this to the player while reeling

# Text shown on screen (change the wording here).
const MSG_BITE := "There's a bite"
const MSG_REEL := "Reel now"
const MSG_ESCAPE := "Fish escaped"

# ----------------------------------------------------------------------------
# Per-player session data
# ----------------------------------------------------------------------------
class FishingSession extends RefCounted:
	var player_id := 0
	var anchor: Node3D = null
	var holder: Node3D = null            # parent of the rod model
	var state := 0                       # FishingManager.State (stored as int)
	var state_time := 0.0

	var base_yaw := 0.0                  # anchor's rotation.y at session start = "straight ahead"
	var look_offset := 0.0               # radians turned away from base_yaw (clamped)

	var rod_id := ""
	var bait_id := ""
	var rod: Dictionary = {}             # line_strength, reel_speed, max_cast_distance, control
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

	var msg_token := 0                   # lets an old message timer know it is outdated

	var catches: Array = []
	var total_weight := 0.0

# --- Internals ---
var _sessions: Dictionary = {}          # { player_id: FishingSession }
var _order: Array[int] = []             # player_ids in seat order
var _input: Node = null
var _game_manager: Node = null
var _db: Node = null                    # GameDB
var _save: Node = null                  # SaveManager
var _inventory: Node = null             # InventoryManager
var _connection: Node = null            # ConnectionManager (messages to the phone)
var _context: Dictionary = {}
var _multiplayer := false
var _elapsed := 0.0
var _time_up := false
var _finished := false
var _warned: Dictionary = {}
var _fish_layout: Node = null           # the scene's "FishLayout" node, found on first catch
var _fish_layout_token := 0             # counts catches, so an old timer cannot hide a newer popup
var _msg_layer: CanvasLayer = null      # on-screen messages
var _msg_labels: Dictionary = {}        # { player_id: Label }


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

	# Context is read ONCE here (C6). Nothing else is read from input in _ready().
	if _game_manager != null and _game_manager.has_method("consume_context"):
		_context = _game_manager.consume_context().duplicate(true)
	_fill_debug_defaults()
	_multiplayer = bool(_context.get("multiplayer", false)) or debug_multiplayer
	if _multiplayer and time_limit_sec <= 0.0:
		push_warning("FishingManager: multiplayer round has no time_limit_sec - Cancel is disabled in multiplayer, so nothing ends the round. Set time_limit_sec (e.g. 180).")

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

# (Re)creates one session per id. Called automatically from _ready().
func start_session(player_ids: Array[int]) -> void:
	for s in _sessions.values():
		_remove_bobber(s)
		_remove_rod_model(s)
	_sessions.clear()
	_order.clear()
	_clear_messages()
	_elapsed = 0.0
	_time_up = false
	_finished = false

	var rod_id := String(_context.get("rod_id", ""))
	var bait_id := String(_context.get("bait_id", ""))
	for i in player_ids.size():
		var pid := player_ids[i]
		var s := FishingSession.new()
		s.player_id = pid
		s.anchor = _anchor_for_index(i)
		s.holder = _holder_for_index(i)
		# "Straight ahead" = wherever the anchor points right now.
		s.base_yaw = s.anchor.rotation.y if s.anchor != null else 0.0
		s.look_offset = 0.0
		s.rod_id = rod_id
		s.bait_id = bait_id
		_load_rod(s)
		_sessions[pid] = s
		_order.append(pid)
		# Phone shows the fishing screen as soon as the round starts.
		_send_game_state(pid, "casting")

	if debug_log:
		print("[FishingManager] sessions %s | multiplayer=%s | spot='%s' rod='%s' bait='%s' | require_bait=%s | input=%s db=%s connection=%s" % [
				str(_order), str(_multiplayer), String(_context.get("spot_id", "")), rod_id, bait_id,
				str(require_bait), str(_input != null), str(_db != null), str(_connection != null)])


# Swap a player's rod. Allowed in IDLE only, so a stronger rod cannot be
# swapped in while a fish is on. Returns true if the swap happened.
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


# Swap a player's bait. IDLE only. Bait itself lives in the Tackle Box; the
# inventory overlay decides which bait the player may pick.
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


# Lightweight snapshot for HUD code (tension bar, progress bar, power meter).
func get_session_info(player_id: int) -> Dictionary:
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		return {}
	var line_strength := maxf(float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH)), 0.001)
	return {
		"state": s.state,
		"tension_ratio": s.tension / line_strength,   # >= 1.0 means the line is in danger
		"progress": s.progress,
		"stamina_ratio": s.stamina / maxf(s.max_stamina, 0.001),
		"surging": s.surging,
		"cast_charge": _input.get_cast_charge() if _input != null else 0.0,
		"catch_count": s.catches.size(),
		"total_weight": s.total_weight,
		"rod_id": s.rod_id,
		"bait_id": s.bait_id,
		"look_degrees": rad_to_deg(s.look_offset),     # -75 .. +75
	}


func get_state(player_id: int) -> int:
	var s := _sessions.get(player_id) as FishingSession
	return s.state if s != null else State.IDLE


func get_time_left() -> float:
	if time_limit_sec <= 0.0:
		return -1.0
	return maxf(time_limit_sec - _elapsed, 0.0)


# Ends the round and returns to the scene named in the context (via GameManager).
func finish_session() -> void:
	if _finished:
		return
	_finished = true
	var results := {}
	for pid in _order:
		var s: FishingSession = _sessions[pid]
		_remove_bobber(s)
		results[pid] = {"catches": s.catches.duplicate(true), "total_weight": s.total_weight}
		# Exiting fishing = back in the overworld. (Not conditional on return_to:
		# GameManager's overworld scene ids are "overworld_*", so a name check
		# would never match.)
		_send_game_state(pid, "overworld")
	session_finished.emit(results)

	var payload := {"results": results}
	if _multiplayer:
		payload["winner"] = _winner_id(results)   # player_id with the heaviest total, -1 = tie
	if _game_manager == null:
		return
	if _game_manager.has_method("end_fishing"):
		_game_manager.end_fishing(payload)
	elif _game_manager.has_method("change_scene"):
		# Temporary fallback until GameManager gets end_fishing() (FM-REQ-6).
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

	# Time is up: let ongoing fights finish, then end the round.
	if _time_up and all_idle:
		finish_session()


func _update_session(s: FishingSession, delta: float) -> void:
	# View rotation (tilt / A,D). LOCKED from the moment of the swing: the
	# player can only turn while IDLE (not CASTING, WAITING, REELING, ...).
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


# --- CASTING ---------------------------------------------------------------
func _update_casting(s: FishingSession, delta: float) -> void:
	s.cast_time += delta
	var t := clampf(s.cast_time / s.cast_duration, 0.0, 1.0)
	if s.bobber != null:
		var pos := s.cast_start.lerp(s.cast_target, t)
		pos.y += s.cast_arc * 4.0 * t * (1.0 - t)   # parabola: 0 at both ends
		s.bobber.global_position = pos
	if t >= 1.0:
		s.bite_timer = _roll_bite_delay()
		_set_state(s, State.WAITING)
		bobber_landed.emit(s.player_id, s.cast_target)


# --- WAITING ---------------------------------------------------------------
func _update_waiting(s: FishingSession, delta: float) -> void:
	if s.bobber != null:
		var pos := s.cast_target
		pos.y += sin(s.state_time * 3.0) * 0.03   # gentle float
		s.bobber.global_position = pos

	s.bite_timer -= delta
	if s.bite_timer <= 0.0:
		_try_bite(s)


# bite_multiplier DIVIDES the wait: 2.0 = bites arrive twice as fast.
func _roll_bite_delay() -> float:
	var mult := maxf(float(_context.get("bite_multiplier", 1.0)), 0.1)
	return randf_range(bite_delay_min, bite_delay_max) / mult


func _try_bite(s: FishingSession) -> void:
	var fish := _roll_fish(s)
	if fish.is_empty():
		# Nothing can bite here (empty odds): keep waiting, try again later.
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


# ----------------------------------------------------------------------------
# EVENT HOOKS: bite / reeling / escape
# Put extra effects (sounds, camera shake, particles) in these three functions.
# ----------------------------------------------------------------------------

# A fish just bit. Phone: vibrate. Screen: "There's a bite".
# After bite_message_seconds on_reeling() takes over ("Reel now").
func on_bite(s: FishingSession) -> void:
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "bite"})
	_show_message(s.player_id, MSG_BITE, 0.0)   # 0 = stays until replaced

	s.msg_token += 1
	var token := s.msg_token
	if bite_message_seconds <= 0.0:
		on_reeling(s)
	else:
		get_tree().create_timer(bite_message_seconds).timeout.connect(func() -> void:
			if token == s.msg_token and s.state == State.REELING:
				on_reeling(s))


# Reeling time. Phone: show the reeling UI. Screen: "Reel now".
func on_reeling(s: FishingSession) -> void:
	# (The phone's reeling screen is already up: {"game_state": "reeling"} is
	# sent the moment the bite starts, from _set_state().)
	_show_message(s.player_id, MSG_REEL, 0.0)   # stays until the fight ends


# The fish got away (line snapped or it got loose). Phone: vibrate again and
# hide the reeling UI. Screen: "Fish escaped".
func on_escape(s: FishingSession) -> void:
	s.msg_token += 1   # cancels a pending "Reel now"
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "escape"})
	_show_message(s.player_id, MSG_ESCAPE, result_display_time)


# The fish was landed (kept or released). Hides the reeling UI and message.
func on_fight_won(s: FishingSession) -> void:
	s.msg_token += 1
	_hide_message(s.player_id)


# --- Phone messages ---------------------------------------------------------
# Single player: any phone is Player 1, so everyone connected gets it.
# Multiplayer: only the phone that belongs to that player_id.
func _notify_phone(player_id: int, data: Dictionary) -> void:
	if not send_phone_messages:
		return
	if _connection == null:
		_warn_once("no_connection", "ConnectionManager autoload not found - phone messages are not sent.")
		return
	var msg := data.duplicate()
	msg["player_id"] = player_id
	_send_to_phones(player_id, msg)


# Phone screen packets: {"game_state": "casting" | "reeling" | "overworld"}.
# casting   = the fishing screen: ready to cast, casting, waiting for a bite
# reeling   = a fish bit, the fight is on
# overworld = fishing was exited, back in the overworld
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


# --- On-screen messages ------------------------------------------------------
# seconds = 0 keeps the text until another message replaces it or it is hidden.
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
	# Each player gets their own slice of the screen width (one slice in single player).
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


# --- THE CATCH ROLL --------------------------------------------------------
# Returns {id, display_name, size_cm, weight, pull_strength, stamina}, or {}
# when nothing can bite.
func _roll_fish(s: FishingSession) -> Dictionary:
	if _db == null or not _db.is_loaded:
		_warn_once("db_not_loaded", "GameDB missing or not loaded - nothing can bite.")
		return {}

	var spot_id := String(_context.get("spot_id", ""))
	var odds: Dictionary = _db.get_catch_odds(spot_id, s.bait_id, s.rod_id, _build_odds_context())
	if odds.is_empty():
		_warn_once("empty_odds", "get_catch_odds() returned nothing for spot '%s', bait '%s', rod '%s' (unknown id, locked location, or no bait). Waiting and retrying." % [spot_id, s.bait_id, s.rod_id])
		return {}

	var fish_id := _pick_weighted(odds)
	if fish_id == "" or not _db.has_fish(fish_id):
		return {}
	var record: Object = _db.get_fish(fish_id)

	# Size leans toward avg_size (triangular distribution).
	var lo := _stat(record, "min_size", 10.0)
	var hi := maxf(_stat(record, "max_size", 50.0), lo)
	var avg := clampf(_stat(record, "avg_size", (lo + hi) * 0.5), lo, hi)
	var size_cm := snappedf(_triangular(lo, avg, hi), 0.1)
	var weight_kg: float = _db.get_weight_for_size_kg(fish_id, size_cm)

	return {
		"id": fish_id,
		"display_name": String(record.get("display_name")),
		"size_cm": size_cm,
		"weight": snappedf(weight_kg, 0.01),
		# TEMPORARY defaults until FishData has these fields (FM-REQ-3)
		"pull_strength": _stat(record, "pull_strength", TEMP_FISH_PULL_STRENGTH),
		"stamina": _stat(record, "stamina", TEMP_FISH_STAMINA),
	}


# Weighted random pick of one key from {id: chance}. The chances need not
# add up to exactly 1.0.
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


# Triangular distribution between lo and hi with its peak at mode.
func _triangular(lo: float, mode: float, hi: float) -> float:
	if hi <= lo:
		return lo
	var u := randf()
	var f := (mode - lo) / (hi - lo)
	if u < f:
		return lo + sqrt(u * (hi - lo) * (mode - lo))
	return hi - sqrt((1.0 - u) * (hi - lo) * (hi - mode))


# The context dictionary GameDB expects. Keys that are not provided are
# left out, so their modifiers simply do not apply.
func _build_odds_context() -> Dictionary:
	var ctx := {"unlocked": _get_unlock_flags()}
	var tod := time_of_day
	var wx := weather
	# A WeatherSystem node in the scene overrides the two plain variables.
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


# The WeatherSystem node (WeatherSystem.gd), found once. Looked up on first use,
# not in _ready(), so the node order in the scene tree does not matter.
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


# --- REELING ---------------------------------------------------------------
func _update_reeling(s: FishingSession, delta: float) -> void:
	# >>> TWEAK REELING SPEED <<< reel_speed comes from the rod record; if the
	# record has no `reel_speed` yet, TEMP_ROD_REEL_SPEED (top of this file) is used.
	var reel_speed := float(s.rod.get("reel_speed", TEMP_ROD_REEL_SPEED))
	var line_strength := float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH))
	var control := float(s.rod.get("control", TEMP_ROD_CONTROL))
	var reeling: float = _input.get_reel_strength(s.player_id) if _input != null else 0.0

	# Fish alternates between calm periods and surges (hard pulls).
	s.surge_timer -= delta
	if s.surge_timer <= 0.0:
		s.surging = not s.surging
		s.surge_timer = randf_range(0.8, 1.6) if s.surging else randf_range(1.5, 3.0)
		if s.surging:
			# Immediate vibration pulse as soon as a surge starts
			s.surge_vibrate_timer = surge_vibrate_interval
			_notify_phone(s.player_id, {"type": "vibrate", "reason": "surge"})

	# Keep pulsing vibration on the phone while the fish is surging
	if s.surging:
		s.surge_vibrate_timer -= delta
		if s.surge_vibrate_timer <= 0.0:
			s.surge_vibrate_timer = surge_vibrate_interval
			_notify_phone(s.player_id, {"type": "vibrate", "reason": "surge"})

	# A tired fish pulls less.
	var stamina_ratio := s.stamina / s.max_stamina
	var pull_mult := SURGE_PULL_MULT if s.surging else CALM_PULL_MULT
	var fish_pull := float(s.fish["pull_strength"]) * pull_mult * (0.4 + 0.6 * stamina_ratio)

	# Tension eases toward (fish pull + reel force). Reeling during a surge
	# is what snaps lines, so players should reel in bursts.
	# >>> TWEAK REELING SPEED <<< REEL_TENSION_FORCE
	var target := fish_pull + reeling * reel_speed * REEL_TENSION_FORCE
	var rate := TENSION_RISE_RATE if target > s.tension else TENSION_FALL_RATE
	s.tension = move_toward(s.tension, target, rate * delta)

	# Reeling wins distance; the fish takes it back.
	# >>> TWEAK REELING SPEED <<< REEL_PROGRESS_RATE
	s.progress += reeling * reel_speed * REEL_PROGRESS_RATE * delta
	s.progress -= fish_pull * FISH_DRAG_RATE * delta
	s.progress = clampf(s.progress, 0.0, 1.0)

	# The fish wears itself out.
	s.stamina = maxf(s.stamina - (SURGE_DRAIN if s.surging else CALM_DRAIN) * delta, 0.0)

	# Line snaps if overloaded for too long (better rod control = more forgiving).
	if s.tension > line_strength:
		s.snap_timer += delta
	else:
		s.snap_timer = maxf(s.snap_timer - delta * 2.0, 0.0)

	# Bobber sinks smoothly over bobber_sink_duration (1.0s) and glides toward the player.
	if s.bobber != null:
		var origin := _anchor_water_pos(s)
		var to_target := s.cast_target - origin
		var away := clampf((1.0 - s.progress) / maxf(1.0 - START_PROGRESS, 0.01), 0.0, 2.0)
		var wanted := origin + to_target.normalized() * maxf(to_target.length() * away, CATCH_STOP_DISTANCE)
		
		var sink_t := clampf(s.state_time / maxf(bobber_sink_duration, 0.01), 0.0, 1.0)
		var sink_depth := bobber_bite_sink * sink_t * (1.2 if s.surging else 1.0)
		wanted.y = water_level - sink_depth
		
		s.bobber.global_position = s.bobber.global_position.lerp(wanted, 1.0 - exp(-10.0 * delta))

	if s.snap_timer >= SNAP_GRACE_SEC * maxf(control, 0.1):
		_fish_escapes(s, "line_snapped")
	elif s.progress <= 0.0:
		_fish_escapes(s, "got_away")
	elif s.progress >= 1.0:
		_fish_won(s)


# The fight was won. The fish is kept (fish_caught) unless the Fish Box is
# full, in which case it is released (fish_released) per D4.
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


# Unlocks the species in SaveManager for the Almanac.
func _record_caught_fish(fish_id: String) -> void:
	if _save == null or not _save.has_method("record_caught_fish"):
		_warn_once("record_caught_fish", "SaveManager.record_caught_fish() not found - Almanac will not unlock.")
		return
	var is_new := bool(_save.record_caught_fish(fish_id))
	if is_new and debug_log:
		print("[FishingManager] New Almanac entry unlocked: '%s'" % fish_id)


# C8: InventoryManager.add_fish(fish_id, size_cm) returns false when full.
func _store_fish(fish: Dictionary) -> bool:
	if _inventory == null or not _inventory.has_method("add_fish"):
		_warn_once("add_fish", "InventoryManager.add_fish() not found - catch is counted but NOT stored (FM-REQ-9).")
		return true
	return bool(_inventory.add_fish(String(fish["id"]), float(fish["size_cm"])))


# Shows the caught fish's picture on the scene's "FishLayout" node for
# CATCH_POPUP_SECONDS, then hides it again. A new catch restarts the 5 seconds.
# One layout for everyone: in 2-player mode the latest catch wins.
const CATCH_POPUP_SECONDS := 5.0
const FISH_IMAGE_PROPERTIES := ["jpg", "image", "icon", "texture"]
var _popup: CanvasLayer = null

func _show_catch_popup(player_id: int, fish: Dictionary, kept: bool) -> void:
	# 1. Find the node.
	if not is_instance_valid(_fish_layout):
		_fish_layout = get_tree().root.find_child("FishLayout", true, false)
	if _fish_layout == null:
		_warn_once("fish_layout", "no node named 'FishLayout' in the scene - nothing to show the catch on.")
		return

	# 2. The fish's picture, from its database record (a Texture2D or a res:// path).
	var record: Object = _db.get_fish(String(fish["id"])) if _db != null else null
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
		_warn_once("fish_image", "fish '%s' has no picture (tried %s on its record)." % [String(fish["id"]), str(FISH_IMAGE_PROPERTIES)])
		return

	# 3. Put it on FishLayout: its "jpg" property (a String property gets the
	#    path, anything else the texture), or the texture of a TextureRect.
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

	# 4. Visible for 5 seconds, then hidden again.
	_fish_layout.set("visible", true)
	_fish_layout_token += 1
	var token := _fish_layout_token
	var hide_layout := func() -> void:
		if token == _fish_layout_token and is_instance_valid(_fish_layout):
			_fish_layout.set("visible", false)
	get_tree().create_timer(CATCH_POPUP_SECONDS).timeout.connect(hide_layout)

func _fish_escapes(s: FishingSession, reason: String) -> void:
	_set_state(s, State.ESCAPED)
	fish_escaped.emit(s.player_id, s.fish.duplicate(true), reason)
	on_escape(s)


# ----------------------------------------------------------------------------
# Input handlers
# ----------------------------------------------------------------------------
func _connect_input() -> void:
	_input.cast_triggered.connect(_on_cast)
	_input.interact_pressed.connect(_on_interact)
	_input.cancel_pressed.connect(_on_cancel)


func _on_cast(player_id: int, power: float) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		if debug_log:
			print("[FishingManager] cast ignored: no session for player %d (sessions: %s)" % [player_id, str(_order)])
		return
	if s.state != State.IDLE or _finished:
		if debug_log:
			print("[FishingManager] cast ignored: player %d is %s" % [player_id, "finished" if _finished else State.keys()[s.state]])
		return
	if _time_up:
		_reject_cast(player_id, "time_up")
		return

	# D10 + D5: bait is always required and is spent on cast.
	if require_bait:
		if s.bait_id == "":
			_reject_cast(player_id, "no_bait", "no bait_id set (scene context or debug_bait_id)")
			return
		if not _spend_bait(s):
			_reject_cast(player_id, "no_bait", "none of '%s' in the Tackle Box" % s.bait_id)
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

	# The line leaves from the rod's LineTip when the rod model has one.
	if s.line_tip != null and is_instance_valid(s.line_tip):
		s.cast_start = s.line_tip.global_position
	else:
		s.cast_start = origin + Vector3.UP * 1.0
	s.cast_target = Vector3(origin.x + forward.x * distance, water_level, origin.z + forward.z * distance)
	s.cast_duration = 0.6 + 0.6 * power
	s.cast_arc = CAST_ARC_BASE + CAST_ARC_POWER * power
	s.cast_time = 0.0

	_spawn_bobber(s)
	# The state change to CASTING is what locks view rotation (see _update_session).
	_set_state(s, State.CASTING)
	cast_started.emit(player_id, power, s.cast_target)


# Tap / E: recall the line before a bite (C7).
func _on_interact(player_id: int) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s != null and s.state == State.WAITING:
		_remove_bobber(s)
		_set_state(s, State.IDLE)


# Backspace / X: leave the minigame (single player, only while IDLE).
func _on_cancel(player_id: int) -> void:
	if _multiplayer:
		return
	var s := _sessions.get(player_id) as FishingSession
	if s != null and s.state == State.IDLE:
		finish_session()


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
func _fill_debug_defaults() -> void:
	var fallbacks := {"spot_id": debug_spot_id, "rod_id": debug_rod_id, "bait_id": debug_bait_id}
	for key in fallbacks:
		if String(_context.get(key, "")) == "" and String(fallbacks[key]) != "":
			_context[key] = fallbacks[key]


func _pick_player_ids() -> Array[int]:
	print("[FM DEBUG] phones=%s max_players=%d" % [_input.get_connected_phone_ids(), max_players])
	var ids: Array[int] = []
	if _multiplayer and _input != null:
		ids.assign(_input.get_connected_phone_ids())
		ids.sort()
		if ids.size() > max_players:
			ids.resize(max_players)
	if ids.is_empty():
		ids.append(1)   # single player (keyboard, or any phone remapped to 1)
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
	if debug_log:
		print("[FishingManager] player %d: %s -> %s" % [s.player_id, State.keys()[old], State.keys()[new_state]])
	# Screen packets for the phone: the reeling screen only while a fish is on,
	# the fishing ("casting") screen otherwise (idle, casting, waiting, result).
	var screen := _phone_screen_for(new_state)
	if screen != _phone_screen_for(old):
		_send_game_state(s.player_id, screen)
	state_changed.emit(s.player_id, new_state, old)


# Which phone screen goes with a fishing state.
func _phone_screen_for(state: int) -> String:
	return "reeling" if state == State.REELING else "casting"


# A phone (re)connected: it boots to its overworld screen, so tell it where we are.
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


# Bait is spent on cast (D5). In multiplayer there is no inventory (D7), so
# bait is required but not consumed.
func _spend_bait(s: FishingSession) -> bool:
	if _multiplayer:
		return true
	if _inventory == null or not _inventory.has_method("consume_item"):
		_warn_once("bait_inventory", "InventoryManager not found - bait is NOT consumed.")
		return true
	return bool(_inventory.consume_item(s.bait_id, 1))


# Loads the rod's stats from GameDB and swaps the 3D model.
# Missing stat fields fall back to the TEMP_ROD_* defaults.
func _load_rod(s: FishingSession) -> void:
	var record: Object = null
	if _db != null and s.rod_id != "" and _db.has_rod(s.rod_id):
		record = _db.get_rod(s.rod_id)
	s.rod = {
		"line_strength": _stat(record, "line_strength", TEMP_ROD_LINE_STRENGTH),
		"reel_speed": _stat(record, "reel_speed", TEMP_ROD_REEL_SPEED),
		"max_cast_distance": _stat(record, "max_cast_distance", TEMP_ROD_MAX_CAST_DISTANCE),
		"control": _stat(record, "control", TEMP_ROD_CONTROL),
	}

	_remove_rod_model(s)
	if record == null or s.holder == null:
		return
	var model: Node3D = _db.instantiate_rod_model(s.rod_id)
	if model == null:
		return   # the rod has no model yet
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


# Reads a numeric property from a GameDB record by name. Returns the default
# when the record is null or does not have that property yet.
func _stat(record: Object, prop: String, default_value: float) -> float:
	if record == null:
		return default_value
	var v: Variant = record.get(prop)
	if v == null:
		return default_value
	return float(v)


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("FishingManager: " + message)
