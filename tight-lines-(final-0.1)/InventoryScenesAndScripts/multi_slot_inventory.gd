extends Node
class_name MultiSlotInventory
## Multi-Slot Inventory System — single-file version
##
## This script works two ways at once:
##  1. As a plain class: MultiSlotInventory.get_item("sword"), .save_inventory(inv), etc.
##     are all static, so they're reachable from anywhere once this file has
##     loaded — no autoload required.
##  2. As an Autoload (optional): add it under Project Settings -> Autoload
##     (any singleton name you like, e.g. "InventorySystem") so _ready()
##     automatically scans res://items/ for ItemData .tres files on startup.
##     If you skip the autoload, call MultiSlotInventory.load_item_resources()
##     yourself once at game start, or register items manually with
##     MultiSlotInventory.define_item(...).
##
## The supporting classes (ItemData, InventoryItem, Inventory, InventoryGridUI)
## are nested inner classes below, since GDScript only allows one top-level
## `extends` per file.
##
## Usage:
##   var inv := MultiSlotInventory.Inventory.new(Vector2i(10, 6))
##   var sword := MultiSlotInventory.InventoryItem.new(MultiSlotInventory.get_item("sword"))
##   inv.add_item(sword)
##   var ui := MultiSlotInventory.InventoryGridUI.new()
##   add_child(ui)
##   ui.setup(inv)
##
##   MultiSlotInventory.save_inventory(inv)      # -> user://inventory.json
##   var loaded := MultiSlotInventory.load_inventory()


# ---------------------------------------------------------------------------
# ITEM DATA — static definition of an item type. Create .tres files from
# this via the editor Inspector: right click in FileSystem -> New Resource
# -> ItemData won't show unless this is its own class_name file; if you
# want .tres authoring in the editor, keep ItemData in its own file
# (scripts/data/item_data.gd) and only inline the rest. Otherwise, build
# ItemData instances purely in code with register_item() below.
# ---------------------------------------------------------------------------
class ItemData:
	extends Resource

	@export var id: String
	@export var display_name: String
	@export var icon: Texture2D
	@export var size := Vector2i(1, 1)   # width x height in cells
	@export var max_stack := 1


# ---------------------------------------------------------------------------
# INVENTORY ITEM — one placed instance of an ItemData
# ---------------------------------------------------------------------------
class InventoryItem:
	extends RefCounted

	var data: ItemData
	var cell := Vector2i.ZERO
	var rotated := false
	var quantity := 1

	func _init(p_data: ItemData = null) -> void:
		data = p_data

	func get_size() -> Vector2i:
		return Vector2i(data.size.y, data.size.x) if rotated else data.size

	func to_dict() -> Dictionary:
		return {
			"id": data.id,
			"x": cell.x,
			"y": cell.y,
			"rotated": rotated,
			"qty": quantity,
		}

	static func from_dict(d: Dictionary) -> InventoryItem:
		var item_data: ItemData = MultiSlotInventory.get_item(d.get("id", ""))
		if item_data == null:
			return null   # item no longer exists in the registry
		var item := InventoryItem.new(item_data)
		item.cell = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		item.rotated = bool(d.get("rotated", false))
		item.quantity = int(d.get("qty", 1))
		return item


