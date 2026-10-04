extends Node

# ============================================================================
# CONNECTION MANAGER (GODOT / PC SIDE)  — module 2 of 3: the connectivity layer
# ============================================================================
# This script's ONLY job is talking to phones over the network and emitting
# signals when something happens (a player connects, or sends input). It
# does not know or care what a "swipe" or "swing" actually DOES in your
# game — that translation happens in a separate script (the "adapter"
# layer, module 3) that listens to these signals.
#
# Keeping this separation means: if you later add a second connection type
# (e.g. Bluetooth) as a parallel option, it just needs to emit these same
# signals, and NOTHING in your actual game logic needs to change at all.
#
# This runs on the PC, which either hosts its own Wi-Fi hotspot or shares
# an existing LAN. Each phone connects to it over the local network — no
# internet required either way.
# ============================================================================

# Signals now include a "player_id" so the game knows WHICH player sent the
# input. Any other node listening to these signals should expect this extra
# first argument now.
signal player_connected(player_id)
signal player_disconnected(player_id)

# The three input types this project uses:
#   swipe — player dragged a finger across the phone screen
#   tap   — player briefly pressed the screen
#   swing — player physically swung/moved the phone (detected via gyroscope
#           on the phone itself; the PHONE decides when a "swing" happened,
#           this server just relays that decision)
signal swipe_input(player_id, direction, dx, dy)
signal tap_input(player_id, x, y)
signal swing_input(player_id, magnitude)

const PORT := 9080

# When true, every gameplay message received from a phone is printed to the
# Output panel. Handy for confirming that swipes/taps/swings really arrive.
# Set to false once everything works.
@export var debug_log := true

# ============================================================================
# AUTO-DISCOVERY (so phones don't need a hardcoded/manually-typed IP)
# ============================================================================
# Phones can broadcast a small UDP message onto the local network asking
# "is a game server here?" This server listens for that exact message on
# DISCOVERY_PORT, and replies directly to whoever asked with this PC's IP
# address — letting the phone app auto-fill/connect without any typing.
#
# UDP is used here (instead of the main WebSocket/TCP connection) because
# UDP supports BROADCASTING to an unknown address — exactly what's needed
# when the phone doesn't know the PC's IP yet. Once discovery finds the IP,
# the actual game connection still goes over the normal WebSocket (TCP) port.
# ============================================================================
const DISCOVERY_PORT := 9081

# Must exactly match the string the phone app broadcasts.
const DISCOVERY_MESSAGE := "DISCOVER_FISHING_SERVER"

var _discovery_udp := PacketPeerUDP.new()

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

# A newly-accepted connection isn't assigned a player_id right away —
# first we need to hear its "connected" handshake message, which carries
# the phone's persistent device_id. Until that arrives, the connection
# sits here rather than in _peers.
var _pending_peers: Array = [] # [ WebSocketPeer, ... ]

# Remembers which player_id was already assigned to which device_id, so
# that if the SAME phone disconnects and reconnects (e.g. it briefly lost
# Wi-Fi, the app was closed and reopened, or its IP address changed), it
# gets its original player_id back instead of incrementing to a brand new
# one. device_id is a random UUID the phone generates once and saves
# permanently — far more reliable than tracking by IP address, since IP
# addresses can change between sessions while the device_id never does.
var _device_id_to_player_id: Dictionary = {} # { device_id: player_id }

# Keeps track of the next ID to hand out to a newly connected phone.
# Starts at 1 and goes up by 1 each time someone new connects, so every
# player gets their own unique number (1, 2, 3, ...).
var _next_player_id := 1

func _ready():
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
	# always print every available option too — use this list if the
	# suggested address above doesn't work.
	_print_all_interfaces()

	# Start listening for discovery broadcasts from phones (see the block
	# comment above DISCOVERY_PORT for why this uses UDP instead of the
	# main WebSocket connection).
	# FIX: Godot's PacketPeerUDP has broadcast handling DISABLED by default.
	# It is now enabled BEFORE bind() — some Godot versions only honor the
	# flag when set before the socket is bound (a plain OS-level socket,
	# like Python's, needs no such flag at all).
	_discovery_udp.set_broadcast_enabled(true)
	var discovery_err = _discovery_udp.bind(DISCOVERY_PORT)
	if discovery_err != OK:
		push_error("Failed to start discovery listener on UDP %d (error %s). Is another server (e.g. the old Python one) still running?" % [DISCOVERY_PORT, str(discovery_err)])
	else:
		print("Discovery listener active on UDP port %d" % DISCOVERY_PORT)

	set_process(true)

