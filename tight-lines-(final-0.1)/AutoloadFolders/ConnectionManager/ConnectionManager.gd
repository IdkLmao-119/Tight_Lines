extends Node

# ============================================================================
# CONNECTION MANAGER (GODOT / PC SIDE) - the connectivity layer
# ============================================================================
# This script's ONLY job is talking to phones over the network and emitting
# signals when something happens (a player connects, or sends input). It
# does not know or care what a "swipe" or "swing" actually DOES in your
# game - that translation happens in InputManager, which listens to these
# signals.
#
# This runs on the PC, which either hosts its own Wi-Fi hotspot or shares
# an existing LAN. Each phone connects to it over the local network - no
# internet required either way.
#
# CHANGES in this version (disconnect-during-fishing soft-lock fix):
#   1. process_mode = ALWAYS. GameManager pauses the tree when a phone drops
#      during fishing (D3). Without this, this node froze too, so the phone's
#      reconnect was never accepted and the pause could never end (IM-NEW-1).
#   2. A reconnecting device_id now CLOSES its old, stale socket instead of
#      silently overwriting (and leaking) it.
#   3. heartbeat_interval on every WebSocketPeer, so a dead phone is noticed
#      in seconds instead of waiting for the TCP timeout.
# ============================================================================

signal player_connected(player_id)
signal player_disconnected(player_id)
signal player_screen_changed(player_id, screen_name)
signal player_name_changed(player_id, player_name)

# swipe - player dragged a finger across the phone screen
# tap   - player briefly pressed the screen
# swing - player physically swung/moved the phone
signal swipe_input(player_id, direction, dx, dy)
signal tap_input(player_id, x, y)
signal swing_input(player_id, magnitude)
signal cancel_input(player_id)
# reel - circular "crank" gesture on the phone, streamed as degrees turned
# since the last message (+ = clockwise = reel in, - = counter-clockwise)
signal reel_input(player_id, delta)

# tilt - how far the phone is tilted left/right, streamed continuously
signal tilt_input(player_id, value)

# move - d-pad / analog joystick movement vector (x, y)
signal move_input(player_id, x, y)

# menu - button actions for fish_box, almanac, equipment
signal menu_action_input(player_id, action)

# interact - direct interact button press
signal interact_input(player_id)

# knotting - mobile tracing minigame progress and completion
signal knot_progress_input(player_id, progress)
signal knot_complete_input(player_id, knot_name, accuracy)

const PORT := 9080

# When true, every gameplay message received from a phone is printed to the
# Output panel. Set to false once everything works.
@export var debug_log: bool = false

# Tilt messages arrive ~20 times per second per phone, which would flood the
# Output panel, so they are hidden from debug_log unless this is turned on.
@export var debug_log_tilt := false

# Seconds between WebSocket pings. A phone that stops answering is dropped
# after a few missed pings, so a lost connection is detected quickly.
@export var heartbeat_seconds := 5.0

# ============================================================================
# AUTO-DISCOVERY (so phones don't need a hardcoded/manually-typed IP)
# ============================================================================
# Phones broadcast a small UDP message asking "is a game server here?". This
# server listens on DISCOVERY_PORT and replies directly to whoever asked.
# ============================================================================
const DISCOVERY_PORT := 9081

# Must exactly match the string the phone app broadcasts.
const DISCOVERY_MESSAGE := "DISCOVER_FISHING_SERVER"

var _discovery_udp := PacketPeerUDP.new()

# ============================================================================
# CONNECTIVITY MODE
# ============================================================================
#   HOTSPOT: The PC creates its own Wi-Fi network (Settings > Mobile Hotspot).
#   LAN:     The PC and phones are already on the same existing network.
# The server behaves identically either way; this only changes which IP
# address is suggested to the player.
# ============================================================================
enum ConnectivityMode { HOTSPOT, LAN }

@export var connectivity_mode: ConnectivityMode = ConnectivityMode.HOTSPOT

var _tcp_server := TCPServer.new()

var _peers: Dictionary = {} # { player_id: WebSocketPeer }

# Newly accepted connections wait here until their "connected" handshake
# (carrying the phone's device_id) arrives.
var _pending_peers: Array = [] # [ WebSocketPeer, ... ]

# Remembers which player_id belongs to which device_id, so a phone that
# reconnects gets its original player_id back.
var _device_id_to_player_id: Dictionary = {} # { device_id: player_id }

const MAX_PLAYER_NAME_LENGTH := 18

var _next_player_id := 1

