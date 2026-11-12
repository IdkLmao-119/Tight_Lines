extends Node

# ============================================================================
# GAME MANAGER (GODOT)  -  TightLines   (Ver. 3)
# ============================================================================
# Autoload singleton (Project Settings > Autoload, name it exactly "GameManager").
#
# Responsibilities:
#   1. SCENE SWITCHING  - fade out, threaded load (progress bar for slow loads),
#                         swap, fade in. Remembers the previous scene.
#   2. MUSIC            - one track per scene, crossfaded on scene change.
#   3. SCENE CONTEXT    - pass data to the next scene; remember per-scene state
#                         (e.g. player position) so 2D scenes don't reset.
#   4. PAUSE            - pause with REASONS (player, inventory, disconnect).
#   5. INVENTORY OVERLAY- opens/closes the inventory over overworld/fishing.
#   6. VOLUME BUSES     - Master / Music / SFX volume (linear 0.0 - 1.0).
#   7. INPUT LINK       - tells InputManager the active context on every change.
#
# It does NOT read gameplay input (InputManager does) and does NOT save files
# (SaveManager does).
#
# NOTE: do not add `class_name GameManager` here - it would clash with the
# autoload's global name.
# ============================================================================

# --- Signals ---------------------------------------------------------------
signal scene_change_started(scene_id: String)
signal scene_changed(scene_id: String)
signal scene_change_failed(scene_id: String)
signal load_progress(ratio: float)            # 0.0 - 1.0 while loading
signal paused_changed(is_paused: bool)
signal inventory_overlay_changed(is_open: bool)
signal volume_changed(bus_name: String, linear: float)