# Tries to find the correct local IP address for whichever connectivity
# mode is currently selected. Returns "unknown" if nothing matching was
# found, in which case check the full interface list printed on startup.
func _get_local_ip() -> String:
	var interfaces = IP.get_local_interfaces()
	var fallback := ""

	for iface in interfaces:
		# "friendly" is the human-readable adapter name Windows shows,
		# e.g. "Wi-Fi", "Ethernet", or a hotspot-specific virtual adapter.
		var friendly_name: String = iface.get("friendly", "").to_lower()

		for addr in iface.get("addresses", []):
			# Skip IPv6 and loopback-style addresses — we only want a
			# normal local IPv4 address phones can actually connect to.
			if not _is_private_ipv4(addr):
				continue
			if _is_virtual_adapter(friendly_name, addr):
				continue

			# Remember the first reasonable candidate so we never give up with
			# "unknown" just because an adapter name didn't match our
			# Windows-specific guesses (also makes Linux/macOS names like
			# wlan0 / en0 work).
			if fallback == "":
				fallback = addr

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
					if "wi-fi" in friendly_name or "ethernet" in friendly_name or friendly_name.begins_with("wl") or friendly_name.begins_with("en") or friendly_name.begins_with("eth"):
						return addr

	# Nothing matched the selected mode's heuristics (e.g. mode is HOTSPOT
	# but the PC is really on a normal router). Use the best remaining guess
	# instead of silently giving up.
	if fallback != "":
		return fallback
	return "unknown"

# FIX: accepts 192.168.x.x, 10.x.x.x AND 172.16-31.x.x (used by e.g. iPhone
# hotspots and some routers) as private LAN addresses.
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
# private addresses that a phone can never reach, so we skip them when guessing.
func _is_virtual_adapter(friendly_name: String, addr: String) -> bool:
	for bad in ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "docker", "vbox", "loopback"]:
		if bad in friendly_name:
			return true
	return addr.begins_with("192.168.56.") # default VirtualBox host-only range

# FIX: picks the PC address on the SAME subnet as the phone that sent the
# discovery request (assumes a /24 network, which covers virtually every
# home/hotspot setup). Much more reliable than guessing from adapter names,
# since it answers with the address the phone can actually reach.
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

# Prints every detected network interface and its address(es), labeled with
# a best-guess of what it is. Use this to manually pick the right address if
# the automatic suggestion above doesn't match what you expect.
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
	# Newly accepted connections go into _pending_peers, NOT _peers — we
	# don't know who they are yet, since that information (device_id)
	# arrives in their first message, not at the raw connection level.
	while _tcp_server.is_connection_available():
		var tcp_stream = _tcp_server.take_connection()
		var ws := WebSocketPeer.new()
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

				# We specifically require the FIRST message from any new
				# connection to be a "connected" handshake carrying a
				# device_id — this is what lets us assign the right
				# player_id before treating anything else it sends as
				# real gameplay input.
				if typeof(data) == TYPE_DICTIONARY and data.get("type") == "connected" and data.has("device_id"):
					var device_id = data["device_id"]
					var player_id: int

					if _device_id_to_player_id.has(device_id):
						# This device has connected before — reuse its
						# existing player_id instead of handing out a new one.
						player_id = _device_id_to_player_id[device_id]
						print("Player %d reconnected (device_id=%s)" % [player_id, device_id])
					else:
						# First time we've ever seen this device — assign
						# the next available ID and remember it for next time.
						player_id = _next_player_id
						_next_player_id += 1
						_device_id_to_player_id[device_id] = player_id
						print("Player %d connected (device_id=%s)" % [player_id, device_id])

					# Whether this is a fresh player_id or a reused one,
					# always point it at the NEW connection object — the
					# old one (if any) is no longer usable anyway once a
					# phone has reconnected.
					_peers[player_id] = ws
					emit_signal("player_connected", player_id)
					identified = true
					break # any further packets are handled next frame,
						  # now that this ws lives in _peers below

			if not identified:
				still_pending.append(ws)

		elif state != WebSocketPeer.STATE_CLOSED:
			# Still connecting/closing — keep waiting, don't drop it yet.
			still_pending.append(ws)
		# else: STATE_CLOSED — the connection died before ever identifying
		# itself. We simply drop it; there's no player_id to clean up since
		# one was never assigned.

	_pending_peers = still_pending

	# --- STEP 3: Check every ALREADY-IDENTIFIED phone for new messages ---
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
	# disconnected players from our dictionary. Note: we deliberately do
	# NOT remove anything from _device_id_to_player_id here — that mapping
	# is meant to persist for the whole server session, so if this same
	# device reconnects later, it gets its same player_id back.
	for player_id in disconnected_ids:
		_peers.erase(player_id)
		emit_signal("player_disconnected", player_id)

