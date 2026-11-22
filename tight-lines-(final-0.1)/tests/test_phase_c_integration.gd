extends SceneTree

const FISHING_SCENE_PATH := "res://3DFishingScene/Area1FishingScenes/3DFishingRiceField.tscn"
const OVERWORLD_UI_PATH := "res://UIScenesAndScript/OverworldUI/2DsceneUI.tscn"
const SAVE_SLOTS_PATH := "res://UIScenesAndScript/SaveSlots/SaveSlots.tscn"

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
		print("[FAIL] " + label)


func _run() -> void:
	print("=== Phase C Integration Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var sm := root.get_node_or_null("SaveManager")
	sm.new_game()

	# 1. Persistent clock/weather sync into 3D Fishing Scene's WeatherSystem
	gm.set_world_time_state({"game_minutes": 1260.0, "day_count": 4, "weather": "rain"})
	var fishing_scene := (load(FISHING_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(fishing_scene)
	current_scene = fishing_scene
	await process_frame
	await process_frame

	var ws := fishing_scene.find_child("WeatherSystem", true, false)
	_check(ws != null, "WeatherSystem found in 3DFishingRiceField")
	if ws != null:
		_check(String(ws.get("time_of_day")) == "night", "WeatherSystem inherited 'night' from GameManager")
		_check(String(ws.get("weather")) == "rain", "WeatherSystem inherited 'rain' from GameManager")
		_check(String(ws.call("get_clock_text")) == "21:00", "WeatherSystem inherited 21:00 clock")

		# Advance weather in 3D scene -> verify GameManager persists it
		ws.call("set_weather", "fog", true)
		_check(String(gm.get("world_weather")) == "fog", "WeatherSystem change propagated back to GameManager")

	fishing_scene.queue_free()
	await process_frame

	# 2. Overworld 2DsceneUI: WorldMapButton + WorldMapOverlay (Rest + Fast Travel lock gating)
	var ow_ui := (load(OVERWORLD_UI_PATH) as PackedScene).instantiate()
	root.add_child(ow_ui)
	await process_frame

	var map_btn := ow_ui.find_child("WorldMapButton", true, false) as Button
	var map_overlay := ow_ui.find_child("WorldMapOverlay", true, false) as Control
	var stuck_map_ui := ow_ui.find_child("WorldMapUi", true, false)
	_check(stuck_map_ui == null, "Stuck WorldMapUi node is removed from GameHUD Overlays")
	_check(map_btn != null and map_overlay != null, "OverworldUI built WorldMapButton and WorldMapOverlay")
	_check(map_btn.text.contains("Day 4"), "WorldMapButton shows persistent Day 4: %s" % map_btn.text)

	map_btn.pressed.emit()
	await process_frame
	_check(map_overlay.visible, "Clicking WorldMapButton opens WorldMapOverlay")

	# Test mobile/D-Pad interaction inside WorldMapOverlay
	map_overlay.call("handle_mobile_action", "back")
	await process_frame
	_check(not map_overlay.visible, "WorldMapOverlay handle_mobile_action('back') closes overlay")
	ow_ui.call("toggle_world_map")
	await process_frame
	_check(map_overlay.visible, "toggle_world_map reopens WorldMapOverlay")

	# Check locked vs unlocked destinations
	var snap1: Dictionary = map_overlay.call("get_destination_snapshot")
	_check(not bool(snap1["overworld_river_park"]["disabled"]), "Marikina River Park is unlocked at start")
	_check(bool(snap1["overworld_mangrove"]["disabled"]), "Calatagan Mangroves is locked before unlock_calatagan")
	_check(bool(snap1["overworld_island"]["disabled"]), "Fortune Island is locked before unlock_fortune_island")

	# Rest to Dusk -> verify overlay & button update
	var rest_dusk := map_overlay.find_child("Rest_dusk", true, false) as Button
	_check(rest_dusk != null, "Rest_dusk button exists on WorldMapOverlay")
	rest_dusk.pressed.emit()
	await process_frame
	_check(String(gm.get("world_time_of_day")) == "dusk", "Clicking Rest_dusk advanced GameManager to dusk")
	_check(map_btn.text.contains("17:30"), "WorldMapButton updated to 17:30: %s" % map_btn.text)

	# Unlock Calatagan & Fortune Island -> Calatagan unlocks on WorldMap, Fortune Island stays boat-only
	sm.add_unlock_flag("unlock_calatagan")
	sm.add_unlock_flag("unlock_fortune_island")
	map_overlay.call("refresh")
	var snap2: Dictionary = map_overlay.call("get_destination_snapshot")
	_check(not bool(snap2["overworld_mangrove"]["disabled"]), "Calatagan unlocked on WorldMap after flag granted")
	_check(bool(snap2["overworld_island"]["disabled"]), "Fortune Island fast travel via WorldMap stays disabled (boat via Calatagan only)")
	ow_ui.queue_free()
	await process_frame

	# 3. SaveSlots UI rich preview rendering
	var backup_slot0_exists: bool = sm.slot_exists(0)
	var backup_slot0_data: Dictionary = sm.load_game(0) if backup_slot0_exists else {}
	sm.add_money(555)
	sm.save_slot(0)

	var slots_ui := (load(SAVE_SLOTS_PATH) as PackedScene).instantiate()
	root.add_child(slots_ui)
	await process_frame
	var slot_list := slots_ui.find_child("SlotList", true, false)
	var first_btn := slot_list.get_child(0) as Button if slot_list != null and slot_list.get_child_count() > 0 else null
	_check(first_btn != null and first_btn.text.contains("₱555") and first_btn.text.contains("Almanac"),
		"SaveSlots button renders rich preview (₱555 + Almanac %%)")
	slots_ui.queue_free()

	# Restore slot 0 cleanly
	if backup_slot0_exists:
		sm.save_game(0, backup_slot0_data)
	else:
		sm.delete_save(0)

	await process_frame
	print("=== Phase C Integration Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
