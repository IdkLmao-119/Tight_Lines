extends SceneTree

var _passed := 0
var _failed := 0
var _time_signals := 0


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
	print("=== Phase C Unit Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var sm := root.get_node_or_null("SaveManager")
	var db := root.get_node_or_null("GameDB")
	_check(gm != null and sm != null and db != null, "GameManager, SaveManager, GameDB loaded")
	if gm == null or sm == null or db == null:
		quit(1)
		return

	# 1. Dead "cutscene" entry removed
	_check(not gm.SCENES.has("cutscene"), "Dead 'cutscene' entry removed from GameManager.SCENES")
	_check(gm.get_scene_display_name("overworld_river_park") == "Marikina River Park",
		"get_scene_display_name returns 'Marikina River Park'")

	# 2. Persistent world clock & rest_to_phase
	gm.world_time_changed.connect(func(_st: Dictionary) -> void:
		_time_signals += 1)
	gm.reset_world_time()
	var st0: Dictionary = gm.get_world_time_state()
	_check(int(st0["day_count"]) == 1 and String(st0["time_of_day"]) == "day",
		"reset_world_time starts at Day 1 / day")

	var st_night: Dictionary = gm.rest_to_phase("night", "rain")
	_check(int(st_night["day_count"]) == 1, "Resting 08:00 -> night (21:00) stays on Day 1")
	_check(String(st_night["time_of_day"]) == "night" and String(st_night["weather"]) == "rain",
		"rest_to_phase sets night + rain")

	var st_dawn: Dictionary = gm.rest_to_phase("dawn", "fog")
	_check(int(st_dawn["day_count"]) == 2, "Resting night (21:00) -> dawn (05:30) advances to Day 2")
	_check(String(st_dawn["time_of_day"]) == "dawn" and String(st_dawn["weather"]) == "fog",
		"rest_to_phase sets dawn + fog")
	_check(_time_signals >= 3, "world_time_changed emitted on reset & rest")
	_check(String(gm.get_world_clock_text()).contains("Day 2") and String(gm.get_world_clock_text()).contains("05:30"),
		"get_world_clock_text formats Day 2 • 05:30: %s" % gm.get_world_clock_text())

	# 3. SaveManager persists world_time & builds rich slot preview
	sm.new_game()
	sm.add_money(325)
	sm.set_difficulty("angler")
	var all_fish: Array = db.get_all_fish()
	if not all_fish.is_empty():
		sm.record_fish_catch(all_fish[0].id, all_fish[0].avg_size)
	gm.set_world_time_state({"game_minutes": 1260.0, "day_count": 3, "weather": "storm"})

	var save_dict: Dictionary = JSON.parse_string(JSON.stringify(sm.build_save_data()))
	_check(save_dict.has("world_time"), "build_save_data includes world_time")
	gm.reset_world_time()
	sm.apply_save_data(save_dict)
	var restored: Dictionary = gm.get_world_time_state()
	_check(int(restored["day_count"]) == 3 and String(restored["weather"]) == "storm" and String(restored["time_of_day"]) == "night",
		"apply_save_data restores Day 3 / night / storm")

	# Test rich get_slot_info on a temporary slot (slot 99) and delete it
	var test_slot := 99
	_check(sm.save_slot(test_slot), "Saved temporary test slot 99")
	var info: Dictionary = sm.get_slot_info(test_slot)
	_check(bool(info["exists"]), "get_slot_info reports exists=true")
	_check(int(info["money"]) == 325, "get_slot_info reports money=325")
	_check(int(info["day_count"]) == 3, "get_slot_info reports day_count=3")
	_check(String(info["clock_text"]) == "21:00", "get_slot_info reports clock_text='21:00'")
	_check(String(info["difficulty"]) == "Angler", "get_slot_info reports difficulty='Angler'")
	_check(int(info["caught_count"]) == 1 and int(info["total_fish"]) >= 50,
		"get_slot_info reports caught_count=1 / total_fish=%d" % int(info["total_fish"]))
	sm.delete_save(test_slot)
	_check(not sm.slot_exists(test_slot), "Cleaned up temporary test slot 99")

	print("=== Phase C Unit Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
