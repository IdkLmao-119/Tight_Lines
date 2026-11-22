extends Node

# ============================================================================
# QUEST MANAGER (GODOT)  -  TightLines                                (Ver. 1)
# ============================================================================
# Autoload singleton named exactly "QuestManager". It loads LAST
# (DECISIONS.md C11): GameDB, SaveManager, ConnectionManager, InputManager,
# GameManager, InventoryManager, QuestManager.
#
# JOB: track quests through their lifecycle, count progress, hand out rewards,
# and give SaveManager one Dictionary to store. It draws no UI and reads no
# input. A quest log UI should call the query functions and listen to the
# signals below.
#
# LIFECYCLE
#     INACTIVE  ->  IN_PROGRESS  ->  COMPLETED
#   INACTIVE    : quest not given yet.
#   IN_PROGRESS : progress is tracked.
#   COMPLETED   : rewards were given (money, bait, rods, unlock flags).
#
# QUESTLINES AND BRANCHING
#   Every quest lists "prerequisites": quest ids that must ALL be COMPLETED
#   before it becomes IN_PROGRESS. A quest with NO prerequisites is the start
#   of a questline and is IN_PROGRESS from the beginning of a new game.
#       quest 1 (no prerequisites)           -> starts in progress
#       quest 2a, 2b  (prerequisite: 1)      -> BOTH start when 1 completes
#       quest 3a (prerequisite: 2a)          -> starts only when 2a completes
#       quest 3b (prerequisite: 2b)          -> starts only when 2b completes
#   Two prerequisites on one quest make a "join" (it needs both branches).
#
# QUEST TYPES (the "goal" of a quest)
#   almanac_completion : the Almanac (SaveManager caught-fish list) must contain
#                        ALL fish that match the filters. Progress = how many
#                        of them are already in the Almanac. Fish caught BEFORE
#                        the quest started count.
#   catch_count        : catch fish N times (repeats count). Fed by
#                        report_catch(), which FishingManager calls on a catch.
#   first_catch_count  : discover N fish species for the first time. Fed by
#                        SaveManager.fish_caught, which fires only the first
#                        time a species is recorded. Only discoveries made
#                        WHILE the quest is active count.
#   Filters (all optional, combined with AND):
#     location_id  : only fish in that location's fish pool ("all fish in area")
#     size_classes : only these size categories, e.g. ["small", "medium"]
#     fish_ids     : only these exact fish
#
# DATA FORMAT (see QUEST_DEFS below)
#   {
#     "id": "quest_xxx",              # lowercase snake_case, starts with quest_
#     "questline": "main_story",
#     "title": "...", "description": "...",
#     "start_text": "...",            # optional NPC line when it starts
#     "complete_text": "...",         # optional NPC line when it completes
#     "prerequisites": ["quest_yyy"],
#     "goal": {"type": "...", "location_id": "", "size_classes": [],
#              "fish_ids": [], "count": 3},
#     "rewards": {"money": 100,
#                 "bait": [{"id": "bait_worm", "count": 10}],
#                 "rods": ["rod_xxx"]},
#     "unlock_flags": ["unlock_dock"], # given to SaveManager on completion (D11)
#   }
#   For almanac_completion, "count" is optional: 0 (default) means ALL matching
#   fish; a number N means "any N of the matching fish".
#
# REWARDS NEVER GET LOST
#   If the Tackle Box is full, the leftover bait is kept as a "pending reward"
#   (saved) and retried on every scene change or claim_pending_rewards().
#   Money works the same way when SaveManager has no add_money() yet.
#
# SAVING
#   SaveManager stores to_save_data() under save["quests"] and calls
#   load_save_data() when a slot loads. load_save_data({}) = brand-new game
#   (every quest resets, questline starters become IN_PROGRESS).
# ============================================================================

# --- Signals (for the quest log UI, HUD pop-ups and other modules) ---
signal quest_activated(quest_id: String)
signal quest_progress_changed(quest_id: String, current: int, target: int)
signal quest_completed(quest_id: String)
signal questline_completed(questline_id: String)
# summary: {money, bait: {id: count}, rods: [ids], unlock_flags: [flags],
#           pending_money, pending_bait: {id: count}}
signal rewards_granted(quest_id: String, summary: Dictionary)
signal quests_changed   # anything changed (use this to redraw a quest log)

# --- Constants ---
const STATE_INACTIVE := "inactive"
const STATE_IN_PROGRESS := "in_progress"
const STATE_COMPLETED := "completed"

const TYPE_ALMANAC := "almanac_completion"
const TYPE_CATCH_COUNT := "catch_count"
const TYPE_FIRST_CATCH := "first_catch_count"
const QUEST_TYPES := [TYPE_ALMANAC, TYPE_CATCH_COUNT, TYPE_FIRST_CATCH]