# ---------------------------------------------------------------------------
# INVENTORY — the grid itself: placement rules + serialization
# ---------------------------------------------------------------------------
class Inventory:
	extends RefCounted

	signal changed

	var grid_size: Vector2i
	var cells: Array = []                 # null or InventoryItem, flat array
	var items: Array = []                 # Array[InventoryItem]

	func _init(size := Vector2i(10, 6)) -> void:
		grid_size = size
		cells.resize(size.x * size.y)
		cells.fill(null)

	func _idx(c: Vector2i) -> int:
		return c.y * grid_size.x + c.x

	func in_bounds(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < grid_size.x and c.y < grid_size.y

	func get_item_at(c: Vector2i) -> InventoryItem:
		return cells[_idx(c)] if in_bounds(c) else null

	# 'ignore' lets an item being moved overlap its own old position
	func can_place(item: InventoryItem, at: Vector2i, ignore: InventoryItem = null) -> bool:
		var s := item.get_size()
		for y in s.y:
			for x in s.x:
				var c := at + Vector2i(x, y)
				if not in_bounds(c):
					return false
				var occupant = cells[_idx(c)]
				if occupant != null and occupant != ignore:
					return false
		return true

	func place(item: InventoryItem, at: Vector2i) -> bool:
		if not can_place(item, at, item):
			return false
		if item in items:
			_clear_cells(item)
		else:
			items.append(item)
		item.cell = at
		_fill_cells(item)
		changed.emit()
		return true

	func remove(item: InventoryItem) -> void:
		_clear_cells(item)
		items.erase(item)
		changed.emit()

	func find_free_spot(item: InventoryItem):
		for y in grid_size.y:
			for x in grid_size.x:
				if can_place(item, Vector2i(x, y)):
					return Vector2i(x, y)
		return null   # no space available

	func add_item(item: InventoryItem) -> bool:
		var spot = find_free_spot(item)
		if spot == null:
			return false
		return place(item, spot)

	func _fill_cells(item: InventoryItem) -> void:
		var s := item.get_size()
		for y in s.y:
			for x in s.x:
				cells[_idx(item.cell + Vector2i(x, y))] = item

	func _clear_cells(item: InventoryItem) -> void:
		var s := item.get_size()
		for y in s.y:
			for x in s.x:
				cells[_idx(item.cell + Vector2i(x, y))] = null

	# -- Serialization --------------------------------------------------

	func to_dict() -> Dictionary:
		var arr := []
		for item in items:
			arr.append(item.to_dict())
		return {"width": grid_size.x, "height": grid_size.y, "items": arr}

	static func from_dict(d: Dictionary) -> Inventory:
		var inv := Inventory.new(Vector2i(int(d.get("width", 10)), int(d.get("height", 6))))
		for entry in d.get("items", []):
			var item := InventoryItem.from_dict(entry)
			if item and not inv.place(item, item.cell):
				push_warning("Could not restore %s at %s" % [item.data.id, item.cell])
		return inv


# ---------------------------------------------------------------------------
# UI — a Control that draws the grid and lets the player pick up / rotate /
# drop items. Instance it in code (InventoryGridUI.new()) and add_child it,
# or attach this inner class's logic to a Control node in a scene by
# pasting just this class's body into its own script if you'd rather author
# the layout visually.
# ---------------------------------------------------------------------------
class InventoryGridUI:
	extends Control

	const CELL := 64

	var inventory: Inventory
	var held: InventoryItem = null
	var _views := {}    # InventoryItem -> TextureRect

	func setup(inv: Inventory) -> void:
		inventory = inv
		custom_minimum_size = Vector2(inv.grid_size) * CELL
		inv.changed.connect(_refresh)
		_refresh()

	func _draw() -> void:
		for y in inventory.grid_size.y:
			for x in inventory.grid_size.x:
				draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)),
						Color(1, 1, 1, 0.25), false)
		if held:
			var c := _mouse_cell()
			var ok := inventory.can_place(held, c, held)
			var col := Color(0, 1, 0, 0.35) if ok else Color(1, 0, 0, 0.35)
			draw_rect(Rect2(Vector2(c) * CELL, Vector2(held.get_size()) * CELL), col)

	func _mouse_cell() -> Vector2i:
		return Vector2i(get_local_mouse_position() / CELL)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			queue_redraw()
			if held and _views.has(held):
				_views[held].position = get_local_mouse_position() - Vector2(held.get_size()) * CELL / 2
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := _mouse_cell()
			if held == null:
				held = inventory.get_item_at(c)     # pick up
			elif inventory.can_place(held, c, held):
				inventory.place(held, c)            # drop
				held = null
			queue_redraw()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_R and held:
			held.rotated = not held.rotated
			_refresh()
			queue_redraw()

	func _refresh() -> void:
		for v in _views.values():
			v.queue_free()
		_views.clear()
		for item in inventory.items:
			var tr := TextureRect.new()
			tr.texture = item.data.icon
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.size = Vector2(item.get_size()) * CELL
			tr.position = Vector2(item.cell) * CELL
			add_child(tr)
			_views[item] = tr