# ============================================================================
# SCENE REGISTRY  -  edit this block to add scenes / change music
# ============================================================================
# "path"     : the .tscn file
# "music"    : track to play in this scene. "" = keep whatever is playing.
#              Missing files are skipped with a warning.
# "pausable" : false for menus/cutscenes (pause requests are ignored there)
# "input"    : InputManager context: "menu", "overworld" or "fishing".
#
# Paths are PLACEHOLDERS - change them to match your project tree.
const SCENES: Dictionary = {
	"main_menu": {
		"path": "res://UIScenesAndScript/MainMenu/MainMenu.tscn",
		"input": "menu",
		"music": "res://audio/music/main_menu.ogg",
		"pausable": false,
	},
	"save_slots": {
		"path": "res://UIScenesAndScript/MainMenu/SaveSlots.tscn",
		"input": "menu",
		"music": "res://audio/music/main_menu.ogg",   # same track = no restart
		"pausable": false,
	},
	"cutscene": {
		"path": "res://cutscenes/Cutscene.tscn",
		"input": "menu",
		"music": "res://audio/music/cutscene.ogg",
		"pausable": false,
	},
	"overworld_spawn": {
		"path": "res://OverWorldSceneAndScript/1_MainArea/Spawn/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_fish_market": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_river_park": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_rice_field": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_fishing_pens": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_salt_farm": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_mangrove": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_island": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_house_1": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/House_Folder/Area01_House1.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"overworld_house_2": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/House_Folder/Area01_House2.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_rice_field": {
		"path": "res://fishing/FishingMinigame.tscn",
		"input": "fishing",
		"music": "res://audio/music/fishing.ogg",
		"pausable": true,
	},
	"fishing_river_park": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_fish_market": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_fishing_pens": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_salt_farm": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_mangrove": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing_island": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"multiplayer": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"input": "overworld",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
}

# Placeholder path of the inventory overlay UI (no owner yet).
const INVENTORY_OVERLAY_SCENE := "res://ui/InventoryOverlay.tscn"

# --- Tuning ----------------------------------------------------------------
const FADE_TIME := 0.4              # seconds, each direction
const MUSIC_CROSSFADE_TIME := 1.0   # seconds
const LOADING_BAR_DELAY_MS := 250   # only show the bar if loading takes longer
const SILENT_DB := -60.0

# --- InputManager link -----------------------------------------------------
# The values MUST match the order of InputManager.InputContext:
#   NONE = 0, MENU = 1, OVERWORLD = 2, FISHING = 3
# InputManager is looked up by path at runtime, so GameManager still works
# (just without input switching) if it isn't installed yet.
const INPUT_MANAGER_PATH := "/root/InputManager"
const INPUT_CONTEXTS: Dictionary = {"none": 0, "menu": 1, "overworld": 2, "fishing": 3}

# --- Audio bus names -------------------------------------------------------
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# --- Pause reasons ---------------------------------------------------------
# The game is paused while ANY reason is active. Disconnect reasons are named
# "disconnect_<player_id>".
const REASON_USER := "user"
const REASON_OVERLAY := "overlay"
const REASON_DISCONNECT_PREFIX := "disconnect_"

# --- Public state ----------------------------------------------------------
var current_scene_id: String = ""
var previous_scene_id: String = ""
var pending_context: Dictionary = {}     # read it with consume_context()
var is_changing_scene := false
var is_multiplayer := false              # set from the context's "multiplayer"
var scene_memory: Dictionary = {}        # { scene_id: Dictionary of saved state }

# --- Internals -------------------------------------------------------------
var _current_input_name: String = ""     # input context of the live scene
var _current_context: Dictionary = {}    # context the live scene was entered with
var _previous_context: Dictionary = {}   # context the previous scene had
var _fishing_return_to: String = "overworld"
var _pause_reasons: Dictionary = {}

var _fade_rect: ColorRect
var _loading_bar: ProgressBar
var _loading_label: Label
var _fade_tween: Tween
var _overlay_layer: CanvasLayer
var _overlay_node: Node = null
var _overlay_prev_input: String = ""

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer     # the one currently audible
var _music_tween: Tween
var _current_music_path: String = ""
var _warned_missing: Dictionary = {}     # so each missing file warns once


func _ready() -> void:
	# Must keep running while the tree is paused (fades, music, overlay).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_buses()
	_build_overlay()
	_build_music_players()

	# Deferred: current_scene and InputManager aren't ready yet.
	call_deferred("_sync_initial_scene")
	call_deferred("_connect_input_manager")


# ============================================================================
# SCENE SWITCHING
# ============================================================================
# `target` can be a registry id ("overworld") or a raw "res://...tscn" path.
# `context` is handed to the next scene - it calls GameManager.consume_context()
# in its _ready(). Example:
#     GameManager.change_scene("fishing", {"spot_id": "pier", "rod_id": "basic"})
# Special context keys GameManager reads itself: "multiplayer" (bool),
# "return_to" (scene id, used by end_fishing()).
func change_scene(target: String, context: Dictionary = {}) -> void:
	if is_changing_scene:
		push_warning("GameManager: scene change already in progress, ignoring '%s'." % target)
		return

	var entry := _resolve_scene(target)
	if entry.is_empty():
		push_error("GameManager: unknown scene '%s' (not in SCENES and not a valid path)." % target)
		return

	is_changing_scene = true
	var scene_id: String = entry["id"]
	pending_context = context.duplicate(true)
	if scene_id == "fishing":
		_fishing_return_to = str(context.get("return_to", "overworld"))

	# Let the scene we are leaving save its state (e.g. player position).
	_save_leaving_scene_state()

	scene_change_started.emit(scene_id)

	# Close the overlay and never carry a paused state into the next scene.
	close_inventory()
	_clear_pause_reasons()

	# Ignore all input (keyboard AND phone) while the screen is transitioning.
	_set_input_context("none")

	# Block clicks during the transition, then fade to black.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, FADE_TIME)

	var packed := await _load_packed_scene(entry["path"])
	if packed == null:
		await _abort_transition(scene_id)
		return

	var swap_err := get_tree().change_scene_to_packed(packed)
	if swap_err != OK:
		push_error("GameManager: change_scene_to_packed failed for '%s' (error %d)." % [entry["path"], swap_err])
		await _abort_transition(scene_id)
		return

	# change_scene_to_packed is deferred - wait for the new scene to exist.
	await get_tree().process_frame
	await get_tree().process_frame

	# Remember where we came from (only after the swap succeeded).
	if scene_id != current_scene_id and current_scene_id != "":
		previous_scene_id = current_scene_id
		_previous_context = _current_context
	current_scene_id = scene_id
	_current_context = context.duplicate(true)

	_play_scene_music(entry)
	_enter_scene_input(entry, context)

	await _fade_to(0.0, FADE_TIME)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_changing_scene = false
	scene_changed.emit(scene_id)


# Reloads the current scene with the SAME context it was entered with.
func reload_current_scene() -> void:
	if current_scene_id != "":
		change_scene(current_scene_id, _current_context.duplicate(true))


# Returns to the previous scene (one step back, with the context it had).
# Not for leaving fishing - use end_fishing() for that.
func go_back() -> void:
	if previous_scene_id == "":
		push_warning("GameManager: no previous scene to go back to.")
		return
	change_scene(previous_scene_id, _previous_context.duplicate(true))


# FishingManager calls this when a round ends. Returns to the scene that
# started fishing ("return_to" in the fishing context, default "overworld")
# and hands it the result: ctx["result"] = {results: {player_id: {...}}}.
func end_fishing(result: Dictionary) -> void:
	change_scene(_fishing_return_to, {"result": result})


# Returns the context passed to this scene, then clears it so stale data
# can't leak into a later scene.
func consume_context() -> Dictionary:
	var ctx := pending_context
	pending_context = {}
	return ctx


# --- Scene memory ----------------------------------------------------------
# Before leaving a scene, GameManager calls get_scene_state() on it (if it has
# that method) and stores the result. The scene restores it in _ready():
#     var mem: Dictionary = GameManager.recall("overworld")
#     if mem.has("player_pos"): player.global_position = mem["player_pos"]
func remember(scene_id: String, data: Dictionary) -> void:
	scene_memory[scene_id] = data


func recall(scene_id: String) -> Dictionary:
	return scene_memory.get(scene_id, {})


func _save_leaving_scene_state() -> void:
	var cs := get_tree().current_scene
	if current_scene_id != "" and cs != null and cs.has_method("get_scene_state"):
		scene_memory[current_scene_id] = cs.call("get_scene_state")


func _resolve_scene(target: String) -> Dictionary:
	if SCENES.has(target):
		var e: Dictionary = SCENES[target].duplicate()
		e["id"] = target
		return e
	for id in SCENES:
		if SCENES[id]["path"] == target:
			var e2: Dictionary = SCENES[id].duplicate()
			e2["id"] = id
			return e2
	# Unregistered but valid path: allowed, keeps current music, pausable.
	if target.begins_with("res://") and ResourceLoader.exists(target):
		return {"id": "", "path": target, "music": "", "pausable": true, "input": ""}
	return {}


func _load_packed_scene(path: String) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("GameManager: could not start loading '%s' (error %d)." % [path, err])
		return null

	var started := Time.get_ticks_msec()
	var progress: Array = []
	var bar_shown := false
	_loading_bar.value = 0.0   # don't show the previous load's leftover value

	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var ratio: float = progress[0] if progress.size() > 0 else 0.0
			load_progress.emit(ratio)
			if not bar_shown and Time.get_ticks_msec() - started > LOADING_BAR_DELAY_MS:
				bar_shown = true
				_loading_bar.visible = true
				_loading_label.visible = true
			_loading_bar.value = ratio * 100.0
			await get_tree().process_frame
		else:
			push_error("GameManager: loading '%s' failed (status %d)." % [path, status])
			_loading_bar.visible = false
			_loading_label.visible = false
			return null

	_loading_bar.visible = false
	_loading_label.visible = false
	load_progress.emit(1.0)
	return ResourceLoader.load_threaded_get(path) as PackedScene


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade_rect, "modulate:a", alpha, duration)
	await _fade_tween.finished