var _player_screens: Dictionary = {} # { player_id: String }
var _player_base_screens: Dictionary = {} # { player_id: String }
var _player_names: Dictionary = {} # { player_id: String }


func _ready():
	# FIX 1: keep polling sockets while the game is paused. GameManager pauses
	# the tree when a phone disconnects during fishing; this node must keep
	# running so the reconnect can be accepted and the pause can end.
	process_mode = Node.PROCESS_MODE_ALWAYS

	print("=== Multiplayer WebSocketServer _ready() called ===")
	var err = _tcp_server.listen(PORT)
	if err != OK:
		push_error("FAILED to start server on TCP %d (error %s). Is another server (e.g. the old Python one) still running?" % [PORT, str(err)])
		print("!!! SERVER NOT STARTED - port %d unavailable !!!" % PORT)
		return
	print("=== WebSocket server started on port %d ===" % PORT)
	var suggested_ip = _get_local_ip()
	print("Connect phones to: ws://%s:%d" % [suggested_ip, PORT])

	# Auto-detection isn't 100% reliable across every Windows setup, so we
	# always print every available option too.
	_print_all_interfaces()

	# Godot's PacketPeerUDP has broadcast handling DISABLED by default; enable
	# it BEFORE bind().
	_discovery_udp.set_broadcast_enabled(true)
	var discovery_err = _discovery_udp.bind(DISCOVERY_PORT)
	if discovery_err != OK:
		push_error("Failed to start discovery listener on UDP %d (error %s). Is another server (e.g. the old Python one) still running?" % [DISCOVERY_PORT, str(discovery_err)])
	else:
		print("Discovery listener active on UDP port %d" % DISCOVERY_PORT)

	set_process(true)


# Tries to find the correct local IP address for the selected connectivity
# mode. Returns "unknown" if nothing matching was found.
func _get_local_ip() -> String:
	var interfaces = IP.get_local_interfaces()
	var fallback := ""

	for iface in interfaces:
		var friendly_name: String = iface.get("friendly", "").to_lower()

		for addr in iface.get("addresses", []):
			if not _is_private_ipv4(addr):
				continue
			if _is_virtual_adapter(friendly_name, addr):
				continue

			if fallback == "":
				fallback = addr

			match connectivity_mode:
				ConnectivityMode.HOTSPOT:
					if addr.begins_with("192.168.137.") \
					or "local area connection" in friendly_name \
					or "wi-fi direct" in friendly_name:
						return addr

				ConnectivityMode.LAN:
					if addr.begins_with("192.168.137."):
						continue
					if "wi-fi" in friendly_name or "ethernet" in friendly_name or friendly_name.begins_with("wl") or friendly_name.begins_with("en") or friendly_name.begins_with("eth"):
						return addr

	if fallback != "":
		return fallback
	return "unknown"


# Accepts 192.168.x.x, 10.x.x.x AND 172.16-31.x.x as private LAN addresses.
func _is_private_ipv4(addr: String) -> bool:
	if addr.begins_with("192.168.") or addr.begins_with("10."):
		return true
	if addr.begins_with("172."):
		var parts := addr.split(".")
		if parts.size() == 4:
			var second := int(parts[1])
			return second >= 16 and second <= 31
	return false


# Virtual adapters (VirtualBox / VMware / Hyper-V / WSL / Docker) often have
# private addresses that a phone can never reach, so we skip them.
func _is_virtual_adapter(friendly_name: String, addr: String) -> bool:
	for bad in ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "docker", "vbox", "loopback"]:
		if bad in friendly_name:
			return true
	return addr.begins_with("192.168.56.") # default VirtualBox host-only range


# Picks the PC address on the SAME subnet as the phone that sent the
# discovery request (assumes a /24 network).
func _get_ip_on_same_subnet(peer_ip: String) -> String:
	var parts := peer_ip.replace("::ffff:", "").split(".")
	if parts.size() != 4:
		return ""
	var prefix := ".".join(parts.slice(0, 3)) + "."
	for iface in IP.get_local_interfaces():
		for addr in iface.get("addresses", []):
			if addr.begins_with(prefix):
				return addr
	return ""


func _print_all_interfaces():
	print("--- All detected network interfaces (for manual reference) ---")
	for iface in IP.get_local_interfaces():
		var friendly_name = iface.get("friendly", "unknown")
		for addr in iface.get("addresses", []):
			if _is_private_ipv4(addr):
				print("  [%s] %s" % [friendly_name, addr])
	print("----------------------------------------------------------------")


