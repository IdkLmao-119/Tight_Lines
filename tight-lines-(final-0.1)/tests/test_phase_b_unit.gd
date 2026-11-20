extends SceneTree

var _passed := 0
var _failed := 0
var _record_signal_count := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)
		print("[FAIL] " + label)


func _run() -> void:
	print("=== Phase B Unit Tests ===")

	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var db := root.get_node_or_null("GameDB")
	_check(sm != null and inv != null and db != null, "SaveManager, InventoryManager, GameDB loaded")
	if sm == null or inv == null or db == null:
		quit(1)
		return

	sm.new_game()
	sm.fish_record_broken.connect(func(_fid: String, _sz: float, _w: float) -> void:
		_record_signal_count += 1)

	# 1. Personal Best & Trophy Tier
	var all_fish: Array = db.get_all_fish()
	_check(not all_fish.is_empty(), "GameDB has fish records")
	var sample_fish: FishData = all_fish[0]
	var fid := sample_fish.id
	var mid_size := lerpf(sample_fish.min_size, sample_fish.max_size, 0.55)
	var gold_size := lerpf(sample_fish.min_size, sample_fish.max_size, 0.95)
	var small_size := lerpf(sample_fish.min_size, sample_fish.max_size, 0.15)

	_check(sm.get_trophy_tier(fid, small_size) == "", "Small fish gets no trophy tier")
	_check(sm.get_trophy_tier(fid, mid_size) == "Bronze", "Mid-size fish gets Bronze trophy tier")
	_check(sm.get_trophy_tier(fid, gold_size) == "Gold", "Near-max fish gets Gold trophy tier")

	var first: Dictionary = sm.record_fish_catch(fid, mid_size)
	_check(bool(first["is_new_species"]), "First catch flags is_new_species=true")
	_check(not bool(first["is_new_record"]), "First catch is not a record break yet")
	_check(int(first["record"]["count"]) == 1, "Catch count is 1 after first catch")

	var smaller: Dictionary = sm.record_fish_catch(fid, small_size)
	_check(not bool(smaller["is_new_species"]) and not bool(smaller["is_new_record"]), "Smaller repeat catch does not break record")
	_check(int(sm.get_fish_record(fid)["count"]) == 2, "Catch count increments to 2")

	var bigger: Dictionary = sm.record_fish_catch(fid, gold_size)
	_check(bool(bigger["is_new_record"]), "Larger repeat catch breaks personal record")
	_check(String(bigger["trophy_tier"]) == "Gold", "Record catch reports Gold trophy")
	_check(_record_signal_count == 1, "fish_record_broken signal emitted once")

	# Save/load round trip of fish_records
	var saved_json: String = JSON.stringify(sm.build_save_data())
	var parsed: Dictionary = JSON.parse_string(saved_json)
	sm.new_game()
	_check(int(sm.get_fish_record(fid)["count"]) == 0, "new_game resets fish_records")
	sm.apply_save_data(parsed)
	_check(int(sm.get_fish_record(fid)["count"]) == 3, "fish_records count survives JSON save/load")
	_check(is_equal_approx(float(sm.get_fish_record(fid)["best_size_cm"]), snappedf(gold_size, 0.1)),
		"fish_records best_size_cm survives JSON save/load")

	# 2. Fish Lock/Favorite & persistence
	inv.clear_all()
	_check(inv.add_fish(fid, gold_size), "Added fish to FISH_BOX")
	var uid: int = inv.get_uid_at(inv.FISH_BOX, 0)
	_check(not inv.is_item_locked(uid), "New fish starts unlocked")
	_check(inv.toggle_item_locked(uid) == true, "toggle_item_locked locks fish")
	_check(inv.is_item_locked(uid), "is_item_locked reports true")

	var inv_snap: Dictionary = JSON.parse_string(JSON.stringify(inv.to_save_data()))
	inv.clear_all()
	inv.load_save_data(inv_snap)
	var restored_uid: int = inv.get_uid_at(inv.FISH_BOX, 0)
	_check(inv.is_item_locked(restored_uid), "Locked flag persists through inventory save/load")

	# 3. Compost Pit bait crafting
	var locked_res: Dictionary = inv.compost_fish(restored_uid)
	_check(not bool(locked_res["ok"]) and String(locked_res["reason"]) == "locked",
		"compost_fish refuses locked fish")

	inv.set_item_locked(restored_uid, false)
	var bait_before: int = inv.get_used_slot_count(inv.TACKLE_BOX)
	var ok_res: Dictionary = inv.compost_fish(restored_uid)
	_check(bool(ok_res["ok"]), "compost_fish succeeds on unlocked fish")
	_check(int(ok_res["count"]) >= 1, "compost_fish yields >= 1 bait (%s x%d)" % [ok_res.get("bait_name", ""), int(ok_res.get("count", 0))])
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 0, "Composted fish removed from FISH_BOX")
	_check(inv.get_used_slot_count(inv.TACKLE_BOX) > bait_before, "Crafted bait added to TACKLE_BOX")

	print("=== Phase B Unit Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
