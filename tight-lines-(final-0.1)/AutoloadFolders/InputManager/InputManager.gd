extends Node

# ============================================================================
# INPUT MANAGER (autoload) — res://scripts/autoload/input_manager.gd
# ============================================================================
# Listens to ConnectionManager's raw phone signals and translates them into
# ONE unified set of gameplay signals. Keyboard/mouse feeds the same signals,
# so game code never needs to know where an input came from.
#
# PHONE MAPPING
#   Swing -> cast_pressed(power)
#   Swipe -> reel(strength)          (any direction; strength from swipe length)
#   Tap   -> interact_pressed()      (alternate key for Interact)
#
# KEYBOARD / MOUSE MAPPING
#   Hold + release Space -> cast_pressed(power)
#   Hold R / Left Mouse  -> reel(1.0) every frame
#   E                    -> interact_pressed()
#
# AUTOLOAD ORDER: ConnectionManager must be listed ABOVE InputManager.
# ============================================================================

signal cast_pressed(power: float)     # power 0.0 - 1.0
signal reel(strength: float)          # strength 0.0 - 1.0
signal interact_pressed()             # talk / enter fishing spot / confirm prompt, etc.

# HUD / debugging helpers
signal cast_charge_changed(value: float)   # keyboard cast charging, for CastPowerMeter
signal input_source_changed(source: InputSource)

enum InputSource { KEYBOARD_MOUSE, CONTROLLER }

# Which gameplay actions are currently allowed. Interact works in EVERY
# context (including NONE / Overworld). Cast only fires in CAST, and reel only
# in REELING, so stray swings/swipes at the wrong moment are ignored.
# FishingController calls InputManager.set_context(...) as its state changes;
# the Overworld should leave it at NONE.
enum Context { NONE, CAST, WAITING, REELING }

# ----------------------------------------------------------------------------
# TUNING
# ----------------------------------------------------------------------------
# Swing magnitude (rad/s) maps [swing_min, swing_max] -> [min_cast_power, 1.0].
# swing_min should match SWING_THRESHOLD in MainActivity.java.
@export var swing_min := 4.0
@export var swing_max := 12.0
@export var min_cast_power := 0.2

# Seconds Space must be held for a full-power keyboard cast.
@export var cast_charge_time := 1.2

# Swipe length (pixels, from dx/dy) that counts as a full-strength reel.
@export var swipe_reel_full_length := 800.0
@export var min_reel_strength := 0.3

# If true, keyboard/mouse keeps working while a phone is connected.
@export var keyboard_fallback_with_controller := true

@export var debug_log := false

# ----------------------------------------------------------------------------
# STATE
# ----------------------------------------------------------------------------
var context: Context = Context.NONE
var active_source: InputSource = InputSource.KEYBOARD_MOUSE

# Only ONE phone drives the game (ConnectionManager supports many).
# -1 = no controller connected.
var controller_player_id := -1
var _connected_players: Array[int] = []

var _charging := false
var _charge := 0.0

const ACTION_CAST := "fish_cast"
const ACTION_REEL := "fish_reel"
const ACTION_INTERACT := "interact"


func _ready() -> void:
	_ensure_default_actions()

	var cm := get_node_or_null("/root/ConnectionManager")
	if cm == null:
		push_warning("InputManager: ConnectionManager autoload not found — keyboard/mouse only.")
		return

	cm.player_connected.connect(_on_player_connected)
	cm.player_disconnected.connect(_on_player_disconnected)
	cm.swing_input.connect(_on_swing)
	cm.swipe_input.connect(_on_swipe)
	cm.tap_input.connect(_on_tap)

	# Pick up phones that connected before this node was ready.
	for id in cm.get_connected_players():
		_on_player_connected(id)


# ----------------------------------------------------------------------------
# PUBLIC API
# ----------------------------------------------------------------------------
func set_context(new_context: Context) -> void:
	if context == new_context:
		return
	context = new_context
	_cancel_charge()
	_log("context -> %s" % Context.keys()[new_context])


func is_controller_connected() -> bool:
	return controller_player_id != -1


