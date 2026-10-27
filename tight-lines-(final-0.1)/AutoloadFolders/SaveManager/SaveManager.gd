extends Node
# ============================================================================
# SAVE MANAGER (GODOT)  — TightLines                                  (Ver. 3)
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
#                     has no other home: unlock flags, owned rods, equipped rod,
#                     equipped bait.
#   3. SETTINGS       Volume lives in its OWN global file, user://settings.json
#                     (C3), NOT in slot files. save_settings() / load_settings();
#                     volume is applied at startup with call_deferred.
#
# RULES FROM DECISIONS.md
#   C2   Slot files are user://saves/slot_N.json.
#   C3   Volume in user://settings.json.
#   D2   Saves store NO scene. Loading a slot always opens "overworld": the
#        caller (Save Slots screen / GameManager) does
#        GameManager.change_scene("overworld") after load_slot() succeeds.
#   D8   Old saves are ignored: a "version" field is written, but a file is
#        NEVER refused for being old. A missing section resets that module.
#   D10  A new game must give the player a way to get bait: see the
#        NEW_GAME_* constants below (fill in once GameDB has starter ids).
#   D11  Unlock flags are granted by QuestManager through add_unlock_flag().
#   Sec. 4  add_unlock_flag / has_unlock_flag / get_unlock_flags, plus
#        owned_rods, equipped_rod, equipped_bait are saved in every slot.
#
# SLOT FILE (JSON):
#   { "version": 1, "timestamp": "...",
#     "inventory": { ... InventoryManager.to_save_data() ... },
#     "unlock_flags": ["unlock_dock"], "owned_rods": ["rod_basic"],
#     "equipped_rod": "rod_basic", "equipped_bait": "bait_worm" }
# Loaded data is VALIDATED: unknown or malformed ids and flags are dropped with
# a warning. Currency, fish log and quest progress get added to
# build_save_data() / apply_save_data() when those modules exist.
# ============================================================================

signal slot_saved(slot: int)
signal slot_loaded(slot: int)
signal unlock_flag_added(flag: String)
signal equipment_changed   # owned rods, equipped rod or equipped bait changed

const SAVE_DIR := "user://saves/"
const SETTINGS_PATH := "user://settings.json"
const SAVE_EXTENSION := "json"
# Written into every file for the future. Files are never refused over it (D8).
const SAVE_FORMAT_VERSION := 1
const SETTINGS_FORMAT_VERSION := 1
const VOLUME_KEYS := ["master", "music", "sfx"]

# --- What a brand-new game starts with (D10) --------------------------------
# Left empty on purpose: the real ids come from GameDB's starter bait / starting
# rod (DECISIONS.md section 6, GameDatabase to-do 5). Example once they exist:
#   NEW_GAME_OWNED_ROD_IDS = ["rod_basic"]
#   NEW_GAME_EQUIPPED_ROD  = "rod_basic"
#   NEW_GAME_EQUIPPED_BAIT = "bait_worm"
#   NEW_GAME_STARTER_ITEMS = {"bait_worm": 10}   # added to the Tackle Box
const NEW_GAME_OWNED_ROD_IDS: Array = []
const NEW_GAME_EQUIPPED_ROD := ""
const NEW_GAME_EQUIPPED_BAIT := ""
const NEW_GAME_STARTER_ITEMS: Dictionary = {}

# --- Player state owned here ------------------------------------------------
var _unlock_flags: Array = []      # Array of String
var _owned_rods: Array = []        # Array of String (rod ids)
var _equipped_rod := ""
var _equipped_bait := ""

var _slug_regex := RegEx.new()     # same rule as GameDB: lowercase snake_case


func _ready() -> void:
	_slug_regex.compile("^[a-z][a-z0-9_]*$")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_reset_player_state()
	# Deferred (C3): GameManager must exist before volume can be applied.
	load_settings.call_deferred()


# ============================================================================
# SLOT STORAGE
# ============================================================================

# Writes `data` to a slot. Returns true on success. Does NOT change `data`
# (a copy gets the "version" and "timestamp" fields).
func save_game(slot: int, data: Dictionary) -> bool:
	var to_write := data.duplicate(true)
	to_write["version"] = SAVE_FORMAT_VERSION
	to_write["timestamp"] = Time.get_datetime_string_from_system()
	return _write_json(_slot_path(slot), to_write)


# Returns the slot's data, or an empty Dictionary if the slot is empty or the
# file is unreadable.
func load_game(slot: int) -> Dictionary:
	return _read_json(_slot_path(slot))


