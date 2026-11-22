extends Control

signal close_requested

@export_group("Spawn & Scale")
@export var fish_scale: float = 2.0

@export_group("Movement Speed (Pixels/Sec)")
@export var min_speed: float = 60.0
@export var max_speed: float = 110.0

var fishes: Array[Dictionary] = []

@onready var _tank_area: TextureRect = $Panel/TextureRect
@onready var _add_button: Button = $Panel/HBoxContainer/Button
@onready var _remove_button: Button = $Panel/HBoxContainer/Button2
@onready var _back_button: Button = $Panel/HBoxContainer/Button3

var _add_popup: PopupMenu = null
var _remove_popup: PopupMenu = null
var _add_popup_uids: Array[int] = []
var _updating_save := false


func _ready() -> void:
	_tank_area.clip_contents = true
	_add_button.pressed.connect(_on_add_button_pressed)
	_remove_button.pressed.connect(_on_remove_button_pressed)
	_back_button.pressed.connect(close)

	_add_popup = PopupMenu.new()
	_add_popup.max_size = Vector2i(360, 320)
	_add_popup.id_pressed.connect(_on_add_popup_id_pressed)
	add_child(_add_popup)

	_remove_popup = PopupMenu.new()
	_remove_popup.max_size = Vector2i(360, 320)
	_remove_popup.id_pressed.connect(_on_remove_popup_id_pressed)
	add_child(_remove_popup)

	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_signal(&"fish_tank_changed"):
		sm.connect(&"fish_tank_changed", _on_save_fish_tank_changed)

	_rebuild_from_save()


func close() -> void:
	visible = false
	close_requested.emit()


func add_fish_from_box(uid: int) -> bool:
	var inv := get_node_or_null("/root/InventoryManager")
	var sm := get_node_or_null("/root/SaveManager")
	if inv == null:
		return false

	var fish: Dictionary = inv.call("get_item", uid)
	if fish.is_empty() or String(fish.get("container", "")) != String(inv.get("FISH_BOX")):
		return false

	var fish_id := String(fish["item_id"])
	var meta: Dictionary = (fish["meta"] as Dictionary).duplicate(true) if fish.get("meta") is Dictionary else {}
	if int(inv.call("remove_item", uid)) <= 0:
		return false

	if sm != null:
		_updating_save = true
		var ok := bool(sm.call("add_tank_fish", fish_id, meta))
		_updating_save = false
		if not ok:
			# Roll back so the fish is never lost if SaveManager rejects it.
			inv.call("add_item", fish_id, 1, meta)
			return false

	_spawn_fish(fish_id, meta, true)
	return true


func remove_fish_at(index: int) -> bool:
	if index < 0 or index >= fishes.size():
		return false

	var entry: Dictionary = fishes[index]
	var fish_id := String(entry["item_id"])
	var meta: Dictionary = (entry["meta"] as Dictionary).duplicate(true)

	var inv := get_node_or_null("/root/InventoryManager")
	if inv != null:
		if not bool(inv.call("can_add", fish_id, 1, meta)) or int(inv.call("add_item", fish_id, 1, meta)) != 0:
			_notify("Fish Box is full! Make room before removing fish.")
			return false

	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		_updating_save = true
		sm.call("remove_tank_fish", index)
		_updating_save = false

	_despawn_fish_at(index)
	return true


