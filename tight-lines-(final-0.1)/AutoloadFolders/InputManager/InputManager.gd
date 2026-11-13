extends Node

# ============================================================================
# INPUT MANAGER (GODOT / PC SIDE)  — TightLines
# ============================================================================
# Turns raw input (keyboard + phone gestures relayed by ConnectionManager)
# into ONE unified API that the rest of the game uses. Gameplay code never
# needs to know where an input came from.
#
# SETUP
#   Project Settings > Autoload, in this order:
#       ConnectionManager  (res://.../ConnectionManager.gd)
#       InputManager       (res://.../InputManager.gd)
#
# HOW GAME CODE USES IT
#   GameManager sets the context on every scene change:
#       InputManager.set_context(InputManager.InputContext.FISHING)
#       InputManager.set_multiplayer_mode(true)   # split-screen 3D session
#
#   Then gameplay either connects to signals...
#       InputManager.cast_triggered.connect(_on_cast)    # (player_id, power)
#   ...or polls every frame:
#       var look := InputManager.get_look(player_id)     # -1..+1, rotate view
#
# CONTEXTS
#   NONE      — all input ignored (loading screens, transitions)
#   MENU      — menus + cutscenes. Keyboard uses Godot's built-in ui_* actions
#               natively. Phone gestures are INJECTED as ui_* actions, so
#               Control focus navigation works with zero extra code.
#   OVERWORLD — 2D world: move, interact, cancel, pause
#   FISHING   — 3D minigame: cast, reel, interact, look (view rotation)
#
# MULTIPLAYER RULES
#   Single player : keyboard is Player 1. ANY connected phone also acts as
#                   Player 1 (its player_id is remapped to 1).
#   Multiplayer   : phones keep the player_id ConnectionManager gave them.
#                   In the FISHING context the KEYBOARD IS DISABLED.
#                   In other contexts the keyboard still works (Player 1).
#   DEBUG         : with debug_keyboard_p2 = true (debug builds only), the
#                   keyboard also works in multiplayer FISHING:
#                   Player 1 = the normal keys, Player 2 = the IJKL scheme.
#
# PHONE GESTURE MAP
#   FISHING   swing         = cast (swing speed -> power)
#             swipe (any)   = reel
#             tap           = interact (general button; e.g. set the hook)
#             tilt L/R      = rotate player's view (get_look())
#   OVERWORLD swipe = short move pulse | tap = interact | swing = cancel
#   MENU      swipe = navigate | tap = accept | swing = cancel
#
# KEYBOARD (FISHING)
#                          Player 1            Player 2 (debug only)
#   Cast (hold, release)   Space / Enter       U
#   Reel                   R / Down            K
#   Interact               E                   I
#   Look left / right      A,D / Left,Right    J, L
# ============================================================================

# --- Connection state -------------------------------------------------------
signal controller_connected(player_id)
signal controller_disconnected(player_id)

# --- Meta -------------------------------------------------------------------
signal context_changed(new_context)
signal multiplayer_changed(enabled)
# Useful for swapping on-screen prompts ("Press E" vs "Tap").
signal device_changed(player_id, device)

# --- Fishing ----------------------------------------------------------------
# power is 0.0–1.0. Phone: from swing magnitude. Keyboard: from hold time.
signal cast_triggered(player_id, power)
signal reel(player_id, strength)
signal reel_crank(player_id, delta_degrees)   # signed: + clockwise (reel in), - counter-clockwise

# --- General ----------------------------------------------------------------
signal interact_pressed(player_id)
signal cancel_pressed(player_id)
signal pause_pressed(player_id)

# NOTE: view rotation (tilt / A-D keys) is continuous, so it is POLLING ONLY:
#       call get_look(player_id) each frame.

enum InputContext { NONE, MENU, OVERWORLD, FISHING }

const DEVICE_KEYBOARD := &"keyboard"
const DEVICE_PHONE := &"phone"

# Player ID used for the keyboard (and for phones in single-player).
const KEYBOARD_PLAYER_ID := 1

# DEBUG second keyboard player (IJKL scheme). See debug_keyboard_p2 below.
const DEBUG_PLAYER2_ID := 2

const CONNECTION_MANAGER_PATH := "/root/ConnectionManager"

# --- Tuning -----------------------------------------------------------------
# Phone swing magnitudes (rad/s) mapped onto 0..1 cast power. The phone app
# only reports swings above 4.0, so that is the floor.
const SWING_MIN_MAGNITUDE := 8.0
const SWING_MAX_MAGNITUDE := 18.0
const MIN_CAST_POWER := 0.15