# Checks for any incoming discovery broadcasts from phones, and replies
# with this PC's IP address so the phone can connect without needing a
# manually-typed address.
func _process_discovery_requests():
	while _discovery_udp.get_available_packet_count() > 0:
		var packet = _discovery_udp.get_packet()
		var message = packet.get_string_from_utf8()

		if message == DISCOVERY_MESSAGE:
			# get_packet_ip()/get_packet_port() tell us exactly who sent
			# this request, so we can reply directly to THEM (not broadcast
			# our reply to everyone, which would be unnecessary noise).
			var sender_ip = _discovery_udp.get_packet_ip()
			var sender_port = _discovery_udp.get_packet_port()

			# FIX: prefer the address on the phone's own subnet, falling back to
			# the mode-based guess. We ALWAYS reply now: the phone app reads the
			# reply packet's SOURCE address (which the OS sets correctly), so the
			# reply itself matters more than the text inside it.
			var my_ip = _get_ip_on_same_subnet(sender_ip)
			if my_ip == "":
				my_ip = _get_local_ip()

			_discovery_udp.set_dest_address(sender_ip, sender_port)
			_discovery_udp.put_packet(my_ip.to_utf8_buffer())
			print("Discovery request from %s — replied with %s" % [sender_ip, my_ip])

# Takes a raw text message (expected to be JSON) from a specific phone,
# figures out what kind of message it is, and emits the matching signal —
# now tagged with which player_id it came from.
func _warn_if_unconnected(sig_name: String):
	if debug_log and get_signal_connection_list(sig_name).is_empty():
		push_warning("'%s' arrived but NOTHING is connected to the '%s' signal yet." % [sig_name, sig_name])

func _handle_message(player_id: int, message: String):
	var data = JSON.parse_string(message)

	if typeof(data) != TYPE_DICTIONARY:
		if debug_log:
			print("[Player %d] ignored non-JSON-object message: %s" % [player_id, message])
		return

	if debug_log:
		print("[Player %d] received: %s" % [player_id, message])

	match data.get("type"):
		"connected":
			# By the time a message reaches THIS function, the phone is
			# already identified and assigned to _peers (see the pending
			# connection handling in _process()) — so a "connected"
			# message here is just a harmless duplicate/no-op, not the
			# real identification step.
			pass

		"swipe":
			# direction is a simple string like "up"/"down"/"left"/"right",
			# already figured out by the phone app. dx/dy are the raw swipe
			# distances in case your game wants finer-grained control than
			# just a direction (e.g. a swipe's exact angle or speed).
			_warn_if_unconnected("swipe_input")
			emit_signal(
				"swipe_input",
				player_id,
				data.get("direction", ""),
				data.get("dx", 0.0),
				data.get("dy", 0.0)
			)

		"tap":
			# x/y are normalized screen coordinates (0.0 to 1.0), so they
			# mean the same thing regardless of the phone's actual screen
			# resolution.
			_warn_if_unconnected("tap_input")
			emit_signal("tap_input", player_id, data.get("x", 0.0), data.get("y", 0.0))

		"swing":
			# magnitude is how forceful the swing was (peak rotation speed
			# detected by the phone), useful for things like "harder swing =
			# stronger cast."
			_warn_if_unconnected("swing_input")
			emit_signal("swing_input", player_id, data.get("magnitude", 0.0))

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
	_discovery_udp.close()
