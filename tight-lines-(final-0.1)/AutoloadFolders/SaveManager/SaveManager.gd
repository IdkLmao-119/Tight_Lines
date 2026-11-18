extends Node
# ============================================================================
# SAVE MANAGER (GODOT)  — TightLines                                  (Ver. 3.1)
# ============================================================================
# Autoload singleton named "SaveManager". Autoload order (DECISIONS.md C11):
#   GameDB, SaveManager, ConnectionManager, InputManager, GameManager,
#   InventoryManager, QuestManager.
# Other modules are looked up by name at runtime (never at load time), so the
# order above is safe and a module that is not registered yet is just skipped.
#
# THREE JOBS
#   1. SLOT STORAGE   save_game / load_game / delete_save / slot_exists
#                     (original names kept). Safe writes: temp file first,
#                     replace the slot only when complete.
#   2. GAME STATE     build_save_data() / apply_save_data() collect and hand
#                     back the state of the other modules. save_slot(slot) and
#                     load_slot(slot) combine both. Owns the player state that
#                     has no other home: saved scene, difficulty, unlock flags,
#                     owned rods, equipped rod, equipped bait, caught fish.
#   3. SETTINGS       Volume lives in its OWN global file, user://settings.json
#                     (C3), NOT in slot files. save_settings() / load_settings();
#                     volume is applied at startup with call_deferred.
# ============================================================================

signal slot_saved(slot: int)
signal slot_loaded(slot: int)
signal unlock_flag_added(flag: String)
signal equipment_changed   # owned rods, equipped rod or equipped bait changed
signal difficulty_changed(difficulty: String)
signal fish_caught(fish_id: String)

const SAVE_DIR := "user://saves/"
const SETTINGS_PATH := "user://settings.json"
const SAVE_EXTENSION := "json"
const SAVE_FORMAT_VERSION := 1
const SETTINGS_FORMAT_VERSION := 1
const VOLUME_KEYS := ["master", "music", "sfx"]

# --- What a brand-new game starts with (D10) ---
const NEW_GAME_OWNED_ROD_IDS: Array = []
const NEW_GAME_EQUIPPED_ROD := ""
const NEW_GAME_EQUIPPED_BAIT := ""
const NEW_GAME_DIFFICULTY := "casual"
const NEW_GAME_STARTER_ITEMS: Dictionary = {}

const DEFAULT_START_SCENE := "overworld_spawn"
const NON_SAVABLE_SCENES := ["main_menu", "save_slots"]

# --- Player state owned here ---
var _unlock_flags: Array = []      # Array of String
var _owned_rods: Array = []        # Array of String (rod ids)
var _caught_fish: Array = []       # Array of String (fish ids)
var _equipped_rod := ""
var _equipped_bait := ""
var _difficulty := NEW_GAME_DIFFICULTY
var _saved_scene := DEFAULT_START_SCENE

var _slug_regex := RegEx.new()     # same rule as GameDB: lowercase snake_case


func _ready() -> void:
	_slug_regex.compile("^[a-z][a-z0-9_]*$")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_reset_player_state()
	load_settings.call_deferred()


# ============================================================================
# SLOT STORAGE
# ============================================================================

func save_game(slot: int, data: Dictionary) -> bool:
	var to_write := data.duplicate(true)
	to_write["version"] = SAVE_FORMAT_VERSION
	to_write["timestamp"] = Time.get_datetime_string_from_system()
	return _write_json(_slot_path(slot), to_write)


func load_game(slot: int) -> Dictionary:
	return _read_json(_slot_path(slot))