const ID_PREFIX := "quest_"
const SAVE_VERSION := 1

# ============================================================================
# QUEST DATA  -  edit this block to add or change quests
# ============================================================================
# The sample below shows a branching questline using only size categories, so
# it works with any fish data. To give bait or rods, add (ids must exist in
# GameDB):
#     "rewards": {"money": 100,
#                 "bait": [{"id": "bait_worm", "count": 10}],
#                 "rods": ["rod_xxx"]},
# A bad reference is reported with push_error and that reward is skipped.
const QUEST_DEFS: Array = [
	# --- Main Story (linear progression) ---
	{
		"id": "quest_gear_up",
		"questline": "main_story",
		"title": "Tight Lines: Marikina River",
		"description": "Catch every small fish in the Marikina River.",
		"start_text": "I'll fill these pages. As many as I can.",
		"complete_text": "That's the last one! Next stop, Imus.",
		"prerequisites": [],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_marikina",
			"size_classes": ["small"],
		},
		"rewards": {
			"money": 100,
			"bait": [{"id": "bait_1", "count": 5}],
		},
		"unlock_flags": ["unlock_imus"],
	},
	{
		"id": "quest_paddy_page",
		"questline": "main_story",
		"title": "Paddy Page",
		"description": "Catch every small fish in the Imus rice fields.",
		"start_text": "Find out what lives in the Imus rice field.",
		"complete_text": "Every blank is a name now. Kawit is next.",
		"prerequisites": ["quest_gear_up"],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_imus",
			"size_classes": ["small"],
		},
		"rewards": {"money": 150},
		"unlock_flags": ["unlock_kawit"],
	},
	{
		"id": "quest_salt_and_sea",
		"questline": "main_story",
		"title": "Salt and Sea",
		"description": "Catch every small fish at the Kawit seaside.",
		"start_text": "Imus taught me patience. Let's see if it's enough out here.",
		"complete_text": "That's all of Kawit. Next up, Noveleta.",
		"prerequisites": ["quest_paddy_page"],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_kawit",
			"size_classes": ["small"],
		},
		"rewards": {"money": 200},
		"unlock_flags": ["unlock_fish_pens"],
	},
	{
		"id": "quest_fenced_in",
		"questline": "main_story",
		"title": "Fenced In",
		"description": "Catch every small and medium fish in the Noveleta fishing pen.",
		"start_text": "Catch every small and medium fish in the Noveleta fishing pen.",
		"complete_text": "Something white is shining way over there... the salt farm.",
		"prerequisites": ["quest_salt_and_sea"],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_fish_pens",
			"size_classes": ["small", "medium"],
		},
		"rewards": {"money": 250},
		"unlock_flags": ["unlock_salt_farm"],
	},
	{
		"id": "quest_bright_water",
		"questline": "main_story",
		"title": "Bright Water",
		"description": "Catch every small and medium fish in the Noveleta salt farm.",
		"start_text": "Catch every small and medium fish in the Noveleta salt farm.",
		"complete_text": "All of Cavite is done. Batangas next.",
		"prerequisites": ["quest_fenced_in"],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_salt_farm",
			"size_classes": ["small", "medium"],
		},
		"rewards": {"money": 300},
		"unlock_flags": ["unlock_cavite_complete", "unlock_calatagan"],
	},
	{
		"id": "quest_roots",
		"questline": "main_story",
		"title": "Roots",
		"description": "Catch every fish in the Calatagan mangrove forest.",
		"start_text": "Quiet water, tight spaces. I'll have to be careful with my casts.",
		"complete_text": "Time to leave the mangroves and head out to Fortune Island.",
		"prerequisites": ["quest_bright_water"],
		"goal": {
			"type": "almanac_completion",
			"location_id": "location_calatagan",
		},
		"rewards": {"money": 400},
		"unlock_flags": ["unlock_fortune_island"],
	},
	{
		"id": "quest_deep_giants",
		"questline": "main_story",
		"title": "The Unfinished Almanac",
		"description": "Complete 100% of the Philippine Fish Almanac.",
		"start_text": "Bigger fish, deeper water. Let's see if I'm ready for it.",
		"complete_text": "Another page unlocked... ??? on the Map.",
		"prerequisites": ["quest_roots"],
		"goal": {
			"type": "almanac_completion",
		},
		"rewards": {"money": 500},
		"unlock_flags": ["unlock_ending_home"],
	},

	# --- Optional Side Quests (one per area) ---
	{
		"id": "quest_pocket_change",
		"questline": "side_quests",
		"title": "Pocket Change",
		"description": "Catch 5 fish in the Marikina River to earn extra pesos.",
		"prerequisites": [],
		"goal": {"type": "catch_count", "location_id": "location_marikina", "count": 5},
		"rewards": {"money": 75},
	},
	{
		"id": "quest_bait_tester",
		"questline": "side_quests",
		"title": "Bait Tester",
		"description": "Discover 3 fish species in the Imus rice fields.",
		"prerequisites": ["quest_gear_up"],
		"goal": {"type": "first_catch_count", "location_id": "location_imus", "count": 3},
		"rewards": {
			"money": 100,
			"bait": [{"id": "bait_2", "count": 5}],
		},
	},
	{
		"id": "quest_big_sea_catch",
		"questline": "side_quests",
		"title": "Big Sea Catch",
		"description": "Catch 5 fish at the Kawit seaside.",
		"prerequisites": ["quest_paddy_page"],
		"goal": {"type": "catch_count", "location_id": "location_kawit", "count": 5},
		"rewards": {"money": 150},
	},
	{
		"id": "quest_steady_hands",
		"questline": "side_quests",
		"title": "Steady Hands",
		"description": "Catch 8 fish in the Noveleta fishing pen.",
		"prerequisites": ["quest_salt_and_sea"],
		"goal": {"type": "catch_count", "location_id": "location_fish_pens", "count": 8},
		"rewards": {"money": 175},
	},
	{
		"id": "quest_all_day_angler",
		"questline": "side_quests",
		"title": "All-Day Angler",
		"description": "Catch 10 fish in the Noveleta salt farm.",
		"prerequisites": ["quest_fenced_in"],
		"goal": {"type": "catch_count", "location_id": "location_salt_farm", "count": 10},
		"rewards": {"money": 200},
	},
	{
		"id": "quest_rainy_catch",
		"questline": "side_quests",
		"title": "Rainy Catch",
		"description": "Discover 3 fish species in the Calatagan mangrove forest.",
		"prerequisites": ["quest_bright_water"],
		"goal": {"type": "first_catch_count", "location_id": "location_calatagan", "count": 3},
		"rewards": {"money": 250},
	},
	{
		"id": "quest_night_fisher",
		"questline": "side_quests",
		"title": "Night Fisher",
		"description": "Catch 5 fish at Fortune Island.",
		"prerequisites": ["quest_roots"],
		"goal": {"type": "catch_count", "location_id": "location_fortune_island", "count": 5},
		"rewards": {"money": 300},
	},
]