func _process(_delta):
	_process_discovery_requests()

	# --- STEP 1: Accept any new incoming phone connections ---
	while _tcp_server.is_connection_available():
		var tcp_stream = _tcp_server.take_connection()
		var ws := WebSocketPeer.new()
		# FIX 3: ping regularly so a dead phone is detected quickly. Must be
		# set BEFORE accept_stream().
		ws.heartbeat_interval = heartbeat_seconds
		var err = ws.accept_stream(tcp_stream)

		if err == OK:
			_pending_peers.append(ws)
		else:
			push_error("Failed to accept WebSocket stream: " + str(err))

	# --- STEP 2: Poll pending connections, waiting for their handshake ---
	var still_pending: Array = []

	for ws in _pending_peers:
		ws.poll()
		var state = ws.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			var identified := false

			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				var message = packet.get_string_from_utf8()
				var data = JSON.parse_string(message)

				# The FIRST message from any new connection must be a
				# "connected" handshake carrying a device_id.
				if typeof(data) == TYPE_DICTIONARY and data.get("type") == "connected":
					_handle_handshake(ws, data)
					identified = true
					break # remaining packets are handled next frame

			if not identified:
				still_pending.append(ws)

		elif state != WebSocketPeer.STATE_CLOSED:
			# Still connecting/closing - keep waiting.
			still_pending.append(ws)
		# else: STATE_CLOSED before identifying - just drop it.

	_pending_peers = still_pending

	# --- STEP 3: Check every ALREADY-IDENTIFIED phone for new messages ---
	var disconnected_ids: Array = []

	for player_id in _peers.keys():
		var ws: WebSocketPeer = _peers[player_id]
		ws.poll()
		var state = ws.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				var message = packet.get_string_from_utf8()
				_handle_message(player_id, message)
		elif state == WebSocketPeer.STATE_CLOSED:
			print("Player %d disconnected" % player_id)
			disconnected_ids.append(player_id)

	# _device_id_to_player_id is deliberately NOT cleared here, so the same
	# device gets its same player_id back when it reconnects.
	for player_id in disconnected_ids:
		_peers.erase(player_id)
		_player_screens.erase(player_id)
		_player_base_screens.erase(player_id)
		emit_signal("player_disconnected", player_id)
		emit_signal("player_screen_changed", player_id, "disconnected")


# Replies to phone discovery broadcasts with this PC's IP address.
func _process_discovery_requests():
	while _discovery_udp.get_available_packet_count() > 0:
		var packet = _discovery_udp.get_packet()
		var message = packet.get_string_from_utf8()

		if message == DISCOVERY_MESSAGE:
			var sender_ip = _discovery_udp.get_packet_ip()
			var sender_port = _discovery_udp.get_packet_port()

			var my_ip = _get_ip_on_same_subnet(sender_ip)
			if my_ip == "":
				my_ip = _get_local_ip()

			_discovery_udp.set_dest_address(sender_ip, sender_port)
			_discovery_udp.put_packet(my_ip.to_utf8_buffer())
			print("Discovery request from %s - replied with %s" % [sender_ip, my_ip])


func _warn_if_unconnected(sig_name: String):
	if debug_log and get_signal_connection_list(sig_name).is_empty():
		push_warning("'%s' arrived but NOTHING is connected to the '%s' signal yet." % [sig_name, sig_name])


func _handle_handshake(peer: WebSocketPeer, data: Dictionary) -> void:
	var device_id := String(data.get("device_id", "")).strip_edges()
	if device_id == "":
		device_id = "peer_%d" % peer.get_instance_id()
	var player_id: int

	if _device_id_to_player_id.has(device_id):
		player_id = _device_id_to_player_id[device_id]
		print("Player %d reconnected (device_id=%s)" % [player_id, device_id])
	else:
		player_id = _next_player_id
		_next_player_id += 1
		_device_id_to_player_id[device_id] = player_id
		print("Player %d connected (device_id=%s)" % [player_id, device_id])

	# FIX 2: if this player still has an old socket (the PC
	# had not noticed it died yet), close it instead of
	# overwriting and leaking it.
	if _peers.has(player_id) and _peers[player_id] != peer:
		_peers[player_id].close()
	_peers[player_id] = peer

	var initial_screen := String(data.get("screen", "overworld")).strip_edges().to_lower()
	if initial_screen == "":
		initial_screen = "overworld"
	_player_base_screens[player_id] = initial_screen
	_player_screens[player_id] = initial_screen

	var raw_name := String(data.get("player_name", "")).strip_edges()
	if raw_name != "" and not has_custom_player_name(player_id):
		_player_names[player_id] = raw_name.substr(0, MAX_PLAYER_NAME_LENGTH)

	emit_signal("player_connected", player_id)
	emit_signal("player_screen_changed", player_id, _player_screens[player_id])
	if has_custom_player_name(player_id):
		emit_signal("player_name_changed", player_id, get_player_name(player_id))


