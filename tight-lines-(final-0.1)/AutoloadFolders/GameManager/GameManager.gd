extends Node

# ============================================================================
# GAME MANAGER (GODOT)  -  TightLines
# ============================================================================
# Autoload singleton (Project Settings > Autoload, name it exactly "GameManager").
#
# Responsibilities:
#   1. SCENE SWITCHING  - fade out, threaded load (with progress bar for heavy
#                         scenes like the 3D fishing level), swap, fade in.
#   2. MUSIC            - one track per scene, crossfaded on scene change. If
#                         the next scene uses the SAME track, it keeps playing.
#   3. SCENE CONTEXT    - pass data to the next scene (fishing spot, rod...).
#   4. PAUSE STATE      - pause flag + signal, ignored in menu-type scenes.
#   5. VOLUME BUSES     - Master / Music / SFX volume (linear 0.0 - 1.0).
#
# It does NOT read gameplay input (that is InputManager's job) and does NOT
# save anything itself (SaveManager can call get/apply_volume_settings()).
#
# NOTE: do not add `class_name GameManager` here - it would clash with the
# autoload's global name.
# ============================================================================

# --- Signals ---------------------------------------------------------------
signal scene_change_started(scene_id: String)
signal scene_changed(scene_id: String)
signal load_progress(ratio: float)            # 0.0 - 1.0 while loading
signal paused_changed(is_paused: bool)
signal volume_changed(bus_name: String, linear: float)

# ============================================================================
# SCENE REGISTRY  -  edit this block to add scenes / change music
# ============================================================================
# "path"     : the .tscn file
# "music"    : track to play in this scene. "" = keep whatever is playing.
#              Missing files are skipped with a warning, so the game runs
#              fine before the audio assets exist.
# "pausable" : false for menus/cutscenes (pause requests are ignored there)
#
# Paths follow the architecture doc - change them to match your project tree.
const SCENES: Dictionary = {
	"main_menu": {
		"path": "res://ui/MainMenu.tscn",
		"music": "res://audio/music/main_menu.ogg",
		"pausable": false,
	},
	"save_slots": {
		"path": "res://ui/SaveSlots.tscn",
		"music": "res://audio/music/main_menu.ogg",   # same track = no restart
		"pausable": false,
	},
	"options": {
		"path": "res://ui/Options.tscn",
		"music": "res://audio/music/main_menu.ogg",
		"pausable": false,
	},
	"cutscene": {
		"path": "res://cutscenes/Cutscene.tscn",
		"music": "res://audio/music/cutscene.ogg",
		"pausable": false,
	},
	"overworld": {
		"path": "res://OverWorldSceneAndScript/Area01Scene/MainArea1/MainArea01.tscn",
		"music": "res://audio/music/overworld.ogg",
		"pausable": true,
	},
	"fishing": {
		"path": "res://fishing/FishingMinigame.tscn",
		"music": "res://audio/music/fishing.ogg",
		"pausable": true,
	},
}

# --- Tuning ----------------------------------------------------------------
const FADE_TIME := 0.4              # seconds, each direction
const MUSIC_CROSSFADE_TIME := 1.0   # seconds
const LOADING_BAR_DELAY_MS := 250   # only show the bar if loading takes longer
const SILENT_DB := -60.0

# --- Audio bus names -------------------------------------------------------
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# --- Public state ----------------------------------------------------------
var current_scene_id: String = ""
var pending_context: Dictionary = {}   # read it with consume_context()
var is_changing_scene := false

# --- Internals -------------------------------------------------------------
var _fade_rect: ColorRect
var _loading_bar: ProgressBar
var _loading_label: Label
var _fade_tween: Tween

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer     # the one currently audible
var _music_tween: Tween
var _current_music_path: String = ""
var _warned_missing: Dictionary = {}     # so each missing file warns once