# --- Internal state ---
var _defs: Dictionary = {}            # { quest_id: cleaned definition }
var _order: Array = []                # quest ids in authored order
var _states: Dictionary = {}          # { quest_id: STATE_* }  (missing = inactive)
var _progress: Dictionary = {}        # { quest_id: int }  (almanac is computed live)
var _pending_bait: Dictionary = {}    # { bait_id: count } waiting for room
var _last_catch_spot_id: String = ""
var _unlocked_on_current_catch: Array[String] = []
var _in_catch_event := false

var _evaluating := false              # guards re-entrant unlock checks
var _reevaluate := false
var _slug_regex := RegEx.new()        # same rule as GameDB / SaveManager


func _ready() -> void:
	_slug_regex.compile("^[a-z][a-z0-9_]*$")
	_connect_modules()
	load_definitions(QUEST_DEFS)


# ============================================================================
# SETUP
# ============================================================================

# Cleans and validates quest data, then starts a fresh game state.
# Bad quests are reported with push_error and left out (the rest still work).
# Safe to call again (e.g. tests); it resets all quest progress.
func load_definitions(defs: Array) -> void:
	var candidates: Dictionary = {}
	var order: Array = []
	for raw in defs:
		var def := _normalize_def(raw)
		if def.is_empty():
			continue
		if candidates.has(def["id"]):
			push_error("QuestManager: duplicate quest id '%s'; the second one is ignored." % def["id"])
			continue
		candidates[def["id"]] = def
		order.append(def["id"])

	# Keep only quests whose prerequisites can all be reached. This drops
	# quests with a missing prerequisite or a cycle (A needs B, B needs A).
	var resolved: Dictionary = {}
	var progressed := true
	while progressed:
		progressed = false
		for id in order:
			if resolved.has(id):
				continue
			var ok := true
			for pre in candidates[id]["prerequisites"]:
				if not resolved.has(pre):
					ok = false
					break
			if ok:
				resolved[id] = true
				progressed = true
	_defs = {}
	_order = []
	for id in order:
		if resolved.has(id):
			_defs[id] = candidates[id]
			_order.append(id)
		else:
			push_error("QuestManager: quest '%s' dropped: a prerequisite is missing or the prerequisites form a loop." % id)

	reset()


