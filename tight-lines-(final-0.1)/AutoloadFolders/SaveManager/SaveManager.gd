extends Node
# ============================================================================
# SAVE MANAGER (GODOT)  — TightLines                                  (Ver. 3.2)
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
#                     back the state of the other modules (inventory, quests).
#                     save_slot(slot) and load_slot(slot) combine both. Owns
#                     the player state that has no other home: saved scene,
#                     difficulty, unlock flags, owned rods, equipped rod,
#                     equipped bait, caught fish.
#   3. SETTINGS       Volume lives in its OWN global file, user://settings.json
#                     (C3), NOT in slot files. save_settings() / load_settings();
#                     volume is applied at startup with call_deferred.
#
# Ver. 3.2: quest progress is saved under data["quests"] (QuestManager).
# ============================================================================

signal slot_saved(slot: int)
signal slot_loaded(slot: int)
signal unlock_flag_added(flag: String)
signal equipment_changed   # owned rods, equipped rod or equipped bait changed
signal difficulty_changed(difficulty: String)
signal fish_caught(fish_id: String)
signal fish_record_broken(fish_id: String, size_cm: float, weight_kg: float)
signal fish_tank_changed
signal money_changed(amount: int)

const SAVE_DIR := "user://saves/"
const SETTINGS_PATH := "user://settings.json"
const SAVE_EXTENSION := "json"
const SAVE_FORMAT_VERSION := 1
const SETTINGS_FORMAT_VERSION := 1
const VOLUME_KEYS := ["master", "music", "sfx"]

# --- What a brand-new game starts with (D10) ---
const NEW_GAME_OWNED_ROD_IDS: Array = ["rod_light"]
const NEW_GAME_EQUIPPED_ROD := "rod_light"
const NEW_GAME_EQUIPPED_BAIT := "bait_1"
const NEW_GAME_DIFFICULTY := "casual"
const NEW_GAME_STARTER_MONEY := 0
const NEW_GAME_STARTER_ITEMS: Dictionary = {"bait_1": 10}

const DEFAULT_START_SCENE := "overworld_house_2"
const NON_SAVABLE_SCENES := ["main_menu", "save_slots", "multiplayer_lobby", "multiplayer"]

# --- Player state owned here ---
var _unlock_flags: Array = []      # Array of String
var _owned_rods: Array = []        # Array of String (rod ids)
var _caught_fish: Array = []       # Array of String (fish ids)
var _fish_records: Dictionary = {} # { fish_id: { count, best_size_cm, best_weight_kg } }
var _fish_tank: Array = []         # Array of { item_id: String, meta: Dictionary }
var _equipped_rod := ""
var _equipped_bait := ""
var _difficulty := NEW_GAME_DIFFICULTY
var _saved_scene := DEFAULT_START_SCENE
var _money: int = NEW_GAME_STARTER_MONEY

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
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func slot_exists(slot: int) -> bool:
	var path := _slot_path(slot)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")


func get_slot_info(slot: int) -> Dictionary:
	var data := load_game(slot)
	if data.is_empty():
		return {
			"exists": false, "timestamp": "", "version": 0,
			"scene_id": "", "scene_name": "", "money": 0,
			"caught_count": 0, "total_fish": 0, "almanac_percent": 0,
			"day_count": 1, "clock_text": "", "difficulty": NEW_GAME_DIFFICULTY,
		}
	var scene_id := String(data.get("scene", DEFAULT_START_SCENE))
	var gm := _autoload("GameManager")
	var scene_name := String(gm.call("get_scene_display_name", scene_id)) if (gm != null and gm.has_method("get_scene_display_name")) else scene_id
	var raw_caught: Array = data.get("caught_fish", []) if data.get("caught_fish") is Array else []
	var caught: Array = []
	for fid in raw_caught:
		if fid is String and not caught.has(fid):
			caught.append(fid)
	var db := _autoload("GameDB")
	var total_fish := 0
	if db != null and bool(db.get("is_loaded")) and db.has_method("get_ids"):
		total_fish = (db.call("get_ids", "fish") as Array).size()
	var almanac_pct := int(round(float(caught.size()) / float(total_fish) * 100.0)) if total_fish > 0 else 0
	var wt: Dictionary = data.get("world_time", {}) if data.get("world_time") is Dictionary else {}
	var day_num := maxi(int(wt.get("day_count", 1)), 1)
	var total_min := posmod(int(float(wt.get("game_minutes", 480.0))), 1440)
	var clock_str := "%02d:%02d" % [(total_min / 60) % 24, total_min % 60]
	return {
		"exists": true,
		"timestamp": String(data.get("timestamp", "")),
		"version": int(data.get("version", 0)),
		"scene_id": scene_id,
		"scene_name": scene_name,
		"money": maxi(int(data.get("money", 0)), 0),
		"caught_count": caught.size(),
		"total_fish": total_fish,
		"almanac_percent": almanac_pct,
		"day_count": day_num,
		"clock_text": clock_str,
		"difficulty": String(data.get("difficulty", NEW_GAME_DIFFICULTY)).capitalize(),
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
		"money": _money,
		"unlock_flags": _unlock_flags.duplicate(),
		"owned_rods": _owned_rods.duplicate(),
		"caught_fish": _caught_fish.duplicate(),
		"fish_records": _fish_records.duplicate(true),
		"fish_tank": _fish_tank.duplicate(true),
		"equipped_rod": _equipped_rod,
		"equipped_bait": _equipped_bait,
	}
	var inventory := _autoload("InventoryManager")
	if inventory != null:
		data["inventory"] = inventory.call("to_save_data")

	# Quest progress (QuestManager owns the format).
	var quests := _autoload("QuestManager")
	if quests != null:
		data["quests"] = quests.call("to_save_data")

	# Persistent world clock & weather.
	if game_manager != null and game_manager.has_method("get_world_time_state"):
		data["world_time"] = game_manager.call("get_world_time_state")
	return data


