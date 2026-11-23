extends Node3D

# ============================================================================
# FISHING MANAGER (SCENE NODE) - TightLines          Version 0.5.1 (2026-11-17)
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
# 0.5.1: replaced the random pan with a smooth fish sweep (left then right, or right
#        then left); the camera eases toward the bobber instead of moving on its own
#        (exports under "Fish Sweep (reeling)").
# 0.4.9: tension only falls when the player RELEASES the reel (get_release_strength).
# Variable labels: every export/const has "what it does | when to tweak".
# ============================================================================

# --- Signals (for UI, camera rigs, audio, SaveManager) ---
signal state_changed(player_id: int, new_state: int, old_state: int)
signal cast_started(player_id: int, power: float, target: Vector3)
signal bobber_landed(player_id: int, position: Vector3)
signal fish_bit(player_id: int)
signal fish_caught(player_id: int, fish: Dictionary)
signal fish_released(player_id: int, fish: Dictionary, reason: String)
signal fish_escaped(player_id: int, fish: Dictionary, reason: String)
signal knotting_started(player_id: int)
signal knotting_completed(player_id: int, knot_name: String, accuracy: float)
signal cast_rejected(player_id: int, reason: String)
signal rod_changed(player_id: int, rod_id: String)
signal bait_changed(player_id: int, bait_id: String)
signal difficulty_changed(difficulty: int)
signal session_finished(results: Dictionary)

enum State { IDLE, CASTING, WAITING, REELING, CAUGHT, ESCAPED, KNOTTING }
enum Difficulty { CASUAL, ANGLER }

# --- Scene setup ---
# Each variable: WHAT IT DOES  |  WHEN TO TWEAK
@export_group("Scene setup")
@export var player_anchors: Array[Node3D] = []   # Node3D per player that turns with the camera / casts from. | Assign in the Inspector, one per player.
@export var rod_holders: Array[Node3D] = []      # Where each rod model is attached (falls back to the anchor). | Assign if the rod should sit somewhere other than the camera anchor.
@export var bobber_scene: PackedScene            # Your own bobber scene. | Assign when you have a bobber model; empty = red sphere.
@export var water_level := 0.0                   # World Y of the water surface; bobber lands/floats here. | Change if the water plane is not at Y = 0.
@export var max_players := 2                     # Most players one round supports. | Raise only if you add more viewports/anchors.
@export var weather_system: Node                 # WeatherSystem node (found by itself if empty). | Only if you have several WeatherSystem nodes.
@export var difficulty: Difficulty = Difficulty.CASUAL   # CASUAL = longer snap grace; ANGLER = strict. | Debug here; normally set by the options/save.

@export_group("Casting")
@export var min_cast_distance := 4.0             # Cast distance at zero power (metres). | Raise if weak casts land too close to the player.
@export var look_turn_speed := 1.5               # How fast the view turns while idle (rad/sec at full tilt/key). | Lower if aiming feels twitchy, raise if sluggish.
@export var max_look_angle_deg := 75.0           # How far the view can turn left AND right. | Lower to keep players facing the water.

@export_group("Bites")
@export var bite_delay_min := 30.0               # Shortest wait before a bite (seconds). | Lower for faster action.
@export var bite_delay_max := 45.0              # Longest wait before a bite (seconds). | Raise for a calmer, slower game.
@export var bobber_bite_sink := 0.12             # How far the bobber dips on a bite (metres). | Raise if the bite is hard to notice.
@export var bobber_sink_duration := 1.0          # Seconds the bobber takes to sink. | Lower for a sudden, snappy dip.

@export_group("Camera Shake")
@export var enable_camera_shake := true          # Shake the view while the fish surges. | Turn off for motion comfort.
@export var shake_base_intensity := 0.06         # Shake size (radians), scales with tension. | Lower if it is nauseating, raise for drama.
@export var shake_frequency := 30.0              # Shake speed. | Lower for a slow rumble, raise for a rattle.

@export_group("Fish Sweep (reeling)")
@export var enable_fish_sweep := true            # While reeling the fish swims left then right (or right then left) in smooth sweeps, and the camera follows the bobber. | Turn off for a fixed view.
@export var pan_bobber_meters := 4.0             # How far the bobber sweeps to each side of the line (metres). | Match your water width.
@export var pan_period_calm := 3.2               # Seconds for one full left-and-right sweep while the fish is calm. | Raise for slower, lazier sweeps.
@export var pan_period_surge := 1.8              # Same, while the fish is surging. | Lower for a more frantic fish.
@export var pan_amount_calm := 0.6               # How wide the sweep is while calm (0..1 of the full width). | Raise for wider swims.
@export var pan_amount_surge := 1.0              # How wide the sweep is while surging (0..1). | Lower to calm surges down.
@export var pan_bobber_smooth := 5.0             # How tightly the bobber follows the sweep (higher = snappier). | Lower for floatier motion.
@export var pan_camera_follow := 0.8             # How much of the bobber's sideways angle the camera follows (0 = fixed, 1 = fully centred on it). | Lower to keep the view steadier.
@export var pan_camera_smooth := 3.0             # How smoothly the camera catches up (higher = tighter). | Lower for a lazier camera.

@export_group("Fight length")
@export_range(0.5, 5.0, 0.1) var fight_length_multiplier := 4.0   # How long the reel fight lasts compared to before (1.0 = old length, 2.0 = twice as long, 3.0 = three times). | Raise for longer fights, lower for quicker catches.

@export_group("Fish Music")
@export var fish_music: Array[FishMusicEntry] = []   # One row per special fish: drag the fish record and the song into it. | Add a row for each fish that should have its own music.
@export var fish_music_fade_in := 0.4            # Seconds to fade the track in when the fish bites. | Raise for a gentler start.
@export var fish_music_fade_out := 0.8           # Seconds to fade out when the fish is caught or escapes. | Raise for a softer ending.
@export var fish_music_volume_db := 0.0          # Track volume. | Lower if it drowns out the scene music.

@export_group("3D Presentation & Juice")
@export var enable_fishing_line := true          # Draw a 3D fishing line from the rod tip to the bobber.
@export var line_segments := 14                  # Curve segments along the fishing line.
@export var rod_tip_fallback_offset := Vector3(0.0, 2.2, -0.35) # Local offset on rod holder if no LineTip Marker3D exists.
@export var enable_rod_flex := true              # Bend/pitch the rod holder smoothly with line tension.
@export var rod_flex_max_pitch_deg := 22.0       # Max forward pitch (degrees) at full tension.
@export var rod_flex_max_yaw_deg := 10.0         # Max sideways flex (degrees) following fish sweep.
@export var enable_water_splashes := true        # Spawn 3D splash particle bursts on cast landing, bite, and surges.
@export var enable_sfx := true                   # Play procedural fishing SFX on the SFX bus.

@export_group("HUD / UI")
@export var show_tension_bar := true            # On-screen tension bar while reeling. | Turn off if your own HUD draws it.
@export var node_to_hide_on_bite: CanvasLayer    # CanvasLayer to set invisible on bite, and visible again after reeling. | Assign your UI layer here.

@export_group("Messages")
@export var show_messages := true                # "There's a bite" / "Reel now" / "Fish escaped" text. | Turn off if your HUD shows messages.
@export var bite_message_seconds := 0.8          # How long "There's a bite" shows before "Reel now". | Raise if players miss the bite cue.
@export var message_font_size := 48              # Size of those messages. | Match your UI scale.
@export var send_phone_messages := true          # Send game_state and vibrate packets to the Android app. | Turn off to test without a phone.
@export var surge_vibrate_interval := 0.35       # Seconds between phone vibrations during a surge. | Raise if the phone buzz feels constant.

@export_group("Round rules")
@export var result_display_time := 2.5           # Seconds the CAUGHT / ESCAPED result stays before IDLE. | Lower to get back to casting faster.
@export var time_limit_sec := 0.0                # Round length in seconds, 0 = no limit. | MUST be set for multiplayer, or nothing ends the round.
@export var require_bait: bool = true            # true = a cast needs bait and spends it (D10 says always true).
@export var store_catches_in_inventory := true   # Put kept fish in the Fish Box (single player only, D7). | Turn off to test without InventoryManager.
@export var enable_knotting_minigame := true     # Require the mobile knotting tracing minigame after a tension line snap. | Turn off to skip straight back to IDLE.

@export_group("Debug / standalone testing")
@export var debug_spot_id := ""                  # Spot used when no GameManager context is passed. | Fill in for F6 testing.
@export var debug_rod_id := ""                   # Rod used when no context is passed. | Fill in for F6 testing.
@export var debug_bait_id := ""                  # Bait used when no context is passed. | Fill in for F6 testing.
@export var force_debug_equipment := false       # Always use debug_rod_id and debug_bait_id, ignoring SaveManager/context.
@export var debug_multiplayer := false           # Test the 2-player scene without GameManager. | F6 testing only.
@export var debug_log := true                    # Print state changes and rejections. | Turn off in a release build.

