extends Node

# ============================================================================
# INVENTORY MANAGER (GODOT)  — List Inventory logic for TightLines  (Ver. 4)
# ============================================================================
# Register as an Autoload named "InventoryManager"
# (Project Settings > Autoload, AFTER GameDB).
#
# This script is LOGIC ONLY. It knows nothing about drawing, dragging, or
# input. A UI scene (the Tackle Box / Fish Box screen) should:
#   - call the functions below when the player does something, and
#   - listen to the signals below to redraw itself.
#
# DESIGN:
#   - Two fixed-capacity list containers: TACKLE_BOX and FISH_BOX.
#   - Each entry in a list represents either one stack of stackable items
#     or one individual fish.
#   - Bait and supplies STACK (up to their max_stack). Fish NEVER stack —
#     every fish is its own entry and carries its own data (e.g. size_cm).
#   - Fish go in the FISH_BOX only. Everything else goes in the TACKLE_BOX.
#
# ITEM DEFINITIONS (static data) come from GameDB, NOT from here.
# Expected Dictionary format per item_id:
#     { "category": "fish",         # "fish", "bait", "supply", ...
#       "max_stack": 1 }            # ignored (forced to 1) for "fish"
#
# ITEM INSTANCES (what is actually in the boxes) are Dictionaries:
#     { uid, item_id, container, count, meta (Dictionary) }
# ============================================================================

# --- Signals (for the UI and other modules) ---
signal inventory_changed(container_id: String)
signal item_added(container_id: String, uid: int, item_id: String, count: int)
signal item_removed(container_id: String, uid: int, item_id: String, count: int)
signal item_moved(uid: int, from_container: String, to_container: String)
signal stack_changed(uid: int, new_count: int)
signal item_rejected(container_id: String, item_id: String, reason: String)
# reason is one of: "unknown_item", "wrong_container", "no_space", "invalid"

# --- Containers ---
const TACKLE_BOX := "tackle_box"
const FISH_BOX := "fish_box"
const FISH_CATEGORY := "fish"
const SAVE_VERSION := 2
const GAME_DB_PATH := "/root/GameDB"

# Maximum number of list entries (stacks or individual fish) per box.
const CONTAINER_CAPACITIES := {
	"tackle_box": 48,
	"fish_box": 48,
}

# --- Item definition lookup ---
var item_def_provider: Callable = Callable()
var _fallback_defs: Dictionary = {}
var _def_cache: Dictionary = {}      # { item_id: normalized definition }
var _warned_items: Dictionary = {}   # so each unknown item warns only once

# --- Internal state ---
var _lists: Dictionary = {}   # { container_id: Array[int] of uids in slot order }
var _items: Dictionary = {}   # { uid: item Dictionary }
var _next_uid: int = 1


func _ready() -> void:
	for container_id in CONTAINER_CAPACITIES.keys():
		_lists[container_id] = []
	item_def_provider = Callable(self, "_game_db_item_def")


# ============================================================================
# ITEM DEFINITIONS
# ============================================================================

func connect_item_definitions(provider: Callable) -> void:
	item_def_provider = provider
	refresh_definitions()


func register_item_def(item_id: String, def: Dictionary) -> void:
	_fallback_defs[item_id] = def
	_def_cache.erase(item_id)


func refresh_definitions() -> void:
	_def_cache.clear()
	_warned_items.clear()


func get_item_def(item_id: String) -> Dictionary:
	if _def_cache.has(item_id):
		return (_def_cache[item_id] as Dictionary).duplicate()

	var raw: Dictionary = {}
	if item_def_provider.is_valid():
		raw = _coerce_def(item_def_provider.call(item_id))
	if raw.is_empty() and _fallback_defs.has(item_id):
		raw = _coerce_def(_fallback_defs[item_id])

	if raw.is_empty():
		if not _warned_items.has(item_id):
			_warned_items[item_id] = true
			push_warning("InventoryManager: no definition found for item '%s'" % item_id)
		return {}

	var def := _normalize_def(raw)
	_def_cache[item_id] = def
	return def.duplicate()


