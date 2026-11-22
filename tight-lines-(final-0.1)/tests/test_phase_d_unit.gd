extends SceneTree

const FishingManagerScript := preload("res://AutoloadFolders/FishingManager/FishingManager.gd")
const WeatherSystemScript := preload("res://AutoloadFolders/WeatherSystem/WeatherSystem.gd")

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
	print("=== Phase D Unit Tests ===")

	# 1. Multiplayer win mode scoring (total_weight, biggest_fish, most_fish, tie)
	# P1: 3 small fish (1.0 + 1.0 + 1.0 = 3.0 kg, max 1.0 kg, count 3)
	# P2: 1 huge fish (2.5 kg, max 2.5 kg, count 1)
	var results := {
		1: {"total_weight": 3.0, "catches": [{"weight": 1.0}, {"weight": 1.0}, {"weight": 1.0}]},
		2: {"total_weight": 2.5, "catches": [{"weight": 2.5}]},
	}
	_check(FishingManagerScript.compute_winner_id(results, "total_weight") == 1,
		"total_weight mode picks Player 1 (3.0 kg > 2.5 kg)")
	_check(FishingManagerScript.compute_winner_id(results, "biggest_fish") == 2,
		"biggest_fish mode picks Player 2 (2.5 kg > 1.0 kg)")
	_check(FishingManagerScript.compute_winner_id(results, "most_fish") == 1,
		"most_fish mode picks Player 1 (3 fish > 1 fish)")

	var tied := {
		1: {"total_weight": 2.0, "catches": [{"weight": 2.0}]},
		2: {"total_weight": 2.0, "catches": [{"weight": 2.0}]},
	}
	_check(FishingManagerScript.compute_winner_id(tied, "total_weight") == -1, "total_weight tie returns -1")
	_check(FishingManagerScript.compute_winner_id(tied, "biggest_fish") == -1, "biggest_fish tie returns -1")
	_check(FishingManagerScript.compute_winner_id(tied, "most_fish") == -1, "most_fish tie returns -1")

	# 2. GameHUD phone menu map includes quests
	var game_hud_script: GDScript = load("res://UIScenesAndScript/Shared/game_hud.gd")
	_check(game_hud_script.PHONE_MENU_NAMES.has("quests"), "GameHUD.PHONE_MENU_NAMES includes 'quests'")

	# 3. WeatherSystem split-screen midpoint camera tracking
	var host := Node3D.new()
	var vp1 := SubViewport.new()
	var cam1 := Camera3D.new()
	cam1.position = Vector3(-10.0, 2.0, 0.0)
	cam1.current = true
	vp1.add_child(cam1)
	host.add_child(vp1)

	var vp2 := SubViewport.new()
	var cam2 := Camera3D.new()
	cam2.position = Vector3(10.0, 2.0, 0.0)
	cam2.current = true
	vp2.add_child(cam2)
	host.add_child(vp2)

	var ws: Node3D = WeatherSystemScript.new()
	host.add_child(ws)
	root.add_child(host)
	current_scene = host
	await process_frame
	ws.call("_follow_camera")
	var rain_node := ws.get_node_or_null("Rain") as Node3D
	_check(rain_node != null, "WeatherSystem created Rain node")
	if rain_node != null:
		_check(is_equal_approx(rain_node.global_position.x, 0.0),
			"Split-screen Rain centers at midpoint X=0.0 between cameras at -10 and +10")
	host.queue_free()

	# 4. Audit regression checks (GameDB 0 warnings, Bait economy, Story chain, Swing power, Split-screen)
	var db := root.get_node_or_null("GameDB")
	var im := root.get_node_or_null("InputManager")
	var sm := root.get_node_or_null("SaveManager")
	var story := root.get_node_or_null("StoryManager")
	if db != null:
		_check(db.load_warnings.is_empty() and db.load_errors.is_empty(), "GameDB loaded with 0 warnings and 0 errors")
		var b1 = db.get_bait("bait_1")
		var b2 = db.get_bait("bait_2")
		_check(b1 != null and b1.unlimited and b2 != null and not b2.unlimited and b2.compost_weight > 0.0,
			"bait_1 is unlimited fallback and bait_2..6 are consumable with compost weight")
	if im != null:
		var gentle_power: float = float(im.call("_swing_to_power", 14.0))
		_check(gentle_power <= 0.35, "Light swing at threshold (14.0) produces gentle cast power (%.2f)" % gentle_power)
	if story != null and sm != null:
		sm.add_unlock_flag("saw_lolo_diary")
		_check(bool(story.call("requirements_met", "marikina_street")),
			"marikina_street unlocks when saw_lolo_diary flag is set")
		story.command_emitted.emit("objective", PackedStringArray(["Go to the jeep."]))
		_check(String(story.call("get_current_objective")) == "Go to the jeep.",
			"Story objective set to 'Go to the jeep.'")
		story.call("notify_jeep_reached")
		_check(String(story.call("get_current_objective")) == "",
			"notify_jeep_reached completes and clears 'Go to the jeep.' objective")

	await process_frame
	print("=== Phase D Unit Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