# --- Day / weather words used when NO WeatherSystem node is in the scene ---
var time_of_day := ""
var weather := ""
var season := ""

# --- Fallback defaults used if GameDB records lack a field ---
# These only matter until the record has its own value. | Tweak only to change the "default" rod/fish.
const UI_THEME: Theme = preload("res://UIScenesAndScript/Shared/ui_theme.tres")
const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")
const FISHING_SFX_SCRIPT := preload("res://AutoloadFolders/FishingManager/fishing_sfx.gd")
const GAME_MANAGER_SCRIPT := preload("res://AutoloadFolders/GameManager/GameManager.gd")
const TEMP_ROD_LINE_STRENGTH := 10.0     # Default line strength; the tension bar is measured against it. | Raise for a sturdier default rod.
const TEMP_ROD_MAX_CAST_DISTANCE := 20.0 # Default max cast distance (metres). | Match your water size.
const TEMP_ROD_CONTROL := 1.0            # Default control; multiplies the snap grace time. | Raise to forgive longer overloads.
const TEMP_FISH_PULL_STRENGTH := 4.0     # Default fish pull. | Only for fish without a pull_strength.
const TEMP_FISH_STAMINA := 20.0          # Default fish stamina (seconds of fight). | Only for fish without stamina.
const TEMP_ROD_REEL_SPEED := 1.0         # Default reel speed; how fast reeling wins line. | Raise to make reeling feel stronger.

# --- Reel fight tuning ---
# TENSION BAR = fish half + reel half, each capped (FISH_SHARE_MAX / REEL_SHARE_MAX).
# Tension only goes UP by itself and only goes DOWN when the player releases the reel.
const REEL_PROGRESS_RATE := 0.20         # Line won per second at full reeling (progress 0..1). | Lower = longer fights, higher = quicker catches.
const TENSION_RISE_RATE := 1             # How fast tension builds (line-strength units/sec; /line_strength = bar fraction/sec). Used for the fish surge AND for reeling. | Lower if the bar fills too fast, raise if the fight is too safe.
const TENSION_FALL_RATE := 3.0           # How fast RELEASING the reel lowers tension (same units, at full release). | Raise if releasing is too slow to save the line, lower to make it riskier.
const FISH_SHARE_MAX := 0.7              # Fish's part of the bar (0..1). Keep FISH + REEL = 1.0. | Raise to make the fish matter more than your reeling.
const REEL_SHARE_MAX := 0.7              # Reeling's part of the bar (0..1). Keep FISH + REEL = 1.0. | Raise to punish heavy reeling more.
const RELEASE_LINE_LOSS_RATE := 0.04     # Progress the fish takes back per second at full release. | Raise so releasing costs more distance, lower to make it cheap.
const FISH_DRAG_RATE := 0.008            # Line the fish takes back per second (scaled by its pull). | Raise if fish never fight back enough, lower if they win too much.
const START_PROGRESS := 0.35             # Fight starts this far toward landed (0..1). | Raise for an easier start, lower for a harder one.
const SNAP_GRACE_SEC := 0.5              # Seconds the bar may stay in the danger zone before the line snaps (x rod control, x2.5 in Casual). | Raise to forgive, lower to be strict.
const PULL_FOR_FULL_SHARE := 6.0         # Fish pull that fills the fish's whole half. Higher = fish fills less of its half. | Raise if fish fill their half too easily.
const SNAP_RATIO := 0.90                 # Bar level (0..1) where the snap timer starts. | Raise toward 1.0 to make snaps rarer.
const SURGE_REEL_PROGRESS_MULT := 0.5    # Share of line won when reeling DURING a surge. | Lower to discourage reeling into a surge, raise to soften it.
const CALM_REEL_PROGRESS_MULT := 1.3     # Multiplier for reeling while fish is calm | Lower to discourage reeling while calm, raise to encourage reeling while calm
const SURGE_PULL_MULT := 1.4             # Fish pull multiplier while surging. | Lower to make surges gentler.
const CALM_PULL_MULT := 0.8              # Fish pull multiplier while calm. | Raise so calm moments are less restful.
const SURGE_DRAIN := 1.0                 # Stamina lost per second while surging. | Raise so fish tire faster.
const CALM_DRAIN := 0.5                  # Stamina lost per second while calm. | Raise so fish tire faster.
const CAST_ARC_BASE := 2.0               # Height of the cast arc at zero power (metres). | Visual only.
const CAST_ARC_POWER := 3.0              # Extra arc height at full power (metres). | Visual only.
const CATCH_STOP_DISTANCE := 2.0         # How close the bobber gets to the player when the fish is nearly landed. | Visual only.

const WEATHER_BITE_SPEED := {
	"clear": 1.00,
	"cloudy": 1.20,
	"rain": 1.30,
	"rainy": 1.30,
	"storm": 0.80,
}
const HOUR_BITE_SPEED_GENERAL: Array[float] = [
	0.80, 0.80, 0.75, 0.80, 1.00, 1.35, 1.40, 1.25,
	1.10, 1.00, 0.90, 0.80, 0.75, 0.75, 0.80, 0.90,
	1.10, 1.30, 1.45, 1.30, 1.05, 0.95, 0.90, 0.85,
]
const HOUR_BITE_SPEED_NOCTURNAL: Array[float] = [
	1.50, 1.45, 1.40, 1.30, 1.15, 0.95, 0.80, 0.65,
	0.55, 0.50, 0.45, 0.40, 0.35, 0.35, 0.40, 0.45,
	0.55, 0.70, 0.90, 1.15, 1.30, 1.40, 1.45, 1.45,
]

const MSG_BITE := "There's a bite"       # Text shown on a bite. | Change wording / language.
const MSG_REEL := "Reel now"             # Text shown after the bite message. | Change wording / language.
const MSG_ESCAPE := "Fish escaped"       # Text shown when the fish gets away. | Change wording / language.
const MSG_LINE_SNAPPED := "Line snapped!" # Text shown when the line snaps due to tension.
const MSG_KNOT_PHONE := "Tie a knot on your phone!"
const MSG_KNOT_KEYBOARD := "Line snapped!\nTie a knot on your phone (or press E)"
const MSG_KNOT_TIED := "Knot tied! Ready to cast"
const MSG_NO_CATCH_ODDS := "hm. seems like I need to change up my gear"

const CATCH_POPUP_SECONDS := 5.0         # How long the catch popup and picture stay up. | Lower to move on faster.
const FISH_IMAGE_PROPERTIES := ["icon_3d", "jpg", "image", "icon", "texture"]   # FishData property names tried for the fish picture. | Add the name your FishData uses.
const SPOT_STORY_PREFIXES := {
	"location_imus": "imus",
	"location_kawit": "kawit",
	"location_fish_pens": "pen",
	"location_salt_farm": "salt",
	"location_calatagan": "mangrove",
	"location_fortune_island": "island",
}

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
	var cached_tip_local_offset := Vector3.ZERO
	var has_cached_tip_offset := false
	var holder_base_rotation := Vector3.ZERO
	var line_mesh_node: MeshInstance3D = null
	var line_im: ImmediateMesh = null
	var line_mat: StandardMaterial3D = null
	var reel_sfx_timer := 0.0
	var surge_splash_timer := 0.0
	var telemetry_timer := 0.0

	var bobber: Node3D = null
	var fish: Dictionary = {}
	var pending_fish: Dictionary = {}

	var cast_start := Vector3.ZERO
	var cast_target := Vector3.ZERO
	var cast_duration := 1.0
	var cast_arc := 2.0
	var cast_time := 0.0

	var bite_timer := 0.0

	var tension := 0.0
	var fish_tension := 0.0              # fish half of the bar, 0..FISH_SHARE_MAX
	var reel_tension := 0.0              # reeling half of the bar, 0..REEL_SHARE_MAX
	var progress := 0.0
	var stamina := 0.0
	var max_stamina := 1.0
	var surging := false
	var surge_timer := 0.0
	var surge_vibrate_timer := 0.0
	var snap_timer := 0.0
	var needs_knot := false
	var knot_progress := 0.0
	var escape_reason := ""

	var msg_token := 0
	var shake_time := 0.0

	var pan_pos := 0.0                   # sideways sweep position, -1..1
	var pan_phase := 0.0                 # position in the left/right cycle (radians)
	var pan_sign := 1.0                  # +1 = sweep one way first, -1 = the other way first
	var pan_amp := 0.6                   # current sweep width (eases between calm and surge)
	var pan_cam := 0.0                   # camera yaw offset (radians), eased toward the bobber

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
var _quest: Node = null
var _fish_music_player: AudioStreamPlayer = null
var _fish_music_tween: Tween = null
var _scene_music_suppressed := false
var _context: Dictionary = {}
var _multiplayer := false
var _win_mode := "total_weight"
var _elapsed := 0.0
var _time_up := false
var _finished := false
var _warned: Dictionary = {}
var _fish_layout: Node = null
var _fish_layout_token := 0
var _popup: CanvasLayer = null
var _popups: Dictionary = {}
var _player_names: Dictionary = {}
var _msg_layer: CanvasLayer = null
var _msg_labels: Dictionary = {}
var _tension_layer: CanvasLayer = null
var _tension_bars: Dictionary = {}
var _sfx: Node = null
var _splash_count := 0


