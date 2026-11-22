extends SceneTree

const FISHING_SCENE_PATH := "res://3DFishingScene/Area1FishingScenes/3DFishingRiceField.tscn"
const OPTIONS_SCENE_PATH := "res://UIScenesAndScript/Options/Options.tscn"

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
	print("=== Phase A Integration Tests ===")

	# 1. Load real 3D Fishing Scene (FishingManager + FishingUI + WeatherSystem + Rod)
	var packed := load(FISHING_SCENE_PATH) as PackedScene
	_check(packed != null, "Loaded 3DFishingRiceField.tscn")
	if packed == null:
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var fm := scene.find_child("FishingManager", true, false)
	var ui := scene.find_child("3DSceneUI", true, false)
	var ws := scene.find_child("WeatherSystem", true, false)
	_check(fm != null, "Found FishingManager in 3DFishingRiceField")
	_check(ui != null, "Found 3DSceneUI (FishingUI) in 3DFishingRiceField")
	_check(ws != null, "Found WeatherSystem in 3DFishingRiceField")

	if fm == null or ui == null:
		quit(1)
		return

	var im := root.get_node_or_null("InputManager")
	if im != null:
		im.set_context(im.InputContext.FISHING)

	# 2. Verify initial HUD status pill shows weather/time & equipment
	var snap_idle: Dictionary = ui.call("get_hud_snapshot")
	_check(String(snap_idle.get("status_text", "")) != "", "FishingUI status pill populated: %s" % snap_idle.get("status_text", ""))
	_check(not bool(snap_idle.get("fight_visible", true)), "Fight HUD hidden while IDLE")

	# 3. Trigger cast -> verify CASTING state, bobber, and 3D fishing line creation
	var splashes_before: int = fm.call("get_splash_spawn_count")
	fm.call("_on_cast", 1, 0.75)
	await process_frame

	_check(int(fm.call("get_state", 1)) == 1, "State transitioned to CASTING (1)")
	var line_node := fm.find_child("FishingLine_P1", true, false) as MeshInstance3D
	_check(line_node != null, "3D FishingLine_P1 node created during cast")
	if line_node != null and line_node.material_override is StandardMaterial3D:
		var line_mat := line_node.material_override as StandardMaterial3D
		_check(line_mat.render_priority >= 10 and line_node.sorting_offset > 0.0,
			"3D FishingLine_P1 renders above water plane (render_priority=%d, sorting_offset=%.1f)" % [line_mat.render_priority, line_node.sorting_offset])

	# 4. Advance casting to WAITING -> verify bobber_landed splash
	var s = fm._sessions[1]
	s.cast_time = s.cast_duration
	fm._update_session(s, 0.05)
	await process_frame
	_check(int(fm.call("get_state", 1)) == 2, "State transitioned to WAITING (2)")
	_check(int(fm.call("get_splash_spawn_count")) > splashes_before, "Water splash spawned on bobber landing")

	# 5. Trigger bite -> verify REELING state, Fight HUD visible, tension & release, rod flex
	var splashes_before_bite: int = fm.call("get_splash_spawn_count")
	fm._try_bite(s)
	await process_frame
	_check(int(fm.call("get_state", 1)) == 3, "State transitioned to REELING (3)")
	_check(int(fm.call("get_splash_spawn_count")) > splashes_before_bite, "Water splash spawned on fish bite")

	var snap_reel: Dictionary = ui.call("get_hud_snapshot")
	_check(bool(snap_reel.get("fight_visible", false)), "Fight HUD visible during REELING")
	_check(String(snap_reel.get("surge_text", "")) != "", "Surge/Reel hint displayed during REELING")

	# Simulate reeling to build tension, then releasing with tl_release to drop tension
	var base_rot: Vector3 = s.holder_base_rotation
	Input.action_press(&"tl_reel")
	for _i in 10:
		fm._update_session(s, 0.05)
	Input.action_release(&"tl_reel")
	var tension_after_reel: float = s.tension
	_check(tension_after_reel > 0.0, "Tension increased while reeling (%.3f)" % tension_after_reel)
	if s.holder != null:
		_check(not s.holder.rotation.is_equal_approx(base_rot), "Rod holder flexed under tension")

	Input.action_press(&"tl_release")
	for _i in 10:
		fm._update_session(s, 0.05)
	Input.action_release(&"tl_release")
	_check(s.tension < tension_after_reel, "Holding tl_release reduced line tension (%.3f -> %.3f)" % [tension_after_reel, s.tension])

	# 6. Win fight -> CAUGHT -> return to IDLE -> verify line & HUD cleanup
	fm._fish_won(s)
	await process_frame
	_check(int(fm.call("get_state", 1)) == 4, "State transitioned to CAUGHT (4)")
	s.state_time = fm.result_display_time + 0.1
	fm._update_session(s, 0.05)
	await process_frame
	_check(int(fm.call("get_state", 1)) == 0, "State returned to IDLE (0)")
	_check(fm.find_child("FishingLine_P1", true, false) == null, "3D FishingLine_P1 cleaned up on IDLE")

	var snap_after: Dictionary = ui.call("get_hud_snapshot")
	_check(not bool(snap_after.get("fight_visible", true)), "Fight HUD hidden again after returning to IDLE")

	# 7. Verify Options scene SFX slider & Difficulty toggle integration
	var opt_packed := load(OPTIONS_SCENE_PATH) as PackedScene
	_check(opt_packed != null, "Loaded Options.tscn")
	if opt_packed != null:
		var opt := opt_packed.instantiate()
		root.add_child(opt)
		await process_frame
		var sfx_slider := opt.find_child("SfxSlider", true, false) as HSlider
		var diff_btn := opt.find_child("DifficultyButton", true, false) as Button
		_check(sfx_slider != null, "Options has SfxSlider")
		_check(diff_btn != null, "Options has DifficultyButton")
		if diff_btn != null:
			var before_txt := diff_btn.text
			diff_btn.pressed.emit()
			_check(diff_btn.text != before_txt, "DifficultyButton toggles difficulty (%s -> %s)" % [before_txt, diff_btn.text])
			# Restore to Casual
			if diff_btn.text == "Angler":
				diff_btn.pressed.emit()
		opt.queue_free()

	# 8. Verify FishMusicEntry auto-loading & playback fallback via GameDB
	var db := root.get_node_or_null("GameDB")
	var gm := root.get_node_or_null("GameManager")
	_check(db != null, "GameDB autoload found for fish music check")
	if db != null:
		var marlin_entry: FishMusicEntry = db.call("get_fish_music", "fish_marlin")
		var tuna_entry: FishMusicEntry = db.call("get_fish_music", "fish_yellowfin_tuna")
		_check(marlin_entry != null and marlin_entry.fish != null and marlin_entry.fish.id == "fish_marlin" and marlin_entry.music != null,
			"GameDB indexed Marlin.tres for fish_marlin")
		_check(tuna_entry != null and tuna_entry.fish != null and tuna_entry.fish.id == "fish_yellowfin_tuna" and tuna_entry.music != null,
			"GameDB indexed YellowFinTuna.tres for fish_yellowfin_tuna")
		var large_fish_count := 0
		var large_music_ok := true
		var large_fight_mult_ok := true
		for f_item in db.call("get_all", "fish"):
			var f := f_item as FishData
			if f != null and f.size_class == "large":
				large_fish_count += 1
				var fme: FishMusicEntry = db.call("get_fish_music", f.id)
				if fme == null or fme.fish == null or fme.fish.id != f.id or fme.music == null or not fme.music.resource_path.contains("Through The Fire And Flames"):
					large_music_ok = false
					print("[FAIL] Missing or mismatched FishMusicEntry for large fish: ", f.id)
				var expected_mult := 5.0 if f.id in ["fish_marlin", "fish_yellowfin_tuna"] else 3.0
				if not is_equal_approx(f.fight_length_multiplier, expected_mult):
					large_fight_mult_ok = false
					print("[FAIL] %s fight_length_multiplier=%.2f expected=%.2f" % [f.id, f.fight_length_multiplier, expected_mult])
		_check(large_fish_count == 15 and large_music_ok,
			"All %d large fish have Through The Fire And Flames FishMusicEntry in GameDB" % large_fish_count)
		_check(large_fish_count == 15 and large_fight_mult_ok,
			"All %d large fish have expected fight_length_multiplier (5.0 bosses, 3.0 others)" % large_fish_count)

	fm.call("_play_fish_music", "fish_yellowfin_tuna")
	await process_frame
	var fmp := fm.find_child("FishMusicPlayer", true, false) as AudioStreamPlayer
	_check(fmp != null and fmp.playing, "FishingManager plays fish_yellowfin_tuna via GameDB fallback")
	if fmp != null and fmp.stream is AudioStreamMP3:
		_check((fmp.stream as AudioStreamMP3).loop, "Fish music MP3 stream has loop enabled")
	if gm != null:
		_check(bool(gm.get("_music_suppressed")), "GameManager scene music suppressed while fish music plays")

	fm.call("_play_fish_music", "fish_marlin")
	await process_frame
	_check(fmp != null and fmp.playing, "FishingManager plays fish_marlin music")

	fm.call("_stop_fish_music")
	await process_frame
	if gm != null:
		_check(not bool(gm.get("_music_suppressed")), "GameManager scene music restored after _stop_fish_music")

	scene.queue_free()
	await process_frame
	print("=== Phase A Integration Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