# Shared recovery for a failed load/swap: stay on the current scene, restore
# its input, fade back in, and tell listeners it failed.
func _abort_transition(failed_scene_id: String) -> void:
	pending_context = {}
	_set_input_context(_current_input_name)
	await _fade_to(0.0, FADE_TIME)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_changing_scene = false
	scene_change_failed.emit(failed_scene_id)


# If a scene was launched directly (F6 / main scene), sync to it so its music
# starts, pause rules apply and InputManager gets the right context.
func _sync_initial_scene() -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	for id in SCENES:
		if SCENES[id]["path"] == cs.scene_file_path:
			current_scene_id = id
			var e: Dictionary = SCENES[id].duplicate()
			e["id"] = id
			_play_scene_music(e)
			_enter_scene_input(e, {})
			return


# ============================================================================
# MUSIC
# ============================================================================
# Two players are used so one can fade out while the other fades in.
func play_music(path: String, fade_time: float = MUSIC_CROSSFADE_TIME) -> void:
	if path == "":
		return
	# Same track already playing: do nothing (no restart between menu scenes).
	if path == _current_music_path and _music_active.playing:
		return

	if not ResourceLoader.exists(path):
		if not _warned_missing.has(path):
			_warned_missing[path] = true
			push_warning("GameManager: music file not found: %s (skipping)." % path)
		return

	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("GameManager: '%s' is not an audio stream." % path)
		return
	_enable_loop(stream)

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	var old_player := _music_active
	var new_player := _music_b if _music_active == _music_a else _music_a
	new_player.stream = stream
	new_player.volume_db = SILENT_DB
	new_player.play()

	_music_active = new_player
	_current_music_path = path

	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.set_parallel(true)
	_music_tween.set_trans(Tween.TRANS_SINE)
	_music_tween.tween_property(new_player, "volume_db", 0.0, fade_time)
	if old_player.playing:
		_music_tween.tween_property(old_player, "volume_db", SILENT_DB, fade_time)
		_music_tween.chain().tween_callback(old_player.stop)