func _ready() -> void:
	_input = get_node_or_null("/root/InputManager")
	_game_manager = get_node_or_null("/root/GameManager")
	_db = get_node_or_null("/root/GameDB")
	_save = get_node_or_null("/root/SaveManager")
	_inventory = get_node_or_null("/root/InventoryManager")
	_connection = get_node_or_null("/root/ConnectionManager")
	_quest = get_node_or_null("/root/QuestManager")

	if enable_sfx:
		_sfx = FISHING_SFX_SCRIPT.new()
		_sfx.name = "FishingSFX"
		add_child(_sfx)

	if _input == null:
		push_error("FishingManager: InputManager autoload not found - no input will work.")
	if _db == null:
		push_error("FishingManager: GameDB autoload not found - no fish can bite.")

	if _game_manager != null and _game_manager.has_method("consume_context"):
		_context = _game_manager.consume_context().duplicate(true)

	if _context.has("time_limit_sec"):
		time_limit_sec = maxf(float(_context.get("time_limit_sec", 0.0)), 0.0)
	if _context.has("player_names") and _context["player_names"] is Dictionary:
		set_player_names(_context["player_names"])

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
	_win_mode = String(_context.get("win_mode", "total_weight")).strip_edges().to_lower()
	if not ["total_weight", "biggest_fish", "most_fish"].has(_win_mode):
		_win_mode = "total_weight"
	if _multiplayer and time_limit_sec <= 0.0:
		push_warning("FishingManager: multiplayer round has no time_limit_sec - Cancel is disabled in multiplayer.")

	_fill_debug_defaults()

	if _input != null:
		_connect_input()
	if _connection != null and _connection.has_signal("player_connected"):
		_connection.player_connected.connect(_on_phone_connected)
	if _save != null and _save.has_signal("equipment_changed"):
		_save.equipment_changed.connect(_on_save_equipment_changed)

	start_session(_pick_player_ids())


func _exit_tree() -> void:
	# Never leave the scene music muted when the scene closes mid-fight.
	if _scene_music_suppressed and _game_manager != null and _game_manager.has_method("set_music_suppressed"):
		_game_manager.set_music_suppressed(false, 0.0)
	if _connection != null and _connection.has_signal("player_connected") \
			and _connection.player_connected.is_connected(_on_phone_connected):
		_connection.player_connected.disconnect(_on_phone_connected)
	if _save != null and _save.has_signal("equipment_changed") \
			and _save.equipment_changed.is_connected(_on_save_equipment_changed):
		_save.equipment_changed.disconnect(_on_save_equipment_changed)
	if _input == null:
		return
	if _input.cast_triggered.is_connected(_on_cast):
		_input.cast_triggered.disconnect(_on_cast)
	if _input.interact_pressed.is_connected(_on_interact):
		_input.interact_pressed.disconnect(_on_interact)
	if _input.cancel_pressed.is_connected(_on_cancel):
		_input.cancel_pressed.disconnect(_on_cancel)
	if _input.has_signal("menu_action") and _input.menu_action.is_connected(_on_menu_action):
		_input.menu_action.disconnect(_on_menu_action)
	if _input.has_signal("knot_progress") and _input.knot_progress.is_connected(_on_knot_progress):
		_input.knot_progress.disconnect(_on_knot_progress)
	if _input.has_signal("knot_completed") and _input.knot_completed.is_connected(_on_knot_completed):
		_input.knot_completed.disconnect(_on_knot_completed)


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
		_remove_fishing_line(s)
		_remove_rod_model(s)
	_sessions.clear()
	_order.clear()
	_clear_messages()
	_clear_tension_bars()
	_clear_popups()
	_elapsed = 0.0
	_time_up = false
	_finished = false

	if node_to_hide_on_bite != null:
		node_to_hide_on_bite.visible = true

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
		s.holder_base_rotation = s.holder.rotation if s.holder != null else Vector3.ZERO
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
		"cast_charge": _input.get_cast_charge(player_id) if _input != null else 0.0,
		"catch_count": s.catches.size(),
		"total_weight": s.total_weight,
		"rod_id": s.rod_id,
		"bait_id": s.bait_id,
		"look_degrees": rad_to_deg(s.look_offset),
		"difficulty": difficulty,
		"fish_name": String(s.fish.get("display_name", "")),
		"release_active": _get_release(player_id) > 0.0,
		"needs_knot": s.needs_knot,
		"knot_progress": s.knot_progress,
	}


func get_state(player_id: int) -> int:
	var s := _sessions.get(player_id) as FishingSession
	return s.state if s != null else State.IDLE


func get_time_left() -> float:
	if time_limit_sec <= 0.0:
		return -1.0
	return maxf(time_limit_sec - _elapsed, 0.0)


func is_time_up() -> bool:
	return _time_up


func get_context() -> Dictionary:
	return _context.duplicate(true)


func get_player_order() -> Array[int]:
	return _order.duplicate()


func set_player_names(names: Dictionary) -> void:
	_player_names.clear()
	for key in names:
		var clean := String(names[key]).strip_edges()
		if clean != "":
			_player_names[int(key)] = clean


func get_player_name(player_id: int) -> String:
	var custom := String(_player_names.get(player_id, "")).strip_edges()
	if custom != "":
		return custom
	if _connection != null and _connection.has_method("get_player_name"):
		return String(_connection.call("get_player_name", player_id))
	return "Player %d" % player_id


func finish_session() -> void:
	if _finished:
		return
	_finished = true
	if node_to_hide_on_bite != null:
		node_to_hide_on_bite.visible = true
	var results := {}
	var names_snapshot := {}
	for pid in _order:
		var s: FishingSession = _sessions[pid]
		_remove_bobber(s)
		results[pid] = {"catches": s.catches.duplicate(true), "total_weight": s.total_weight}
		names_snapshot[pid] = get_player_name(pid)
		_send_game_state(pid, "overworld")
	_clear_tension_bars()
	session_finished.emit(results)

	var payload := {"results": results}
	if _multiplayer:
		payload["winner"] = compute_winner_id(results, _win_mode)
		payload["win_mode"] = _win_mode
		payload["player_names"] = names_snapshot
		payload["player_order"] = _order.duplicate()
		payload["time_limit_sec"] = time_limit_sec
	if _game_manager == null:
		return
	if _game_manager.has_method("end_fishing"):
		_game_manager.end_fishing(payload)
	elif _game_manager.has_method("change_scene"):
		_warn_once("end_fishing", "GameManager.end_fishing() missing - using change_scene() fallback.")
		var back := String(_context.get("return_to", ""))
		_game_manager.change_scene(back if back != "" else "overworld", {"result": payload})


func _winner_id(results: Dictionary) -> int:
	return compute_winner_id(results, _win_mode)


static func compute_winner_id(results: Dictionary, mode: String = "total_weight") -> int:
	var best := -1
	var best_score := -1.0
	var tie := false
	for pid in results:
		var entry: Dictionary = results[pid]
		var score := 0.0
		match mode:
			"most_fish":
				var catches: Array = entry.get("catches", [])
				score = float(catches.size())
			"biggest_fish":
				var catches: Array = entry.get("catches", [])
				for fish in catches:
					if fish is Dictionary:
						score = maxf(score, float(fish.get("weight", 0.0)))
			_:
				score = float(entry.get("total_weight", 0.0))
		if score > best_score + 0.0001:
			best_score = score
			best = int(pid)
			tie = false
		elif absf(score - best_score) <= 0.0001:
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
			var wait_sec := minf(result_display_time, 1.4) if (s.state == State.ESCAPED and s.needs_knot) else result_display_time
			if s.state_time >= wait_sec:
				_remove_bobber(s)
				if s.state == State.ESCAPED and s.needs_knot and not _time_up:
					_start_knotting(s)
				else:
					s.needs_knot = false
					_set_state(s, State.IDLE)
		State.KNOTTING:
			if _time_up:
				s.needs_knot = false
				s.knot_progress = 0.0
				_hide_message(s.player_id)
				_set_state(s, State.IDLE)

	_update_fishing_line(s)
	_update_rod_flex(s, delta)