# ----------------------------------------------------------------------------
# PHONE INPUT  (from ConnectionManager)
# ----------------------------------------------------------------------------
# Swing -> Cast. Force of the swing becomes cast power.
func _on_swing(player_id: int, magnitude: float) -> void:
	if player_id != controller_player_id or context != Context.CAST:
		return
	_set_source(InputSource.CONTROLLER)
	var t := clampf(inverse_lerp(swing_min, swing_max, magnitude), 0.0, 1.0)
	var power := lerpf(min_cast_power, 1.0, t)
	_log("swing %.2f -> cast power %.2f" % [magnitude, power])
	cast_pressed.emit(power)


# Swipe -> Reel. Any direction counts; longer swipe = stronger reel.
func _on_swipe(player_id: int, _direction: String, dx: float, dy: float) -> void:
	if player_id != controller_player_id or context != Context.REELING:
		return
	_set_source(InputSource.CONTROLLER)
	var length := Vector2(dx, dy).length()
	var strength := clampf(length / swipe_reel_full_length, min_reel_strength, 1.0)
	_log("swipe %.0fpx -> reel %.2f" % [length, strength])
	reel.emit(strength)


# Tap -> Interact. Works in every context (Overworld included).
func _on_tap(player_id: int, _x: float, _y: float) -> void:
	if player_id != controller_player_id:
		return
	_set_source(InputSource.CONTROLLER)
	_log("tap -> interact")
	interact_pressed.emit()


func _on_player_connected(player_id: int) -> void:
	if not _connected_players.has(player_id):
		_connected_players.append(player_id)
	if controller_player_id == -1:
		controller_player_id = player_id
		_set_source(InputSource.CONTROLLER)
		_log("controller attached: player %d" % player_id)


func _on_player_disconnected(player_id: int) -> void:
	_connected_players.erase(player_id)
	if player_id != controller_player_id:
		return
	if _connected_players.is_empty():
		controller_player_id = -1
		_set_source(InputSource.KEYBOARD_MOUSE)
		_log("controller detached, using keyboard/mouse")
	else:
		controller_player_id = _connected_players[0]
		_log("controller switched to player %d" % controller_player_id)


# ----------------------------------------------------------------------------
# KEYBOARD / MOUSE
# ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _keyboard_enabled():
		_cancel_charge()
		return

	if _charging:
		_charge = minf(_charge + delta / cast_charge_time, 1.0)
		cast_charge_changed.emit(_charge)

	if context == Context.REELING and Input.is_action_pressed(ACTION_REEL):
		_set_source(InputSource.KEYBOARD_MOUSE)
		reel.emit(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _keyboard_enabled():
		return

	if event.is_action_pressed(ACTION_INTERACT):
		_set_source(InputSource.KEYBOARD_MOUSE)
		interact_pressed.emit()

	if context != Context.CAST:
		return

	if event.is_action_pressed(ACTION_CAST):
		_set_source(InputSource.KEYBOARD_MOUSE)
		_charging = true
		_charge = 0.0
		cast_charge_changed.emit(0.0)
	elif event.is_action_released(ACTION_CAST) and _charging:
		var power := maxf(_charge, min_cast_power)
		_cancel_charge()
		cast_pressed.emit(power)


func _keyboard_enabled() -> bool:
	return not is_controller_connected() or keyboard_fallback_with_controller


func _cancel_charge() -> void:
	if _charging or _charge > 0.0:
		_charging = false
		_charge = 0.0
		cast_charge_changed.emit(0.0)


# ----------------------------------------------------------------------------
# HELPERS
# ----------------------------------------------------------------------------
func _set_source(source: InputSource) -> void:
	if active_source != source:
		active_source = source
		input_source_changed.emit(source)


# Registers default key bindings in code; rebind freely in Project Settings.
func _ensure_default_actions() -> void:
	_add_key_action(ACTION_CAST, KEY_SPACE)
	_add_key_action(ACTION_INTERACT, KEY_E)
	if not InputMap.has_action(ACTION_REEL):
		_add_key_action(ACTION_REEL, KEY_R)
		var lmb := InputEventMouseButton.new()
		lmb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(ACTION_REEL, lmb)


func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _log(msg: String) -> void:
	if debug_log:
		print("[InputManager] ", msg)