func _create_fish_sprite(tex: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.scale = Vector2(fish_scale, fish_scale)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


func _spawn_fish(fish_id: String, meta: Dictionary, start_inside: bool = false) -> void:
	var tex := _get_fish_texture(fish_id)
	var sprite: TextureRect = null
	if tex != null:
		sprite = _create_fish_sprite(tex)
		_tank_area.add_child(sprite)

	var entry := {
		"item_id": fish_id,
		"meta": meta.duplicate(true),
		"sprite": sprite,
		"tween": null,
		"direction": 0,
	}
	fishes.append(entry)

	if sprite != null:
		_start_fish_swim(entry, start_inside)


func _start_fish_swim(entry: Dictionary, start_inside: bool = false) -> void:
	var sprite := entry.get("sprite") as TextureRect
	if sprite == null or not is_instance_valid(sprite) or sprite.is_queued_for_deletion():
		return

	var prev_tween: Variant = entry.get("tween")
	if prev_tween is Tween and (prev_tween as Tween).is_valid():
		(prev_tween as Tween).kill()

	var tank_size := _tank_area.size
	if tank_size.x <= 0.0 or tank_size.y <= 0.0:
		tank_size = Vector2(868.0, 500.75)

	var scaled_size := sprite.texture.get_size() * fish_scale
	var left_to_right := randf() < 0.5
	# Sprites face left by default, so flip_h makes them face right.
	sprite.flip_h = left_to_right

	var start_x := (
		randf_range(0.0, maxf(0.0, tank_size.x - scaled_size.x))
		if start_inside
		else (-scaled_size.x if left_to_right else tank_size.x)
	)
	var end_x := tank_size.x if left_to_right else -scaled_size.x
	var random_y := randf_range(0.0, maxf(0.0, tank_size.y - scaled_size.y))

	sprite.position = Vector2(start_x, random_y)

	var distance := absf(end_x - start_x)
	var speed := randf_range(min_speed, max_speed)
	var duration := distance / maxf(speed, 1.0)

	var tween := sprite.create_tween()
	entry["tween"] = tween
	entry["direction"] = 1 if left_to_right else -1
	tween.tween_property(sprite, "position:x", end_x, duration)
	tween.tween_callback(_start_fish_swim.bind(entry, false))


func _despawn_fish_at(index: int) -> void:
	if index < 0 or index >= fishes.size():
		return
	var entry: Dictionary = fishes[index]
	var tween: Variant = entry.get("tween")
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	var sprite: Variant = entry.get("sprite")
	if sprite is TextureRect and is_instance_valid(sprite):
		(sprite as TextureRect).queue_free()
	fishes.remove_at(index)


func _rebuild_from_save() -> void:
	for i in range(fishes.size() - 1, -1, -1):
		_despawn_fish_at(i)

	var sm := get_node_or_null("/root/SaveManager")
	if sm == null or not sm.has_method(&"get_fish_tank"):
		return
	var saved: Array = sm.call(&"get_fish_tank")
	for raw in saved:
		if raw is Dictionary:
			var fid := String(raw.get("item_id", ""))
			var meta: Dictionary = raw["meta"] if raw.get("meta") is Dictionary else {}
			if fid != "":
				_spawn_fish(fid, meta, true)


func _on_save_fish_tank_changed() -> void:
	if not _updating_save:
		_rebuild_from_save()


func _on_add_button_pressed() -> void:
	_add_popup.clear()
	_add_popup_uids.clear()

	var inv := get_node_or_null("/root/InventoryManager")
	var fish_list: Array = inv.call("get_items", inv.get("FISH_BOX")) if inv != null else []
	if fish_list.is_empty():
		_add_popup.add_item("No fish in Fish Box", -1)
		_add_popup.set_item_disabled(0, true)
	else:
		for i in fish_list.size():
			var fish: Dictionary = fish_list[i]
			var fid := String(fish["item_id"])
			var meta: Dictionary = fish["meta"] if fish.get("meta") is Dictionary else {}
			_add_popup_uids.append(int(fish["uid"]))
			_add_popup.add_icon_item(_get_fish_texture(fid), _format_fish_label(fid, meta), i)
			_add_popup.set_item_icon_max_width(i, 36)

	_add_popup.reset_size()
	_add_popup.popup_centered()


func _on_remove_button_pressed() -> void:
	_remove_popup.clear()
	if fishes.is_empty():
		_remove_popup.add_item("Tank is empty", -1)
		_remove_popup.set_item_disabled(0, true)
	else:
		for i in fishes.size():
			var entry: Dictionary = fishes[i]
			var fid := String(entry["item_id"])
			var meta: Dictionary = entry["meta"] if entry.get("meta") is Dictionary else {}
			_remove_popup.add_icon_item(_get_fish_texture(fid), _format_fish_label(fid, meta), i)
			_remove_popup.set_item_icon_max_width(i, 36)

	_remove_popup.reset_size()
	_remove_popup.popup_centered()


func _on_add_popup_id_pressed(id: int) -> void:
	if id >= 0 and id < _add_popup_uids.size():
		add_fish_from_box(_add_popup_uids[id])


func _on_remove_popup_id_pressed(id: int) -> void:
	if id >= 0 and id < fishes.size():
		remove_fish_at(id)


func _get_fish_record(fish_id: String) -> FishData:
	var db := get_node_or_null("/root/GameDB")
	if db != null and bool(db.call("has_fish", fish_id)):
		return db.call("get_fish", fish_id) as FishData
	return null


func _get_fish_texture(fish_id: String) -> Texture2D:
	var record := _get_fish_record(fish_id)
	if record != null:
		return record.icon if record.icon != null else record.icon_3d
	return null


func _format_fish_label(fish_id: String, meta: Dictionary) -> String:
	var record := _get_fish_record(fish_id)
	var display_name := record.display_name if (record != null and record.display_name != "") else fish_id
	var prefix := "★ " if bool(meta.get("locked", false)) else ""
	if meta.has("size_cm"):
		return "%s%s (%.1f cm)" % [prefix, display_name, float(meta["size_cm"])]
	return "%s%s" % [prefix, display_name]


func _notify(msg: String) -> void:
	var hud := get_parent().get_parent() if get_parent() != null else null
	if hud != null and hud.has_method(&"show_toast"):
		hud.call(&"show_toast", msg)
	else:
		push_warning(msg)
