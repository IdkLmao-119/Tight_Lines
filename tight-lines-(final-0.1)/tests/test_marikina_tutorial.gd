extends SceneTree

const RIVER_FISHING_SCENE := "res://3DFishingScene/Area1FishingScenes/3DFishingRiverPark.tscn"
const RICE_FISHING_SCENE := "res://3DFishingScene/Area1FishingScenes/3DFishingRiceField.tscn"

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
	print("=== Marikina Tutorial Tests ===")

	var gm := root.get_node_or_null("GameManager")
	var sm := root.get_node_or_null("SaveManager")
	var story := root.get_node_or_null("StoryManager")
	_check(gm != null and sm != null and story != null, "Autoloads loaded")
	if gm == null or sm == null or story == null:
		quit(1)
		return

	# 1. StoryManager loaded both Marikina River cutscenes
	_check(bool(story.call("has_cutscene", "marikina_arrival")), "StoryManager loaded marikina_arrival")
	_check(bool(story.call("has_cutscene", "marikina_fishing_intro")), "StoryManager loaded marikina_fishing_intro")

	# 2. First-visit scene matching & main story chain preservation
	sm.new_game()
	_check(String(story.call("find_cutscene_for_scene", "overworld_river_park")) == "marikina_arrival",
		"Fresh save triggers marikina_arrival in overworld_river_park")
	_check(String(story.call("find_cutscene_for_scene", "fishing_river_park")) == "marikina_fishing_intro",
		"Fresh save triggers marikina_fishing_intro in fishing_river_park")

	sm.add_unlock_flag("seen_marikina_street")
	sm.add_unlock_flag("unlock_imus")
	_check(String(story.call("find_cutscene_for_scene", "overworld_rice_field")) == "imus_arrival",
		"Main story chain intact: imus_arrival still triggers after seen_marikina_street + unlock_imus")

	# 3. Seen flags prevent replay
	sm.add_unlock_flag("seen_marikina_arrival")
	sm.add_unlock_flag("seen_marikina_fishing_intro")
	_check(String(story.call("find_cutscene_for_scene", "overworld_river_park")) == "",
		"marikina_arrival does not replay after seen_marikina_arrival")
	_check(String(story.call("find_cutscene_for_scene", "fishing_river_park")) == "",
		"marikina_fishing_intro does not replay after seen_marikina_fishing_intro")

	# 4. Interactive Fishing Tutorial Card in 3DFishingRiverPark.tscn
	sm.new_game()
	gm.pending_context = {"spot_id": "location_marikina"}
	var river_scene := (load(RIVER_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(river_scene)
	current_scene = river_scene
	await process_frame
	await process_frame

	var fm := river_scene.find_child("FishingManager", true, false)
	var ui := river_scene.find_child("3DSceneUI", true, false)
	var hud := river_scene.find_child("GameHUD", true, false)
	_check(fm != null and ui != null and hud != null, "3DFishingRiverPark has FishingManager, 3DSceneUI, and GameHUD")

	if fm != null and ui != null:
		var snap: Dictionary = ui.call("get_hud_snapshot")
		_check(bool(snap.get("tutorial_visible", false)), "Tutorial card visible in IDLE on first Marikina visit")
		_check(String(snap.get("tutorial_title", "")).contains("1/4"), "IDLE shows Step 1/4: %s" % snap.get("tutorial_title", ""))

		var sessions: Dictionary = fm.get("_sessions")
		var s = sessions.get(1)
		_check(s != null, "FishingSession 1 exists")
		if s != null:
			s.state = 2 # WAITING
			await process_frame
			snap = ui.call("get_hud_snapshot")
			_check(String(snap.get("tutorial_title", "")).contains("2/4"), "WAITING shows Step 2/4: %s" % snap.get("tutorial_title", ""))

			s.state = 3 # REELING (calm)
			s.surging = false
			s.tension = 0.0
			await process_frame
			snap = ui.call("get_hud_snapshot")
			_check(String(snap.get("tutorial_title", "")).contains("REEL IT IN"), "REELING calm shows REEL IT IN: %s" % snap.get("tutorial_title", ""))

			s.surging = true
			await process_frame
			snap = ui.call("get_hud_snapshot")
			_check(String(snap.get("tutorial_title", "")).contains("EASE THE TENSION"), "REELING surging shows EASE THE TENSION: %s" % snap.get("tutorial_title", ""))

			s.state = 6 # KNOTTING
			await process_frame
			snap = ui.call("get_hud_snapshot")
			_check(String(snap.get("tutorial_title", "")).contains("TIE A KNOT"), "KNOTTING shows TIE A KNOT: %s" % snap.get("tutorial_title", ""))

			s.state = 4 # CAUGHT
			await process_frame
			snap = ui.call("get_hud_snapshot")
			_check(String(snap.get("tutorial_title", "")).contains("4/4"), "CAUGHT shows Step 4/4 complete: %s" % snap.get("tutorial_title", ""))
			_check(sm.has_unlock_flag("seen_marikina_fishing_tutorial"), "CAUGHT sets seen_marikina_fishing_tutorial flag")
			if hud != null:
				_check(String(hud.call("get_active_toast_text")) == "", "seen_marikina_fishing_tutorial does not trigger Unlocked toast")

	river_scene.queue_free()
	await process_frame

	# 5. Re-instantiating after completion hides tutorial card
	gm.pending_context = {"spot_id": "location_marikina"}
	var river_again := (load(RIVER_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(river_again)
	current_scene = river_again
	await process_frame
	await process_frame
	var ui_again := river_again.find_child("3DSceneUI", true, false)
	_check(ui_again != null and not bool(ui_again.call("get_hud_snapshot").get("tutorial_visible", true)),
		"Tutorial card stays hidden on revisit after completion")
	river_again.queue_free()
	await process_frame

	# 6. skip_tutorial() on a fresh save sets flag and hides card
	sm.new_game()
	gm.pending_context = {"spot_id": "location_marikina"}
	var river_skip := (load(RIVER_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(river_skip)
	current_scene = river_skip
	await process_frame
	await process_frame
	var ui_skip := river_skip.find_child("3DSceneUI", true, false)
	if ui_skip != null:
		ui_skip.call("skip_tutorial")
		await process_frame
		_check(sm.has_unlock_flag("seen_marikina_fishing_tutorial"), "skip_tutorial() sets seen_marikina_fishing_tutorial")
		_check(not bool(ui_skip.call("get_hud_snapshot").get("tutorial_visible", true)), "skip_tutorial() hides tutorial card")
	river_skip.queue_free()
	await process_frame

	# 7. Non-Marikina fishing scene does not show Marikina tutorial card on fresh save
	sm.new_game()
	gm.pending_context = {"spot_id": "location_imus"}
	var rice_scene := (load(RICE_FISHING_SCENE) as PackedScene).instantiate()
	root.add_child(rice_scene)
	current_scene = rice_scene
	await process_frame
	await process_frame
	var ui_rice := rice_scene.find_child("3DSceneUI", true, false)
	_check(ui_rice != null and not bool(ui_rice.call("get_hud_snapshot").get("tutorial_visible", true)),
		"3DFishingRiceField (location_imus) does not show Marikina tutorial card")
	rice_scene.queue_free()
	await process_frame

	print("=== Marikina Tutorial Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