# --- CASTING ---
func _update_casting(s: FishingSession, delta: float) -> void:
	s.cast_time += delta
	var t := clampf(s.cast_time / s.cast_duration, 0.0, 1.0)
	if s.bobber != null:
		var pos := s.cast_start.lerp(s.cast_target, t)
		pos.y += s.cast_arc * 4.0 * t * (1.0 - t)
		s.bobber.global_position = pos
	if t >= 1.0:
		s.pending_fish = _roll_fish(s)
		s.bite_timer = _roll_bite_delay()
		_set_state(s, State.WAITING)
		_spawn_water_splash(s.cast_target, 1.0)
		_play_sfx("splash", -5.0, randf_range(0.92, 1.08))
		bobber_landed.emit(s.player_id, s.cast_target)


# --- WAITING ---
func _update_waiting(s: FishingSession, delta: float) -> void:
	if _time_up:
		s.pending_fish = {}
		_remove_bobber(s)
		_set_state(s, State.IDLE)
		return

	if s.bobber != null:
		var pos := s.cast_target
		pos.y += sin(s.state_time * 3.0) * 0.03
		s.bobber.global_position = pos

	var speed_mult := get_bite_speed_multiplier(bool(s.pending_fish.get("is_nocturnal", false)))
	s.bite_timer -= delta * speed_mult
	if s.bite_timer <= 0.0:
		_try_bite(s)


func _roll_bite_delay() -> float:
	var mult := maxf(float(_context.get("bite_multiplier", 1.0)), 0.1)
	return randf_range(bite_delay_min, bite_delay_max) / mult


func is_current_spot_tidal() -> bool:
	var spot_id := String(_context.get("spot_id", ""))
	if spot_id == "":
		spot_id = debug_spot_id
	if spot_id == "":
		return false
	if _db != null and _db.has_method("has_location") and bool(_db.call("has_location", spot_id)):
		var loc: Variant = _db.call("get_location", spot_id)
		return loc != null and bool(loc.get("is_tidal"))
	if _game_manager != null and _game_manager.has_method("is_location_tidal"):
		return bool(_game_manager.call("is_location_tidal", spot_id))
	return false


func get_tide_state(total_hours_override: float = -1.0) -> Dictionary:
	var t_hours := total_hours_override
	if t_hours < 0.0:
		var ws := _get_weather_system()
		if ws != null and ws.has_method("get_total_elapsed_hours"):
			t_hours = float(ws.call("get_total_elapsed_hours"))
		elif _game_manager != null and _game_manager.has_method("get_total_elapsed_hours"):
			t_hours = float(_game_manager.call("get_total_elapsed_hours"))
		else:
			t_hours = 0.0
	if _game_manager != null and _game_manager.has_method("get_tide_state"):
		return _game_manager.call("get_tide_state", t_hours)
	return GAME_MANAGER_SCRIPT.compute_tide(t_hours)


func get_bite_speed_multiplier(is_nocturnal: bool = false, weather_override: String = "", hour_override: int = -1, tidal_override: int = -1, total_hours_override: float = -1.0) -> float:
	var wx := weather_override
	var hour := hour_override
	var ws := _get_weather_system()
	if wx == "":
		if ws != null:
			var ws_wx := String(ws.get("weather"))
			if ws_wx != "":
				wx = ws_wx
		if wx == "":
			wx = weather
	if hour < 0 and ws != null and ws.has_method("get_hour"):
		hour = posmod(int(floor(float(ws.call("get_hour")))), 24)

	var weather_mult := float(WEATHER_BITE_SPEED.get(wx.to_lower(), 1.0))
	var time_mult := 1.0
	if hour >= 0:
		var h := posmod(hour, 24)
		time_mult = HOUR_BITE_SPEED_NOCTURNAL[h] if is_nocturnal else HOUR_BITE_SPEED_GENERAL[h]

	var is_tidal := (tidal_override > 0) if tidal_override >= 0 else is_current_spot_tidal()
	var tide_mult := 1.0
	if is_tidal:
		var t_hours := total_hours_override
		if t_hours < 0.0 and hour_override >= 0:
			t_hours = float(posmod(hour_override, 24))
		tide_mult = float(get_tide_state(t_hours).get("multiplier", 1.0))
	return maxf(weather_mult * time_mult * tide_mult, 0.05)


func _try_bite(s: FishingSession) -> void:
	var fish := s.pending_fish if not s.pending_fish.is_empty() else _roll_fish(s)
	s.pending_fish = {}
	if fish.is_empty():
		s.bite_timer = _roll_bite_delay()
		return
	s.fish = fish

	s.tension = 0.0
	s.fish_tension = 0.0
	s.reel_tension = 0.0
	s.progress = START_PROGRESS
	s.max_stamina = maxf(float(fish["stamina"]), 1.0)
	s.stamina = s.max_stamina
	s.surging = false
	s.surge_timer = randf_range(1.0, 2.0)
	s.surge_vibrate_timer = 0.0
	s.snap_timer = 0.0
	s.pan_pos = 0.0
	s.pan_phase = 0.0
	s.pan_sign = 1.0 if randf() < 0.5 else -1.0
	s.pan_amp = pan_amount_calm
	s.pan_cam = 0.0

	_set_state(s, State.REELING)
	if s.bobber != null:
		_spawn_water_splash(s.bobber.global_position, 1.35)
	_play_sfx("bite", -3.0, 1.0)
	fish_bit.emit(s.player_id)
	on_bite(s)
	_play_fish_music(String(fish["id"]))


# --- EVENT HOOKS ---
func on_bite(s: FishingSession) -> void:
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "bite"})
	_show_message(s.player_id, MSG_BITE, 0.0)
	_try_play_spot_story_beat("first_bite")

	s.msg_token += 1
	var token := s.msg_token
	if bite_message_seconds <= 0.0:
		on_reeling(s)
	else:
		get_tree().create_timer(bite_message_seconds).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			if token == s.msg_token and s.state == State.REELING:
				on_reeling(s))


func _try_play_spot_story_beat(event_suffix: String) -> void:
	if _multiplayer:
		return
	var spot_id := String(_context.get("spot_id", ""))
	if not SPOT_STORY_PREFIXES.has(spot_id):
		return
	var prefix := String(SPOT_STORY_PREFIXES[spot_id])
	var beat_id := "%s_%s" % [prefix, event_suffix]
	var sm := get_node_or_null("/root/StoryManager")
	if sm == null:
		return
	if not bool(sm.call("has_seen", prefix + "_arrival")):
		return
	if bool(sm.call("has_seen", beat_id)) or not bool(sm.call("has_cutscene", beat_id)):
		return
	if bool(sm.call("is_playing")):
		return
	sm.call("play", beat_id)


func on_reeling(s: FishingSession) -> void:
	_show_message(s.player_id, MSG_REEL, 0.0)