func _connect_modules() -> void:
	var save_manager := _autoload("SaveManager")
	if save_manager != null and save_manager.has_signal("fish_caught"):
		save_manager.connect("fish_caught", _on_fish_caught)
	else:
		push_warning("QuestManager: SaveManager has no 'fish_caught' signal; first_catch_count and almanac quests will not update.")

	var game_manager := _autoload("GameManager")
	if game_manager != null and game_manager.has_signal("scene_changed"):
		game_manager.connect("scene_changed", _on_scene_changed)


# ============================================================================
# EVENTS FROM OTHER MODULES
# ============================================================================

func set_current_spot_id(spot_id: String) -> void:
	_last_catch_spot_id = spot_id


func _resolve_current_spot_id() -> String:
	if _last_catch_spot_id != "":
		return _last_catch_spot_id
	if get_tree() != null and get_tree().current_scene != null:
		var fm := get_tree().current_scene.find_child("FishingManager", true, false)
		if fm != null and fm.has_method("get_context"):
			var ctx: Variant = fm.call("get_context")
			if ctx is Dictionary:
				return String((ctx as Dictionary).get("spot_id", ""))
	return ""


# FishingManager calls this ONCE for every fish the player catches (repeats
# included). `spot_id` is the fishing location id, if known.
#     QuestManager.report_catch(fish_id, size_cm, spot_id)
func report_catch(fish_id: String, _size_cm: float = 0.0, spot_id: String = "") -> void:
	if spot_id != "":
		_last_catch_spot_id = spot_id
	var eff_spot := spot_id if spot_id != "" else _resolve_current_spot_id()
	var prev_in_catch := _in_catch_event
	_in_catch_event = true
	for id in _ids_in_state(STATE_IN_PROGRESS):
		if _unlocked_on_current_catch.has(id):
			continue
		if _states.get(id, STATE_INACTIVE) != STATE_IN_PROGRESS:
			continue   # an earlier quest in this loop may have changed things
		var goal: Dictionary = _defs[id]["goal"]
		if goal["type"] == TYPE_CATCH_COUNT and _fish_matches(goal, fish_id, eff_spot):
			_add_progress(id, 1)
	_in_catch_event = prev_in_catch
	_unlocked_on_current_catch.clear()


# SaveManager.fish_caught: fires only the FIRST time a species is recorded.
func _on_fish_caught(fish_id: String) -> void:
	_unlocked_on_current_catch.clear()
	var spot_id := _resolve_current_spot_id()
	var prev_in_catch := _in_catch_event
	_in_catch_event = true
	for id in _ids_in_state(STATE_IN_PROGRESS):
		if _unlocked_on_current_catch.has(id):
			continue
		if _states.get(id, STATE_INACTIVE) != STATE_IN_PROGRESS:
			continue
		var goal: Dictionary = _defs[id]["goal"]
		match goal["type"]:
			TYPE_FIRST_CATCH:
				if _fish_matches(goal, fish_id, spot_id):
					_add_progress(id, 1)
			TYPE_ALMANAC:
				_check_progress(id)
	_in_catch_event = prev_in_catch


func _on_scene_changed(_scene_id: String) -> void:
	claim_pending_rewards()


# ============================================================================
# QUERIES (for the quest log UI)
# ============================================================================

func has_quest(quest_id: String) -> bool:
	return _defs.has(quest_id)


func get_state(quest_id: String) -> String:
	if not _defs.has(quest_id):
		return STATE_INACTIVE
	return String(_states.get(quest_id, STATE_INACTIVE))


func is_inactive(quest_id: String) -> bool:
	return get_state(quest_id) == STATE_INACTIVE


func is_in_progress(quest_id: String) -> bool:
	return get_state(quest_id) == STATE_IN_PROGRESS


func is_completed(quest_id: String) -> bool:
	return get_state(quest_id) == STATE_COMPLETED


# Quest ids in authored order. Pass a STATE_* to filter ("" = all quests).
func get_quest_ids(state: String = "") -> Array:
	if state == "":
		return _order.duplicate()
	return _ids_in_state(state)


# {"current": int, "target": int}. A completed quest reports target/target.
func get_progress(quest_id: String) -> Dictionary:
	if not _defs.has(quest_id):
		return {"current": 0, "target": 0}
	var target := _target_of(quest_id)
	match get_state(quest_id):
		STATE_COMPLETED:
			return {"current": target, "target": target}
		STATE_IN_PROGRESS:
			return {"current": mini(_current_of(quest_id), target), "target": target}
	return {"current": 0, "target": target}