func stop_music(fade_time: float = MUSIC_CROSSFADE_TIME) -> void:
	_current_music_path = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.set_parallel(true)
	for p in [_music_a, _music_b]:
		if p.playing:
			_music_tween.tween_property(p, "volume_db", SILENT_DB, fade_time)
	_music_tween.chain().tween_callback(func():
		_music_a.stop()
		_music_b.stop())


func _play_scene_music(entry: Dictionary) -> void:
	var track: String = entry.get("music", "")
	if track != "":
		play_music(track)


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _build_music_players() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for p in [_music_a, _music_b]:
		p.bus = BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
	_music_active = _music_a


# ============================================================================
# PAUSE  (reason-based: the game is paused while ANY reason is active)
# ============================================================================
func is_paused() -> bool:
	return get_tree().paused


# Player pause request (ESC). value = false resumes.
func set_paused(value: bool) -> void:
	if value:
		if not _current_scene_pausable() or is_changing_scene or _overlay_node != null:
			return  # menus / cutscenes / transitions / overlay can't be paused
		_add_pause_reason(REASON_USER)
	else:
		_resume_from_pause()


func toggle_pause() -> void:
	if get_tree().paused:
		_resume_from_pause()
	else:
		set_paused(true)


# Clears the player's pause. In SINGLE-PLAYER it also clears a disconnect
# pause (the keyboard player can carry on). In MULTIPLAYER a disconnect pause
# only clears when the missing phone reconnects.
func _resume_from_pause() -> void:
	if _overlay_node != null:
		return  # the overlay pause ends through close_inventory()
	_pause_reasons.erase(REASON_USER)
	if not is_multiplayer:
		_clear_disconnect_reasons()
	_refresh_pause()


func _add_pause_reason(reason: String) -> void:
	_pause_reasons[reason] = true
	_refresh_pause()


func _remove_pause_reason(reason: String) -> void:
	_pause_reasons.erase(reason)
	_refresh_pause()


func _clear_pause_reasons() -> void:
	_pause_reasons.clear()
	_refresh_pause()


func _clear_disconnect_reasons() -> void:
	for key in _pause_reasons.keys():
		if str(key).begins_with(REASON_DISCONNECT_PREFIX):
			_pause_reasons.erase(key)


func _refresh_pause() -> void:
	var want_paused := not _pause_reasons.is_empty()
	if get_tree().paused == want_paused:
		return
	get_tree().paused = want_paused
	paused_changed.emit(want_paused)


func _current_scene_pausable() -> bool:
	if SCENES.has(current_scene_id):
		return SCENES[current_scene_id].get("pausable", true)
	return true


# ============================================================================
# INVENTORY OVERLAY  (single-player only, overworld + fishing)
# ============================================================================
# Opening pauses the game and switches input to MENU. Closing restores the
# previous input context. The overlay UI calls close_inventory() itself
# (e.g. on ui_cancel).
func is_inventory_open() -> bool:
	return _overlay_node != null


func open_inventory() -> void:
	if _overlay_node != null or is_changing_scene or is_multiplayer:
		return
	if current_scene_id != "overworld" and current_scene_id != "fishing":
		return
	if get_tree().paused:
		return  # already paused (pause menu or disconnect)
	if not ResourceLoader.exists(INVENTORY_OVERLAY_SCENE):
		push_warning("GameManager: inventory overlay scene not found: %s" % INVENTORY_OVERLAY_SCENE)
		return
	var packed := load(INVENTORY_OVERLAY_SCENE) as PackedScene
	if packed == null:
		return

	_overlay_node = packed.instantiate()
	_overlay_layer.add_child(_overlay_node)
	_overlay_prev_input = _current_input_name
	_set_input_context("menu")
	_add_pause_reason(REASON_OVERLAY)
	inventory_overlay_changed.emit(true)


func close_inventory() -> void:
	if _overlay_node == null:
		return
	_overlay_node.queue_free()
	_overlay_node = null
	_set_input_context(_overlay_prev_input)
	_remove_pause_reason(REASON_OVERLAY)
	inventory_overlay_changed.emit(false)


func toggle_inventory() -> void:
	if _overlay_node != null:
		close_inventory()
	else:
		open_inventory()