func on_escape(s: FishingSession, reason: String = "") -> void:
	s.msg_token += 1
	var is_snap := (reason == "line_snapped")
	_notify_phone(s.player_id, {"type": "vibrate", "reason": "line_snapped" if is_snap else "escape"})
	var display_sec := minf(result_display_time, 1.4) if (is_snap and enable_knotting_minigame) else result_display_time
	_show_message(s.player_id, MSG_LINE_SNAPPED if is_snap else MSG_ESCAPE, display_sec)


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
		if _connection.has_method("is_player_connected") and not bool(_connection.is_player_connected(player_id)):
			return
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme = UI_THEME
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", mini(message_font_size, 34) if _multiplayer else message_font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.anchor_left = float(index) / count
	label.anchor_right = float(index + 1) / count
	label.anchor_top = 0.62
	label.anchor_bottom = 0.78
	label.offset_left = 16.0 if _multiplayer else 0.0
	label.offset_right = -16.0 if _multiplayer else 0.0
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

		if ratio >= SNAP_RATIO:
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
	bar.theme = UI_THEME

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
		s.msg_token += 1
		_show_message(s.player_id, MSG_NO_CATCH_ODDS, 3.5)
		return {}

	var fish_id := _pick_weighted(odds)
	if fish_id == "" or not _db.has_fish(fish_id):
		if fish_id == "":
			s.msg_token += 1
			_show_message(s.player_id, MSG_NO_CATCH_ODDS, 3.5)
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
		"fight_length_multiplier": _record_float(record, "fight_length_multiplier", 1.0),
		"is_nocturnal": bool(record.get("is_nocturnal")),
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
	if (weather_system == null or not is_instance_valid(weather_system)) and get_tree() != null:
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
		s.surge_splash_timer -= delta
		if s.surge_splash_timer <= 0.0:
			s.surge_splash_timer = 0.55
			if s.bobber != null:
				_spawn_water_splash(s.bobber.global_position, 0.85)
			_play_sfx("surge_splash", -9.0, randf_range(0.9, 1.15))

	if reeling > 0.0:
		s.reel_sfx_timer -= delta
		if s.reel_sfx_timer <= 0.0:
			s.reel_sfx_timer = 0.14
			var tension_pitch := lerpf(0.95, 1.35, clampf(s.tension / maxf(line_strength, 0.001), 0.0, 1.0))
			_play_sfx("reel_tick", -10.0, tension_pitch)
	else:
		s.reel_sfx_timer = 0.0

	var stamina_ratio := s.stamina / s.max_stamina
	var pull_mult := SURGE_PULL_MULT if s.surging else CALM_PULL_MULT
	var fish_pull := float(s.fish.get("pull_strength", TEMP_FISH_PULL_STRENGTH)) * pull_mult * (0.4 + 0.6 * stamina_ratio)

	# TENSION BAR = fish share (0..0.5) + reel share (0..0.5), as a ratio of the bar.
	# Fish share: a fresh fish surging at PULL_FOR_FULL_SHARE fills its whole half;
	# a calm or tired fish fills much less.
	# Tension is ACCUMULATED and never falls with time. Only releasing the reel lowers it.
	var release := _get_release(s.player_id)

	# Fish half (cap 0.5): rises only while the fish surges, faster for stronger fish.
	if s.surging:
		var fish_strength := clampf(fish_pull / PULL_FOR_FULL_SHARE, 0.0, 1.0)
		s.fish_tension += fish_strength * TENSION_RISE_RATE / maxf(line_strength, 0.001) * delta
	# Reel half (cap 0.5): rises while reeling.
	s.reel_tension += clampf(reeling, 0.0, 1.0) * TENSION_RISE_RATE / maxf(line_strength, 0.001) * delta

	# Releasing (reel spun counterclockwise) lowers both halves.
	if release > 0.0:
		var drain := release * TENSION_FALL_RATE / maxf(line_strength, 0.001) * delta
		s.fish_tension -= drain
		s.reel_tension -= drain

	s.fish_tension = clampf(s.fish_tension, 0.0, FISH_SHARE_MAX)
	s.reel_tension = clampf(s.reel_tension, 0.0, REEL_SHARE_MAX)
	s.tension = (s.fish_tension + s.reel_tension) * line_strength

	# Reeling against a surge wins far less line AND fills the bar: discourages it.
	var reel_gain := reeling * reel_speed * REEL_PROGRESS_RATE
	if s.surging:
		reel_gain *= SURGE_REEL_PROGRESS_MULT
	else:
		reel_gain *= CALM_REEL_PROGRESS_MULT
	# fight_length_multiplier stretches the fight: line is won AND lost more slowly, so the
	# odds of landing the fish stay the same but the fight lasts longer.
	var fish_fight_mult := maxf(float(s.fish.get("fight_length_multiplier", 1.0)), 0.1)
	var pace := 1.0 / (maxf(fight_length_multiplier, 0.1) * fish_fight_mult)
	s.progress += reel_gain * pace * delta
	s.progress -= fish_pull * FISH_DRAG_RATE * pace * delta
	# Letting line out costs distance: the fish takes it back.
	s.progress -= release * RELEASE_LINE_LOSS_RATE * pace * delta
	s.progress = clampf(s.progress, 0.0, 1.0)

	# Scale stamina drain with fish_fight_mult so boss fish do not exhaust early and shorten the fight.
	s.stamina = maxf(s.stamina - (SURGE_DRAIN if s.surging else CALM_DRAIN) / fish_fight_mult * delta, 0.0)

	if s.tension >= line_strength * SNAP_RATIO:
		s.snap_timer += delta
	else:
		s.snap_timer = maxf(s.snap_timer - delta * 2.0, 0.0)

	# Fish sweep (drives the bobber; the camera follows the bobber)
	_update_pan(s, delta)

	# Camera shake (the pan yaw is part of the base aim)
	if s.anchor != null:
		var base_yaw := s.base_yaw + s.look_offset
		if enable_fish_sweep:
			base_yaw += s.pan_cam
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

	# Stream live tension/surge telemetry to connected phone (~10 Hz)
	s.telemetry_timer -= delta
	if s.telemetry_timer <= 0.0:
		s.telemetry_timer = 0.1
		var t_ratio := clampf(s.tension / maxf(line_strength, 0.001), 0.0, 1.0)
		_notify_phone(s.player_id, {
			"type": "telemetry",
			"tension": snappedf(t_ratio, 0.01),
			"progress": snappedf(s.progress, 0.01),
			"surging": s.surging,
		})

	if s.bobber != null:
		var origin := _anchor_water_pos(s)
		var to_target := s.cast_target - origin
		var away := clampf((1.0 - s.progress) / maxf(1.0 - START_PROGRESS, 0.01), 0.0, 2.0)
		var wanted := origin + to_target.normalized() * maxf(to_target.length() * away, CATCH_STOP_DISTANCE)
		if enable_fish_sweep:
			# Sideways sweep, perpendicular to the line; smaller as the fish gets close.
			var side := to_target.normalized().cross(Vector3.UP)
			wanted += side * s.pan_pos * pan_bobber_meters * clampf(away, 0.3, 1.0)

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


# Smooth left-then-right (or right-then-left) sweep of the fish. The sweep is a sine wave,
# so it eases at each end and never jerks. It is wider and faster while the fish surges.
# The camera does not move on its own: it eases toward the bobber's sideways angle.
func _update_pan(s: FishingSession, delta: float) -> void:
	if not enable_fish_sweep:
		s.pan_pos = 0.0
		s.pan_cam = 0.0
		return

	var period := maxf(pan_period_surge if s.surging else pan_period_calm, 0.2)
	var amount := pan_amount_surge if s.surging else pan_amount_calm
	s.pan_amp = lerpf(s.pan_amp, amount, 1.0 - exp(-3.0 * delta))
	s.pan_phase = fposmod(s.pan_phase + delta * TAU / period, TAU)   # phase, not time: no jump when the period changes

	var target := sin(s.pan_phase) * s.pan_sign * s.pan_amp
	s.pan_pos = lerpf(s.pan_pos, target, 1.0 - exp(-pan_bobber_smooth * delta))

	# Camera follows where the bobber actually is (smoothly), not a separate motion.
	var cam_target := 0.0
	if s.bobber != null and is_instance_valid(s.bobber):
		var origin := _anchor_water_pos(s)
		var aim := s.cast_target - origin
		var now := s.bobber.global_position - origin
		if aim.length() > 0.01 and now.length() > 0.01:
			var aim_yaw := atan2(-aim.x, -aim.z)
			var bobber_yaw := atan2(-now.x, -now.z)
			cam_target = wrapf(bobber_yaw - aim_yaw, -PI, PI) * pan_camera_follow
	s.pan_cam = lerpf(s.pan_cam, cam_target, 1.0 - exp(-pan_camera_smooth * delta))


# Release strength 0..1 (reel spun counterclockwise). InputManager has no such function
# yet (request FM-REQ-21); until it does, the input action "tl_release" is used if it exists.
func _get_release(player_id: int) -> float:
	if _input != null and _input.has_method("get_release_strength"):
		return clampf(float(_input.get_release_strength(player_id)), 0.0, 1.0)
	if InputMap.has_action("tl_release"):
		return 1.0 if Input.is_action_pressed("tl_release") else 0.0
	_warn_once("release_input", "no release input: add InputManager.get_release_strength(player_id) or a 'tl_release' action - tension can never go down.")
	return 0.0


func _fish_won(s: FishingSession) -> void:
	var fish := s.fish.duplicate(true)
	var kept := true
	if store_catches_in_inventory and not _multiplayer:
		var spot_id := String(_context.get("spot_id", ""))
		if _quest != null and _quest.has_method("set_current_spot_id"):
			_quest.call("set_current_spot_id", spot_id)
		kept = _store_fish(fish)
		var rec_info := _record_caught_fish(String(fish["id"]), float(fish["size_cm"]), float(fish["weight"]))
		fish["is_new_species"] = bool(rec_info.get("is_new_species", false))
		fish["is_new_record"] = bool(rec_info.get("is_new_record", false))
		fish["trophy_tier"] = String(rec_info.get("trophy_tier", ""))
		_report_catch(String(fish["id"]), float(fish["size_cm"]), spot_id)

	if kept:
		s.catches.append(fish)
		s.total_weight += float(fish["weight"])

	_set_state(s, State.CAUGHT)
	if s.bobber != null:
		_spawn_water_splash(s.bobber.global_position, 1.4)
	_play_sfx("catch", -3.0, 1.0)
	on_fight_won(s)
	if kept:
		fish_caught.emit(s.player_id, fish)
	else:
		fish_released.emit(s.player_id, fish, "fish_box_full")
	_show_catch_popup(s.player_id, fish, kept)
	_try_play_spot_story_beat("first_catch")


