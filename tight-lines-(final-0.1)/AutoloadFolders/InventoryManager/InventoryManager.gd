extends Node

# ============================================================================
# INVENTORY MANAGER (GODOT)  — Grid Inventory logic for TightLines
# ============================================================================
# Register as an Autoload named "InventoryManager"
# (Project Settings > Autoload).
#
# This script is LOGIC ONLY. It knows nothing about drawing, dragging, or
# input. A future UI scene (the Tackle Box / Fish Box screen) should:
#   - call the functions below when the player does something, and
#   - listen to the signals below to redraw itself.
#
# DESIGN (as decided):
#   - Two fixed-size grids: TACKLE_BOX and FISH_BOX.
#   - Items are RECTANGLES of any size (1x1, 1x3, 2x2 ...) and can be
#     ROTATED 90 degrees (a 1x3 becomes 3x1). Square items can't rotate.
#   - Bait and supplies STACK (up to their max_stack). Fish NEVER stack —
#     every fish is its own item and carries its own data (species, weight).
#   - Fish go in the FISH_BOX only. Everything else goes in the TACKLE_BOX.
#
# ITEM DEFINITIONS (static data) come from GameDatabase, NOT from here.
# This script just needs, for any item_id, a Dictionary like:
#     { "size": Vector2i(1, 3),     # width x height, unrotated
#       "category": "fish",         # "fish", "bait", "supply", ...
#       "max_stack": 1 }            # ignored (forced to 1) for "fish"
# Hook it up with connect_item_definitions() — see below. Because
# GameDatabaseManager is being reworked (JSON -> .tres), this is the only
# place that needs to change when that rework lands.
#
# ITEM INSTANCES (what is actually in the boxes) are Dictionaries:
#     { uid, item_id, container, pos (Vector2i), rotated (bool),
#       size (Vector2i, unrotated), count, meta (Dictionary) }
# "uid" is a unique number per stack/fish. "meta" holds per-item data such as
# a fish's {"species_id": "...", "weight": 2.4, "length": 41.0}.
# Keep meta JSON-safe (numbers, strings, bools, arrays, dictionaries) so
# SaveManager can write it straight to JSON.
# ============================================================================

# --- Signals (for the UI and other modules) ---
signal inventory_changed(container_id: String)   # anything in that box changed
signal item_added(container_id: String, uid: int, item_id: String, count: int)
signal item_removed(container_id: String, uid: int, item_id: String, count: int)
signal item_moved(uid: int, from_container: String, to_container: String)
signal item_rotated(uid: int)
signal stack_changed(uid: int, new_count: int)
signal item_rejected(container_id: String, item_id: String, reason: String)
# reason is one of: "unknown_item", "wrong_container", "no_space", "invalid"

# --- Containers ---
const TACKLE_BOX := "tackle_box"
const FISH_BOX := "fish_box"
const FISH_CATEGORY := "fish"
const SAVE_VERSION := 1

# Fixed grid sizes in cells (width x height). Change these numbers to taste.
const CONTAINER_SIZES := {
	"tackle_box": Vector2i(8, 6),
	"fish_box": Vector2i(6, 8),
}

# --- Item definition lookup ---
# A Callable that takes an item_id (String) and returns the definition
# Dictionary described at the top. Set it with connect_item_definitions().
var item_def_provider: Callable = Callable()

# Local definitions used only for testing / until GameDatabase is ready.
var _fallback_defs: Dictionary = {}

# --- Internal state ---
var _grids: Dictionary = {}   # { container_id: Array of uid ints, 0 = empty }
var _items: Dictionary = {}   # { uid: item Dictionary }
var _next_uid: int = 1


func _ready() -> void:
	for container_id in CONTAINER_SIZES.keys():
		_reset_grid(container_id)


# ============================================================================
# ITEM DEFINITIONS
# ============================================================================

# Example, once GameDatabase can look up items:
#     InventoryManager.connect_item_definitions(GameDatabase.get_item_data)
func connect_item_definitions(provider: Callable) -> void:
	item_def_provider = provider