func _ready() -> void:
	# Must keep running while the tree is paused (fades, music, pause toggling).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_buses()
	_build_overlay()
	_build_music_players()

	# If a scene was launched directly (F6 / main scene), sync to it so its
	# music starts and pause rules apply. Deferred: current_scene isn't set yet.
	call_deferred("_sync_initial_scene")


func _unhandled_input(event: InputEvent) -> void:
	# Optional convenience: if a "pause" action exists in the Input Map,
	# toggle pause with it. Remove if InputManager will own this later.
	if InputMap.has_action("pause") and event.is_action_pressed("pause"):
		# Only consume the key when pausing is actually allowed here, so
		# menus can still use the same key for their own purposes.
		if _current_scene_pausable() and not is_changing_scene:
			toggle_pause()
			get_viewport().set_input_as_handled()


# ============================================================================
# SCENE SWITCHING
# ============================================================================
# `target` can be a registry id ("overworld") or a raw "res://...tscn" path.
# `context` is handed to the next scene - it calls GameManager.consume_context()
# in its _ready(). Example:
#     GameManager.change_scene("fishing", {"spot_id": "pier", "rod_id": "basic"})
func change_scene(target: String, context: Dictionary = {}) -> void:
	if is_changing_scene:
		push_warning("GameManager: scene change already in progress, ignoring '%s'." % target)
		return

	var entry := _resolve_scene(target)
	if entry.is_empty():
		push_error("GameManager: unknown scene '%s' (not in SCENES and not a valid path)." % target)
		return

	is_changing_scene = true
	pending_context = context
	var scene_id: String = entry["id"]
	scene_change_started.emit(scene_id)

	# Never carry a paused state into the next scene.
	_apply_pause(false)

	# Block clicks during the transition, then fade to black.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, FADE_TIME)

	var packed := await _load_packed_scene(entry["path"])
	if packed == null:
		# Load failed: fade back in and stay on the current scene.
		pending_context = {}
		await _fade_to(0.0, FADE_TIME)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		is_changing_scene = false
		return

	var swap_err := get_tree().change_scene_to_packed(packed)
	if swap_err != OK:
		push_error("GameManager: change_scene_to_packed failed for '%s' (error %d)." % [entry["path"], swap_err])
		pending_context = {}
		await _fade_to(0.0, FADE_TIME)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		is_changing_scene = false
		return

	# change_scene_to_packed is deferred - wait for the new scene to exist.
	await get_tree().process_frame
	await get_tree().process_frame

	current_scene_id = scene_id
	_play_scene_music(entry)

	await _fade_to(0.0, FADE_TIME)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_changing_scene = false
	scene_changed.emit(scene_id)


# Convenience for ReloadCurrent (e.g. retry after a failed catch).
func reload_current_scene() -> void:
	if current_scene_id != "":
		change_scene(current_scene_id)


# Returns the context passed to this scene, then clears it so stale data
# can't leak into a later scene.
func consume_context() -> Dictionary:
	var ctx := pending_context
	pending_context = {}
	return ctx


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
		return {"id": "", "path": target, "music": "", "pausable": true}
	return {}


func _load_packed_scene(path: String) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("GameManager: could not start loading '%s' (error %d)." % [path, err])
		return null

	var started := Time.get_ticks_msec()
	var progress: Array = []
	var bar_shown := false

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
# PAUSE
# ============================================================================
func is_paused() -> bool:
	return get_tree().paused


func set_paused(value: bool) -> void:
	if value and not _current_scene_pausable():
		return  # menus / cutscenes can't be paused
	if value and is_changing_scene:
		return
	_apply_pause(value)


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func _apply_pause(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	paused_changed.emit(value)


func _current_scene_pausable() -> bool:
	if SCENES.has(current_scene_id):
		return SCENES[current_scene_id].get("pausable", true)
	return true


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


# For SaveManager: store this dictionary in the settings part of the save file,
# and call apply_volume_settings() on startup.
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