# ============================================================================
# VOLUME BUSES   (linear 0.0 - 1.0, what an Options slider naturally gives)
# ============================================================================
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("GameManager: no audio bus named '%s'." % bus_name)
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	volume_changed.emit(bus_name, linear)


func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


# For SaveManager: store this in user://settings.json and call
# apply_volume_settings() at startup (with call_deferred).
func get_volume_settings() -> Dictionary:
	return {
		"master": get_bus_volume(BUS_MASTER),
		"music": get_bus_volume(BUS_MUSIC),
		"sfx": get_bus_volume(BUS_SFX),
	}


func apply_volume_settings(settings: Dictionary) -> void:
	set_bus_volume(BUS_MASTER, float(settings.get("master", 1.0)))
	set_bus_volume(BUS_MUSIC, float(settings.get("music", 1.0)))
	set_bus_volume(BUS_SFX, float(settings.get("sfx", 1.0)))


# Creates the Music and SFX buses at runtime if the project doesn't have them
# yet (so nothing breaks before you build an audio bus layout).
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


# ============================================================================
# TRANSITION OVERLAY  (built in code, so there is no scene file to maintain)
# ============================================================================
func _build_overlay() -> void:
	# Inventory overlay layer sits UNDER the fade layer.
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 50
	add_child(_overlay_layer)

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	layer.add_child(_fade_rect)

	# A full-screen column anchored to the bottom, so the label and bar stay
	# centered at any resolution without manual offsets.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	_fade_rect.add_child(box)

	_loading_label = Label.new()
	_loading_label.text = "Loading..."
	_loading_label.visible = false
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.visible = false
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(400, 14)
	_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_loading_bar)

	var bottom_margin := Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 60)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom_margin)


# ============================================================================
# INPUT MANAGER LINK
# ============================================================================
# Connects to InputManager's signals (deferred, so load order doesn't matter).
func _connect_input_manager() -> void:
	var im: Node = get_node_or_null(INPUT_MANAGER_PATH)
	if im == null:
		push_warning("GameManager: no InputManager at %s - pause/disconnect/inventory input disabled." % INPUT_MANAGER_PATH)
		return
	_try_connect(im, "pause_pressed", _on_pause_pressed)
	_try_connect(im, "controller_disconnected", _on_controller_disconnected)
	_try_connect(im, "controller_connected", _on_controller_connected)
	_try_connect(im, "inventory_pressed", _on_inventory_pressed)


func _try_connect(node: Node, signal_name: String, callable: Callable) -> void:
	if node.has_signal(signal_name):
		node.connect(signal_name, callable)
	else:
		push_warning("GameManager: InputManager has no '%s' signal (yet)." % signal_name)


func _on_pause_pressed(_player_id: int) -> void:
	toggle_pause()


func _on_inventory_pressed(_player_id: int) -> void:
	toggle_inventory()


# A phone dropped during fishing: pause until it comes back (D3).
func _on_controller_disconnected(player_id: int) -> void:
	if current_scene_id != "fishing" or is_changing_scene:
		return
	_add_pause_reason("%s%d" % [REASON_DISCONNECT_PREFIX, player_id])


# The phone is back: drop its pause reason. If nothing else holds the pause,
# the game resumes by itself.
func _on_controller_connected(player_id: int) -> void:
	_remove_pause_reason("%s%d" % [REASON_DISCONNECT_PREFIX, player_id])


# Sets InputManager's context by name ("none", "menu", "overworld", "fishing").
# "" or a missing InputManager = do nothing.
func _set_input_context(context_name: String) -> void:
	if context_name == "":
		return
	var im: Node = get_node_or_null(INPUT_MANAGER_PATH)
	if im == null or not im.has_method("set_context"):
		return
	im.call("set_context", INPUT_CONTEXTS.get(context_name, INPUT_CONTEXTS["menu"]))


# Called once the new scene exists: applies its input context and the
# multiplayer flag. The flag is applied on EVERY scene change (default false),
# so phones return to single-player ids after a multiplayer round.
func _enter_scene_input(entry: Dictionary, context: Dictionary) -> void:
	var context_name: String = entry.get("input", "")
	if context_name != "":
		_current_input_name = context_name
	_set_input_context(_current_input_name)

	is_multiplayer = bool(context.get("multiplayer", false))
	var im: Node = get_node_or_null(INPUT_MANAGER_PATH)
	if im != null and im.has_method("set_multiplayer_mode"):
		im.call("set_multiplayer_mode", is_multiplayer)