func delete_save(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


# For the Save Slots screen: {"exists": bool, "timestamp": String, "version": int}.
# (No "outdated" flag: old saves are never refused, D8.)
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

# Collects the state of every module that is registered.
func build_save_data() -> Dictionary:
	var data := {
		"unlock_flags": _unlock_flags.duplicate(),
		"owned_rods": _owned_rods.duplicate(),
		"equipped_rod": _equipped_rod,
		"equipped_bait": _equipped_bait,
	}
	var inventory := _autoload("InventoryManager")
	if inventory != null:
		data["inventory"] = inventory.call("to_save_data")
	return data


# Hands loaded data back to the modules, validating as it goes. A missing
# section resets that module to its new-game state (D8). Safe to call with {}.
func apply_save_data(data: Dictionary) -> void:
	_reset_player_state()

	# Inventory (InventoryManager validates item ids and positions itself).
	var inventory := _autoload("InventoryManager")
	if inventory != null:
		if data.get("inventory") is Dictionary:
			inventory.call("load_save_data", data["inventory"])
		else:
			inventory.call("clear_all")

	# Unlock flags.
	if data.has("unlock_flags"):
		_unlock_flags = _clean_flags(data["unlock_flags"])

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


# Saves the current game into a slot. Returns true on success.
func save_slot(slot: int) -> bool:
	var ok := save_game(slot, build_save_data())
	if ok:
		slot_saved.emit(slot)
	return ok


# Loads a slot into the game. Returns false if the slot is empty or unreadable.
# Old versions are NEVER refused (D8). The scene is not touched (D2): on
# success the caller opens the overworld with
# GameManager.change_scene("overworld").
func load_slot(slot: int) -> bool:
	var data := load_game(slot)
	if data.is_empty():
		return false
	if int(data.get("version", 0)) > SAVE_FORMAT_VERSION:
		push_warning("SaveManager: slot %d was written by a newer version of the game; loading what is understood." % slot)
	apply_save_data(data)
	slot_loaded.emit(slot)
	return true


# Resets every module to a fresh game and gives the starting items (D10).
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
# UNLOCK FLAGS  (granted by QuestManager, read by FishingManager)  — D11
# ============================================================================

# Returns true if the flag is NEW. False if it was already set, or if it is
# not valid lowercase snake_case (same rule as GameDB's unlock_flag).
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


# A COPY of every flag. Pass it straight in as the "unlocked" key of the odds
# context: context["unlocked"] = SaveManager.get_unlock_flags()
func get_unlock_flags() -> Array:
	return _unlock_flags.duplicate()


# ============================================================================
# RODS AND BAIT  (rods are not grid items, so they live here)  — section 4
# ============================================================================
# FishingManager announces a change with a signal; whoever listens calls these
# setters, then save_slot() persists them with the rest of the game.

func get_owned_rods() -> Array:
	return _owned_rods.duplicate()


func has_rod(rod_id: String) -> bool:
	return _owned_rods.has(rod_id)


# Adds a rod the player now owns (e.g. bought in the Shop). Returns true if new.
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


# The rod must be owned. Returns true on success.
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


# The bait must exist in GameDB. It does NOT have to be in the Tackle Box right
# now (it can run out); FishingManager checks the stock when casting.
func set_equipped_bait(bait_id: String) -> bool:
	if not _db_knows("has_bait", bait_id):
		push_warning("SaveManager: unknown bait id '%s'." % bait_id)
		return false
	if _equipped_bait != bait_id:
		_equipped_bait = bait_id
		equipment_changed.emit()
	return true


# ============================================================================
# SETTINGS  (global, not per slot)  — C3
# ============================================================================

# Writes the current volumes to user://settings.json. Call it when the player
# leaves the Options screen (or after a volume change).
func save_settings() -> bool:
	var game_manager := _autoload("GameManager")
	if game_manager == null:
		return false
	return _write_json(SETTINGS_PATH, {
		"version": SETTINGS_FORMAT_VERSION,
		"volume": game_manager.call("get_volume_settings"),
	})


# Reads user://settings.json and applies the volumes. Runs automatically at
# startup (deferred). Returns false if there is no usable settings file.
func load_settings() -> bool:
	var data := _read_json(SETTINGS_PATH)
	if data.is_empty():
		return false
	var game_manager := _autoload("GameManager")
	if game_manager == null:
		return false
	var volume := _clean_volume(data.get("volume"))
	if volume.is_empty():
		return false
	game_manager.call("apply_volume_settings", volume)
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
	_equipped_rod = NEW_GAME_EQUIPPED_ROD
	_equipped_bait = NEW_GAME_EQUIPPED_BAIT


# Does GameDB know this id? `method` is "has_rod" or "has_bait". If GameDB is
# not available yet the id cannot be checked, so it is accepted.
func _db_knows(method: String, id: String) -> bool:
	var db := _autoload("GameDB")
	if db == null or not bool(db.get("is_loaded")):
		return true
	return bool(db.call(method, id))


# Keeps only valid, unique lowercase snake_case strings.
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


# Keeps only unique strings that GameDB knows (`method` = "has_rod" etc.).
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


# Keeps only numeric volumes and limits them to 0.0 - 1.0.
func _clean_volume(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for key in VOLUME_KEYS:
		var value: Variant = raw.get(key)
		if value is float or value is int:
			result[key] = clampf(float(value), 0.0, 1.0)
	return result


# Writes JSON to a temp file, then replaces the real file only when the write
# is complete, so a crash mid-save cannot corrupt the old file.
func _write_json(path: String, data: Dictionary) -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s' (error %d)." % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	file.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("SaveManager: could not finish writing '%s' (error %d)." % [path, err])
		return false
	return true


# Returns the parsed file, or {} if it is missing, unreadable or corrupt.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read '%s' (error %d)." % [path, FileAccess.get_open_error()])
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		push_warning("SaveManager: '%s' is corrupt; ignoring it." % path)
		return {}
	return data