func delete_save(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	var data := load_game(slot)
	if data.is_empty():
		return {"exists": false, "timestamp": "", "version": 0}
	return {
		"exists": true,
		"timestamp": String(data.get("timestamp", "")),
		"version": int(data.get("version", 0)),
	}


# ============================================================================
# GAME STATE
# ============================================================================

func build_save_data() -> Dictionary:
	var game_manager := _autoload("GameManager")
	var scene_to_save := _saved_scene
	if game_manager != null and game_manager.get("current_scene_id") is String:
		var current: String = game_manager.get("current_scene_id")
		if current != "" and not NON_SAVABLE_SCENES.has(current):
			scene_to_save = current

	var data := {
		"scene": scene_to_save,
		"difficulty": _difficulty,
		"unlock_flags": _unlock_flags.duplicate(),
		"owned_rods": _owned_rods.duplicate(),
		"caught_fish": _caught_fish.duplicate(),
		"equipped_rod": _equipped_rod,
		"equipped_bait": _equipped_bait,
	}
	var inventory := _autoload("InventoryManager")
	if inventory != null:
		data["inventory"] = inventory.call("to_save_data")
	return data


func apply_save_data(data: Dictionary) -> void:
	_reset_player_state()

	# Scene.
	if data.get("scene") is String and data["scene"] != "" and not NON_SAVABLE_SCENES.has(data["scene"]):
		_saved_scene = data["scene"]

	# Difficulty.
	if data.get("difficulty") is String:
		var diff := String(data["difficulty"]).to_lower()
		if diff == "casual" or diff == "angler":
			_difficulty = diff

	# Inventory.
	var inventory := _autoload("InventoryManager")
	if inventory != null:
		if data.get("inventory") is Dictionary:
			inventory.call("load_save_data", data["inventory"])
		else:
			inventory.call("clear_all")

	# Unlock flags.
	if data.has("unlock_flags"):
		_unlock_flags = _clean_flags(data["unlock_flags"])

	# Caught fish (Almanac).
	if data.has("caught_fish"):
		_caught_fish = _clean_ids(data["caught_fish"], "has_fish", "fish")

	# Rods.
	if data.has("owned_rods"):
		_owned_rods = _clean_ids(data["owned_rods"], "has_rod", "rod")
	var rod := String(data["equipped_rod"]) if data.get("equipped_rod") is String else _equipped_rod
	if rod != "" and not _owned_rods.has(rod):
		push_warning("SaveManager: equipped rod '%s' is not an owned rod; choosing another." % rod)
		rod = ""
	if rod == "" and not _owned_rods.is_empty():
		rod = _owned_rods[0]
	_equipped_rod = rod

	# Bait.
	var bait := String(data["equipped_bait"]) if data.get("equipped_bait") is String else _equipped_bait
	if bait != "" and not _db_knows("has_bait", bait):
		push_warning("SaveManager: equipped bait '%s' is not in the database; clearing it." % bait)
		bait = ""
	_equipped_bait = bait

	equipment_changed.emit()
	difficulty_changed.emit(_difficulty)


func save_slot(slot: int) -> bool:
	var ok := save_game(slot, build_save_data())
	if ok:
		slot_saved.emit(slot)
	return ok


func load_slot(slot: int) -> bool:
	var data := load_game(slot)
	if data.is_empty():
		return false
	if int(data.get("version", 0)) > SAVE_FORMAT_VERSION:
		push_warning("SaveManager: slot %d was written by a newer version of the game; loading what is understood." % slot)
	apply_save_data(data)
	slot_loaded.emit(slot)
	return true


func get_saved_scene() -> String:
	return _saved_scene


func new_game() -> void:
	apply_save_data({})
	var inventory := _autoload("InventoryManager")
	if inventory == null:
		return
	for item_id in NEW_GAME_STARTER_ITEMS:
		var leftover: int = inventory.call("add_item", item_id, int(NEW_GAME_STARTER_ITEMS[item_id]))
		if leftover > 0:
			push_warning("SaveManager: no room for %d starter '%s'." % [leftover, item_id])


# ============================================================================
# DIFFICULTY MANAGEMENT
# ============================================================================

func get_difficulty() -> String:
	return _difficulty


func set_difficulty(diff: String) -> void:
	var clean := diff.to_lower()
	if clean == "casual" or clean == "angler":
		if _difficulty != clean:
			_difficulty = clean
			difficulty_changed.emit(_difficulty)
	else:
		push_warning("SaveManager: invalid difficulty '%s'. Expected 'casual' or 'angler'." % diff)


# ============================================================================
# UNLOCK FLAGS
# ============================================================================

func add_unlock_flag(flag: String) -> bool:
	if _slug_regex.search(flag) == null:
		push_warning("SaveManager: '%s' is not a valid unlock flag (lowercase snake_case)." % flag)
		return false
	if _unlock_flags.has(flag):
		return false
	_unlock_flags.append(flag)
	unlock_flag_added.emit(flag)
	return true


func has_unlock_flag(flag: String) -> bool:
	return _unlock_flags.has(flag)


func get_unlock_flags() -> Array:
	return _unlock_flags.duplicate()


# ============================================================================
# CAUGHT FISH
# ============================================================================

func record_caught_fish(fish_id: String) -> bool:
	if not _db_knows("has_fish", fish_id):
		push_warning("SaveManager: unknown fish id '%s'." % fish_id)
		return false
	if _caught_fish.has(fish_id):
		return false
	_caught_fish.append(fish_id)
	fish_caught.emit(fish_id)
	return true


func has_caught_fish(fish_id: String) -> bool:
	return _caught_fish.has(fish_id)


func get_caught_fish() -> Array:
	return _caught_fish.duplicate()


# ============================================================================
# RODS AND BAIT
# ============================================================================

func get_owned_rods() -> Array:
	return _owned_rods.duplicate()


func has_rod(rod_id: String) -> bool:
	return _owned_rods.has(rod_id)


func add_owned_rod(rod_id: String) -> bool:
	if not _db_knows("has_rod", rod_id):
		push_warning("SaveManager: unknown rod id '%s'." % rod_id)
		return false
	if _owned_rods.has(rod_id):
		return false
	_owned_rods.append(rod_id)
	equipment_changed.emit()
	return true


func get_equipped_rod() -> String:
	return _equipped_rod


func set_equipped_rod(rod_id: String) -> bool:
	if not _owned_rods.has(rod_id):
		push_warning("SaveManager: cannot equip rod '%s' (not owned)." % rod_id)
		return false
	if _equipped_rod != rod_id:
		_equipped_rod = rod_id
		equipment_changed.emit()
	return true


func get_equipped_bait() -> String:
	return _equipped_bait


func set_equipped_bait(bait_id: String) -> bool:
	if not _db_knows("has_bait", bait_id):
		push_warning("SaveManager: unknown bait id '%s'." % bait_id)
		return false
	if _equipped_bait != bait_id:
		_equipped_bait = bait_id
		equipment_changed.emit()
	return true


# ============================================================================
# SETTINGS
# ============================================================================

func save_settings() -> bool:
	var game_manager := _autoload("GameManager")
	var input_manager := _autoload("InputManager")
	if game_manager == null:
		return false
	var data := {
		"version": SETTINGS_FORMAT_VERSION,
		"volume": game_manager.call("get_volume_settings"),
	}
	if input_manager != null:
		data["cast_sensitivity"] = input_manager.cast_sensitivity
	return _write_json(SETTINGS_PATH, data)


func load_settings() -> bool:
	var data := _read_json(SETTINGS_PATH)
	if data.is_empty():
		return false
	var game_manager := _autoload("GameManager")
	if game_manager != null:
		var volume := _clean_volume(data.get("volume"))
		if not volume.is_empty():
			game_manager.call("apply_volume_settings", volume)
	var input_manager := _autoload("InputManager")
	if input_manager != null and data.has("cast_sensitivity"):
		input_manager.cast_sensitivity = float(data.get("cast_sensitivity", 1.0))
	return true


# ============================================================================
# INTERNAL
# ============================================================================

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.%s" % [slot, SAVE_EXTENSION]


func _autoload(autoload_name: String) -> Node:
	return get_node_or_null("/root/" + autoload_name)


func _reset_player_state() -> void:
	_unlock_flags = []
	_owned_rods = NEW_GAME_OWNED_ROD_IDS.duplicate()
	_caught_fish = []
	_equipped_rod = NEW_GAME_EQUIPPED_ROD
	_equipped_bait = NEW_GAME_EQUIPPED_BAIT
	_difficulty = NEW_GAME_DIFFICULTY
	_saved_scene = DEFAULT_START_SCENE


func _db_knows(method: String, id: String) -> bool:
	var db := _autoload("GameDB")
	if db == null or not bool(db.get("is_loaded")):
		return true
	return bool(db.call(method, id))


func _clean_flags(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		push_warning("SaveManager: unlock_flags is not a list; ignored.")
		return result
	for flag in raw:
		if flag is String and _slug_regex.search(flag) != null:
			if not result.has(flag):
				result.append(flag)
		else:
			push_warning("SaveManager: dropped invalid unlock flag '%s'." % str(flag))
	return result


func _clean_ids(raw: Variant, method: String, label: String) -> Array:
	var result: Array = []
	if not (raw is Array):
		push_warning("SaveManager: %s list is not a list; ignored." % label)
		return result
	for id in raw:
		if not (id is String):
			push_warning("SaveManager: dropped a non-text %s id." % label)
		elif not _db_knows(method, id):
			push_warning("SaveManager: dropped unknown %s id '%s'." % [label, id])
		elif not result.has(id):
			result.append(id)
	return result


func _clean_volume(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for key in VOLUME_KEYS:
		var value: Variant = raw.get(key)
		if value is float or value is int:
			result[key] = clampf(float(value), 0.0, 1.0)
	return result


func _write_json(path: String, data: Dictionary) -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s'." % tmp_path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("SaveManager: could not finish writing '%s'." % path)
		return false
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read '%s'." % path)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		push_warning("SaveManager: '%s' is corrupt; ignoring it." % path)
		return {}
	return data