# Holding the cast key this long (seconds) gives full power.
const KEYBOARD_CAST_CHARGE_TIME := 1.0

# The phone has no joystick/hold gestures, so these are approximated by short
# "pulses" that expire on their own.
const PHONE_MOVE_PULSE_SEC := 0.35
const PHONE_REEL_PULSE_SEC := 0.30
# Phone "crank" (circular reel gesture)
const CRANK_MIN_STEP := 50.0      # degrees per message below this = noise, ignored for reel pulse
const CRANK_MAX_STEP := 180.0     # degrees per message above this = glitch, rejected
const CRANK_ACTIVE_SEC := 0.3    # how long reeling stays "on" after the last clockwise step

# Tilt: values inside the deadzone count as 0 so a phone held roughly level
# doesn't drift the view. The phone sends -1..+1 where +/-1 = 40 degrees, so
# 0.12 is roughly a 5 degree deadzone. Raise it if the view creeps.
const TILT_DEADZONE := 0.12
# The phone streams tilt ~20x/sec. If nothing arrives for this long, tilt is
# treated as 0 (protects against a stuck view if the connection stalls).
const TILT_TIMEOUT_SEC := 0.5

@export var debug_log := false

# DEBUG: lets the keyboard play in multiplayer FISHING. Keyboard = Player 1
# (normal keys) AND a second keyboard scheme (IJKL) = Player 2. Only has an
# effect in debug builds, and only while multiplayer_mode is true.
@export var debug_keyboard_p2 := true

# --- Keyboard bindings ------------------------------------------------------
# Registered into Godot's InputMap at startup. If an action with the same
# name ALREADY exists in your Project Settings > Input Map, it is left alone
# (so your own mapping wins). Prefix "tl_" avoids clashing with other actions.
# Menus use Godot's built-in ui_* actions, so they are not listed here.
const KEY_BINDINGS := {
	&"tl_move_left": [KEY_A, KEY_LEFT],
	&"tl_move_right": [KEY_D, KEY_RIGHT],
	&"tl_move_up": [KEY_W, KEY_UP],
	&"tl_move_down": [KEY_S, KEY_DOWN],
	&"tl_interact": [KEY_E],
	&"tl_cancel": [KEY_BACKSPACE, KEY_X],
	&"tl_pause": [KEY_ESCAPE],
	&"tl_cast": [KEY_SPACE, KEY_ENTER],
	&"tl_reel": [KEY_R, KEY_DOWN],
	&"tl_look_left": [KEY_A, KEY_LEFT],
	&"tl_look_right": [KEY_D, KEY_RIGHT],
	# Debug Player 2 (IJKL scheme)
	&"tl_p2_look_left": [KEY_J],
	&"tl_p2_look_right": [KEY_L],
	&"tl_p2_cast": [KEY_U],
	&"tl_p2_reel": [KEY_K],
	&"tl_p2_interact": [KEY_I],
}

const MENU_SWIPE_ACTIONS := {
	"up": &"ui_up",
	"down": &"ui_down",
	"left": &"ui_left",
	"right": &"ui_right",
}