func _is_finite_float(v: float) -> bool:
	return not is_nan(v) and not is_inf(v)


# Takes a raw JSON text message from a phone and emits the matching signal,
# tagged with the player_id it came from.
func _handle_message(player_id: int, message: String):
	var data = JSON.parse_string(message)

	if typeof(data) != TYPE_DICTIONARY:
		if debug_log:
			print("[Player %d] ignored non-JSON-object message: %s" % [player_id, message])
		return

	if debug_log and (data.get("type") != "tilt" or debug_log_tilt):
		print("[Player %d] received: %s" % [player_id, message])

	match String(data.get("type", "")):
		"connected":
			# Harmless duplicate: identification already happened in _process().
			if data.has("screen"):
				var dup_screen := String(data.get("screen", "overworld")).strip_edges().to_lower()
				if dup_screen == "":
					dup_screen = "overworld"
				_player_base_screens[player_id] = dup_screen
				_set_player_screen(player_id, dup_screen)
			if data.has("player_name"):
				var dup_name := String(data.get("player_name", "")).strip_edges()
				if dup_name != "" and not has_custom_player_name(player_id):
					set_player_name(player_id, dup_name)

		"screen_state":
			var screen := String(data.get("screen", "overworld")).strip_edges().to_lower()
			var active_menu := String(data.get("active_menu", "none")).strip_edges().to_lower()
			if screen == "":
				screen = "overworld"
			if screen != "menu":
				_player_base_screens[player_id] = screen
			elif active_menu != "" and active_menu != "none":
				screen = "menu:" + active_menu
			_set_player_screen(player_id, screen)

		"set_name":
			set_player_name(player_id, String(data.get("name", "")))
			
		"cancel":
			_warn_if_unconnected("cancel_input")
			emit_signal("cancel_input", player_id)
			
		"swipe":
			var dx := float(data.get("dx", 0.0))
			var dy := float(data.get("dy", 0.0))
			if not _is_finite_float(dx) or not _is_finite_float(dy):
				return
			_warn_if_unconnected("swipe_input")
			emit_signal(
				"swipe_input",
				player_id,
				String(data.get("direction", "")),
				dx,
				dy
			)

		"tap":
			# x/y are normalized (0.0 to 1.0).
			var tx := float(data.get("x", 0.0))
			var ty := float(data.get("y", 0.0))
			if not _is_finite_float(tx) or not _is_finite_float(ty):
				return
			_warn_if_unconnected("tap_input")
			emit_signal("tap_input", player_id, tx, ty)

		"swing":
			# magnitude = peak rotation speed detected by the phone.
			var mag := float(data.get("magnitude", 0.0))
			if not _is_finite_float(mag):
				return
			_warn_if_unconnected("swing_input")
			emit_signal("swing_input", player_id, mag)

		"reel":
			var r_delta := float(data.get("delta", 0.0))
			if not _is_finite_float(r_delta):
				return
			emit_signal("reel_input", player_id, r_delta)

		"tilt":
			# value is -1.0 (left) .. +1.0 (right). Not passed through
			# _warn_if_unconnected: it streams constantly.
			var t_val := float(data.get("value", 0.0))
			if not _is_finite_float(t_val):
				return
			emit_signal("tilt_input", player_id, t_val)

		"move":
			var mx := float(data.get("x", 0.0))
			var my := float(data.get("y", 0.0))
			if not _is_finite_float(mx) or not _is_finite_float(my):
				return
			emit_signal("move_input", player_id, mx, my)

		"menu":
			emit_signal("menu_action_input", player_id, String(data.get("action", "")))

		"interact":
			emit_signal("interact_input", player_id)

		"knot_progress":
			var kp := float(data.get("progress", 0.0))
			if not _is_finite_float(kp):
				return
			emit_signal("knot_progress_input", player_id, clampf(kp, 0.0, 1.0))

		"knot_complete":
			var acc := float(data.get("accuracy", 1.0))
			if not _is_finite_float(acc):
				return
			emit_signal(
				"knot_complete_input",
				player_id,
				String(data.get("knot_name", "")),
				clampf(acc, 0.0, 1.0)
			)