func apply_save_data(data: Dictionary) -> void:
	_reset_player_state()
	var gm_reset := _autoload("GameManager")
	if gm_reset != null and gm_reset.get("scene_memory") is Dictionary:
		(gm_reset.get("scene_memory") as Dictionary).clear()
	var sm_reset := _autoload("StoryManager")
	if sm_reset != null and sm_reset.has_method("clear_queued_cutscenes"):
		sm_reset.call("clear_queued_cutscenes")

	# Scene.
	if data.get("scene") is String and data["scene"] != "" and not NON_SAVABLE_SCENES.has(data["scene"]):
		_saved_scene = data["scene"]

	# Difficulty.
	if data.get("difficulty") is String:
		var diff := String(data["difficulty"]).to_lower()
		if diff == "casual" or diff == "angler":
			_difficulty = diff

	# Money.
	if data.has("money") and (data["money"] is int or data["money"] is float):
		_money = maxi(int(data["money"]), 0)

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

	# Caught fish (Almanac) & Personal Best records.
	if data.has("caught_fish"):
		_caught_fish = _clean_ids(data["caught_fish"], "has_fish", "fish")
	if data.has("fish_records"):
		_fish_records = _clean_fish_records(data["fish_records"])
		for fid in _fish_records.keys():
			if not _caught_fish.has(fid):
				_caught_fish.append(fid)
	if data.has("fish_tank"):
		_fish_tank = _clean_fish_tank(data["fish_tank"])

	# Rods.
	if data.has("owned_rods"):
		var raw_rods: Array = []
		if data["owned_rods"] is Array:
			for r in data["owned_rods"]:
				if r is String:
					raw_rods.append(_migrate_rod_id(r))
		_owned_rods = _clean_ids(raw_rods, "has_rod", "rod")
	if _owned_rods.is_empty() and _db_knows("has_rod", NEW_GAME_EQUIPPED_ROD):
		_owned_rods.append(NEW_GAME_EQUIPPED_ROD)
	var rod := _migrate_rod_id(String(data["equipped_rod"])) if data.get("equipped_rod") is String else _equipped_rod
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
	if bait == "" and _db_knows("has_bait", NEW_GAME_EQUIPPED_BAIT):
		bait = NEW_GAME_EQUIPPED_BAIT
	_equipped_bait = bait

	# Quests. Kept LAST on purpose: loading can complete a quest, and that
	# gives rewards (rods, bait, unlock flags) that the blocks above would
	# otherwise overwrite. A missing/invalid "quests" section = new quests (D8).
	var quests := _autoload("QuestManager")
	if quests != null:
		var quest_data: Dictionary = data["quests"] if data.get("quests") is Dictionary else {}
		quests.call("load_save_data", quest_data)
		if quests.has_method("claim_pending_rewards"):
			quests.call("claim_pending_rewards")

	# World clock & weather.
	var gm := _autoload("GameManager")
	if gm != null:
		if data.get("world_time") is Dictionary and gm.has_method("set_world_time_state"):
			gm.call("set_world_time_state", data["world_time"])
		elif gm.has_method("reset_world_time"):
			gm.call("reset_world_time")

	equipment_changed.emit()
	difficulty_changed.emit(_difficulty)
	money_changed.emit(_money)
	fish_tank_changed.emit()


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
	# apply_save_data({}) also resets QuestManager, which makes every
	# questline starter IN_PROGRESS.
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


