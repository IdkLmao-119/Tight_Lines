extends SceneTree

const FishingManagerScript := preload("res://AutoloadFolders/FishingManager/FishingManager.gd")
const FishingSFXScript := preload("res://AutoloadFolders/FishingManager/fishing_sfx.gd")

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
	print("=== Phase A Unit Tests ===")

	# 1. InputManager tl_release / tl_p2_release registration
	var im := root.get_node_or_null("InputManager")
	_check(im != null, "InputManager autoload is available")
	_check(InputMap.has_action(&"tl_release"), "InputMap has tl_release action")
	_check(InputMap.has_action(&"tl_p2_release"), "InputMap has tl_p2_release action")

	if im != null:
		im.set_context(im.InputContext.OVERWORLD)
		Input.action_press(&"tl_release")
		_check(is_equal_approx(im.get_release_strength(1), 0.0), "get_release_strength is 0.0 outside FISHING context")
		im.set_context(im.InputContext.FISHING)
		_check(is_equal_approx(im.get_release_strength(1), 1.0), "get_release_strength is 1.0 when tl_release held in FISHING context")
		Input.action_release(&"tl_release")
		_check(is_equal_approx(im.get_release_strength(1), 0.0), "get_release_strength returns to 0.0 on release")

	# 2. FishingManager 50/50 tension constants
	_check(is_equal_approx(FishingManagerScript.FISH_SHARE_MAX + FishingManagerScript.REEL_SHARE_MAX, 1.0),
		"FISH_SHARE_MAX + REEL_SHARE_MAX == 1.0")
	_check(FishingManagerScript.RELEASE_LINE_LOSS_RATE > 0.0,
		"RELEASE_LINE_LOSS_RATE is positive so releasing has tactical tradeoff")

	# 2b. Per-fish fight_length_multiplier (Marlin & Yellowfin Tuna = 5x)
	var db := root.get_node_or_null("GameDB")
	if db != null:
		_check(db.load_warnings.is_empty() and db.load_errors.is_empty(),
			"GameDB loaded with 0 warnings and 0 errors with fight_length_multiplier")
		var marlin: FishData = db.get_fish("fish_marlin")
		var tuna: FishData = db.get_fish("fish_yellowfin_tuna")
		var amberjack: FishData = db.get_fish("fish_amberjack")
		_check(marlin != null and is_equal_approx(marlin.fight_length_multiplier, 5.0),
			"fish_marlin has fight_length_multiplier == 5.0")
		_check(tuna != null and is_equal_approx(tuna.fight_length_multiplier, 5.0),
			"fish_yellowfin_tuna has fight_length_multiplier == 5.0")
		_check(amberjack != null and is_equal_approx(amberjack.fight_length_multiplier, 1.0),
			"Other fish (fish_amberjack) default to fight_length_multiplier == 1.0")

	var fm: Node = FishingManagerScript.new()
	fm.show_tension_bar = false
	fm.send_phone_messages = false
	fm.enable_sfx = false
	fm.enable_water_splashes = false
	fm.enable_fish_sweep = false
	fm._input = im
	if im != null:
		im.set_context(im.InputContext.FISHING)
		Input.action_press(&"tl_reel")

	var s1: RefCounted = FishingManagerScript.FishingSession.new()
	s1.player_id = 1
	s1.state = FishingManagerScript.State.REELING
	s1.rod = {"line_strength": 18.0, "reel_speed": 1.4, "control": 1.5}
	s1.fish = {"pull_strength": 16.0, "stamina": 80.0, "fight_length_multiplier": 1.0}
	s1.progress = 0.35
	s1.stamina = 80.0
	s1.max_stamina = 80.0
	s1.surging = false
	s1.surge_timer = 10.0

	var s5: RefCounted = FishingManagerScript.FishingSession.new()
	s5.player_id = 1
	s5.state = FishingManagerScript.State.REELING
	s5.rod = {"line_strength": 18.0, "reel_speed": 1.4, "control": 1.5}
	s5.fish = {"pull_strength": 16.0, "stamina": 80.0, "fight_length_multiplier": 5.0}
	s5.progress = 0.35
	s5.stamina = 80.0
	s5.max_stamina = 80.0
	s5.surging = false
	s5.surge_timer = 10.0

	fm._update_reeling(s1, 0.1)
	fm._update_reeling(s5, 0.1)
	if im != null:
		Input.action_release(&"tl_reel")

	var dp1: float = float(s1.progress) - 0.35
	var dp5: float = float(s5.progress) - 0.35
	var ds1: float = 80.0 - float(s1.stamina)
	var ds5: float = 80.0 - float(s5.stamina)
	_check(absf(dp1) > 0.0 and is_equal_approx(dp1, dp5 * 5.0) and (im == null or dp1 > 0.0),
		"fight_length_multiplier = 5.0 slows reel progress delta by 5x")
	_check(ds1 > 0.0 and is_equal_approx(ds1, ds5 * 5.0),
		"fight_length_multiplier = 5.0 slows stamina drain by 5x")
	fm.free()

	# 3. Fishing line sag & color math
	var sag_wait: float = FishingManagerScript.compute_line_sag(FishingManagerScript.State.WAITING, 0.0)
	var sag_reel_low: float = FishingManagerScript.compute_line_sag(FishingManagerScript.State.REELING, 0.1)
	var sag_reel_high: float = FishingManagerScript.compute_line_sag(FishingManagerScript.State.REELING, 0.95)
	_check(sag_wait > sag_reel_low and sag_reel_low > sag_reel_high,
		"Line sag decreases from WAITING -> low tension -> high tension")

	var col_calm: Color = FishingManagerScript.compute_line_color(0.2)
	var col_warn: Color = FishingManagerScript.compute_line_color(0.7)
	var col_danger: Color = FishingManagerScript.compute_line_color(0.92)
	_check(col_calm.b > col_danger.b and col_danger.r >= 0.95 and col_danger.g < 0.4,
		"Line color transitions calm -> warning -> danger red")
	_check(col_warn.r > 0.9 and col_warn.g > 0.7,
		"Line warning color is warm amber")

	# 4. Rod flex angles
	var flex_zero: Vector2 = FishingManagerScript.compute_rod_flex_angles(0.0, 0.0, false)
	var flex_calm: Vector2 = FishingManagerScript.compute_rod_flex_angles(0.5, 0.5, false)
	var flex_surge: Vector2 = FishingManagerScript.compute_rod_flex_angles(0.5, -0.5, true)
	_check(is_equal_approx(flex_zero.x, 0.0) and is_equal_approx(flex_zero.y, 0.0),
		"Zero tension produces zero rod flex")
	_check(flex_surge.x > flex_calm.x, "Surging increases rod pitch flex")
	_check(flex_calm.y > 0.0 and flex_surge.y < 0.0, "Rod yaw flex matches fish sweep direction")

	# 5. Procedural FishingSFX clip generation
	var sfx: Node = FishingSFXScript.new()
	root.add_child(sfx)
	await process_frame
	for clip_name in ["cast", "splash", "surge_splash", "bite", "reel_tick", "snap", "catch"]:
		_check(sfx.has_clip(clip_name), "FishingSFX generated clip '%s'" % clip_name)
	_check(sfx.play("cast"), "FishingSFX.play('cast') succeeds")
	var custom := AudioStreamWAV.new()
	sfx.set_override("cast", custom)
	_check(sfx.has_clip("cast"), "FishingSFX override registered cleanly")
	sfx.set_override("cast", null)
	sfx.queue_free()

	print("=== Phase A Unit Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