# For tests or placeholder content before GameDatabase has items.
func register_item_def(item_id: String, def: Dictionary) -> void:
	_fallback_defs[item_id] = def


func get_item_def(item_id: String) -> Dictionary:
	var raw: Variant = null
	if item_def_provider.is_valid():
		raw = item_def_provider.call(item_id)
	if (not (raw is Dictionary) or raw.is_empty()) and _fallback_defs.has(item_id):
		raw = _fallback_defs[item_id]
	if not (raw is Dictionary) or raw.is_empty():
		push_warning("InventoryManager: no definition found for item '%s'" % item_id)
		return {}
	return _normalize_def(raw)


func _normalize_def(raw: Dictionary) -> Dictionary:
	var size := Vector2i(1, 1)
	var s: Variant = raw.get("size", Vector2i(1, 1))
	if s is Vector2i:
		size = s
	elif s is Vector2:
		size = Vector2i(s)
	elif s is Array and s.size() >= 2:
		size = Vector2i(int(s[0]), int(s[1]))
	size = Vector2i(maxi(size.x, 1), maxi(size.y, 1))

	var category := String(raw.get("category", "supply"))
	var max_stack := maxi(int(raw.get("max_stack", 1)), 1)
	if category == FISH_CATEGORY:
		max_stack = 1 # fish never stack

	return {"size": size, "category": category, "max_stack": max_stack}


# Which box an item belongs in. Returns "" if the item is unknown.
func container_for(item_id: String) -> String:
	var def := get_item_def(item_id)
	if def.is_empty():
		return ""
	return FISH_BOX if def["category"] == FISH_CATEGORY else TACKLE_BOX


# ============================================================================
# ADDING ITEMS
# ============================================================================

# Adds `count` of an item, automatically choosing the right box. Stackable
# items first top up existing stacks, then new stacks are placed in the first
# free spot (rotating the item if that is what makes it fit).
#
# `meta` is per-item data (e.g. a fish's species/weight). Items with meta
# never merge into stacks.
#
# Returns the LEFTOVER count that did not fit (0 = everything was added).
# Example: bait_leftover = InventoryManager.add_item("worm", 5)
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

	# 1) Top up existing stacks of the same item.
	if max_stack > 1 and meta.is_empty():
		for uid in _uids_in(container):
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

	# 2) Place new stacks in free space.
	while remaining > 0:
		var spot := find_free_spot(container, def["size"])
		if spot.is_empty():
			break
		var n := mini(remaining, max_stack)
		var new_uid := _create_item(container, item_id, def["size"],
				spot["pos"], spot["rotated"], n, meta)
		remaining -= n
		changed = true
		item_added.emit(container, new_uid, item_id, n)

	if remaining > 0:
		item_rejected.emit(container, item_id, "no_space")
	if changed:
		inventory_changed.emit(container)
	return remaining


# Places an item at an EXACT cell (for drag-and-drop from outside the grid,
# e.g. buying from the Shop straight into a chosen slot). Returns the new
# item's uid, or 0 if it could not be placed there.
func place_item_at(item_id: String, pos: Vector2i, rotated: bool = false,
		count: int = 1, meta: Dictionary = {}) -> int:
	var def := get_item_def(item_id)
	if def.is_empty():
		item_rejected.emit("", item_id, "unknown_item")
		return 0

	var container := container_for(item_id)
	if count < 1 or count > int(def["max_stack"]):
		item_rejected.emit(container, item_id, "invalid")
		return 0

	var fp := footprint(def["size"], rotated)
	if not _can_fit(container, pos, fp):
		item_rejected.emit(container, item_id, "no_space")
		return 0

	var uid := _create_item(container, item_id, def["size"], pos, rotated, count, meta)
	item_added.emit(container, uid, item_id, count)
	inventory_changed.emit(container)
	return uid


# ============================================================================
# MOVING / ROTATING / SPLITTING
# ============================================================================