func _record_caught_fish(fish_id: String, size_cm: float = 0.0, weight_kg: float = -1.0) -> Dictionary:
	if _save == null:
		_warn_once("record_caught_fish", "SaveManager not found - Bestiary will not unlock.")
		return {}
	if _save.has_method("record_fish_catch"):
		var info: Dictionary = _save.record_fish_catch(fish_id, size_cm, weight_kg)
		if bool(info.get("is_new_species", false)) and debug_log:
			print("[FishingManager] New Bestiary entry unlocked: '%s'" % fish_id)
		return info
	if _save.has_method("record_caught_fish"):
		var is_new := bool(_save.record_caught_fish(fish_id))
		return {"is_new_species": is_new, "is_new_record": false, "trophy_tier": ""}
	return {}


# --- Fish music ---
# Plays the track assigned to this fish in `fish_music` while it is on the line (bite -> caught/escaped).
# Fish with no entry play nothing. Uses its own AudioStreamPlayer on the "Music" bus if that bus exists.
func _play_fish_music(fish_id: String) -> void:
	var entry: FishMusicEntry = null
	for e in fish_music:
		if e != null and e.fish != null and e.fish.id == fish_id and e.music != null:
			entry = e
			break
	if entry == null and _db != null and _db.has_method("get_fish_music"):
		entry = _db.get_fish_music(fish_id)
	if entry == null or entry.music == null:
		if debug_log:
			print("[FishingManager] no fish music for '%s' (%d local rows + GameDB; each row needs BOTH a Fish and a Music assigned)" % [fish_id, fish_music.size()])
		return
	if _fish_music_player == null or not is_instance_valid(_fish_music_player):
		_fish_music_player = AudioStreamPlayer.new()
		_fish_music_player.name = "FishMusicPlayer"
		if AudioServer.get_bus_index("Music") != -1:
			_fish_music_player.bus = "Music"
		add_child(_fish_music_player)
	if _fish_music_tween != null and _fish_music_tween.is_valid():
		_fish_music_tween.kill()
	if entry.music is AudioStreamOggVorbis or entry.music is AudioStreamMP3:
		entry.music.loop = true
	elif entry.music is AudioStreamWAV:
		entry.music.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_fish_music_player.stream = entry.music
	_fish_music_player.volume_db = -60.0
	_fish_music_player.play()
	_fish_music_tween = create_tween()
	_fish_music_tween.tween_property(_fish_music_player, "volume_db", fish_music_volume_db + entry.volume_db, maxf(fish_music_fade_in, 0.01))
	_suppress_scene_music(true)
	if debug_log:
		var bus_idx := AudioServer.get_bus_index(_fish_music_player.bus)
		print("[FishingManager] fish music started for '%s' | stream=%s | playing=%s | bus=%s (muted=%s, %.1f dB) | target=%.1f dB" % [
				fish_id, entry.music.resource_path, str(_fish_music_player.playing), _fish_music_player.bus,
				str(AudioServer.is_bus_mute(bus_idx)), AudioServer.get_bus_volume_db(bus_idx),
				fish_music_volume_db + entry.volume_db])


func _stop_fish_music() -> void:
	if _fish_music_player == null or not is_instance_valid(_fish_music_player) or not _fish_music_player.playing:
		return
	if _fish_music_tween != null and _fish_music_tween.is_valid():
		_fish_music_tween.kill()
	var player := _fish_music_player
	_fish_music_tween = create_tween()
	_fish_music_tween.tween_property(player, "volume_db", -60.0, maxf(fish_music_fade_out, 0.01))
	_fish_music_tween.tween_callback(player.stop)
	_suppress_scene_music(false)


# Asks GameManager to silence (true) or bring back (false) the normal scene music.
# Needs GameManager.set_music_suppressed(suppressed: bool, fade_seconds: float).
func _suppress_scene_music(suppressed: bool) -> void:
	if _scene_music_suppressed == suppressed:
		return
	if _game_manager == null or not _game_manager.has_method("set_music_suppressed"):
		_warn_once("music_suppress", "GameManager.set_music_suppressed() not found - scene music keeps playing under the fish music.")
		return
	_scene_music_suppressed = suppressed
	_game_manager.set_music_suppressed(suppressed, fish_music_fade_in if suppressed else fish_music_fade_out)


# Tells QuestManager about a catch ("catch X times" quests).
func _report_catch(fish_id: String, size_cm: float, spot_id: String) -> void:
	if _quest == null or not _quest.has_method("report_catch"):
		_warn_once("report_catch", "QuestManager.report_catch() not found - catch quests will not progress.")
		return
	_quest.report_catch(fish_id, size_cm, spot_id)


func _store_fish(fish: Dictionary) -> bool:
	if _inventory == null or not _inventory.has_method("add_fish"):
		_warn_once("add_fish", "InventoryManager.add_fish() not found - catch is counted but NOT stored.")
		return true
	return bool(_inventory.add_fish(String(fish["id"]), float(fish["size_cm"])))


# Shows the catch: text popup always, plus the fish picture on 'FishLayout' in single-player
# or inside each catching player's half-screen popup in multiplayer.
func _show_catch_popup(player_id: int, fish: Dictionary, kept: bool) -> void:
	if not _multiplayer:
		_show_catch_picture(fish)

	var text := ""
	if _multiplayer:
		text += "%s caught\n" % get_player_name(player_id)
	var badge := ""
	if bool(fish.get("is_new_species", false)):
		badge = "NEW SPECIES! "
	elif bool(fish.get("is_new_record", false)):
		badge = "NEW RECORD! "
	var tier := String(fish.get("trophy_tier", ""))
	if tier != "":
		badge += "[%s] " % tier
	if badge != "":
		text += badge.strip_edges() + "\n"
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
	label.theme = UI_THEME
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)

	if _multiplayer:
		var prev_popup: Variant = _popups.get(player_id)
		if is_instance_valid(prev_popup) and prev_popup is Node:
			(prev_popup as Node).queue_free()
		_popups[player_id] = layer
		var index := maxi(_order.find(player_id), 0)
		var count := maxi(_order.size(), 1)
		var box := VBoxContainer.new()
		box.name = "CatchPopupBox"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 8)
		box.anchor_left = float(index) / count
		box.anchor_right = float(index + 1) / count
		box.anchor_top = 0.0
		box.anchor_bottom = 0.0
		box.offset_left = 24.0
		box.offset_right = -24.0
		box.offset_top = 112.0
		box.offset_bottom = 112.0
		box.grow_vertical = Control.GROW_DIRECTION_END
		layer.add_child(box)

		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 28)
		box.add_child(label)

		var img := _resolve_fish_image(fish)
		var tex: Texture2D = img["texture"]
		if tex != null:
			var pic := TextureRect.new()
			pic.name = "FishPicture"
			pic.texture = tex
			pic.custom_minimum_size = Vector2(210, 210)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pic)
	else:
		layer.add_child(label)
		if is_instance_valid(_popup):
			_popup.queue_free()
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 40)
		_popup = layer

	get_tree().create_timer(CATCH_POPUP_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(layer):
			if is_instance_valid(self) and _multiplayer and _popups.get(player_id) == layer:
				_popups.erase(player_id)
			layer.queue_free())


func _clear_popups() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	for p in _popups.values():
		if is_instance_valid(p) and p is Node:
			(p as Node).queue_free()
	_popups.clear()


func _resolve_fish_image(fish: Dictionary) -> Dictionary:
	var record: FishData = _db.get_fish(String(fish.get("id", ""))) if _db != null else null
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
	return {"texture": texture, "path": path}


func _show_catch_picture(fish: Dictionary) -> void:
	if not is_instance_valid(_fish_layout):
		_fish_layout = get_tree().root.find_child("FishLayout", true, false)
	if _fish_layout == null:
		_warn_once("fish_layout", "no node named 'FishLayout' in the scene - catch picture not shown.")
		return

	var img := _resolve_fish_image(fish)
	var path: String = img["path"]
	var texture: Texture2D = img["texture"]
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
	s.escape_reason = reason
	s.needs_knot = (reason == "line_snapped" and enable_knotting_minigame)
	s.knot_progress = 0.0
	_set_state(s, State.ESCAPED)
	if reason == "line_snapped":
		_play_sfx("snap", -2.0, 1.0)
	else:
		_play_sfx("splash", -6.0, 0.85)
	fish_escaped.emit(s.player_id, s.fish.duplicate(true), reason)
	on_escape(s, reason)
	_try_play_spot_story_beat("first_fail")


# --- Knotting minigame (triggered on tension line snap) ---
func _start_knotting(s: FishingSession) -> void:
	s.knot_progress = 0.0
	_set_state(s, State.KNOTTING)
	_show_knotting_prompt(s)
	knotting_started.emit(s.player_id)


func _show_knotting_prompt(s: FishingSession) -> void:
	s.msg_token += 1
	var has_phone := _has_phone_for_player(s.player_id)
	var pct := int(roundf(clampf(s.knot_progress, 0.0, 1.0) * 100.0))
	var text := MSG_KNOT_PHONE if has_phone else MSG_KNOT_KEYBOARD
	if pct > 0:
		text += "\n(%d%%)" % pct
	_show_message(s.player_id, text, 0.0)


