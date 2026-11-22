extends SceneTree

const FishTankScene := preload("res://UIScenesAndScript/FishTankUI/FishTank.tscn")

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)
		print("[FAIL] ", label)


func _run() -> void:
	print("=== FishTank Unit Tests ===")

	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var db := root.get_node_or_null("GameDB")
	_check(sm != null and inv != null and db != null, "SaveManager, InventoryManager, GameDB loaded")
	if sm == null or inv == null or db == null:
		quit(1)
		return

	sm.new_game()
	inv.clear_all()

	var all_fish: Array = db.get_all_fish()
	_check(not all_fish.is_empty(), "GameDB has fish records")
	var sample_fish: FishData = all_fish[0]
	var fid := sample_fish.id
	var test_size := snappedf(lerpf(sample_fish.min_size, sample_fish.max_size, 0.6), 0.1)

	_check(inv.add_fish(fid, test_size), "Added sample fish to FISH_BOX")
	var uid: int = inv.get_uid_at(inv.FISH_BOX, 0)
	inv.set_item_locked(uid, true)

	var tank: Control = FishTankScene.instantiate()
	root.add_child(tank)
	await process_frame

	# 1. Add fish from Fish Box -> Tank
	_check(tank.add_fish_from_box(uid), "add_fish_from_box moves fish into tank")
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 0, "FISH_BOX is empty after moving fish to tank")
	_check(tank.fishes.size() == 1, "tank.fishes has 1 entry")
	_check(sm.get_fish_tank().size() == 1, "SaveManager.get_fish_tank() has 1 entry")

	var tank_area: TextureRect = tank.get_node("Panel/TextureRect")
	_check(tank_area.get_child_count() == 1, "Tank water has 1 spawned fish TextureRect")
	var entry: Dictionary = tank.fishes[0]
	var sprite := entry.get("sprite") as TextureRect
	var tween := entry.get("tween") as Tween
	_check(sprite != null and is_instance_valid(sprite), "Spawned fish has valid TextureRect")
	_check(tween != null and tween.is_valid(), "Spawned fish has active swim Tween")
	_check(sprite.flip_h == (int(entry["direction"]) == 1), "Sprite flip_h matches swim direction")

	# 2. Randomized swimming (both left->right and right->left occur)
	var saw_ltr := false
	var saw_rtl := false
	for _i in 40:
		tank._start_fish_swim(entry, false)
		var dir := int(entry["direction"])
		if dir == 1:
			if not saw_ltr:
				_check(sprite.flip_h == true, "Left-to-right fish sets flip_h = true")
			saw_ltr = true
		elif dir == -1:
			saw_rtl = true
		if saw_ltr and saw_rtl:
			break
	_check(saw_ltr and saw_rtl, "Randomized swimming produces both L->R and R->L directions")

	# 3. Persistence round-trip + backward compatibility + invalid fish drop
	var saved_json: String = JSON.stringify(sm.build_save_data())
	var parsed: Dictionary = JSON.parse_string(saved_json)
	sm.new_game()
	_check(sm.get_fish_tank().is_empty(), "new_game clears fish tank")
	_check(tank.fishes.is_empty(), "tank.fishes clears on new_game")

	sm.apply_save_data(parsed)
	_check(sm.get_fish_tank().size() == 1, "fish_tank survives JSON save/load")
	_check(tank.fishes.size() == 1, "tank.fishes rebuilds from SaveManager on load")
	var restored_meta: Dictionary = tank.fishes[0]["meta"]
	_check(is_equal_approx(float(restored_meta.get("size_cm", 0.0)), test_size), "Restored fish preserves size_cm")
	_check(bool(restored_meta.get("locked", false)) == true, "Restored fish preserves locked flag")

	# Older save without fish_tank key
	var legacy_save := parsed.duplicate(true)
	legacy_save.erase("fish_tank")
	sm.apply_save_data(legacy_save)
	_check(sm.get_fish_tank().is_empty() and tank.fishes.is_empty(), "Missing fish_tank key in older save loads cleanly as empty")

	# Invalid fish id in fish_tank is dropped
	var bad_save := parsed.duplicate(true)
	bad_save["fish_tank"] = [{"item_id": "fish_does_not_exist", "meta": {}}, {"item_id": fid, "meta": {"size_cm": test_size, "locked": true}}]
	sm.apply_save_data(bad_save)
	_check(sm.get_fish_tank().size() == 1 and tank.fishes.size() == 1, "Unknown fish_id in fish_tank is dropped while valid fish loads")

	# 4. No-data-loss when Fish Box is full
	var cap: int = inv.get_container_capacity(inv.FISH_BOX)
	for _i in cap:
		inv.add_fish(fid, test_size)
	_check(inv.get_free_slot_count(inv.FISH_BOX) == 0, "FISH_BOX filled to capacity (%d)" % cap)
	_check(not tank.remove_fish_at(0), "remove_fish_at(0) returns false when FISH_BOX is full")
	_check(tank.fishes.size() == 1 and sm.get_fish_tank().size() == 1, "Tank fish is preserved when FISH_BOX is full")

	# 5. Remove fish returns it to Fish Box with metadata intact
	inv.clear_all()
	_check(tank.remove_fish_at(0), "remove_fish_at(0) succeeds when FISH_BOX has space")
	_check(tank.fishes.is_empty() and sm.get_fish_tank().is_empty(), "Tank and SaveManager are empty after removal")
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 1, "Removed fish returned to FISH_BOX")
	var ret_uid: int = inv.get_uid_at(inv.FISH_BOX, 0)
	var ret_item: Dictionary = inv.get_item(ret_uid)
	_check(String(ret_item.get("item_id", "")) == fid, "Returned fish has original item_id")
	_check(is_equal_approx(float(ret_item["meta"].get("size_cm", 0.0)), test_size), "Returned fish has original size_cm")
	_check(inv.is_item_locked(ret_uid), "Returned fish preserves locked flag")

	# 6. Back / close hides tank
	tank.visible = true
	tank.close()
	_check(not tank.visible, "close() hides FishTank")

	tank.queue_free()
	await process_frame
	print("=== FishTank Unit Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
