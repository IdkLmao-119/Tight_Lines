extends SceneTree

const FishingManagerScript := preload("res://AutoloadFolders/FishingManager/FishingManager.gd")
const GameManagerScript := preload("res://AutoloadFolders/GameManager/GameManager.gd")
const SEASIDE_SCENE_PATH := "res://3DFishingScene/Area2FishingScenes/3DFishingSeasidePark.tscn"
const RICE_FIELD_SCENE_PATH := "res://3DFishingScene/Area1FishingScenes/3DFishingRiceField.tscn"
const OVERWORLD_UI_PATH := "res://UIScenesAndScript/OverworldUI/2DsceneUI.tscn"

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
	print("=== Tide System Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var db := root.get_node_or_null("GameDB")
	var sm := root.get_node_or_null("SaveManager")
	_check(gm != null and db != null and sm != null, "GameManager, GameDB, SaveManager loaded")
	if gm == null or db == null or sm == null:
		quit(1)
		return

	# 1. JSON config loaded
	var cfg: Dictionary = gm.call("get_tide_config")
	_check(is_equal_approx(float(cfg.get("cycle_hours", 0.0)), 12.42), "tide_config cycle_hours == 12.42")
	_check(is_equal_approx(float(cfg.get("slack_threshold", 0.0)), 0.25), "tide_config slack_threshold == 0.25")
	var mults: Dictionary = cfg.get("multipliers", {})
	_check(is_equal_approx(float(mults.get("rising", 0.0)), 1.25), "rising multiplier == 1.25")
	_check(is_equal_approx(float(mults.get("high_slack", 0.0)), 0.90), "high_slack multiplier == 0.90")
	_check(is_equal_approx(float(mults.get("falling", 0.0)), 1.30), "falling multiplier == 1.30")
	_check(is_equal_approx(float(mults.get("low_slack", 0.0)), 0.85), "low_slack multiplier == 0.85")

	# 2. Sine wave math at quarter-cycle points & 12.42h daily phase shift
	var t_rise: Dictionary = GameManagerScript.compute_tide(0.0, cfg)
	var t_high: Dictionary = GameManagerScript.compute_tide(3.105, cfg)
	var t_fall: Dictionary = GameManagerScript.compute_tide(6.21, cfg)
	var t_low: Dictionary = GameManagerScript.compute_tide(9.315, cfg)
	_check(String(t_rise["state"]) == "rising" and is_equal_approx(float(t_rise["multiplier"]), 1.25),
		"t=0.0 is rising (1.25x)")
	_check(String(t_high["state"]) == "high_slack" and is_equal_approx(float(t_high["multiplier"]), 0.90),
		"t=3.105 is high_slack (0.90x)")
	_check(String(t_fall["state"]) == "falling" and is_equal_approx(float(t_fall["multiplier"]), 1.30),
		"t=6.21 is falling (1.30x)")
	_check(String(t_low["state"]) == "low_slack" and is_equal_approx(float(t_low["multiplier"]), 0.85),
		"t=9.315 is low_slack (0.85x)")

	# Boundary check around slack_threshold = 0.25
	var cos_boundary_hr := 12.42 * acos(0.24) / TAU
	_check(String(GameManagerScript.compute_tide(cos_boundary_hr, cfg)["state"]) == "high_slack",
		"abs(flow)=0.24 < 0.25 is slack")
	var t_day2: Dictionary = GameManagerScript.compute_tide(24.0, cfg)
	_check(not is_equal_approx(float(t_day2["height"]), float(t_rise["height"])),
		"12.42h cycle shifts tide phase between Day 1 (0.0h) and Day 2 (24.0h)")

	# 3. GameDB cleanliness & location tidal flags
	_check(db.load_warnings.is_empty() and db.load_errors.is_empty(),
		"GameDB loaded with 0 warnings and 0 errors")
	for fw_id in ["location_marikina", "location_imus"]:
		_check(not bool(gm.call("is_location_tidal", fw_id)), "%s is freshwater (is_tidal=false)" % fw_id)
	for coastal_id in ["location_kawit", "location_fish_pens", "location_salt_farm", "location_calatagan", "location_fortune_island"]:
		_check(bool(gm.call("is_location_tidal", coastal_id)), "%s is tidal (is_tidal=true)" % coastal_id)

	# 4. FishingManager catch rate formula: Weather * Time * Tide (freshwater = 1.00x)
	var fm: Node = FishingManagerScript.new()
	var base_mult := float(fm.get_bite_speed_multiplier(false, "rain", 9))
	_check(is_equal_approx(base_mult, 1.30), "3-arg get_bite_speed_multiplier backward compatible (1.30)")
	var tidal_rising := float(fm.get_bite_speed_multiplier(false, "rain", 9, 1, 0.0))
	var tidal_falling := float(fm.get_bite_speed_multiplier(false, "clear", 9, 1, 6.21))
	var freshwater_mult := float(fm.get_bite_speed_multiplier(false, "rain", 9, 0, 6.21))
	_check(is_equal_approx(tidal_rising, 1.30 * 1.25), "Tidal rising multiplies weather*time by 1.25x")
	_check(is_equal_approx(tidal_falling, 1.00 * 1.30), "Tidal falling multiplies weather*time by 1.30x")
	_check(is_equal_approx(freshwater_mult, 1.30), "Freshwater ignores tide (1.00x)")
	fm.free()

	# 5. Scene HUD integration: Seaside Park shows TideIndicator, Rice Field hides it, WorldMapOverlay updates on Rest
	sm.new_game()
	gm.set_world_time_state({"game_minutes": 0.0, "day_count": 1, "weather": "clear"})

	var sea_scene := (load(SEASIDE_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(sea_scene)
	current_scene = sea_scene
	await process_frame
	await process_frame
	var sea_ui := sea_scene.find_child("3DSceneUI", true, false)
	var sea_snap: Dictionary = sea_ui.call("get_hud_snapshot") if sea_ui != null else {}
	_check(bool(sea_snap.get("tide_visible", false)), "Seaside Park FishingUI shows TideIndicator")
	_check(String(sea_snap.get("tide_state", "")) == "rising", "Seaside Park TideIndicator shows 'rising' at t=0.0")
	sea_scene.queue_free()
	await process_frame

	var rice_scene := (load(RICE_FIELD_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(rice_scene)
	current_scene = rice_scene
	await process_frame
	await process_frame
	var rice_ui := rice_scene.find_child("3DSceneUI", true, false)
	var rice_snap: Dictionary = rice_ui.call("get_hud_snapshot") if rice_ui != null else {}
	_check(not bool(rice_snap.get("tide_visible", true)), "Rice Field FishingUI hides TideIndicator (freshwater)")
	rice_scene.queue_free()
	await process_frame

	var ow_ui := (load(OVERWORLD_UI_PATH) as PackedScene).instantiate()
	root.add_child(ow_ui)
	await process_frame
	var map_overlay := ow_ui.find_child("WorldMapOverlay", true, false) as Control
	var map_tide := map_overlay.find_child("TideIndicator", true, false) if map_overlay != null else null
	_check(map_tide != null, "WorldMapOverlay contains TideIndicator")
	var rest_dusk := map_overlay.find_child("Rest_dusk", true, false) as Button if map_overlay != null else null
	if rest_dusk != null and map_tide != null:
		rest_dusk.pressed.emit()
		await process_frame
		# 17.5h on Day 1: phase = 2*pi*17.5/12.42 = 8.853 rad -> cos(8.853) = -0.842 -> falling
		_check(String(map_tide.get("tide_state")) == "falling",
			"WorldMapOverlay TideIndicator updates on Rest_dusk (17:30 -> falling)")
	ow_ui.queue_free()
	await process_frame

	print("=== Tide System Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