func _has_phone_for_player(player_id: int) -> bool:
	if _connection != null and _connection.has_method("is_player_connected"):
		if _multiplayer:
			return bool(_connection.is_player_connected(player_id))
		return not _connection.get_connected_players().is_empty()
	if _input != null and _input.has_method("is_mobile_controller_connected"):
		return bool(_input.is_mobile_controller_connected())
	return false


func _on_knot_progress(player_id: int, progress: float) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s == null or s.state != State.KNOTTING:
		return
	s.knot_progress = clampf(progress, 0.0, 1.0)
	_show_knotting_prompt(s)


func _on_knot_completed(player_id: int, knot_name: String, accuracy: float) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s == null or s.state != State.KNOTTING:
		return
	s.needs_knot = false
	s.knot_progress = 1.0
	s.msg_token += 1
	_play_sfx("knot_tied", -3.0, 1.0)
	var msg := MSG_KNOT_TIED if knot_name.strip_edges() == "" else "%s tied!\nReady to cast" % knot_name
	_show_message(s.player_id, msg, 1.6)
	knotting_completed.emit(s.player_id, knot_name, clampf(accuracy, 0.0, 1.0))
	_set_state(s, State.IDLE)


# --- Input handlers ---
func _connect_input() -> void:
	_input.cast_triggered.connect(_on_cast)
	_input.interact_pressed.connect(_on_interact)
	_input.cancel_pressed.connect(_on_cancel)
	if _input.has_signal("menu_action"):
		_input.menu_action.connect(_on_menu_action)
	if _input.has_signal("knot_progress"):
		_input.knot_progress.connect(_on_knot_progress)
	if _input.has_signal("knot_completed"):
		_input.knot_completed.connect(_on_knot_completed)


func _on_menu_action(player_id: int, action: String) -> void:
	if action == "cycle_bait":
		cycle_bait(player_id)


func cycle_bait(player_id: int) -> String:
	var s := _sessions.get(player_id) as FishingSession
	if s == null or s.state != State.IDLE or _multiplayer or _db == null or not _db.is_loaded:
		return ""
	var available: Array[String] = []
	for bait in _db.get_all_bait():
		var bid := String(bait.id)
		if bid.contains("debug") or bid.begins_with("bait_d"):
			continue
		if bool(bait.unlimited) or (_inventory != null and _inventory.has_method("count_of") and int(_inventory.call("count_of", bid)) > 0):
			available.append(bid)
	if available.is_empty():
		return ""
	var idx := available.find(s.bait_id)
	var next_id := available[(idx + 1) % available.size()]
	if set_bait(player_id, next_id):
		if _save != null and _save.has_method("set_equipped_bait"):
			_save.call("set_equipped_bait", next_id)
		var bname := String(_db.get_bait(next_id).display_name)
		_show_message(player_id, "Bait: %s" % bname, 1.5)
		return next_id
	return ""


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
		if s.bait_id == "" and _db != null and _db.has_bait("bait_1"):
			s.bait_id = "bait_1"
			bait_changed.emit(player_id, s.bait_id)
		if s.bait_id == "":
			_reject_cast(player_id, "no_bait", "no bait_id set")
			return
		if not _spend_bait(s):
			if s.bait_id != "bait_1" and _db != null and _db.has_bait("bait_1"):
				var fallback_bait: BaitData = _db.get_bait("bait_1")
				if fallback_bait != null and fallback_bait.unlimited:
					s.bait_id = "bait_1"
					if _save != null and not _multiplayer and _save.has_method("set_equipped_bait"):
						_save.call("set_equipped_bait", "bait_1")
					bait_changed.emit(player_id, "bait_1")
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
	_play_sfx("cast", -4.0, lerpf(0.88, 1.18, power))
	cast_started.emit(player_id, power, s.cast_target)


func _on_interact(player_id: int) -> void:
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		return
	if s.state == State.WAITING:
		s.pending_fish = {}
		_remove_bobber(s)
		_set_state(s, State.IDLE)
	elif s.state == State.KNOTTING and not _has_phone_for_player(player_id):
		# Keyboard-only fallback so PC testing without a mobile controller never soft-locks.
		_on_knot_completed(player_id, "Quick Knot", 1.0)


func _on_cancel(player_id: int) -> void:
	if _multiplayer:
		return
	var s := _sessions.get(player_id) as FishingSession
	if s == null:
		return
	
	# If the bobber is out or waiting for a fish, cancel/recall it back to IDLE
	if s.state == State.WAITING or s.state == State.CASTING:
		s.pending_fish = {}
		_remove_bobber(s)
		_set_state(s, State.IDLE)
		if debug_log:
			print("[FishingManager] player %d canceled cast/wait -> returned to IDLE" % player_id)
	# Do nothing if already IDLE, preventing accidental scene exits


# --- Helpers ---
func _fill_debug_defaults() -> void:
	if force_debug_equipment:
		if debug_rod_id != "":
			_context["rod_id"] = debug_rod_id
		if debug_bait_id != "":
			_context["bait_id"] = debug_bait_id
	else:
		# In single-player, pull the player's equipped rod and bait from SaveManager
		# (set via the Equipment Inventory UI) before falling back to debug exports.
		if not _multiplayer and _save != null:
			if String(_context.get("rod_id", "")) == "" and _save.has_method("get_equipped_rod"):
				var eq_rod := String(_save.get_equipped_rod())
				if eq_rod != "":
					_context["rod_id"] = eq_rod
			if String(_context.get("bait_id", "")) == "" and _save.has_method("get_equipped_bait"):
				var eq_bait := String(_save.get_equipped_bait())
				if eq_bait != "":
					_context["bait_id"] = eq_bait

	var fallbacks := {"spot_id": debug_spot_id, "rod_id": debug_rod_id, "bait_id": debug_bait_id}
	for key in fallbacks:
		if String(_context.get(key, "")) == "" and String(fallbacks[key]) != "":
			_context[key] = fallbacks[key]


func _on_save_equipment_changed() -> void:
	if force_debug_equipment or _multiplayer or _save == null:
		return
	var new_rod := String(_save.get_equipped_rod()) if _save.has_method("get_equipped_rod") else ""
	var new_bait := String(_save.get_equipped_bait()) if _save.has_method("get_equipped_bait") else ""
	if new_rod != "":
		_context["rod_id"] = new_rod
		for pid in _order:
			set_rod(pid, new_rod)
	if new_bait != "":
		_context["bait_id"] = new_bait
		for pid in _order:
			set_bait(pid, new_bait)


func _pick_player_ids() -> Array[int]:
	var ids: Array[int] = []
	if _multiplayer:
		var ctx_ids: Variant = _context.get("player_ids", [])
		if ctx_ids is Array and not ctx_ids.is_empty():
			for raw_id in ctx_ids:
				var pid := int(raw_id)
				if not ids.has(pid):
					ids.append(pid)
					if ids.size() >= max_players:
						break
			if not ids.is_empty():
				return ids
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


func _any_session_in_states(states: Array[int]) -> bool:
	for other in _sessions.values():
		var os := other as FishingSession
		if os != null and states.has(os.state):
			return true
	return false


func _set_state(s: FishingSession, new_state: int) -> void:
	var old := s.state
	s.state = new_state
	s.state_time = 0.0

	if new_state == State.REELING and _multiplayer and _popups.has(s.player_id):
		var prev_popup: Variant = _popups[s.player_id]
		if is_instance_valid(prev_popup) and prev_popup is Node:
			(prev_popup as Node).queue_free()
		_popups.erase(s.player_id)

	if new_state == State.REELING or new_state == State.KNOTTING:
		if node_to_hide_on_bite != null:
			node_to_hide_on_bite.visible = false

	if old == State.REELING:
		if not _any_session_in_states([State.REELING, State.KNOTTING]):
			_stop_fish_music()
		if s.anchor != null:
			s.anchor.rotation.x = 0.0
			s.anchor.rotation.y = s.base_yaw + s.look_offset
		# Fix: the tension bar used to stay on screen after a catch or escape.
		_update_tension_ui(s)
		if node_to_hide_on_bite != null and not _any_session_in_states([State.REELING, State.KNOTTING]):
			node_to_hide_on_bite.visible = true
	elif old == State.KNOTTING:
		if not _any_session_in_states([State.REELING, State.KNOTTING]):
			_stop_fish_music()
		if node_to_hide_on_bite != null and not _any_session_in_states([State.REELING, State.KNOTTING]):
			node_to_hide_on_bite.visible = true

	if new_state == State.IDLE and not _multiplayer and not force_debug_equipment:
		var wanted_rod := String(_context.get("rod_id", ""))
		if wanted_rod != "" and s.rod_id != wanted_rod:
			set_rod(s.player_id, wanted_rod)
		var wanted_bait := String(_context.get("bait_id", ""))
		if wanted_bait != "" and s.bait_id != wanted_bait:
			set_bait(s.player_id, wanted_bait)

	if debug_log:
		print("[FishingManager] player %d: %s -> %s" % [s.player_id, State.keys()[old], State.keys()[new_state]])
	var screen := _phone_screen_for(new_state)
	if screen != _phone_screen_for(old):
		_send_game_state(s.player_id, screen)
	state_changed.emit(s.player_id, new_state, old)