# Moves an existing item to a cell, with the rotation you want it to have
# there. A UI drag-and-drop typically does:
#     var item := InventoryManager.get_item(uid)
#     InventoryManager.move_item(uid, container, drop_cell, item["rotated"])
# (or pass the flipped value if the player pressed Rotate mid-drag).
#
# If the target area is blocked BUT the cell you dropped on holds a stack of
# the same stackable item, the stacks are merged instead (as much as fits).
# Returns true if anything changed.
func move_item(uid: int, to_container: String, to_pos: Vector2i, rotated: bool) -> bool:
	if not _items.has(uid) or not _grids.has(to_container):
		return false

	var item: Dictionary = _items[uid]
	if container_for(item["item_id"]) != to_container:
		item_rejected.emit(to_container, item["item_id"], "wrong_container")
		return false

	var fp := footprint(item["size"], rotated)
	if _can_fit(to_container, to_pos, fp, uid):
		var from_container: String = item["container"]
		_paint(item, 0)
		item["container"] = to_container
		item["pos"] = to_pos
		item["rotated"] = rotated
		_paint(item, uid)
		item_moved.emit(uid, from_container, to_container)
		inventory_changed.emit(from_container)
		if to_container != from_container:
			inventory_changed.emit(to_container)
		return true

	return _try_merge_at(uid, to_container, to_pos)


# Rotates an item 90 degrees IN PLACE (keeping its top-left cell). Returns
# false if it is square or the rotated shape would not fit there.
func rotate_item(uid: int) -> bool:
	if not _items.has(uid):
		return false
	var item: Dictionary = _items[uid]
	var base: Vector2i = item["size"]
	if base.x == base.y:
		return false

	var new_rotated: bool = not item["rotated"]
	var fp := footprint(base, new_rotated)
	if not _can_fit(item["container"], item["pos"], fp, uid):
		return false

	_paint(item, 0)
	item["rotated"] = new_rotated
	_paint(item, uid)
	item_rotated.emit(uid)
	inventory_changed.emit(item["container"])
	return true


# Splits `amount` off a stack into a NEW stack in the first free spot.
# Returns the new stack's uid, or 0 if it could not be done.
func split_stack(uid: int, amount: int) -> int:
	if not _items.has(uid):
		return 0
	var item: Dictionary = _items[uid]
	if amount <= 0 or amount >= int(item["count"]):
		return 0

	var spot := find_free_spot(item["container"], item["size"])
	if spot.is_empty():
		item_rejected.emit(item["container"], item["item_id"], "no_space")
		return 0

	item["count"] -= amount
	var new_uid := _create_item(item["container"], item["item_id"], item["size"],
			spot["pos"], spot["rotated"], amount, item["meta"])
	stack_changed.emit(uid, item["count"])
	inventory_changed.emit(item["container"])
	return new_uid


func _try_merge_at(uid: int, to_container: String, to_pos: Vector2i) -> bool:
	var cs: Vector2i = CONTAINER_SIZES[to_container]
	if to_pos.x < 0 or to_pos.y < 0 or to_pos.x >= cs.x or to_pos.y >= cs.y:
		return false

	var target_uid: int = _grids[to_container][to_pos.y * cs.x + to_pos.x]
	if target_uid == 0 or target_uid == uid:
		return false

	var src: Dictionary = _items[uid]
	var tgt: Dictionary = _items[target_uid]
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
	stack_changed.emit(target_uid, tgt["count"])

	var src_container: String = src["container"]
	if src["count"] <= 0:
		_delete_item(uid)
	else:
		stack_changed.emit(uid, src["count"])

	inventory_changed.emit(src_container)
	if tgt["container"] != src_container:
		inventory_changed.emit(tgt["container"])
	return true


# ============================================================================
# REMOVING / CONSUMING
# ============================================================================

# Removes `count` from a stack (default -1 = the whole stack/fish).
# Returns how many were actually removed. Use this for "release fish",
# "sell fish", "drop item".
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