func record_fish_catch(fish_id: String, size_cm: float, weight_kg: float = -1.0) -> Dictionary:
	if not _db_knows("has_fish", fish_id):
		push_warning("SaveManager: unknown fish id '%s'." % fish_id)
		return {"is_new_species": false, "is_new_record": false, "trophy_tier": "", "record": {}}
	var clean_size := snappedf(maxf(size_cm, 0.0), 0.1)
	var clean_weight := weight_kg
	if clean_weight < 0.0:
		var db := _autoload("GameDB")
		if db != null and bool(db.get("is_loaded")) and db.has_method("get_weight_for_size_kg"):
			clean_weight = float(db.call("get_weight_for_size_kg", fish_id, clean_size))
		else:
			clean_weight = 0.0
	clean_weight = maxf(clean_weight, 0.0)

	var is_new_species := record_caught_fish(fish_id)
	var rec: Dictionary = _fish_records.get(fish_id, {
		"count": 0,
		"best_size_cm": 0.0,
		"best_weight_kg": 0.0,
	})
	var prev_best := snappedf(float(rec.get("best_size_cm", 0.0)), 0.1)
	rec["count"] = int(rec.get("count", 0)) + 1
	var is_new_record := (not is_new_species) and (clean_size > prev_best)
	if clean_size > prev_best:
		rec["best_size_cm"] = clean_size
		rec["best_weight_kg"] = snappedf(clean_weight, 0.01)
	_fish_records[fish_id] = rec
	if is_new_record:
		fish_record_broken.emit(fish_id, float(rec["best_size_cm"]), float(rec["best_weight_kg"]))
	return {
		"is_new_species": is_new_species,
		"is_new_record": is_new_record,
		"trophy_tier": get_trophy_tier(fish_id, clean_size),
		"record": rec.duplicate(true),
	}


func get_fish_record(fish_id: String) -> Dictionary:
	if not _fish_records.has(fish_id):
		return {"count": 1 if _caught_fish.has(fish_id) else 0, "best_size_cm": 0.0, "best_weight_kg": 0.0}
	return (_fish_records[fish_id] as Dictionary).duplicate(true)


func get_trophy_tier(fish_id: String, size_cm: float) -> String:
	var db := _autoload("GameDB")
	if db == null or not bool(db.get("is_loaded")) or not bool(db.call("has_fish", fish_id)):
		return ""
	var fish: Object = db.call("get_fish", fish_id)
	if fish == null:
		return ""
	var lo := float(fish.get("min_size"))
	var hi := float(fish.get("max_size"))
	if hi <= lo:
		return "Bronze"
	var ratio := clampf((size_cm - lo) / (hi - lo), 0.0, 1.0)
	if ratio >= 0.90:
		return "Gold"
	if ratio >= 0.70:
		return "Silver"
	if ratio >= 0.50:
		return "Bronze"
	return ""


# ============================================================================
# FISH TANK
# ============================================================================

func get_fish_tank() -> Array:
	return _fish_tank.duplicate(true)


func add_tank_fish(fish_id: String, meta: Dictionary = {}) -> bool:
	if not _db_knows("has_fish", fish_id):
		push_warning("SaveManager: unknown fish id '%s'." % fish_id)
		return false
	_fish_tank.append({
		"item_id": fish_id,
		"meta": meta.duplicate(true),
	})
	fish_tank_changed.emit()
	return true


func remove_tank_fish(index: int) -> Dictionary:
	if index < 0 or index >= _fish_tank.size():
		return {}
	var entry: Dictionary = (_fish_tank[index] as Dictionary).duplicate(true)
	_fish_tank.remove_at(index)
	fish_tank_changed.emit()
	return entry


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
# CURRENCY (MONEY)
# ============================================================================

func get_money() -> int:
	return _money


func set_money(amount: int) -> void:
	var clean := maxi(amount, 0)
	if _money != clean:
		_money = clean
		money_changed.emit(_money)


func add_money(amount: int) -> void:
	if amount <= 0:
		return
	_money += amount
	money_changed.emit(_money)


func can_afford(amount: int) -> bool:
	return _money >= maxi(amount, 0)