# One COPY of everything a UI needs: the definition plus "state", "current"
# and "target". Empty Dictionary if the quest is unknown.
func get_quest_info(quest_id: String) -> Dictionary:
	if not _defs.has(quest_id):
		return {}
	var info: Dictionary = (_defs[quest_id] as Dictionary).duplicate(true)
	var p := get_progress(quest_id)
	info["state"] = get_state(quest_id)
	info["current"] = p["current"]
	info["target"] = p["target"]
	return info


func get_questline_ids() -> Array:
	var lines: Array = []
	for id in _order:
		var line: String = _defs[id]["questline"]
		if not lines.has(line):
			lines.append(line)
	return lines


func get_questline_quests(questline_id: String) -> Array:
	var result: Array = []
	for id in _order:
		if _defs[id]["questline"] == questline_id:
			result.append(id)
	return result


func is_questline_complete(questline_id: String) -> bool:
	var ids := get_questline_quests(questline_id)
	if ids.is_empty():
		return false
	for id in ids:
		if not is_completed(id):
			return false
	return true


# ============================================================================
# PENDING REWARDS
# ============================================================================

# Tries again to hand over bait that did not fit.
# Called automatically on every scene change; a UI may also call it.
func claim_pending_rewards() -> void:
	var changed := false
	for bait_id in _pending_bait.keys():
		var wanted := int(_pending_bait[bait_id])
		var left := _give_bait(String(bait_id), wanted)
		if left != wanted:
			changed = true
		if left <= 0:
			_pending_bait.erase(bait_id)
		else:
			_pending_bait[bait_id] = left
	if changed:
		quests_changed.emit()


func has_pending_rewards() -> bool:
	return not _pending_bait.is_empty()


# ============================================================================
# SAVE / LOAD  (JSON-friendly; hand this to SaveManager)
# ============================================================================

# Returns a plain Dictionary safe to write as JSON. SaveManager stores it as
#     data["quests"] = QuestManager.to_save_data()
func to_save_data() -> Dictionary:
	var states := {}
	var progress := {}
	for id in _order:
		var state := get_state(id)
		if state == STATE_INACTIVE:
			continue
		states[id] = state
		var goal: Dictionary = _defs[id]["goal"]
		if state == STATE_IN_PROGRESS and goal["type"] != TYPE_ALMANAC:
			progress[id] = int(_progress.get(id, 0))
	return {
		"version": SAVE_VERSION,
		"states": states,
		"progress": progress,
		"pending_bait": _pending_bait.duplicate(),
	}


# Rebuilds quest state from saved data. JSON turns numbers into floats, so
# they are converted back. Quests that no longer exist are dropped with a
# warning. A missing/empty Dictionary means a brand-new game (D8). Call this
# AFTER the inventory and the Almanac (caught fish) have been loaded, so
# almanac quests see the right data.
func load_save_data(data: Dictionary) -> void:
	_clear_state()

	var states: Variant = data.get("states", {})
	if states is Dictionary:
		for raw_id in states:
			var id := String(raw_id)
			var state := String(states[raw_id])
			if not _defs.has(id):
				push_warning("QuestManager: dropped unknown quest '%s' while loading." % id)
				continue
			if state != STATE_IN_PROGRESS and state != STATE_COMPLETED:
				push_warning("QuestManager: quest '%s' had invalid state '%s'; reset." % [id, state])
				continue
			_states[id] = state

	var progress: Variant = data.get("progress", {})
	if progress is Dictionary:
		for raw_id in progress:
			var id := String(raw_id)
			var goal: Dictionary = {}
			if _defs.has(id):
				goal = _defs[id]["goal"]
			if _states.get(id, "") == STATE_IN_PROGRESS and goal.get("type", "") != TYPE_ALMANAC:
				_progress[id] = clampi(int(progress[raw_id]), 0, _target_of(id))

	var pending_bait: Variant = data.get("pending_bait", {})
	if pending_bait is Dictionary:
		for raw_id in pending_bait:
			var count := int(pending_bait[raw_id])
			if count > 0:
				_pending_bait[String(raw_id)] = count

	# Re-check everything: a changed target may complete a quest, and new
	# questline starters (or quests added by a game update) may now be due.
	for id in _order:
		if get_state(id) == STATE_IN_PROGRESS:
			_check_progress(id)
	_evaluate_unlocks()
	quests_changed.emit()


# Back to a brand-new game: everything inactive, then the questline starters
# (quests with no prerequisites) become IN_PROGRESS.
func reset() -> void:
	_clear_state()
	_evaluate_unlocks()
	quests_changed.emit()


func _clear_state() -> void:
	_states.clear()
	_progress.clear()
	_pending_bait.clear()
	_last_catch_spot_id = ""
	_unlocked_on_current_catch.clear()
	_in_catch_event = false


# ============================================================================
# LIFECYCLE
# ============================================================================