# Uses up `count` of an item by ID across all stacks (e.g. "spend 1 worm" when
# casting). Takes from the SMALLEST stacks first so boxes tidy themselves up.
# All-or-nothing: returns false and changes nothing if there isn't enough.
func consume_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return true
	if count_of(item_id) < count:
		return false

	var stacks: Array = []
	for uid in _uids_in(container_for(item_id)):
		if _items[uid]["item_id"] == item_id:
			stacks.append(uid)
	stacks.sort_custom(func(a, b): return _items[a]["count"] < _items[b]["count"])

	var remaining := count
	for uid in stacks:
		if remaining <= 0:
			break
		remaining -= remove_item(uid, remaining)
	return true


# ============================================================================
# QUERIES
# ============================================================================

# Total quantity of an item. Pass a container to limit the search.
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


# Returns COPIES of every item in a container (for the UI to draw).
func get_items(container: String) -> Array:
	var result: Array = []
	for uid in _uids_in(container):
		result.append(_items[uid].duplicate(true))
	return result


# Returns the uid at a cell, or 0 if empty / out of bounds.
func get_uid_at(container: String, cell: Vector2i) -> int:
	if not _grids.has(container):
		return 0
	var cs: Vector2i = CONTAINER_SIZES[container]
	if cell.x < 0 or cell.y < 0 or cell.x >= cs.x or cell.y >= cs.y:
		return 0
	return _grids[container][cell.y * cs.x + cell.x]


func get_container_size(container: String) -> Vector2i:
	return CONTAINER_SIZES.get(container, Vector2i.ZERO)


func get_free_cell_count(container: String) -> int:
	if not _grids.has(container):
		return 0
	return (_grids[container] as Array).count(0)


# Footprint of an item once rotation is applied (1x3 rotated -> 3x1).
func footprint(size: Vector2i, rotated: bool) -> Vector2i:
	return Vector2i(size.y, size.x) if rotated else size


# Would this item fit at this cell with this rotation? (For the UI to
# colour a drag-preview green/red.) Pass the dragged item's uid as
# ignore_uid so it doesn't block itself.
func can_place(container: String, item_id: String, pos: Vector2i,
		rotated: bool, ignore_uid: int = 0) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty() or container_for(item_id) != container:
		return false
	return _can_fit(container, pos, footprint(def["size"], rotated), ignore_uid)


# First free spot (scanning left-to-right, top-to-bottom), trying the item
# unrotated and then rotated. Returns {"pos": Vector2i, "rotated": bool},
# or an empty Dictionary if there is no room.
func find_free_spot(container: String, size: Vector2i) -> Dictionary:
	if not _grids.has(container):
		return {}
	var cs: Vector2i = CONTAINER_SIZES[container]
	var can_rotate := size.x != size.y
	var rotated_size := Vector2i(size.y, size.x)

	for y in range(cs.y):
		for x in range(cs.x):
			var p := Vector2i(x, y)
			if _can_fit(container, p, size):
				return {"pos": p, "rotated": false}
			if can_rotate and _can_fit(container, p, rotated_size):
				return {"pos": p, "rotated": true}
	return {}


# ============================================================================
# SAVE / LOAD  (JSON-friendly; hand this to SaveManager)
# ============================================================================

# Returns a plain Dictionary safe to write as JSON. SaveManager should store
# it under its own key, e.g. save["inventory"] = InventoryManager.to_save_data()
func to_save_data() -> Dictionary:
	var list: Array = []
	for uid in _items.keys():
		var it: Dictionary = _items[uid]
		list.append({
			"uid": uid,
			"item_id": it["item_id"],
			"container": it["container"],
			"x": it["pos"].x,
			"y": it["pos"].y,
			"rotated": it["rotated"],
			"count": it["count"],
			"meta": it["meta"].duplicate(true),
		})
	return {"version": SAVE_VERSION, "next_uid": _next_uid, "items": list}


