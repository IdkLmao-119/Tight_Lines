extends Node

# ============================================================================
# OVERWORLD INPUT PROBE v2 (temporary debug tool) - TightLines
# ============================================================================
# Add a plain Node to any 2D overworld scene and attach this script. It draws a
# status box ON SCREEN (top-left), so nothing depends on the Output panel.
# Run the scene, connect the phone, swipe, and read / screenshot the box.
# Delete the node when the problem is found.
# ============================================================================

const CONTEXT_NAMES := ["NONE", "MENU", "OVERWORLD", "FISHING"]

var _im: Node = null
var _cm: Node = null
var _label: Label = null
var _swipes := 0
var _last_swipe := "(none yet)"
var _last_swipe_time := -100.0
var _peak_move := Vector2.ZERO      # strongest move vector seen since the last swipe
var _player_report: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_im = get_node_or_null("/root/InputManager")
	_cm = get_node_or_null("/root/ConnectionManager")
	if _cm != null:
		_cm.swipe_input.connect(_on_swipe)

	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.position = Vector2(8, 8)
	bg.size = Vector2(760, 330)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	_label = Label.new()
	_label.position = Vector2(16, 14)
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)

	_check_players.call_deferred()


func _on_swipe(player_id: int, direction: String, _dx: float, _dy: float) -> void:
	_swipes += 1
	_last_swipe = "phone %d %s" % [player_id, direction]
	_last_swipe_time = _now()
	_peak_move = Vector2.ZERO


func _process(_delta: float) -> void:
	var lines: Array[String] = []
	lines.append("OVERWORLD INPUT PROBE")
	lines.append("autoloads: InputManager=%s  ConnectionManager=%s" % [_im != null, _cm != null])

	if _im != null:
		var ctx: int = _im.context
		lines.append("scene: %s" % (get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "(none)"))
		lines.append("context: %s   paused: %s   phones: %s" % [
			CONTEXT_NAMES[ctx] if ctx >= 0 and ctx < CONTEXT_NAMES.size() else str(ctx),
			get_tree().paused, str(_im.get_connected_phone_ids())])

		var v: Vector2 = _im.get_move_vector(1)
		if v.length() > _peak_move.length():
			_peak_move = v
		lines.append("")
		lines.append("A) swipes received from phone: %d   last: %s (%.1fs ago)" % [
			_swipes, _last_swipe, _now() - _last_swipe_time if _swipes > 0 else 0.0])
		lines.append("B) InputManager move vector now: %s" % str(v))
		lines.append("   strongest since last swipe:   %s" % str(_peak_move))
	lines.append("")
	for l in _player_report:
		lines.append(l)

	lines.append("")
	lines.append("How to read: swipe on the phone.")
	lines.append(" A stays 0            -> swipes do not reach the PC")
	lines.append(" A counts but B stays (0,0) -> InputManager problem")
	lines.append(" B moves but player does not -> the PLAYER script ignores InputManager")
	_label.text = "\n".join(lines)


# Does the player's script ask InputManager for movement at all?
func _check_players() -> void:
	var found := false
	for n in get_tree().root.find_children("*", "CharacterBody2D", true, false):
		found = true
		var script: Script = n.get_script()
		if script == null:
			_player_report.append("C) '%s' has NO script." % n.name)
			continue
		var src: String = script.source_code
		if src.is_empty():
			_player_report.append("C) '%s': script source not readable here." % n.name)
		elif "get_move_vector" in src:
			_player_report.append("C) '%s' (%s) calls get_move_vector: OK" % [n.name, script.resource_path.get_file()])
		else:
			_player_report.append("C) '%s' (%s) does NOT call InputManager.get_move_vector  <-- BUG" % [n.name, script.resource_path.get_file()])
	if not found:
		_player_report.append("C) no CharacterBody2D in the scene (is the player another node type?)")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