func _coerce_def(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw
	if raw is Object:
		var d := {}
		for key in ["category", "max_stack"]:
			var v: Variant = raw.get(key)
			if v != null:
				d[key] = v
		return d
	return {}


func _normalize_def(raw: Dictionary) -> Dictionary:
	var category := String(raw.get("category", "supply"))
	var max_stack := maxi(int(raw.get("max_stack", 1)), 1)
	if category == FISH_CATEGORY:
		max_stack = 1 # fish never stack
	return {"category": category, "max_stack": max_stack}


func container_for(item_id: String) -> String:
	var def := get_item_def(item_id)
	if def.is_empty():
		return ""
	return FISH_BOX if def["category"] == FISH_CATEGORY else TACKLE_BOX


# ----------------------------------------------------------------------------
# GameDB connection
# ----------------------------------------------------------------------------
func _game_db() -> Node:
	return get_node_or_null(GAME_DB_PATH)


func _game_db_item_def(item_id: String) -> Dictionary:
	var db := _game_db()
	if db == null or not bool(db.get("is_loaded")):
		return {}
	var record: Variant = null
	var category := ""
	if db.call("has_fish", item_id):
		record = db.call("get_fish", item_id)
		category = FISH_CATEGORY
	elif db.call("has_bait", item_id):
		record = db.call("get_bait", item_id)
		category = "bait"
	if record == null:
		return {}
	return {
		"category": category,
		"max_stack": int(record.max_stack),
	}


# ============================================================================
# ADDING ITEMS
# ============================================================================

# Adds `count` of an item, automatically choosing the right box. Stackable
# items first top up existing stacks, then append new entries up to capacity.
# Returns the LEFTOVER count that did not fit (0 = everything was added).
func add_item(item_id: String, count: int = 1, meta: Dictionary = {}) -> int:
	if count <= 0:
		return 0

	var def := get_item_def(item_id)
	if def.is_empty():
		item_rejected.emit("", item_id, "unknown_item")
		return count

	var container := container_for(item_id)
	var max_stack: int = def["max_stack"]
	var remaining := count
	var changed := false

	# 1) Top up existing stacks of the same item (in list order).
	if max_stack > 1 and meta.is_empty():
		for uid in _lists[container]:
			if remaining <= 0:
				break
			var existing: Dictionary = _items[uid]
			if existing["item_id"] != item_id or not existing["meta"].is_empty():
				continue
			if existing["count"] >= max_stack:
				continue
			var moved := mini(max_stack - int(existing["count"]), remaining)
			existing["count"] += moved
			remaining -= moved
			changed = true
			stack_changed.emit(uid, existing["count"])
			item_added.emit(container, uid, item_id, moved)

	# 2) Append new entries while capacity remains.
	var capacity: int = CONTAINER_CAPACITIES[container]
	while remaining > 0 and _lists[container].size() < capacity:
		var n := mini(remaining, max_stack)
		var new_uid := _create_item(container, item_id, n, meta)
		remaining -= n
		changed = true
		item_added.emit(container, new_uid, item_id, n)

	if remaining > 0:
		item_rejected.emit(container, item_id, "no_space")
	if changed:
		inventory_changed.emit(container)
	return remaining


# Would add_item(item_id, count, meta) fit COMPLETELY? Changes nothing and
# emits no signals.
func can_add(item_id: String, count: int = 1, meta: Dictionary = {}) -> bool:
	if count <= 0:
		return true
	var def := get_item_def(item_id)
	if def.is_empty():
		return false

	var container := container_for(item_id)
	var max_stack: int = def["max_stack"]
	var remaining := count

	if max_stack > 1 and meta.is_empty():
		for uid in _lists[container]:
			var existing: Dictionary = _items[uid]
			if existing["item_id"] == item_id and existing["meta"].is_empty():
				remaining -= maxi(max_stack - int(existing["count"]), 0)
				if remaining <= 0:
					return true

	var free_slots := get_free_slot_count(container)
	var slots_needed := ceili(float(remaining) / float(max_stack))
	return slots_needed <= free_slots


# ----------------------------------------------------------------------------
# Fish helpers
# ----------------------------------------------------------------------------

func add_fish(fish_id: String, size_cm: float) -> bool:
	return add_item(fish_id, 1, {"size_cm": size_cm}) == 0


func get_fish_weight_kg(uid: int) -> float:
	var item := get_item(uid)
	var db := _game_db()
	if item.is_empty() or db == null:
		return 0.0
	var size_cm := float(item["meta"].get("size_cm", 0.0))
	return float(db.call("get_weight_for_size_kg", item["item_id"], size_cm))


func get_fish_sell_price(uid: int) -> int:
	var item := get_item(uid)
	var db := _game_db()
	if item.is_empty() or db == null:
		return 0
	var size_cm := float(item["meta"].get("size_cm", 0.0))
	return int(db.call("get_sell_price", item["item_id"], size_cm))


func is_item_locked(uid: int) -> bool:
	if not _items.has(uid):
		return false
	return bool(_items[uid]["meta"].get("locked", false))


func set_item_locked(uid: int, locked: bool) -> bool:
	if not _items.has(uid):
		return false
	var item: Dictionary = _items[uid]
	if locked:
		item["meta"]["locked"] = true
	else:
		item["meta"].erase("locked")
	inventory_changed.emit(String(item["container"]))
	return true


func toggle_item_locked(uid: int) -> bool:
	if not _items.has(uid):
		return false
	var next := not is_item_locked(uid)
	set_item_locked(uid, next)
	return next


# Turns an unlocked fish in the FISH_BOX into weighted bait using BaitData.compost_weight.
# Returns { ok, reason, bait_id, bait_name, count, leftover }.
func compost_fish(uid: int) -> Dictionary:
	if not _items.has(uid):
		return {"ok": false, "reason": "missing"}
	var item: Dictionary = _items[uid]
	if String(item["container"]) != FISH_BOX:
		return {"ok": false, "reason": "not_fish"}
	if is_item_locked(uid):
		return {"ok": false, "reason": "locked"}

	var db := _game_db()
	if db == null or not bool(db.get("is_loaded")):
		return {"ok": false, "reason": "no_db"}

	var candidates: Array = []
	var total_weight := 0.0
	for bait in db.call("get_all_bait"):
		if bool(bait.get("unlimited")):
			continue
		var w := float(bait.get("compost_weight"))
		if w > 0.0:
			candidates.append({"bait": bait, "weight": w})
			total_weight += w
	# Fallback: if no bait has compost_weight > 0, pick from non-debug baits equally.
	if candidates.is_empty():
		for bait in db.call("get_all_bait"):
			if bool(bait.get("unlimited")):
				continue
			var bid := String(bait.get("id"))
			if not bid.contains("debug"):
				candidates.append({"bait": bait, "weight": 1.0})
				total_weight += 1.0
	if candidates.is_empty() or total_weight <= 0.0:
		return {"ok": false, "reason": "no_compost_bait"}

	var roll := randf() * total_weight
	var acc := 0.0
	var picked: Object = candidates[candidates.size() - 1]["bait"]
	for c in candidates:
		acc += float(c["weight"])
		if roll <= acc:
			picked = c["bait"]
			break

	var bait_id := String(picked.get("id"))
	var bait_name := String(picked.get("display_name"))
	var yield_count := 1
	var fish_id := String(item["item_id"])
	if bool(db.call("has_fish", fish_id)):
		var fish_rec: Object = db.call("get_fish", fish_id)
		match String(fish_rec.get("size_class")):
			"medium":
				yield_count = 2
			"large":
				yield_count = 3

	if not can_add(bait_id, yield_count):
		return {"ok": false, "reason": "tackle_box_full", "bait_id": bait_id, "bait_name": bait_name, "count": yield_count}

	remove_item(uid)
	var leftover := add_item(bait_id, yield_count)
	return {
		"ok": true,
		"reason": "",
		"bait_id": bait_id,
		"bait_name": bait_name,
		"count": yield_count - leftover,
		"leftover": leftover,
	}


# ============================================================================
# REORDERING / SPLITTING / ARRANGING
# ============================================================================

# Moves an existing item to `to_index` within its container list.
# If `to_index` currently holds a stack of the same stackable item, the stacks
# are merged instead (as much as fits). Returns true if anything changed.
func move_item(uid: int, to_index: int) -> bool:
	if not _items.has(uid):
		return false

	var item: Dictionary = _items[uid]
	var container: String = item["container"]
	var list: Array = _lists[container]
	var from_index := list.find(uid)
	if from_index == -1 or to_index < 0 or to_index >= list.size():
		return false
	if from_index == to_index:
		return false

	# Check if dropping onto an existing stack of the same item to merge.
	var target_uid: int = list[to_index]
	if _try_merge(uid, target_uid):
		return true

	# Otherwise reorder within the list.
	list.remove_at(from_index)
	list.insert(to_index, uid)
	item_moved.emit(uid, container, container)
	inventory_changed.emit(container)
	return true


# Splits `amount` off a stack into a NEW list entry appended to the box.
# Returns the new stack's uid, or 0 if it could not be done.
func split_stack(uid: int, amount: int) -> int:
	if not _items.has(uid):
		return 0
	var item: Dictionary = _items[uid]
	var container: String = item["container"]
	if amount <= 0 or amount >= int(item["count"]):
		return 0

	if get_free_slot_count(container) <= 0:
		item_rejected.emit(container, item["item_id"], "no_space")
		return 0

	item["count"] -= amount
	var new_uid := _create_item(container, item["item_id"], amount, item["meta"])
	stack_changed.emit(uid, item["count"])
	item_added.emit(container, new_uid, item["item_id"], amount)
	inventory_changed.emit(container)
	return new_uid


# "Sort" button: merges loose stacks of the same stackable item, then sorts
# the list alphabetically by item_id (and by fish size_cm descending, then uid).
func auto_arrange(container: String) -> bool:
	if not _lists.has(container):
		return false
	var list: Array = _lists[container]
	if list.is_empty():
		return true

	# 1) Merge loose stacks (same item, no meta, stackable).
	var groups: Dictionary = {}
	for uid in list:
		var it: Dictionary = _items[uid]
		if not it["meta"].is_empty():
			continue
		var def := get_item_def(it["item_id"])
		if def.is_empty() or int(def["max_stack"]) <= 1:
			continue
		if not groups.has(it["item_id"]):
			groups[it["item_id"]] = []
		groups[it["item_id"]].append(uid)

	for group_item_id in groups.keys():
		var stack_uids: Array = groups[group_item_id]
		var max_stack: int = get_item_def(group_item_id)["max_stack"]
		var total := 0
		for s_uid in stack_uids:
			total += int(_items[s_uid]["count"])
		for s_uid in stack_uids:
			var prev_count := int(_items[s_uid]["count"])
			if total > 0:
				var n := mini(total, max_stack)
				_items[s_uid]["count"] = n
				total -= n
				if n != prev_count:
					stack_changed.emit(s_uid, n)
			else:
				_delete_item(s_uid)
				item_removed.emit(container, s_uid, group_item_id, prev_count)

	# 2) Sort remaining entries cleanly.
	list.sort_custom(func(a: int, b: int) -> bool:
		var ia: String = _items[a]["item_id"]
		var ib: String = _items[b]["item_id"]
		if ia != ib:
			return ia < ib
		var sa := float(_items[a]["meta"].get("size_cm", 0.0))
		var sb := float(_items[b]["meta"].get("size_cm", 0.0))
		if not is_equal_approx(sa, sb):
			return sa > sb
		return a < b)

	inventory_changed.emit(container)
	return true


func _try_merge(src_uid: int, tgt_uid: int) -> bool:
	if src_uid == tgt_uid or not _items.has(src_uid) or not _items.has(tgt_uid):
		return false

	var src: Dictionary = _items[src_uid]
	var tgt: Dictionary = _items[tgt_uid]
	if tgt["item_id"] != src["item_id"]:
		return false
	if not tgt["meta"].is_empty() or not src["meta"].is_empty():
		return false

	var max_stack := int(get_item_def(src["item_id"]).get("max_stack", 1))
	if max_stack <= 1 or tgt["count"] >= max_stack:
		return false

	var moved := mini(max_stack - int(tgt["count"]), int(src["count"]))
	tgt["count"] += moved
	src["count"] -= moved
	stack_changed.emit(tgt_uid, tgt["count"])

	var container: String = src["container"]
	if src["count"] <= 0:
		_delete_item(src_uid)
	else:
		stack_changed.emit(src_uid, src["count"])

	inventory_changed.emit(container)
	return true


# ============================================================================
# REMOVING / CONSUMING
# ============================================================================

# Removes `count` from a stack (default -1 = the whole stack/fish).
# Returns how many were actually removed.
func remove_item(uid: int, count: int = -1) -> int:
	if not _items.has(uid):
		return 0
	var item: Dictionary = _items[uid]
	var container: String = item["container"]
	var item_id: String = item["item_id"]

	var removed: int = int(item["count"]) if count < 0 else mini(count, int(item["count"]))
	if removed <= 0:
		return 0

	item["count"] -= removed
	if item["count"] <= 0:
		_delete_item(uid)
	else:
		stack_changed.emit(uid, item["count"])

	item_removed.emit(container, uid, item_id, removed)
	inventory_changed.emit(container)
	return removed


# Uses up `count` of an item by ID across all stacks (smallest stacks first).
# All-or-nothing: returns false and changes nothing if there isn't enough.
func consume_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return true
	var container := container_for(item_id)
	if container == "" or not _lists.has(container):
		return false
	if count_of(item_id) < count:
		return false

	var stacks: Array = []
	for uid in _lists[container]:
		if _items[uid]["item_id"] == item_id:
			stacks.append(uid)
	stacks.sort_custom(func(a: int, b: int) -> bool:
		var ca: int = _items[a]["count"]
		var cb: int = _items[b]["count"]
		return ca < cb if ca != cb else a < b)

	var remaining := count
	for uid in stacks:
		if remaining <= 0:
			break
		remaining -= remove_item(uid, remaining)
	return true


# ============================================================================
# QUERIES
# ============================================================================

func count_of(item_id: String, container: String = "") -> int:
	var total := 0
	for item in _items.values():
		if item["item_id"] == item_id and (container == "" or item["container"] == container):
			total += int(item["count"])
	return total


func has_item(item_id: String, count: int = 1) -> bool:
	return count_of(item_id) >= count


# Returns a COPY of one item's data (editing it does not change inventory).
func get_item(uid: int) -> Dictionary:
	if not _items.has(uid):
		return {}
	return _items[uid].duplicate(true)


# Returns COPIES of every item in a container in list order (for the UI).
func get_items(container: String) -> Array:
	if not _lists.has(container):
		return []
	var result: Array = []
	for uid in _lists[container]:
		result.append(_items[uid].duplicate(true))
	return result


# Returns the uid at a list index, or 0 if out of bounds.
func get_uid_at(container: String, index: int) -> int:
	if not _lists.has(container):
		return 0
	var list: Array = _lists[container]
	if index < 0 or index >= list.size():
		return 0
	return list[index]


func get_index_of(uid: int) -> int:
	if not _items.has(uid):
		return -1
	var container: String = _items[uid]["container"]
	return (_lists[container] as Array).find(uid)


func get_container_capacity(container: String) -> int:
	return CONTAINER_CAPACITIES.get(container, 0)


func get_used_slot_count(container: String) -> int:
	if not _lists.has(container):
		return 0
	return (_lists[container] as Array).size()


func get_free_slot_count(container: String) -> int:
	return maxi(get_container_capacity(container) - get_used_slot_count(container), 0)


# ============================================================================
# SAVE / LOAD  (JSON-friendly; hand this to SaveManager)
# ============================================================================

func to_save_data() -> Dictionary:
	var list: Array = []
	for container_id in [TACKLE_BOX, FISH_BOX]:
		for uid in _lists[container_id]:
			var it: Dictionary = _items[uid]
			list.append({
				"uid": uid,
				"item_id": it["item_id"],
				"container": it["container"],
				"count": it["count"],
				"meta": it["meta"].duplicate(true),
			})
	return {"version": SAVE_VERSION, "next_uid": _next_uid, "items": list}


func load_save_data(data: Variant) -> void:
	_clear_all()
	if not (data is Dictionary):
		push_warning("InventoryManager: save data missing or invalid; inventory left empty.")
		_emit_all_changed()
		return

	var d: Dictionary = data
	if int(d.get("version", SAVE_VERSION)) > SAVE_VERSION:
		push_warning("InventoryManager: save data is from a newer version (%s); loading anyway." % str(d.get("version")))

	var entries: Array = d["items"] if d.get("items") is Array else []

	var max_uid := int(d.get("next_uid", 1)) - 1
	for raw in entries:
		if raw is Dictionary:
			max_uid = maxi(max_uid, int(raw.get("uid", 0)))
	_next_uid = maxi(max_uid + 1, 1)

	for raw in entries:
		if not (raw is Dictionary):
			continue
		var item_id := String(raw.get("item_id", ""))
		var def := get_item_def(item_id)
		if def.is_empty():
			push_warning("InventoryManager: dropped unknown item '%s' while loading" % item_id)
			continue

		var container := container_for(item_id)
		if get_free_slot_count(container) <= 0:
			push_warning("InventoryManager: no room to restore '%s'; dropped" % item_id)
			continue

		var count := clampi(int(raw.get("count", 1)), 1, int(def["max_stack"]))
		var meta: Dictionary = raw["meta"] if raw.get("meta") is Dictionary else {}

		var uid := int(raw.get("uid", 0))
		if uid <= 0 or _items.has(uid):
			uid = 0 # _create_item will assign a fresh one
		_create_item(container, item_id, count, meta, uid)

	_emit_all_changed()


func clear_all() -> void:
	_clear_all()
	_emit_all_changed()


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

func _emit_all_changed() -> void:
	for container_id in CONTAINER_CAPACITIES.keys():
		inventory_changed.emit(container_id)


func _clear_all() -> void:
	_items.clear()
	_next_uid = 1
	for container_id in CONTAINER_CAPACITIES.keys():
		_lists[container_id] = []


func _create_item(container: String, item_id: String, count: int,
		meta: Dictionary, forced_uid: int = 0) -> int:
	var uid := forced_uid
	if uid <= 0:
		uid = _next_uid
	_next_uid = maxi(_next_uid, uid + 1)

	var item := {
		"uid": uid,
		"item_id": item_id,
		"container": container,
		"count": count,
		"meta": meta.duplicate(true),
	}
	_items[uid] = item
	_lists[container].append(uid)
	return uid


func _delete_item(uid: int) -> void:
	if not _items.has(uid):
		return
	var container: String = _items[uid]["container"]
	_lists[container].erase(uid)
	_items.erase(uid)
