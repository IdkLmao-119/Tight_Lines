extends SceneTree

const LOBBY_SCRIPT := preload("res://UIScenesAndScript/MultiplayerLobby/scene_script_multiplayer_lobby.gd")
const FM_SCRIPT := preload("res://AutoloadFolders/FishingManager/FishingManager.gd")
const MP_FISHING_SCENE := "res://3DFishingScene/MultiplayerFishingScene/3d_fishing_multiplayer.tscn"

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
	print("=== Multiplayer Catching & Edge Cases Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var im := root.get_node_or_null("InputManager")
	var db := root.get_node_or_null("GameDB")

	sm.new_game()
	inv.clear_all()

	# 1. All 7 Arena Spots Catchability across all times of day & weathers
	var times := ["dawn", "day", "dusk", "night"]
	var weathers := ["clear", "cloudy", "rain", "storm"]
	var all_arenas_ok := true
	for spot in LOBBY_SCRIPT.ARENA_SPOTS:
		var spot_id := String(spot["id"])
		var rod_id := String(spot["rod_id"])
		var bait_id := String(spot["bait_id"])
		for tod in times:
			for wx in weathers:
				var odds: Dictionary = db.get_catch_odds(spot_id, bait_id, rod_id, {
					"unlocked": [],
					"time_of_day": tod,
					"weather": wx,
				})
				if odds.is_empty():
					all_arenas_ok = false
					push_error("Empty odds for %s (%s/%s) at %s/%s" % [spot_id, rod_id, bait_id, tod, wx])
	_check(all_arenas_ok, "All 7 multiplayer arenas have non-empty catch odds across all times of day & weathers")

	# 2. Full 2-Player Catching Lifecycle on Fortune Island
	inv.add_item("bait_3", 2)
	var bait_before_mp := int(inv.count_of("bait_3"))
	var unlocked_before: int = sm.get_unlock_flags().size()

	gm.pending_context = {
		"multiplayer": true,
		"time_limit_sec": 60.0,
		"win_mode": "total_weight",
		"spot_id": "location_fortune_island",
		"rod_id": "rod_medium_heavy",
		"bait_id": "bait_3",
		"player_ids": [1, 2],
		"player_names": {1: "Alice", 2: "Bob"},
	}
	var mp_scene := (load(MP_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(mp_scene)
	current_scene = mp_scene
	await process_frame
	await process_frame

	var fm := mp_scene.find_child("FishingManager", true, false)
	_check(fm != null, "Multiplayer FishingManager loaded")

	var caught_events: Array = []
	fm.fish_caught.connect(func(pid: int, fish: Dictionary) -> void:
		caught_events.append({"pid": pid, "fish": fish})
	)

	# Cast both players
	fm.call("_on_cast", 1, 0.7)
	fm.call("_on_cast", 2, 0.8)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.CASTING and int(fm.call("get_state", 2)) == FM_SCRIPT.State.CASTING,
		"Both players transition to CASTING on _on_cast")
	_check(int(inv.count_of("bait_3")) == bait_before_mp,
		"Multiplayer casting does not consume InventoryManager bait")

	var sessions: Dictionary = fm.get("_sessions")
	var s1 = sessions[1]
	var s2 = sessions[2]

	# Advance past cast_duration -> WAITING
	fm.call("_update_casting", s1, 2.0)
	fm.call("_update_casting", s2, 2.0)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.WAITING and int(fm.call("get_state", 2)) == FM_SCRIPT.State.WAITING,
		"Both players transition to WAITING after cast lands")

	# Multiplayer guards: _on_cancel and cycle_bait are disabled
	fm.call("_on_cancel", 1)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.WAITING,
		"_on_cancel does not recall WAITING bobber in multiplayer")
	_check(String(fm.call("cycle_bait", 1)) == "",
		"cycle_bait returns empty string in multiplayer")

	# Recall P1 via _on_interact(1), P2 stays WAITING
	fm.call("_on_interact", 1)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.IDLE and int(fm.call("get_state", 2)) == FM_SCRIPT.State.WAITING,
		"_on_interact recalls P1 to IDLE while P2 remains WAITING")

	# Re-cast P1 -> WAITING, then trigger bites for both
	fm.call("_on_cast", 1, 0.5)
	fm.call("_update_casting", s1, 2.0)
	fm.call("_try_bite", s1)
	fm.call("_try_bite", s2)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.REELING and int(fm.call("get_state", 2)) == FM_SCRIPT.State.REELING,
		"Both players enter REELING with rolled fish on Fortune Island")
	_check(not s1.fish.is_empty() and not s2.fish.is_empty(),
		"Both players rolled non-empty fish records")

	# Reeling builds tension & progress; releasing lowers tension
	var st1: Dictionary = im.call("_get_state", 1)
	st1["crank_until"] = Time.get_ticks_msec() / 1000.0 + 5.0
	st1["release_until"] = 0.0
	var prog_before := float(s1.progress)
	fm.call("_update_reeling", s1, 0.25)
	_check(float(s1.tension) > 0.0 and float(s1.progress) > prog_before,
		"Reeling builds tension and increases catch progress")

	st1["crank_until"] = 0.0
	st1["release_until"] = Time.get_ticks_msec() / 1000.0 + 5.0
	var tension_before_release := float(s1.tension)
	fm.call("_update_reeling", s1, 0.25)
	_check(float(s1.tension) < tension_before_release,
		"Releasing lowers tension")
	st1["release_until"] = 0.0

	# P1 catches fish; P2 stays REELING undisturbed
	fm.call("_fish_won", s1)
	await process_frame
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.CAUGHT and int(fm.call("get_state", 2)) == FM_SCRIPT.State.REELING,
		"P1 enters CAUGHT while P2 remains REELING undisturbed")
	_check(caught_events.size() == 1 and int(caught_events[0]["pid"]) == 1,
		"fish_caught emitted for P1")
	var left_score := mp_scene.find_child("LeftHudScoreLabel", true, false) as Label
	_check(left_score != null and left_score.text.begins_with("1 fish"),
		"P1 HUD score updated to 1 fish (%s)" % (left_score.text if left_score != null else ""))
	_check(int(inv.count_of("bait_3")) == bait_before_mp and sm.get_unlock_flags().size() == unlocked_before,
		"Multiplayer catch does not mutate InventoryManager or SaveManager")

	var popups: Dictionary = fm.get("_popups")
	var p1_box := (popups.get(1) as Node).find_child("CatchPopupBox", true, false) as Control if popups.get(1) is Node else null
	_check(p1_box != null and is_equal_approx(p1_box.anchor_left, 0.0) and is_equal_approx(p1_box.anchor_right, 0.5),
		"P1 catch popup anchored to left half (0.0..0.5)")

	# P2 catches fish
	fm.call("_fish_won", s2)
	await process_frame
	var right_score := mp_scene.find_child("RightHudScoreLabel", true, false) as Label
	_check(right_score != null and right_score.text.begins_with("1 fish"),
		"P2 HUD score updated to 1 fish (%s)" % (right_score.text if right_score != null else ""))
	var p2_box := (popups.get(2) as Node).find_child("CatchPopupBox", true, false) as Control if popups.get(2) is Node else null
	_check(p2_box != null and is_equal_approx(p2_box.anchor_left, 0.5) and is_equal_approx(p2_box.anchor_right, 1.0),
		"P2 catch popup anchored to right half (0.5..1.0)")

	# Return both to IDLE
	fm.call("_set_state", s1, FM_SCRIPT.State.IDLE)
	fm.call("_set_state", s2, FM_SCRIPT.State.IDLE)

	# 3. Line Snap & Knotting Edge Cases
	fm.call("_on_cast", 1, 0.6)
	fm.call("_update_casting", s1, 2.0)
	fm.call("_try_bite", s1)
	fm.call("_on_cast", 2, 0.6)
	fm.call("_update_casting", s2, 2.0)
	fm.call("_try_bite", s2)

	fm.call("_fish_escapes", s1, "line_snapped")
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.ESCAPED and bool(s1.needs_knot),
		"Line snap puts P1 in ESCAPED with needs_knot=true")
	s1.state_time = 2.0
	fm.call("_update_session", s1, 0.1)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.KNOTTING and int(fm.call("get_state", 2)) == FM_SCRIPT.State.REELING,
		"P1 transitions to KNOTTING while P2 stays REELING")

	fm.call("_on_knot_completed", 1, "Bowline", 0.95)
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.IDLE and not bool(s1.needs_knot),
		"_on_knot_completed returns P1 to IDLE with needs_knot=false")

	# 4. Fish Got Away Edge Case
	s2.progress = 0.0
	fm.call("_update_reeling", s2, 0.016)
	_check(int(fm.call("get_state", 2)) == FM_SCRIPT.State.ESCAPED and not bool(s2.needs_knot),
		"progress <= 0.0 triggers ESCAPED (got_away) with needs_knot=false")
	fm.call("_set_state", s2, FM_SCRIPT.State.IDLE)

	# 5. Time-Up & Overtime Finish + KNOTTING time-up exit
	fm.call("_on_cast", 1, 0.5)
	fm.call("_update_casting", s1, 2.0)
	fm.call("_try_bite", s1)
	fm.call("_fish_escapes", s1, "line_snapped")
	fm.call("_start_knotting", s1)

	fm.call("_on_cast", 2, 0.5)
	fm.call("_update_casting", s2, 2.0) # P2 is WAITING

	var rejected_reasons: Array = []
	fm.cast_rejected.connect(func(_pid: int, reason: String) -> void:
		rejected_reasons.append(reason)
	)
	var finished_payloads: Array = []
	fm.session_finished.connect(func(res: Dictionary) -> void:
		finished_payloads.append(res)
	)

	# Prevent GameManager.end_fishing from triggering async scene change during test
	fm.set("_game_manager", null)
	fm.set("_elapsed", 60.0)
	fm.call("_process", 0.016)

	_check(bool(fm.call("is_time_up")), "is_time_up() becomes true when _elapsed >= time_limit_sec")
	_check(int(fm.call("get_state", 1)) == FM_SCRIPT.State.IDLE and int(fm.call("get_state", 2)) == FM_SCRIPT.State.IDLE,
		"KNOTTING and WAITING players exit cleanly to IDLE on time_up")
	_check(finished_payloads.size() == 1, "session_finished emitted exactly once when all players are IDLE after time_up")

	fm.set("_finished", false)
	fm.call("_on_cast", 1, 0.5)
	_check(rejected_reasons.has("time_up"), "Casting after time_up emits cast_rejected('time_up')")

	mp_scene.queue_free()
	await process_frame

	# 6. Swapped Sides ([2, 1]) & Non-Contiguous IDs ([1, 3])
	gm.pending_context = {
		"multiplayer": true,
		"time_limit_sec": 60.0,
		"win_mode": "most_fish",
		"spot_id": "location_imus",
		"rod_id": "rod_medium_heavy",
		"bait_id": "bait_1",
		"player_ids": [2, 1],
		"player_names": {2: "Bob", 1: "Alice"},
	}
	var swapped_scene := (load(MP_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(swapped_scene)
	current_scene = swapped_scene
	await process_frame
	await process_frame

	var sw_fm := swapped_scene.find_child("FishingManager", true, false)
	var sw_left_name := swapped_scene.find_child("LeftHudNameLabel", true, false) as Label
	var sw_right_name := swapped_scene.find_child("RightHudNameLabel", true, false) as Label
	_check(int(swapped_scene.get("_left_pid")) == 2 and int(swapped_scene.get("_right_pid")) == 1,
		"Swapped player_ids [2, 1] assigns _left_pid=2 and _right_pid=1")
	_check(sw_left_name != null and sw_left_name.text == "Bob" and sw_right_name != null and sw_right_name.text == "Alice",
		"Swapped HUD name labels show Bob on left and Alice on right")

	var sample_fish := {"id": "fish_nile_tilapia", "display_name": "Nile Tilapia", "size_cm": 25.0, "weight": 0.6}
	sw_fm.call("_show_catch_popup", 2, sample_fish, true)
	sw_fm.call("_show_catch_popup", 1, sample_fish, true)
	await process_frame
	var sw_popups: Dictionary = sw_fm.get("_popups")
	var sw_p2_box := (sw_popups.get(2) as Node).find_child("CatchPopupBox", true, false) as Control if sw_popups.get(2) is Node else null
	var sw_p1_box := (sw_popups.get(1) as Node).find_child("CatchPopupBox", true, false) as Control if sw_popups.get(1) is Node else null
	_check(sw_p2_box != null and is_equal_approx(sw_p2_box.anchor_left, 0.0) and is_equal_approx(sw_p2_box.anchor_right, 0.5),
		"Swapped P2 popup anchored to left half (0.0..0.5)")
	_check(sw_p1_box != null and is_equal_approx(sw_p1_box.anchor_left, 0.5) and is_equal_approx(sw_p1_box.anchor_right, 1.0),
		"Swapped P1 popup anchored to right half (0.5..1.0)")

	swapped_scene.queue_free()
	await process_frame

	# Non-contiguous IDs [1, 3] & 0-0 tie in compute_winner_id
	var zero_tie := {
		1: {"total_weight": 0.0, "catches": []},
		3: {"total_weight": 0.0, "catches": []},
	}
	_check(FM_SCRIPT.compute_winner_id(zero_tie, "total_weight") == -1
		and FM_SCRIPT.compute_winner_id(zero_tie, "biggest_fish") == -1
		and FM_SCRIPT.compute_winner_id(zero_tie, "most_fish") == -1,
		"0-0 tie returns -1 across all 3 win modes")
	var non_contig := {
		1: {"total_weight": 1.5, "catches": [{"weight": 1.5}]},
		3: {"total_weight": 2.2, "catches": [{"weight": 1.1}, {"weight": 1.1}]},
	}
	_check(FM_SCRIPT.compute_winner_id(non_contig, "total_weight") == 3
		and FM_SCRIPT.compute_winner_id(non_contig, "biggest_fish") == 1
		and FM_SCRIPT.compute_winner_id(non_contig, "most_fish") == 3,
		"compute_winner_id handles non-contiguous IDs [1, 3] across all 3 win modes")

	# 7. InputManager Multiplayer Isolation
	im.set_multiplayer_mode(true)
	im.set_context(im.InputContext.FISHING)
	var cast_pids: Array[int] = []
	var cast_cb := func(pid: int, _pwr: float) -> void:
		cast_pids.append(pid)
	im.cast_triggered.connect(cast_cb)
	im.call("_on_phone_swing", 1, 14.0)
	im.call("_on_phone_swing", 2, 16.0)
	im.cast_triggered.disconnect(cast_cb)
	_check(cast_pids == [1, 2], "InputManager routes phone swings to their own player_ids in multiplayer")

	im.call("_on_phone_reel", 1, 45.0)
	im.call("_on_phone_reel", 2, -45.0)
	_check(im.get_reel_strength(1) == 1.0 and im.get_release_strength(1) == 0.0
		and im.get_reel_strength(2) == 0.0 and im.get_release_strength(2) == 1.0,
		"InputManager isolates reel/release crank state per player without cross-talk")

	im.call("_on_phone_disconnected", 1)
	_check(im.get_reel_strength(1) == 0.0 and im.get_release_strength(2) == 1.0,
		"Disconnecting P1 clears only P1 state and leaves P2 intact")

	await process_frame
	print("=== Multiplayer Catching & Edge Cases Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