func _phone_screen_for(state: int) -> String:
	match state:
		State.REELING:
			return "reeling"
		State.KNOTTING:
			return "knotting"
		_:
			return "casting"


func _on_phone_connected(phone_id: int) -> void:
	if _finished:
		return
	for pid in _order:
		if _multiplayer and pid != phone_id:
			continue
		var s: FishingSession = _sessions[pid]
		_send_game_state(pid, _phone_screen_for(s.state))
		if s.state == State.KNOTTING:
			_show_knotting_prompt(s)


func _anchor_water_pos(s: FishingSession) -> Vector3:
	var p := s.anchor.global_position if s.anchor != null else global_position
	return Vector3(p.x, water_level, p.z)


func _spend_bait(s: FishingSession) -> bool:
	if _multiplayer:
		return true
	if _db != null and s.bait_id != "" and _db.has_bait(s.bait_id):
		var bait_rec: BaitData = _db.get_bait(s.bait_id)
		if bait_rec != null and bait_rec.unlimited:
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
	_cache_rod_tip_offset(s)


func _cache_rod_tip_offset(s: FishingSession) -> void:
	s.has_cached_tip_offset = false
	s.cached_tip_local_offset = rod_tip_fallback_offset
	if s.holder == null or not is_instance_valid(s.holder):
		return
	if s.line_tip != null and is_instance_valid(s.line_tip):
		return
	var best_pos := Vector3.ZERO
	var found_mesh := false
	for child in s.holder.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		for cx in [aabb.position.x, aabb.end.x]:
			for cy in [aabb.position.y, aabb.end.y]:
				for cz in [aabb.position.z, aabb.end.z]:
					var wp := mi.to_global(Vector3(cx, cy, cz))
					if not found_mesh or wp.y > best_pos.y:
						best_pos = wp
						found_mesh = true
	if found_mesh and best_pos.y > water_level + 0.25:
		s.cached_tip_local_offset = s.holder.to_local(best_pos)
	s.has_cached_tip_offset = true


func _remove_rod_model(s: FishingSession) -> void:
	if s.rod_model != null and is_instance_valid(s.rod_model):
		s.rod_model.queue_free()
	s.rod_model = null
	s.line_tip = null
	s.has_cached_tip_offset = false


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
	_remove_fishing_line(s)


# --- 3D Fishing Line, Rod Flex, Water Splashes & SFX ---

static func compute_line_sag(state: int, tension_ratio: float) -> float:
	match state:
		State.CASTING:
			return 0.25
		State.WAITING:
			return 0.55
		State.REELING:
			return lerpf(0.35, 0.02, clampf(tension_ratio, 0.0, 1.0))
		_:
			return 0.15


static func compute_line_color(tension_ratio: float) -> Color:
	var t := clampf(tension_ratio, 0.0, 1.0)
	if t >= 0.85:
		return Color(1.0, 0.28, 0.22, 0.95)
	if t >= 0.6:
		return Color(1.0, 0.85, 0.35, 0.92)
	return Color(0.92, 0.96, 1.0, 0.85)


static func compute_rod_flex_angles(tension_ratio: float, pan_pos: float, surging: bool,
		max_pitch_deg: float = 22.0, max_yaw_deg: float = 10.0) -> Vector2:
	var t := clampf(tension_ratio, 0.0, 1.2)
	var surge_boost := 1.15 if surging else 1.0
	var pitch_rad := deg_to_rad(max_pitch_deg * minf(t * surge_boost, 1.25))
	var yaw_rad := deg_to_rad(max_yaw_deg * clampf(pan_pos, -1.0, 1.0) * minf(t + 0.25, 1.0))
	return Vector2(pitch_rad, yaw_rad)


func _get_line_tip_position(s: FishingSession) -> Vector3:
	if s.line_tip != null and is_instance_valid(s.line_tip):
		return s.line_tip.global_position
	if s.holder != null and is_instance_valid(s.holder):
		if not s.has_cached_tip_offset:
			_cache_rod_tip_offset(s)
		var tip_pos := s.holder.to_global(s.cached_tip_local_offset)
		tip_pos.y = maxf(tip_pos.y, water_level + 0.5)
		return tip_pos
	if s.anchor != null and is_instance_valid(s.anchor):
		return s.anchor.global_position + Vector3(0.4, 1.1, 0.0)
	return global_position + Vector3.UP


func _ensure_fishing_line(s: FishingSession) -> void:
	if s.line_mesh_node != null and is_instance_valid(s.line_mesh_node):
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = false
	mat.render_priority = 12
	mat.albedo_color = Color(0.92, 0.96, 1.0, 0.9)

	var mi := MeshInstance3D.new()
	mi.name = "FishingLine_P%d" % s.player_id
	mi.top_level = true
	mi.mesh = im
	mi.material_override = mat
	mi.sorting_offset = 100.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	s.line_mesh_node = mi
	s.line_im = im
	s.line_mat = mat


func _remove_fishing_line(s: FishingSession) -> void:
	if s.line_mesh_node != null and is_instance_valid(s.line_mesh_node):
		s.line_mesh_node.queue_free()
	s.line_mesh_node = null
	s.line_im = null
	s.line_mat = null


func _update_fishing_line(s: FishingSession) -> void:
	if not enable_fishing_line or s.bobber == null or not is_instance_valid(s.bobber):
		if s.line_mesh_node != null:
			_remove_fishing_line(s)
		return
	_ensure_fishing_line(s)
	var start_pos := _get_line_tip_position(s)
	start_pos.y = maxf(start_pos.y, water_level + 0.35)
	var end_pos := s.bobber.global_position
	end_pos.y = maxf(end_pos.y, water_level + 0.04)
	var line_strength := maxf(float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH)), 0.001)
	var tension_ratio := s.tension / line_strength if s.state == State.REELING else 0.0
	var sag := compute_line_sag(s.state, tension_ratio)
	var segs := maxi(line_segments, 2)

	if s.line_mat != null:
		s.line_mat.albedo_color = compute_line_color(tension_ratio)

	s.line_im.clear_surfaces()
	s.line_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var p := start_pos.lerp(end_pos, u)
		# Parabolic sag peaking at u = 0.5, clamped above the water plane so it never clips under water.
		p.y -= sag * 4.0 * u * (1.0 - u)
		p.y = maxf(p.y, water_level + 0.04)
		s.line_im.surface_add_vertex(p)
	s.line_im.surface_end()


func _update_rod_flex(s: FishingSession, delta: float) -> void:
	if not enable_rod_flex or s.holder == null or not is_instance_valid(s.holder):
		return
	var target_rot := s.holder_base_rotation
	if s.state == State.REELING:
		var line_strength := maxf(float(s.rod.get("line_strength", TEMP_ROD_LINE_STRENGTH)), 0.001)
		var tension_ratio := s.tension / line_strength
		var flex := compute_rod_flex_angles(
			tension_ratio, s.pan_pos, s.surging,
			rod_flex_max_pitch_deg, rod_flex_max_yaw_deg)
		target_rot.x += flex.x
		target_rot.y += flex.y
	elif s.state == State.CASTING:
		target_rot.x -= deg_to_rad(14.0) * sin(clampf(s.cast_time / maxf(s.cast_duration, 0.01), 0.0, 1.0) * PI)
	s.holder.rotation = s.holder.rotation.lerp(target_rot, 1.0 - exp(-10.0 * delta))


func _spawn_water_splash(pos: Vector3, intensity: float = 1.0) -> void:
	if not enable_water_splashes or not is_inside_tree():
		return
	_splash_count += 1
	var p := CPUParticles3D.new()
	p.name = "WaterSplash_%d" % _splash_count
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = clampi(int(18 * intensity), 8, 40)
	p.lifetime = 0.55
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 48.0
	p.initial_velocity_min = 1.8 * intensity
	p.initial_velocity_max = 4.2 * intensity
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.11 * intensity

	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 11
	mat.albedo_color = Color(0.82, 0.95, 1.0, 0.85)
	drop.material = mat
	p.mesh = drop
	p.sorting_offset = 50.0

	add_child(p)
	p.global_position = Vector3(pos.x, water_level + 0.05, pos.z)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.25).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


func _play_sfx(clip_name: String, volume_db: float = -4.0, pitch_scale: float = 1.0) -> void:
	if not enable_sfx or _sfx == null:
		return
	_sfx.play(clip_name, volume_db, pitch_scale)


func get_splash_spawn_count() -> int:
	return _splash_count


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("FishingManager: " + message)