func spend_money(amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if _money < amount:
		return false
	_money -= amount
	money_changed.emit(_money)
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
		input_manager.cast_sensitivity = clampf(float(data.get("cast_sensitivity", 0.5)), 0.0, 1.0)
	return true


# ============================================================================
# INTERNAL
# ============================================================================

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.%s" % [slot, SAVE_EXTENSION]


func _autoload(autoload_name: String) -> Node:
	return get_node_or_null("/root/" + autoload_name)


func reset_state() -> void:
	_reset_player_state()
	var gm := _autoload("GameManager")
	if gm != null and gm.get("scene_memory") is Dictionary:
		(gm.get("scene_memory") as Dictionary).clear()
	var sm := _autoload("StoryManager")
	if sm != null and sm.has_method("clear_queued_cutscenes"):
		sm.call("clear_queued_cutscenes")


func _reset_player_state() -> void:
	_unlock_flags = []
	_owned_rods = NEW_GAME_OWNED_ROD_IDS.duplicate()
	_caught_fish = []
	_fish_records = {}
	_fish_tank = []
	_equipped_rod = NEW_GAME_EQUIPPED_ROD
	_equipped_bait = NEW_GAME_EQUIPPED_BAIT
	_difficulty = NEW_GAME_DIFFICULTY
	_saved_scene = DEFAULT_START_SCENE
	_money = NEW_GAME_STARTER_MONEY
	var gm := _autoload("GameManager")
	if gm != null and gm.get("scene_memory") is Dictionary:
		(gm.get("scene_memory") as Dictionary).clear()
	var sm := _autoload("StoryManager")
	if sm != null and sm.has_method("clear_queued_cutscenes"):
		sm.call("clear_queued_cutscenes")


func _migrate_rod_id(rod_id: String) -> String:
	match rod_id:
		"rod_basic":
			return "rod_light"
		"rod_sturdy":
			return "rod_medium"
	return rod_id


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


func _clean_fish_records(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for raw_id in raw:
		var fid := String(raw_id)
		if not _db_knows("has_fish", fid):
			continue
		var entry: Variant = raw[raw_id]
		if not (entry is Dictionary):
			continue
		result[fid] = {
			"count": maxi(int(entry.get("count", 1)), 1),
			"best_size_cm": maxf(float(entry.get("best_size_cm", 0.0)), 0.0),
			"best_weight_kg": maxf(float(entry.get("best_weight_kg", 0.0)), 0.0),
		}
	return result


func _clean_fish_tank(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array):
		push_warning("SaveManager: fish_tank is not a list; ignored.")
		return result
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var fid := String(entry.get("item_id", ""))
		if fid == "" or not _db_knows("has_fish", fid):
			push_warning("SaveManager: dropped unknown tank fish '%s'." % fid)
			continue
		var meta: Dictionary = (entry["meta"] as Dictionary).duplicate(true) if entry.get("meta") is Dictionary else {}
		if meta.has("size_cm"):
			meta["size_cm"] = maxf(float(meta["size_cm"]), 0.0)
		result.append({
			"item_id": fid,
			"meta": meta,
		})
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
	var bak_path := path + ".bak"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s'." % tmp_path)
		return false
	file.store_string(JSON.stringify(data))
	var write_err := file.get_error()
	file.flush()
	file.close()
	if write_err != OK:
		push_error("SaveManager: write error (%d) on '%s'." % [write_err, tmp_path])
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return false

	var had_existing := FileAccess.file_exists(path)
	if had_existing:
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var bak_err := DirAccess.rename_absolute(path, bak_path)
		if bak_err != OK:
			DirAccess.remove_absolute(path)

	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		if FileAccess.file_exists(bak_path):
			DirAccess.rename_absolute(bak_path, path)
		push_error("SaveManager: could not finish writing '%s'." % path)
		return false

	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	return true


func _read_json(path: String) -> Dictionary:
	var read_path := path
	if not FileAccess.file_exists(read_path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(path + ".bak", path)
		elif FileAccess.file_exists(path + ".tmp"):
			DirAccess.rename_absolute(path + ".tmp", path)
		if not FileAccess.file_exists(path):
			if FileAccess.file_exists(path + ".bak"):
				read_path = path + ".bak"
			elif FileAccess.file_exists(path + ".tmp"):
				read_path = path + ".tmp"
			else:
				return {}
	var file := FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read '%s'." % read_path)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		push_warning("SaveManager: '%s' is corrupt; ignoring it." % read_path)
		return {}
	return data