# Starts every INACTIVE quest whose prerequisites are all COMPLETED. Repeats
# until nothing more changes (an almanac quest can complete the moment it
# starts, which can unlock the next one). Re-entrant calls are folded into
# the running loop.
func _evaluate_unlocks() -> void:
	if _evaluating:
		_reevaluate = true
		return
	_evaluating = true
	var again := true
	while again:
		again = false
		_reevaluate = false
		for id in _order:
			if get_state(id) != STATE_INACTIVE:
				continue
			if _prerequisites_met(id):
				_activate(id)
				again = true
		if _reevaluate:
			again = true
	_evaluating = false


func _prerequisites_met(quest_id: String) -> bool:
	for pre in _defs[quest_id]["prerequisites"]:
		if get_state(pre) != STATE_COMPLETED:
			return false
	return true


func _activate(quest_id: String) -> void:
	_states[quest_id] = STATE_IN_PROGRESS
	_progress[quest_id] = 0
	if _in_catch_event and not _unlocked_on_current_catch.has(quest_id):
		_unlocked_on_current_catch.append(quest_id)
	quest_activated.emit(quest_id)
	quests_changed.emit()
	_check_progress(quest_id)   # an almanac quest may already be satisfied


# Re-reads the progress of an in-progress quest and completes it if done.
func _check_progress(quest_id: String) -> void:
	if get_state(quest_id) != STATE_IN_PROGRESS:
		return
	var goal: Dictionary = _defs[quest_id]["goal"]
	var target := _target_of(quest_id)
	if goal["type"] == TYPE_ALMANAC:
		var current := mini(_current_of(quest_id), target)
		if current != int(_progress.get(quest_id, -1)):
			_progress[quest_id] = current
			quest_progress_changed.emit(quest_id, current, target)
			quests_changed.emit()
	if target > 0 and _current_of(quest_id) >= target:
		_complete(quest_id)


func _add_progress(quest_id: String, amount: int) -> void:
	var target := _target_of(quest_id)
	var current := mini(int(_progress.get(quest_id, 0)) + amount, target)
	_progress[quest_id] = current
	quest_progress_changed.emit(quest_id, current, target)
	quests_changed.emit()
	if current >= target:
		_complete(quest_id)


func _complete(quest_id: String) -> void:
	if get_state(quest_id) != STATE_IN_PROGRESS:
		return
	_states[quest_id] = STATE_COMPLETED
	_progress[quest_id] = _target_of(quest_id)
	var def: Dictionary = _defs[quest_id]

	var summary := _grant_rewards(def)
	quest_completed.emit(quest_id)
	rewards_granted.emit(quest_id, summary)
	quests_changed.emit()

	if is_questline_complete(def["questline"]):
		questline_completed.emit(def["questline"])

	_evaluate_unlocks()


# Debug helper: completes an in-progress quest right now (gives rewards).
func debug_complete(quest_id: String) -> void:
	_complete(quest_id)


# ============================================================================
# GOALS AND FILTERS
# ============================================================================

func _target_of(quest_id: String) -> int:
	var goal: Dictionary = _defs[quest_id]["goal"]
	if goal["type"] == TYPE_ALMANAC:
		var total := _almanac_targets(goal).size()
		var wanted := int(goal["count"])
		return mini(wanted, total) if wanted > 0 else total
	return int(goal["count"])


func _current_of(quest_id: String) -> int:
	var goal: Dictionary = _defs[quest_id]["goal"]
	if goal["type"] != TYPE_ALMANAC:
		return int(_progress.get(quest_id, 0))
	var caught: Array = []
	var save_manager := _autoload("SaveManager")
	if save_manager != null:
		caught = save_manager.call("get_caught_fish")
	var n := 0
	for fish_id in _almanac_targets(goal):
		if caught.has(fish_id):
			n += 1
	return n


# Every fish id the almanac goal asks for (empty if GameDB is not loaded).
func _almanac_targets(goal: Dictionary) -> Array:
	var result: Array = []
	var db := _db()
	if db == null:
		return result
	var ids: Array = []
	var location_id: String = goal["location_id"]
	if location_id != "":
		for entry in db.call("get_location_fish_pool", location_id):
			ids.append(String(entry.fish.id))
	else:
		ids = db.call("get_ids", "fish")
	for fish_id in ids:
		if _fish_passes(db, goal, String(fish_id)):
			result.append(String(fish_id))
	return result


# fish_ids and size_classes filters only (the location filter is separate).
func _fish_passes(db: Node, goal: Dictionary, fish_id: String) -> bool:
	var wanted: Array = goal["fish_ids"]
	if not wanted.is_empty() and not wanted.has(fish_id):
		return false
	var classes: Array = goal["size_classes"]
	if not classes.is_empty():
		if not bool(db.call("has_fish", fish_id)):
			return false
		var fish: Object = db.call("get_fish", fish_id)
		if not classes.has(String(fish.get("size_class"))):
			return false
	return true