# Sends a message to EVERY connected player at once.
func send_to_all(data: Dictionary):
	# send_text(), NOT send(buffer): send() on a byte array goes out as a BINARY
	# frame, which the Android app's onMessage(String) never receives.
	var message = JSON.stringify(data)

	for player_id in _peers.keys():
		var ws: WebSocketPeer = _peers[player_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(message)
			_track_outgoing_screen(player_id, data)


# Sends a message to just ONE specific player.
func send_to_player(player_id: int, data: Dictionary):
	if not _peers.has(player_id):
		push_warning("Tried to send to unknown player_id: %d" % player_id)
		return

	var ws: WebSocketPeer = _peers[player_id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(data))
		_track_outgoing_screen(player_id, data)


func _track_outgoing_screen(player_id: int, data: Dictionary) -> void:
	if data.has("game_state"):
		var state := String(data.get("game_state", "")).strip_edges().to_lower()
		if state != "":
			_player_base_screens[player_id] = state
			var cur := String(_player_screens.get(player_id, ""))
			if not cur.begins_with("menu") or state == "reeling" or state == "knotting":
				_set_player_screen(player_id, state)
	if data.has("active_menu"):
		var menu := String(data.get("active_menu", "")).strip_edges().to_lower()
		if menu == "" or menu == "none":
			_set_player_screen(player_id, String(_player_base_screens.get(player_id, "overworld")))
		else:
			_set_player_screen(player_id, "menu:" + menu)


func _set_player_screen(player_id: int, screen: String) -> void:
	var clean := screen.strip_edges().to_lower()
	if clean == "":
		clean = "overworld"
	if String(_player_screens.get(player_id, "")) == clean:
		return
	_player_screens[player_id] = clean
	emit_signal("player_screen_changed", player_id, clean)


func is_player_connected(player_id: int) -> bool:
	if not _peers.has(player_id):
		return false
	var ws: WebSocketPeer = _peers[player_id]
	return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func get_player_screen(player_id: int) -> String:
	if not is_player_connected(player_id):
		return ""
	return String(_player_screens.get(player_id, "overworld"))


func get_player_screen_display(player_id: int) -> String:
	if not is_player_connected(player_id):
		return "Disconnected"
	var screen := get_player_screen(player_id)
	match screen:
		"overworld":
			return "Overworld"
		"casting":
			return "Casting"
		"reeling":
			return "Reeling"
		"knotting":
			return "Tying Knot"
		"connection":
			return "Connecting"
		"menu":
			return "Menu"
		"menu:fish_box":
			return "Menu (Fish Box)"
		"menu:almanac":
			return "Menu (Almanac)"
		"menu:equipment":
			return "Menu (Inventory)"
		_:
			return screen.replace("menu:", "Menu: ").capitalize()


func get_player_name(player_id: int) -> String:
	var custom := String(_player_names.get(player_id, "")).strip_edges()
	if custom != "":
		return custom
	return "Player %d" % player_id


func has_custom_player_name(player_id: int) -> bool:
	return String(_player_names.get(player_id, "")).strip_edges() != ""


func set_player_name(player_id: int, new_name: String) -> void:
	var clean := new_name.strip_edges()
	if clean.length() > MAX_PLAYER_NAME_LENGTH:
		clean = clean.substr(0, MAX_PLAYER_NAME_LENGTH)
	var prev_display := get_player_name(player_id)
	if clean == "":
		_player_names.erase(player_id)
	else:
		_player_names[player_id] = clean
	var next_display := get_player_name(player_id)
	if next_display != prev_display:
		emit_signal("player_name_changed", player_id, next_display)


func get_local_ip() -> String:
	return _get_local_ip()


func get_port() -> int:
	return PORT


func ping_player(player_id: int) -> bool:
	if not is_player_connected(player_id):
		return false
	send_to_player(player_id, {"type": "vibrate", "reason": "bite"})
	return true


func sync_player_identity(player_id: int, display_name: String, screen_side: String) -> void:
	if not is_player_connected(player_id):
		return
	send_to_player(player_id, {
		"type": "player_info",
		"player_id": player_id,
		"player_name": display_name,
		"screen_side": screen_side,
	})


func clear_all_player_screen_sides() -> void:
	for player_id in _peers.keys():
		sync_player_identity(int(player_id), get_player_name(int(player_id)), "")


func get_connected_players() -> Array:
	return _peers.keys()


func _exit_tree():
	for peer in _peers.values():
		if peer is WebSocketPeer:
			(peer as WebSocketPeer).close()
	_peers.clear()
	for peer in _pending_peers:
		if peer is WebSocketPeer:
			(peer as WebSocketPeer).close()
	_pending_peers.clear()
	_tcp_server.stop()
	_discovery_udp.close()
