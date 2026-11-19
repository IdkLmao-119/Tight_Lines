extends SceneTree

const LOBBY_SCENE := "res://UIScenesAndScript/MultiplayerLobby/MultiplayerLobby.tscn"
const MP_FISHING_SCENE := "res://3DFishingScene/MultiplayerFishingScene/3d_fishing_multiplayer.tscn"
const SP_FISHING_SCENE := "res://3DFishingScene/Area1FishingScenes/3DFishingRiceField.tscn"

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
	print("=== Phase D Integration Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var im := root.get_node_or_null("InputManager")
	sm.new_game()

	# 1. MultiplayerLobby: Win Mode & Arena selectors + state persistence + Results overlay mode label
	var lobby := (load(LOBBY_SCENE) as PackedScene).instantiate()
	root.add_child(lobby)
	await process_frame

	var mode_btn := lobby.find_child("WinModeButton", true, false) as Button
	var arena_btn := lobby.find_child("ArenaButton", true, false) as Button
	_check(mode_btn != null and arena_btn != null, "MultiplayerLobby has WinModeButton and ArenaButton")
	_check(String(lobby.call("get_selected_win_mode")) == "total_weight", "Default win mode is total_weight")

	mode_btn.pressed.emit()
	_check(String(lobby.call("get_selected_win_mode")) == "biggest_fish", "Cycling WinModeButton selects biggest_fish")
	mode_btn.pressed.emit()
	_check(String(lobby.call("get_selected_win_mode")) == "most_fish", "Cycling WinModeButton selects most_fish")

	var first_arena := String(lobby.call("get_selected_arena_id"))
	arena_btn.pressed.emit()
	var second_arena := String(lobby.call("get_selected_arena_id"))
	_check(second_arena != first_arena, "Cycling ArenaButton changes arena (%s -> %s)" % [first_arena, second_arena])

	var state: Dictionary = lobby.call("get_scene_state")
	_check(int(state.get("win_mode_idx", -1)) == 2 and int(state.get("arena_idx", -1)) == 1,
		"Lobby get_scene_state persists win_mode_idx and arena_idx")

	lobby.call("_show_results_overlay", {
		"winner": 2,
		"win_mode": "biggest_fish",
		"player_order": [1, 2],
		"player_names": {1: "Alice", 2: "Bob"},
		"results": {
			1: {"total_weight": 4.0, "catches": [{"weight": 1.0, "display_name": "A", "size_cm": 10.0}]},
			2: {"total_weight": 3.0, "catches": [{"weight": 3.0, "display_name": "B", "size_cm": 30.0}]},
		},
	})
	var winner_lbl := lobby.find_child("ResultsWinnerLabel", true, false) as Label
	_check(winner_lbl != null and winner_lbl.text.contains("Bob Wins!") and winner_lbl.text.contains("Biggest Fish"),
		"Results overlay displays winner + win mode: %s" % (winner_lbl.text if winner_lbl != null else ""))
	lobby.queue_free()
	await process_frame

	# 2. Multiplayer 3D Scene: consumes win_mode & spot_id context and updates HUD timer title
	gm.pending_context = {
		"multiplayer": true,
		"time_limit_sec": 120.0,
		"win_mode": "biggest_fish",
		"spot_id": "location_kawit",
		"player_ids": [1, 2],
	}
	var mp_scene := (load(MP_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(mp_scene)
	current_scene = mp_scene
	await process_frame
	await process_frame

	var mp_fm := mp_scene.find_child("FishingManager", true, false)
	var timer_title := mp_scene.find_child("TimerTitleLabel", true, false) as Label
	_check(mp_fm != null and String(mp_fm.get("_win_mode")) == "biggest_fish",
		"Multiplayer FishingManager applied win_mode='biggest_fish'")
	_check(timer_title != null and timer_title.text.contains("BIGGEST FISH"),
		"Multiplayer HUD timer title displays active win mode: %s" % (timer_title.text if timer_title != null else ""))
	mp_scene.queue_free()
	await process_frame

	# 3. Phone Quick-Swap Bait via InputManager.menu_action("cycle_bait") in 3D Fishing Scene
	inv.clear_all()
	inv.add_item("bait_1", 5)
	inv.add_item("bait_2", 5)
	sm.set_equipped_bait("bait_1")
	gm.pending_context = {}

	var sp_scene := (load(SP_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(sp_scene)
	current_scene = sp_scene
	await process_frame
	await process_frame

	var sp_fm := sp_scene.find_child("FishingManager", true, false)
	var bait_before := String(sp_fm.call("get_session_info", 1).get("bait_id", ""))
	im.menu_action.emit(1, "cycle_bait")
	await process_frame
	var bait_after := String(sp_fm.call("get_session_info", 1).get("bait_id", ""))
	_check(bait_after != "" and bait_after != bait_before,
		"cycle_bait switched active bait (%s -> %s)" % [bait_before, bait_after])
	_check(String(sm.get_equipped_bait()) == bait_after,
		"cycle_bait synced equipped bait to SaveManager (%s)" % sm.get_equipped_bait())
	sp_scene.queue_free()

	await process_frame
	print("=== Phase D Integration Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