# Does a caught fish satisfy all filters of a catch-style goal?
func _fish_matches(goal: Dictionary, fish_id: String, spot_id: String) -> bool:
	var location_id: String = goal["location_id"]
	var no_filter: bool = location_id == "" \
			and (goal["fish_ids"] as Array).is_empty() \
			and (goal["size_classes"] as Array).is_empty()
	if no_filter:
		return true   # any fish counts, even without a database
	var db := _db()
	if db == null:
		return false
	if not _fish_passes(db, goal, fish_id):
		return false
	if location_id == "":
		return true
	if spot_id != "":
		return spot_id == location_id
	for entry in db.call("get_location_fish_pool", location_id):
		if String(entry.fish.id) == fish_id:
			return true
	return false


# ============================================================================
# REWARDS
# ============================================================================

func _grant_rewards(def: Dictionary) -> Dictionary:
	var summary := {
		"money": 0, "bait": {}, "rods": [], "unlock_flags": [],
		"pending_money": 0, "pending_bait": {},
	}
	var rewards: Dictionary = def["rewards"]

	var money := int(rewards.get("money", 0))
	if money > 0:
		_give_money(money)
		summary["money"] = money

	for entry in rewards.get("bait", []):
		var bait_id: String = entry["id"]
		var count: int = entry["count"]
		var left := _give_bait(bait_id, count)
		if count - left > 0:
			summary["bait"][bait_id] = int(summary["bait"].get(bait_id, 0)) + count - left
		if left > 0:
			_pending_bait[bait_id] = int(_pending_bait.get(bait_id, 0)) + left
			summary["pending_bait"][bait_id] = int(summary["pending_bait"].get(bait_id, 0)) + left

	for rod_id in rewards.get("rods", []):
		if _give_rod(String(rod_id)):
			summary["rods"].append(rod_id)

	var save_manager := _autoload("SaveManager")
	for flag in def["unlock_flags"]:
		if save_manager != null and bool(save_manager.call("add_unlock_flag", flag)):
			summary["unlock_flags"].append(flag)
	return summary


# Returns the leftover count that did NOT fit.
func _give_bait(bait_id: String, count: int) -> int:
	var inventory := _autoload("InventoryManager")
	if inventory == null:
		return count
	var leftover: int = inventory.call("add_item", bait_id, count)
	if leftover < count:
		# D10: bait is always required, so equip the first bait received.
		var save_manager := _autoload("SaveManager")
		if save_manager != null and String(save_manager.call("get_equipped_bait")) == "":
			save_manager.call("set_equipped_bait", bait_id)
	return leftover


# Returns true if a NEW rod was added (already-owned rods are skipped).
func _give_rod(rod_id: String) -> bool:
	var save_manager := _autoload("SaveManager")
	if save_manager == null or bool(save_manager.call("has_rod", rod_id)):
		return false
	var added: bool = save_manager.call("add_owned_rod", rod_id)
	if added and String(save_manager.call("get_equipped_rod")) == "":
		save_manager.call("set_equipped_rod", rod_id)
	return added


func _give_money(amount: int) -> void:
	var save_manager := _autoload("SaveManager")
	if save_manager != null and save_manager.has_method("add_money"):
		save_manager.call("add_money", amount)


# ============================================================================
# VALIDATION  (quest data -> cleaned definition)
# ============================================================================