const SWIPE_VECTORS := {
	"up": Vector2.UP,
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------
var context: InputContext = InputContext.MENU:
	set(value):
		if value == context:
			return
		context = value
		_cast_charge_start = -1.0
		_p2_cast_charge_start = -1.0
		context_changed.emit(context)
		if debug_log:
			print("[InputManager] context -> %s" % InputContext.keys()[context])

var multiplayer_mode := false

var _connection_manager: Node = null
var _phones: Array[int] = [] # player_ids of currently connected phones
var _state: Dictionary = {} # { player_id: Dictionary of pulse/tilt state }
var _last_device: Dictionary = {} # { player_id: StringName }
var _cast_charge_start := -1.0 # keyboard cast charge start time, -1 = idle
var _p2_cast_charge_start := -1.0 # debug player 2 cast charge start, -1 = idle
var _warned_remap := false

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
func _ready() -> void:
	_register_keyboard_actions()
	# Deferred so ConnectionManager exists regardless of autoload order.
	_connect_connection_manager.call_deferred()

func _register_keyboard_actions() -> void:
	for action in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue # the user's own mapping takes priority
		InputMap.add_action(action)
		for keycode in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

func _connect_connection_manager() -> void:
	_connection_manager = get_node_or_null(CONNECTION_MANAGER_PATH)
	if _connection_manager == null:
		push_warning("InputManager: no ConnectionManager autoload found at %s — phone input disabled, keyboard only." % CONNECTION_MANAGER_PATH)
		return

	_connection_manager.connect("player_connected", _on_phone_connected)
	_connection_manager.connect("player_disconnected", _on_phone_disconnected)
	_connection_manager.connect("swipe_input", _on_phone_swipe)
	_connection_manager.connect("tap_input", _on_phone_tap)
	_connection_manager.connect("swing_input", _on_phone_swing)
	
	if _connection_manager.has_signal("reel_input"):
		_connection_manager.connect("reel_input", _on_phone_reel)
	if _connection_manager.has_signal("tilt_input"):
		_connection_manager.connect("tilt_input", _on_phone_tilt)
	else:
		push_warning("InputManager: ConnectionManager has no 'tilt_input' signal — update it to the version with tilt support.")

	# Pick up phones that connected before we finished starting.
	for pid in _connection_manager.get_connected_players():
		if not _phones.has(pid):
			_phones.append(pid)

# ----------------------------------------------------------------------------
# Public API — configuration
# ----------------------------------------------------------------------------
func set_context(new_context: InputContext) -> void:
	context = new_context

func set_multiplayer_mode(enabled: bool) -> void:
	if multiplayer_mode == enabled:
		return
	multiplayer_mode = enabled
	_cast_charge_start = -1.0
	_p2_cast_charge_start = -1.0
	_warned_remap = false
	# Pulse/tilt state is keyed by player_id, and the id mapping just changed
	# (all phones = Player 1 vs. their own ids), so old state must not carry over.
	_state.clear()
	multiplayer_changed.emit(enabled)
	print("[InputManager] multiplayer_mode -> %s" % str(enabled))

# True only for the debug second keyboard player: debug build, flag on,
# multiplayer FISHING.
func _debug_p2_active() -> bool:
	return debug_keyboard_p2 and OS.is_debug_build() \
		and context == InputContext.FISHING and multiplayer_mode

func is_keyboard_enabled() -> bool:
	if context == InputContext.NONE:
		return false
	# 3D fishing in multiplayer is phones-only (unless the debug flag is on).
	if context == InputContext.FISHING and multiplayer_mode and not _debug_p2_active():
		return false
	return true

# ----------------------------------------------------------------------------
# Public API — queries
# ----------------------------------------------------------------------------
func is_mobile_controller_connected() -> bool:
	return not _phones.is_empty()

func get_connected_phone_ids() -> Array[int]:
	return _phones.duplicate()

func get_last_device(player_id: int = KEYBOARD_PLAYER_ID) -> StringName:
	return _last_device.get(player_id, DEVICE_KEYBOARD)

# Overworld movement. Keyboard: WASD/arrows. Phone: swipe pulse.
func get_move_vector(player_id: int = KEYBOARD_PLAYER_ID) -> Vector2:
	if context == InputContext.NONE:
		return Vector2.ZERO
	var v := Vector2.ZERO
	if player_id == KEYBOARD_PLAYER_ID and is_keyboard_enabled():
		v = Input.get_vector(&"tl_move_left", &"tl_move_right", &"tl_move_up", &"tl_move_down")
	var st := _get_state(player_id)
	if _now() < st["move_until"]:
		v += st["move"]
	return v.limit_length(1.0)

# View rotation in the 3D fishing scene: -1.0 (turn left) .. +1.0 (turn right).
# Phone: tilt the phone left/right (proportional — tilt further, turn faster).
# Keyboard: A/D or Left/Right (full speed); debug Player 2: J/L.
# Multiply by your turn speed and delta, e.g.
#   camera_yaw -= InputManager.get_look(id) * TURN_SPEED * delta
func get_look(player_id: int = KEYBOARD_PLAYER_ID) -> float:
	if context != InputContext.FISHING:
		return 0.0
	var v := 0.0
	if player_id == KEYBOARD_PLAYER_ID and is_keyboard_enabled():
		v = Input.get_axis(&"tl_look_left", &"tl_look_right")
	elif player_id == DEBUG_PLAYER2_ID and _debug_p2_active():
		v = Input.get_axis(&"tl_p2_look_left", &"tl_p2_look_right")
	var st := _get_state(player_id)
	if _now() - st["look_time"] <= TILT_TIMEOUT_SEC:
		v += _apply_deadzone(st["look"], TILT_DEADZONE)
	return clampf(v, -1.0, 1.0)

# 1.0 while the player is reeling (key held / phone pulse active), else 0.0.
func get_reel_strength(player_id: int = KEYBOARD_PLAYER_ID) -> float:
	if context != InputContext.FISHING:
		return 0.0
	if player_id == KEYBOARD_PLAYER_ID and is_keyboard_enabled() and Input.is_action_pressed(&"tl_reel"):
		return 1.0
	if player_id == DEBUG_PLAYER2_ID and _debug_p2_active() and Input.is_action_pressed(&"tl_p2_reel"):
		return 1.0
	if _now() < _get_state(player_id)["reel_until"]:
		return 1.0
	if _now() < _get_state(player_id)["crank_until"]:
		return 1.0
	return 0.0

# 0..1 charge of the KEYBOARD cast (for a power meter UI). Phones cast
# instantly from the swing, so this is 0 for them. Pass DEBUG_PLAYER2_ID
# (or 2) for the debug second keyboard player's charge.
func get_cast_charge(player_id: int = KEYBOARD_PLAYER_ID) -> float:
	var start := _p2_cast_charge_start if player_id == DEBUG_PLAYER2_ID else _cast_charge_start
	if start < 0.0:
		return 0.0
	return clampf((_now() - start) / KEYBOARD_CAST_CHARGE_TIME, 0.0, 1.0)

# ----------------------------------------------------------------------------
# Keyboard input
# ----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not is_keyboard_enabled():
		_cast_charge_start = -1.0
		_p2_cast_charge_start = -1.0
		return
	if event.pressed and not event.echo:
		_set_device(KEYBOARD_PLAYER_ID, DEVICE_KEYBOARD)

	match context:
		InputContext.OVERWORLD:
			if event.is_action_pressed(&"tl_interact"):
				interact_pressed.emit(KEYBOARD_PLAYER_ID)
			elif event.is_action_pressed(&"tl_cancel"):
				cancel_pressed.emit(KEYBOARD_PLAYER_ID)
			elif event.is_action_pressed(&"tl_pause"):
				pause_pressed.emit(KEYBOARD_PLAYER_ID)

		InputContext.FISHING:
			if event.is_action_pressed(&"tl_cast"):
				_cast_charge_start = _now()
			elif event.is_action_released(&"tl_cast") and _cast_charge_start >= 0.0:
				var power := clampf(get_cast_charge(), MIN_CAST_POWER, 1.0)
				_cast_charge_start = -1.0
				if debug_log:
					print("[InputManager] keyboard cast power %.2f" % power)
				cast_triggered.emit(KEYBOARD_PLAYER_ID, power)
			elif event.is_action_pressed(&"tl_reel"):
				reel.emit(KEYBOARD_PLAYER_ID, 1.0)
			elif event.is_action_pressed(&"tl_interact"):
				interact_pressed.emit(KEYBOARD_PLAYER_ID)
			elif event.is_action_pressed(&"tl_cancel"):
				cancel_pressed.emit(KEYBOARD_PLAYER_ID)
			elif event.is_action_pressed(&"tl_pause"):
				pause_pressed.emit(KEYBOARD_PLAYER_ID)

	if _debug_p2_active():
		_handle_p2_key(event)

# DEBUG: keyboard Player 2 (IJKL scheme). Same behavior as Player 1's keys.
func _handle_p2_key(event: InputEvent) -> void:
	var pid := DEBUG_PLAYER2_ID
	if event.is_action_pressed(&"tl_p2_cast"):
		_p2_cast_charge_start = _now()
	elif event.is_action_released(&"tl_p2_cast") and _p2_cast_charge_start >= 0.0:
		var power := clampf(get_cast_charge(pid), MIN_CAST_POWER, 1.0)
		_p2_cast_charge_start = -1.0
		_set_device(pid, DEVICE_KEYBOARD)
		if debug_log:
			print("[InputManager] keyboard P2 cast power %.2f" % power)
		cast_triggered.emit(pid, power)
	elif event.is_action_pressed(&"tl_p2_reel"):
		_set_device(pid, DEVICE_KEYBOARD)
		reel.emit(pid, 1.0)
	elif event.is_action_pressed(&"tl_p2_interact"):
		_set_device(pid, DEVICE_KEYBOARD)
		interact_pressed.emit(pid)

# ----------------------------------------------------------------------------
# Phone input (from ConnectionManager signals)
# ----------------------------------------------------------------------------
func _on_phone_connected(phone_id: int) -> void:
	if not _phones.has(phone_id):
		_phones.append(phone_id)
	print("[InputManager] controller connected: player %d" % phone_id)
	controller_connected.emit(phone_id)

func _on_phone_disconnected(phone_id: int) -> void:
	_phones.erase(phone_id)
	_state.erase(phone_id)
	print("[InputManager] controller disconnected: player %d" % phone_id)
	controller_disconnected.emit(phone_id)

# Which player_id a phone's input should be reported as (-1 = ignore).
func _phone_player_id(phone_id: int) -> int:
	if context == InputContext.NONE:
		return -1
	if not multiplayer_mode and _phones.size() > 1 and not _warned_remap:
		_warned_remap = true
		push_warning("InputManager: %d phones connected but multiplayer_mode is false, so all phones act as Player 1." % _phones.size())
	return phone_id if multiplayer_mode else KEYBOARD_PLAYER_ID

# Same as above, but also records that this player is now using a phone.
# (Tilt does NOT use this: it streams constantly and would make the "last
# device" flip to phone even when the player is using the keyboard.)
func _accept_phone_input(phone_id: int) -> int:
	var pid := _phone_player_id(phone_id)
	if pid >= 0:
		_set_device(pid, DEVICE_PHONE)
	return pid

func _on_phone_swipe(phone_id: int, direction: String, _dx: float, _dy: float) -> void:
	var pid := _accept_phone_input(phone_id)
	if pid < 0:
		return
	match context:
		InputContext.MENU:
			if MENU_SWIPE_ACTIONS.has(direction):
				_inject_ui_action(MENU_SWIPE_ACTIONS[direction])
		InputContext.OVERWORLD:
			if SWIPE_VECTORS.has(direction):
				_pulse_move(pid, SWIPE_VECTORS[direction])
		InputContext.FISHING:
			# Any swipe direction reels in.
			_pulse_reel(pid)

func _on_phone_tap(phone_id: int, _x: float, _y: float) -> void:
	var pid := _accept_phone_input(phone_id)
	if pid < 0:
		return
	match context:
		InputContext.MENU:
			_inject_ui_action(&"ui_accept")
		InputContext.OVERWORLD, InputContext.FISHING:
			interact_pressed.emit(pid)

func _on_phone_swing(phone_id: int, magnitude: float) -> void:
	var pid := _accept_phone_input(phone_id)
	if pid < 0:
		return
	match context:
		InputContext.MENU:
			_inject_ui_action(&"ui_cancel")
		InputContext.OVERWORLD:
			cancel_pressed.emit(pid)
		InputContext.FISHING:
			var power := _swing_to_power(magnitude)
			if debug_log:
				print("[InputManager] player %d swing %.2f -> cast power %.2f" % [pid, magnitude, power])
			cast_triggered.emit(pid, power)

func _on_phone_tilt(phone_id: int, value: float) -> void:
	if context != InputContext.FISHING:
		return
	var pid := _phone_player_id(phone_id)
	if pid < 0:
		return
	var st := _get_state(pid)
	st["look"] = clampf(value, -1.0, 1.0)
	st["look_time"] = _now()

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
func _swing_to_power(magnitude: float) -> float:
	return clampf(inverse_lerp(SWING_MIN_MAGNITUDE, SWING_MAX_MAGNITUDE, magnitude), MIN_CAST_POWER, 1.0)

# Zeroes out small values and rescales the rest so output still reaches +/-1.
func _apply_deadzone(v: float, deadzone: float) -> float:
	var a := absf(v)
	if a <= deadzone:
		return 0.0
	return signf(v) * (a - deadzone) / (1.0 - deadzone)

func _pulse_move(pid: int, dir: Vector2) -> void:
	var st := _get_state(pid)
	st["move"] = dir
	st["move_until"] = _now() + PHONE_MOVE_PULSE_SEC

func _pulse_reel(pid: int) -> void:
	_get_state(pid)["reel_until"] = _now() + PHONE_REEL_PULSE_SEC
	reel.emit(pid, 1.0)

# Fakes a press+release of a built-in ui_* action so Godot's normal Control
# focus navigation (buttons, lists, slot menus) responds to phone input.
func _inject_ui_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _set_device(pid: int, device: StringName) -> void:
	if _last_device.get(pid, &"") != device:
		_last_device[pid] = device
		device_changed.emit(pid, device)

func _get_state(pid: int) -> Dictionary:
	if not _state.has(pid):
		_state[pid] = {
			"move": Vector2.ZERO, "move_until": 0.0,
			"reel_until": 0.0, "crank_until":0.0,
			"look": 0.0, "look_time": -100.0,
		}
	return _state[pid]

func _on_phone_reel(phone_id: int, crank_delta: float) -> void:
	if context != InputContext.FISHING:
		return
	var pid := _accept_phone_input(phone_id)
	if pid < 0 or absf(crank_delta) > CRANK_MAX_STEP:
		return
	reel_crank.emit(pid, crank_delta)
	if crank_delta >= CRANK_MIN_STEP:
		_get_state(pid)["crank_until"] = _now() + CRANK_ACTIVE_SEC

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