# ---------------------------------------------------------------------------
# ITEM REGISTRY + SAVE/LOAD — static, so they're reachable as
# MultiSlotInventory.get_item(...), MultiSlotInventory.save_inventory(...)
# from anywhere in the project without needing an autoload instance.
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://inventory.json"

static var _items := {}          # id (String) -> ItemData

func _ready() -> void:
	# Only runs if this script is used as an Autoload. Safe to call again
	# manually (e.g. load_item_resources()) if you add items later.
	load_item_resources()

## Scans res://items/ for ItemData .tres files and registers them by id.
## Skip this and call register_item() / define_item() manually if you'd
## rather define items purely in code.
static func load_item_resources() -> void:
	var dir_path := "res://items"
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file in DirAccess.get_files_at(dir_path):
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var data := load(dir_path + "/" + f) as ItemData
			if data:
				_items[data.id] = data

static func register_item(data: ItemData) -> void:
	_items[data.id] = data

static func get_item(id: String) -> ItemData:
	return _items.get(id)

## Creates an ItemData purely in code (no .tres file needed), e.g.:
## MultiSlotInventory.define_item("sword", "Sword", preload("res://icons/sword.png"), Vector2i(1, 3))
static func define_item(id: String, display_name: String, icon: Texture2D,
		size := Vector2i(1, 1), max_stack := 1) -> ItemData:
	var data := ItemData.new()
	data.id = id
	data.display_name = display_name
	data.icon = icon
	data.size = size
	data.max_stack = max_stack
	register_item(data)
	return data

# -- JSON save/load ----------------------------------------------------

static func save_inventory(inv: Inventory, path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(inv.to_dict(), "\t"))

static func load_inventory(path: String = SAVE_PATH) -> Inventory:
	if not FileAccess.file_exists(path):
		return Inventory.new()
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return Inventory.new()
	return Inventory.from_dict(parsed)

# -- SQLite save/load (optional) ---------------------------------------
# Requires the "godot-sqlite" addon (2shady4u) enabled under
# Project Settings -> Plugins. Uncomment to use instead of / alongside JSON.
#
# static var db := SQLite.new()
#
# static func open_db() -> void:
# 	db.path = "user://game.db"
# 	db.open_db()
# 	db.query("""CREATE TABLE IF NOT EXISTS inventory_items (
# 		id INTEGER PRIMARY KEY AUTOINCREMENT,
# 		inventory_id TEXT NOT NULL, item_id TEXT NOT NULL,
# 		cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL,
# 		rotated INTEGER NOT NULL DEFAULT 0,
# 		quantity INTEGER NOT NULL DEFAULT 1);""")
#
# static func save_to_db(inv: Inventory, inv_id: String) -> void:
# 	db.query("BEGIN TRANSACTION;")
# 	db.query_with_bindings("DELETE FROM inventory_items WHERE inventory_id = ?;", [inv_id])
# 	for item in inv.items:
# 		db.query_with_bindings(
# 			"INSERT INTO inventory_items (inventory_id,item_id,cell_x,cell_y,rotated,quantity) VALUES (?,?,?,?,?,?);",
# 			[inv_id, item.data.id, item.cell.x, item.cell.y, int(item.rotated), item.quantity])
# 	db.query("COMMIT;")
#
# static func load_from_db(inv_id: String, size := Vector2i(10, 6)) -> Inventory:
# 	var inv := Inventory.new(size)
# 	db.query_with_bindings("SELECT * FROM inventory_items WHERE inventory_id = ?;", [inv_id])
# 	for row in db.query_result:
# 		var data := get_item(row["item_id"])
# 		if data == null:
# 			continue
# 		var item := InventoryItem.new(data)
# 		item.rotated = row["rotated"] == 1
# 		item.quantity = row["quantity"]
# 		inv.place(item, Vector2i(row["cell_x"], row["cell_y"]))
# 	return inv