func _normalize_def(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		push_error("QuestManager: a quest entry is not a Dictionary; ignored.")
		return {}
	var id := String(raw.get("id", ""))
	if _slug_regex.search(id) == null or not id.begins_with(ID_PREFIX) or id.length() == ID_PREFIX.length():
		push_error("QuestManager: quest id '%s' must be lowercase snake_case and start with '%s'." % [id, ID_PREFIX])
		return {}
	var ctx := "quest '%s'" % id

	var title := String(raw.get("title", "")).strip_edges()
	if title.is_empty():
		push_error("QuestManager: %s needs a title." % ctx)
		return {}
	var questline := String(raw.get("questline", ""))
	if _slug_regex.search(questline) == null:
		push_error("QuestManager: %s needs a questline (lowercase snake_case)." % ctx)
		return {}

	var prerequisites: Array = []
	for pre in _as_array(raw.get("prerequisites", [])):
		var pre_id := String(pre)
		if pre_id == id:
			push_error("QuestManager: %s lists itself as a prerequisite." % ctx)
			return {}
		if not prerequisites.has(pre_id):
			prerequisites.append(pre_id)

	var goal := _normalize_goal(raw.get("goal"), ctx)
	if goal.is_empty():
		return {}

	var unlock_flags: Array = []
	for flag in _as_array(raw.get("unlock_flags", [])):
		if _slug_regex.search(String(flag)) == null:
			push_error("QuestManager: %s: unlock flag '%s' must be lowercase snake_case; skipped." % [ctx, str(flag)])
		elif not unlock_flags.has(String(flag)):
			unlock_flags.append(String(flag))

	return {
		"id": id,
		"questline": questline,
		"title": title,
		"description": String(raw.get("description", "")),
		"start_text": String(raw.get("start_text", "")),
		"complete_text": String(raw.get("complete_text", "")),
		"prerequisites": prerequisites,
		"goal": goal,
		"rewards": _normalize_rewards(raw.get("rewards", {}), ctx),
		"unlock_flags": unlock_flags,
	}


func _normalize_goal(raw: Variant, ctx: String) -> Dictionary:
	if not (raw is Dictionary):
		push_error("QuestManager: %s needs a goal." % ctx)
		return {}
	var type := String(raw.get("type", ""))
	if not QUEST_TYPES.has(type):
		push_error("QuestManager: %s: goal type '%s' must be one of: %s" % [ctx, type, ", ".join(QUEST_TYPES)])
		return {}

	var goal := {
		"type": type,
		"location_id": String(raw.get("location_id", "")),
		"size_classes": [],
		"fish_ids": [],
		"count": int(raw.get("count", 0)),
	}
	if type != TYPE_ALMANAC and int(goal["count"]) < 1:
		push_error("QuestManager: %s: count must be at least 1." % ctx)
		return {}

	for size_class in _as_array(raw.get("size_classes", [])):
		if not FishingTerms.SIZE_CLASSES.has(String(size_class)):
			push_error("QuestManager: %s: size class '%s' is not one of: %s" % [ctx, str(size_class), ", ".join(FishingTerms.SIZE_CLASSES)])
			return {}
		if not goal["size_classes"].has(String(size_class)):
			goal["size_classes"].append(String(size_class))
	for fish_id in _as_array(raw.get("fish_ids", [])):
		if not goal["fish_ids"].has(String(fish_id)):
			goal["fish_ids"].append(String(fish_id))

	# Reference checks (only when GameDB is loaded).
	var db := _db()
	if db != null:
		var location_id: String = goal["location_id"]
		if location_id != "" and not bool(db.call("has_location", location_id)):
			push_error("QuestManager: %s: unknown location '%s'." % [ctx, location_id])
			return {}
		for fish_id in goal["fish_ids"]:
			if not bool(db.call("has_fish", fish_id)):
				push_error("QuestManager: %s: unknown fish '%s'." % [ctx, fish_id])
				return {}
		if type == TYPE_ALMANAC and _almanac_targets(goal).is_empty():
			push_warning("QuestManager: %s: no fish match the almanac filters; it can never complete." % ctx)
	return goal


func _normalize_rewards(raw: Variant, ctx: String) -> Dictionary:
	var rewards := {"money": 0, "bait": [], "rods": []}
	if not (raw is Dictionary):
		return rewards
	rewards["money"] = maxi(int(raw.get("money", 0)), 0)
	var db := _db()

	for entry in _as_array(raw.get("bait", [])):
		if not (entry is Dictionary):
			push_error("QuestManager: %s: a bait reward must look like {\"id\": ..., \"count\": ...}; skipped." % ctx)
			continue
		var bait_id := String(entry.get("id", ""))
		var count := int(entry.get("count", 1))
		if count < 1 or (db != null and not bool(db.call("has_bait", bait_id))):
			push_error("QuestManager: %s: bad bait reward '%s' x%d; skipped." % [ctx, bait_id, count])
			continue
		rewards["bait"].append({"id": bait_id, "count": count})

	for rod_id in _as_array(raw.get("rods", [])):
		if db != null and not bool(db.call("has_rod", String(rod_id))):
			push_error("QuestManager: %s: unknown rod reward '%s'; skipped." % [ctx, str(rod_id)])
			continue
		if not rewards["rods"].has(String(rod_id)):
			rewards["rods"].append(String(rod_id))
	return rewards


# ============================================================================
# SMALL HELPERS
# ============================================================================

func _autoload(autoload_name: String) -> Node:
	return get_node_or_null("/root/" + autoload_name)


# GameDB, but only once it has loaded successfully (otherwise null).
func _db() -> Node:
	var db := _autoload("GameDB")
	if db != null and bool(db.get("is_loaded")):
		return db
	return null


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


func _ids_in_state(state: String) -> Array:
	var result: Array = []
	for id in _order:
		if get_state(id) == state:
			result.append(id)
	return result