# Rebuilds the inventory from saved data. JSON turns every number into a
# float, so values are converted back to ints here. Items whose definition
# no longer exists are dropped (with a warning); items whose saved spot is no
# longer valid (e.g. the item's size changed) are re-placed in free space.
func load_save_data(data: Dictionary) -> void:
	_clear_all()
	_next_uid = maxi(int(data.get("next_uid", 1)), 1)

	for raw in data.get("items", []):
		if not (raw is Dictionary):
			continue
		var item_id := String(raw.get("item_id", ""))
		var def := get_item_def(item_id)
		if def.is_empty():
			push_warning("InventoryManager: dropped unknown item '%s' while loading" % item_id)
			continue

		var container := container_for(item_id)
		var count := clampi(int(raw.get("count", 1)), 1, int(def["max_stack"]))
		var pos := Vector2i(int(raw.get("x", 0)), int(raw.get("y", 0)))
		var rotated := bool(raw.get("rotated", false))
		var meta: Dictionary = raw.get("meta", {}) if raw.get("meta", {}) is Dictionary else {}

		if not _can_fit(container, pos, footprint(def["size"], rotated)):
			var spot := find_free_spot(container, def["size"])
			if spot.is_empty():
				push_warning("InventoryManager: no room to restore '%s'; dropped" % item_id)
				continue
			pos = spot["pos"]
			rotated = spot["rotated"]

		var uid := int(raw.get("uid", 0))
		if uid <= 0 or _items.has(uid):
			uid = 0 # _create_item will assign a fresh one
		_create_item(container, item_id, def["size"], pos, rotated, count, meta, uid)

	for container_id in CONTAINER_SIZES.keys():
		inventory_changed.emit(container_id)


# Empties both boxes (e.g. when starting a New Game).
func clear_all() -> void:
	_clear_all()
	for container_id in CONTAINER_SIZES.keys():
		inventory_changed.emit(container_id)


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

func _reset_grid(container_id: String) -> void:
	var cs: Vector2i = CONTAINER_SIZES[container_id]
	var grid: Array = []
	grid.resize(cs.x * cs.y)
	grid.fill(0)
	_grids[container_id] = grid


func _clear_all() -> void:
	_items.clear()
	_next_uid = 1
	for container_id in CONTAINER_SIZES.keys():
		_reset_grid(container_id)


func _uids_in(container: String) -> Array:
	var result: Array = []
	for uid in _items.keys():
		if _items[uid]["container"] == container:
			result.append(uid)
	return result


# Is this rectangle inside the box and free of OTHER items?
func _can_fit(container: String, pos: Vector2i, fp: Vector2i, ignore_uid: int = 0) -> bool:
	if not _grids.has(container):
		return false
	var cs: Vector2i = CONTAINER_SIZES[container]
	if pos.x < 0 or pos.y < 0 or pos.x + fp.x > cs.x or pos.y + fp.y > cs.y:
		return false

	var grid: Array = _grids[container]
	for y in range(pos.y, pos.y + fp.y):
		for x in range(pos.x, pos.x + fp.x):
			var occupant: int = grid[y * cs.x + x]
			if occupant != 0 and occupant != ignore_uid:
				return false
	return true


# Writes `value` (a uid, or 0 to clear) into every cell the item covers.
func _paint(item: Dictionary, value: int) -> void:
	var cs: Vector2i = CONTAINER_SIZES[item["container"]]
	var fp := footprint(item["size"], item["rotated"])
	var pos: Vector2i = item["pos"]
	var grid: Array = _grids[item["container"]]
	for y in range(pos.y, pos.y + fp.y):
		for x in range(pos.x, pos.x + fp.x):
			grid[y * cs.x + x] = value


func _create_item(container: String, item_id: String, size: Vector2i, pos: Vector2i,
		rotated: bool, count: int, meta: Dictionary, forced_uid: int = 0) -> int:
	var uid := forced_uid
	if uid <= 0:
		uid = _next_uid
	_next_uid = maxi(_next_uid, uid + 1)

	var item := {
		"uid": uid,
		"item_id": item_id,
		"container": container,
		"pos": pos,
		"rotated": rotated,
		"size": size,
		"count": count,
		"meta": meta.duplicate(true),
	}
	_items[uid] = item
	_paint(item, uid)
	return uid


