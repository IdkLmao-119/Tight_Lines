extends Node

# ============================================================================
# MULTIPLAYER WEBSOCKET SERVER
# ============================================================================
# This is the original single-player WebSocket server, updated to support
# MULTIPLE phones connecting at once (for multiplayer). The key change is
# that every connected phone now gets a unique "player_id" number, so the
# game can tell whose input is whose.
#
# This is meant to run on the PC, which hosts its own Wi-Fi hotspot. Each
# phone joins that hotspot and connects to this server over the local network
# — no internet or external router required.
# ============================================================================

# Signals now include a "player_id" so the game knows WHICH player sent the
# input. Any other node listening to these signals should expect this extra
# first argument now.
signal player_connected(player_id)
signal player_disconnected(player_id)
signal gyro_input(player_id, tilt)
signal cast_input(player_id, tilt)
signal reel_input(player_id, intensity)
signal reel_stop(player_id)

const PORT := 9080

# ============================================================================
# CONNECTIVITY MODE
# ============================================================================
# The server itself works identically either way (it listens on ALL network
# interfaces at once, automatically). What actually changes between these
# two modes is just WHICH IP ADDRESS you should give to your phones to
# connect to, since that depends on which network they're joining.
#
#   HOTSPOT: The PC creates its own Wi-Fi network (Settings > Mobile Hotspot).
#            Phones join THAT network directly. No router needed.
#   LAN:     The PC and phones are already on the same existing network
#            (e.g. a venue's Wi-Fi router). No hotspot needed.
#
# Set this in the Inspector, or change it in code before running.
# ============================================================================
enum ConnectivityMode { HOTSPOT, LAN }

@export var connectivity_mode: ConnectivityMode = ConnectivityMode.HOTSPOT

var _tcp_server := TCPServer.new()

# Instead of a simple list of peers, we now use a Dictionary that maps
# each player's unique ID (an integer) to their WebSocketPeer connection.
# A Dictionary is like a lookup table: given a player_id, we can instantly
# find their connection, and vice versa.
var _peers: Dictionary = {} # { player_id: WebSocketPeer }

# Keeps track of the next ID to hand out to a newly connected phone.
# Starts at 1 and goes up by 1 each time someone new connects, so every
# player gets their own unique number (1, 2, 3, ...).
var _next_player_id := 1

func _ready():
	print("=== Multiplayer WebSocketServer _ready() called ===")
	var err = _tcp_server.listen(PORT)
	if err != OK:
		push_error("FAILED to start server: " + str(err))
		return
	print("=== WebSocket server started on port %d ===" % PORT)
	var suggested_ip = _get_local_ip()
	print("Connect phones to: ws://%s:%d" % [suggested_ip, PORT])

	# Auto-detection isn't 100% reliable across every Windows setup, so we
	# always print every available option too — use this list if the
	# suggested address above doesn't work.
	_print_all_interfaces()

	set_process(true)

# Tries to find the correct local IP address for whichever connectivity
# mode is currently selected. Returns "unknown" if nothing matching was
# found, in which case check the full interface list printed on startup.
func _get_local_ip() -> String:
	var interfaces = IP.get_local_interfaces()

	for iface in interfaces:
		# "friendly" is the human-readable adapter name Windows shows,
		# e.g. "Wi-Fi", "Ethernet", or a hotspot-specific virtual adapter.
		var friendly_name: String = iface.get("friendly", "").to_lower()

		for addr in iface.get("addresses", []):
			# Skip IPv6 and loopback-style addresses — we only want a
			# normal local IPv4 address phones can actually connect to.
			if not (addr.begins_with("192.168.") or addr.begins_with("10.")):
				continue

			match connectivity_mode:
				ConnectivityMode.HOTSPOT:
					# Windows' Mobile Hotspot feature almost always hands out
					# addresses starting with 192.168.137.x by default, and
					# often names the virtual adapter something involving
					# "Local Area Connection" or "Wi-Fi Direct".
					if addr.begins_with("192.168.137.") \
					or "local area connection" in friendly_name \
					or "wi-fi direct" in friendly_name:
						return addr

				ConnectivityMode.LAN:
					# For LAN mode, prefer a normal Wi-Fi or Ethernet adapter,
					# and specifically AVOID the hotspot's own virtual adapter
					# so we don't accidentally suggest the wrong network.
					if addr.begins_with("192.168.137."):
						continue
					if "wi-fi" in friendly_name or "ethernet" in friendly_name:
						return addr

	return "unknown"