func _delete_item(uid: int) -> void:
	if not _items.has(uid):
		return
	_paint(_items[uid], 0)
	_items.erase(uid)


# ============================================================================
# SELF-TEST  (debug only)
# ============================================================================
# Call from any scene's _ready() while developing:
#     InventoryManager.run_self_test()
# It uses its own temporary item definitions and EMPTIES the inventory
# afterwards, so don't run it on a real save. Results print to Output.
func run_self_test() -> bool:
	var saved_provider := item_def_provider
	var saved_defs := _fallback_defs.duplicate()
	item_def_provider = Callable()
	_clear_all()

	register_item_def("t_worm", {"size": Vector2i(1, 1), "category": "bait", "max_stack": 10})
	register_item_def("t_tray", {"size": Vector2i(2, 2), "category": "supply", "max_stack": 1})
	register_item_def("t_pike", {"size": Vector2i(1, 3), "category": "fish"})

	# A Dictionary is used (not a plain bool) because GDScript lambdas copy
	# simple local variables, so a bool changed inside would not be seen outside.
	var result := {"ok": true}
	var check := func(condition: bool, label: String) -> void:
		print("[InventoryManager test] %s: %s" % ["PASS" if condition else "FAIL", label])
		if not condition:
			result["ok"] = false

	# Stacking: 25 worms with max 10 -> three stacks (10, 10, 5).
	check.call(add_item("t_worm", 25) == 0, "add 25 worms, nothing left over")
	check.call(count_of("t_worm") == 25, "worm total is 25")
	check.call(_uids_in(TACKLE_BOX).size() == 3, "worms form 3 stacks")

	# Consume across stacks, smallest first.
	check.call(consume_item("t_worm", 7), "consume 7 worms")
	check.call(count_of("t_worm") == 18, "18 worms remain")
	check.call(not consume_item("t_worm", 99), "over-consume is refused")
	check.call(count_of("t_worm") == 18, "refused consume changes nothing")

	# Fish never stack, go to the fish box, and keep their own data.
	add_item("t_pike", 1, {"species_id": "pike", "weight": 3.2})
	add_item("t_pike", 1, {"species_id": "pike", "weight": 4.0})
	check.call(_uids_in(FISH_BOX).size() == 2, "two pike are two separate items")
	check.call(count_of("t_pike", TACKLE_BOX) == 0, "no fish in tackle box")

	# Rotation: a 1x3 fish rotates to 3x1 when there is room.
	var pike_uid: int = _uids_in(FISH_BOX)[0]
	check.call(rotate_item(pike_uid), "rotate a 1x3 fish in place")
	check.call(get_item(pike_uid)["rotated"] == true, "fish now marked rotated")

	# Blocking: a 2x2 tray cannot land on top of worms.
	var worm_cell: Vector2i = get_item(_uids_in(TACKLE_BOX)[0])["pos"]
	check.call(not can_place(TACKLE_BOX, "t_tray", worm_cell, false), "tray blocked by worms")

	# Save / load round trip.
	var snapshot := to_save_data()
	var json_text := JSON.stringify(snapshot)
	var parsed: Variant = JSON.parse_string(json_text) # numbers become floats
	_clear_all()
	load_save_data(parsed)
	check.call(count_of("t_worm") == 18, "worms survive JSON save/load")
	check.call(_uids_in(FISH_BOX).size() == 2, "fish survive JSON save/load")

	# Fill the fish box until it rejects (6x8 box, 1x3 fish).
	var added := 0
	while add_item("t_pike") == 0:
		added += 1
		if added > 100:
			break
	check.call(added > 2 and added < 100, "fish box eventually reports full")

	# Clean up.
	_clear_all()
	_fallback_defs = saved_defs
	item_def_provider = saved_provider
	print("[InventoryManager test] %s" % ("ALL PASSED" if result["ok"] else "SOME FAILED"))
	return result["ok"]