# Prints every detected network interface and its address(es), labeled with
# a best-guess of what it is. Use this to manually pick the right address if
# the automatic suggestion above doesn't match what you expect.
func _print_all_interfaces():
	print("--- All detected network interfaces (for manual reference) ---")
	for iface in IP.get_local_interfaces():
		var friendly_name = iface.get("friendly", "unknown")
		for addr in iface.get("addresses", []):
			if addr.begins_with("192.168.") or addr.begins_with("10."):
				print("  [%s] %s" % [friendly_name, addr])
	print("----------------------------------------------------------------")

func _process(_delta):
	# --- STEP 1: Accept any new incoming phone connections ---
	while _tcp_server.is_connection_available():
		var tcp_stream = _tcp_server.take_connection()
		var ws := WebSocketPeer.new()
		var err = ws.accept_stream(tcp_stream)

		if err == OK:
			# Hand this new phone the next available player ID, then
			# remember it in our dictionary so we can find it again later.
			var player_id = _next_player_id
			_next_player_id += 1

			_peers[player_id] = ws
			print("Player %d connected" % player_id)
			emit_signal("player_connected", player_id)
		else:
			push_error("Failed to accept WebSocket stream: " + str(err))

	# --- STEP 2: Check every connected phone for new messages ---
	# We collect IDs to remove into a separate list first, rather than
	# removing from the Dictionary while looping over it directly, since
	# changing a Dictionary's contents mid-loop can cause errors.
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

	# Now that we're done looping, it's safe to actually remove the
	# disconnected players from our dictionary.
	for player_id in disconnected_ids:
		_peers.erase(player_id)
		emit_signal("player_disconnected", player_id)

# Takes a raw text message (expected to be JSON) from a specific phone,
# figures out what kind of message it is, and emits the matching signal —
# now tagged with which player_id it came from.
func _handle_message(player_id: int, message: String):
	var data = JSON.parse_string(message)

	if not data:
		return

	match data.get("type"):
		"connected":
			print("Mobile device confirmed for player %d" % player_id)
		"gyro":
			emit_signal("gyro_input", player_id, data.get("tilt", 0.0))
		"cast":
			emit_signal("cast_input", player_id, data.get("tilt", 0.0))
		"reel":
			emit_signal("reel_input", player_id, data.get("intensity", 0.5))
		"reel_stop":
			emit_signal("reel_stop", player_id)

# Sends a message to EVERY connected player at once.
# Useful for things all players should see, like a shared game-state update.
func send_to_all(data: Dictionary):
	var message = JSON.stringify(data)
	var buffer = message.to_utf8_buffer()

	for player_id in _peers.keys():
		var ws: WebSocketPeer = _peers[player_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send(buffer)

# Sends a message to just ONE specific player, found by their player_id.
# Useful for things only relevant to a single player, like "you caught a fish!"
func send_to_player(player_id: int, data: Dictionary):
	if not _peers.has(player_id):
		push_warning("Tried to send to unknown player_id: %d" % player_id)
		return

	var ws: WebSocketPeer = _peers[player_id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var message = JSON.stringify(data)
		var buffer = message.to_utf8_buffer()
		ws.send(buffer)

# Returns a list of all currently connected player IDs.
# Handy for things like showing a lobby screen of who's currently connected.
func get_connected_players() -> Array:
	return _peers.keys()

func _exit_tree():
	_tcp_server.stop()
