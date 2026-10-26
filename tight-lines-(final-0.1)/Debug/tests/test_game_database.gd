## Headless tests for GameDB (the .tres version).
##
## Run from the project folder (exit code 0 = all passed, 1 = something failed). The project must have
## been imported once so Godot knows the class names:
## [codeblock]
## godot --headless --path . --import
## godot --headless --path . --script res://tests/test_game_database.gd
## [/codeblock]
##
## Two kinds of test:
## [br]- REAL DATA: loads the .tres files in res://data/ and checks queries and numbers.
## [br]- NEGATIVE: builds a fresh in-memory copy of the placeholder world ([code]SampleData.build_world()[/code]),
##   breaks ONE thing, hands it to [code]load_records()[/code] and checks the loader rejects it with the
##   right message. Nothing in res://data/ is ever modified.
## [br]Disk tests (round trip, broken files, reload) write to user://db_test/ only.
##
## The expected numbers come from the PLACEHOLDER data. If you replace the data, update them.
extends SceneTree

const DatabaseScript := preload("res://AutoloadFolders/GameDatabase/GameDB.gd")
const SampleData := preload("res://tools/tools_sample_data.gd")
const REAL_DATA_DIR := "res://data/"
const TMP_DIR := "user://db_test/"
const FIXTURE_SCENE := "res://tests/fixtures/dummy_rod.tscn"
const NO_TIP_SCENE := "res://tests/fixtures/no_tip_rod.tscn"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_terms_match_exports()
	_test_real_data_loads()
	_test_queries()
	_test_availability()
	_test_catchable_and_odds()
	_test_odds_variants()
	_test_size_weight_price()
	_test_rod_model()
	_test_validation_rules()
	_test_fight_stats()
	_test_new_player_and_grid()
	_test_unlimited_compost_dock()
	_test_cascade_and_modes()
	_test_disk()

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# -----------------------------------------------------------------------------
# FishingTerms must agree with the @export_enum hints (they are duplicated by necessity)
# -----------------------------------------------------------------------------

func _test_terms_match_exports() -> void:
	print("terms")
	var hints := {
		"size_class": [FishData.new(), FishingTerms.SIZE_CLASSES],
		"time_of_day": [OddsModifier.new(), FishingTerms.TIMES_OF_DAY],
		"weather": [OddsModifier.new(), FishingTerms.WEATHERS],
		"season": [OddsModifier.new(), FishingTerms.SEASONS],
	}
	for prop_name in hints:
		var obj: Object = hints[prop_name][0]
		var terms: PackedStringArray = hints[prop_name][1]
		var hint_string := ""
		for p in obj.get_property_list():
			if p["name"] == prop_name:
				hint_string = p["hint_string"]
		# Array[String] hint looks like "4/2:dawn,day,..."; plain looks like "small,medium,large".
		var list := hint_string.substr(hint_string.find(":") + 1) if ":" in hint_string else hint_string
		var words := PackedStringArray()
		for part in list.split(","):
			words.append(part.split(":")[0])
		_check(words == terms, "%s export_enum %s == FishingTerms %s" % [prop_name, words, terms])
	var rod := RodData.new()
	for size_class in FishingTerms.SIZE_CLASSES:
		_check(rod.get("chance_" + size_class) != null, "RodData has chance_%s" % size_class)


# -----------------------------------------------------------------------------
# Real data
# -----------------------------------------------------------------------------

func _test_real_data_loads() -> void:
	print("real data")
	var db := _new_db(true)
	_check(db.load_all(REAL_DATA_DIR), "loads in strict mode (errors: %s)" % [db.load_errors])
	_check(db.load_errors.is_empty(), "no errors")
	_check(db.load_warnings.is_empty(), "no warnings (got %s)" % [db.load_warnings])
	_check(db.get_all_fish().size() == 6, "6 fish")
	_check(db.get_all_bait().size() == 5, "5 bait")
	_check(db.get_all_rods().size() == 3, "3 rods")
	_check(db.get_all_locations().size() == 2, "2 locations")
	_check(db.get_summary().begins_with("loaded: 6 fish"), "summary: " + db.get_summary())
	db.free()


func _test_queries() -> void:
	print("queries")
	var db := _loaded()
	_check(db.has_fish("fish_bass") and not db.has_fish("fish_nope"), "has_fish")
	_check(db.has_bait("bait_worm") and db.has_rod("rod_basic") and db.has_location("location_dock"), "has_*")
	_check(not db.has_fish("bait_worm"), "ids of another kind are not fish")
	var bluegill: FishData = db.get_fish("fish_bluegill")
	_check(bluegill != null and bluegill.scientific_name == "Lepomis macrochirus", "scientific name")
	_check(bluegill.size_class == "small" and bluegill.base_price == 10, "class and price")
	_check(db.get_fish("fish_catfish").get_grid_size() == Vector2i(3, 1), "grid width x height")
	_check(db.get_fish("fish_nope") == null, "unknown fish gives null")
	_check(db.get_ids("fish").size() == 6 and db.get_all("rod").size() == 3, "get_ids / get_all")
	_check(db.get_record("bait", "bait_dough") == db.get_bait("bait_dough"), "get_record is the typed record")
	_check(db.get_bait("bait_worm").max_stack == 99, "bait stack")
	_check(db.get_rod("rod_heavy").rod_price == 500, "rod price")
	_check(db.get_location_fish_pool("location_kawit").size() == 5, "kawit pool size")
	_check(db.get_bait_enabled_fish("bait_minnow").size() == 2, "minnow enables 2")
	_check(db.bait_enables_fish("bait_worm", "fish_bass") and not db.bait_enables_fish("bait_worm", "fish_carp"), "bait_enables_fish")
	_check(db.get_bait_boost("bait_worm", "fish_bluegill") == 1.5 and db.get_bait_boost("bait_worm", "fish_perch") == 1.0, "bait boost")
	_check(db.get_location_weight_multiplier("location_kawit", "fish_carp") == 0.5, "location weight multiplier")
	_check(db.get_location_weight_multiplier("location_dock", "fish_bluegill") == 0.0, "fish absent from spot = 0")
	_check(db.get_size_class_ids() == PackedStringArray(["small", "medium", "large"]), "size class ids")
	_check(db.get_fish_ids_in_class("large").size() == 2, "2 large fish")
	var probs: Dictionary = db.get_rod_size_probabilities("rod_heavy")
	_check(is_equal_approx(probs["large"], 0.5) and db.get_rod_size_probabilities("rod_nope").is_empty(), "rod probabilities")
	_check(db.get_condition_values("weather").has("storm") and db.get_condition_values("bogus").is_empty(), "condition values")
	db.free()


func _test_availability() -> void:
	print("availability")
	var db := _loaded()
	_check(db.is_location_available("location_kawit", _ctx("day", "clear", "dry")), "kawit always open")
	_check(not db.is_location_available("location_dock", _ctx("day", "clear", "dry")), "dock closed without flag")
	_check(db.is_location_available("location_dock", _ctx("day", "clear", "dry", ["unlock_dock"])), "dock open with flag")
	_check(not db.is_location_available("location_nope", {}), "unknown location unavailable")
	_check(db.get_unlock_flag("location_dock") == "unlock_dock" and db.get_unlock_flag("location_kawit") == "", "unlock flag")
	_check(db.get_catch_odds("location_dock", "bait_worm", "rod_basic", _ctx("day", "clear", "dry")).is_empty(), "closed location: no odds")
	db.free()


func _test_catchable_and_odds() -> void:
	print("odds")
	var db := _loaded()
	var dry := _ctx("day", "clear", "dry")
	var wet := _ctx("day", "clear", "wet")
	var ids: Array = db.get_catchable_fish_ids("location_kawit", "bait_worm", dry)
	ids.sort()
	_check(ids == ["fish_bass", "fish_bluegill", "fish_perch"], "worm at kawit: %s" % [ids])
	_check(db.get_catchable_fish_ids("location_kawit", "bait_nope", dry).is_empty(), "unknown bait: nothing")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", dry),
		{"fish_bluegill": 0.375, "fish_perch": 0.125, "fish_bass": 0.5}, "kawit dry worm sturdy")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", wet),
		{"fish_bluegill": 0.25, "fish_perch": 0.25, "fish_bass": 0.5}, "kawit wet worm sturdy")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", {}),
		{"fish_bluegill": 0.3, "fish_perch": 0.2, "fish_bass": 0.5}, "empty context: no modifier applies, bait boost still does")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_heavy", dry),
		{"fish_bluegill": 0.3375, "fish_perch": 0.1125, "fish_bass": 0.55}, "heavy rod: lost large share redistributed equally")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_basic", dry),
		{"fish_bluegill": 0.75, "fish_perch": 0.25}, "basic rod only catches small")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", dry, {"fish_perch": 2.0}),
		{"fish_bluegill": 0.3, "fish_perch": 0.2, "fish_bass": 0.5}, "extra multiplier on perch")
	_check(db.get_catch_odds("location_kawit", "bait_nope", "rod_basic", dry).is_empty(), "no bait: no odds")
	_check(db.get_catch_odds("location_kawit", "bait_worm", "rod_nope", dry).is_empty(), "unknown rod: no odds")
	db.free()


func _test_odds_variants() -> void:
	print("odds variants")
	# Dock, minnow, heavy rod: bass (medium) + catfish (large), no small fish => nothing redistributed to small.
	var db := _loaded()
	var ctx := _ctx("day", "clear", "dry", ["unlock_dock"])
	_check_odds(db.get_catch_odds("location_dock", "bait_minnow", "rod_heavy", ctx),
		{"fish_bass": 0.4, "fish_catfish": 0.6}, "dock minnow heavy: lost small 0.2 split equally (+0.1 each)")
	# Rain boosts catfish only within its class, but alone in class it keeps the class share.
	_check_odds(db.get_catch_odds("location_dock", "bait_minnow", "rod_heavy", _ctx("day", "rain", "dry", ["unlock_dock"])),
		{"fish_bass": 0.4, "fish_catfish": 0.6}, "alone in class: multipliers do not change odds")
	db.free()

	# Location weight multiplier: perch x3 at kawit => bluegill 0.125, perch 0.375 (sturdy rod, wet-free).
	var world := SampleData.build_world()
	var kawit: LocationData = SampleData.find(world["all"], "location_kawit")
	for entry in kawit.fish_pool:
		if entry.fish.id == "fish_perch":
			entry.weight_multiplier = 3.0
			entry.modifiers.clear()
	for bait in world["bait"]:
		if bait.id == "bait_worm":
			bait.boosts.clear()
	var db2 := _new_db(true)
	_check(db2.load_records(world["all"]), "variant world loads: %s" % [db2.load_errors])
	_check_odds(db2.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", {}),
		{"fish_bluegill": 0.125, "fish_perch": 0.375, "fish_bass": 0.5}, "perch location multiplier 3")
	db2.free()


func _test_size_weight_price() -> void:
	print("size / weight / price")
	var db := _loaded()
	_check(is_equal_approx(db.get_weight_for_size_kg("fish_bluegill", 15.0), 0.15), "average size = average weight")
	_check(is_equal_approx(db.get_weight_for_size_kg("fish_bluegill", 7.5), 0.075), "half size = half weight")
	_check(db.get_sell_price("fish_bluegill", 25.0) == 17, "bluegill 25 cm sells for 17")
	_check(db.get_sell_price("fish_bluegill", 7.5) == 5, "bluegill 7.5 cm sells for 5")
	_check(db.get_sell_price("fish_carp", 65.0) == 90, "carp at average size = base price")
	_check(db.get_weight_for_size_kg("fish_nope", 10.0) == 0.0 and db.get_sell_price("fish_nope", 10.0) == 0, "unknown fish: 0")
	var range_kg: Vector2 = db.get_fish("fish_bass").get_weight_range_kg()
	_check(is_equal_approx(range_kg.x, 1.2 * 25.0 / 40.0) and is_equal_approx(range_kg.y, 1.2 * 60.0 / 40.0), "weight range %s" % [range_kg])
	db.free()


func _test_rod_model() -> void:
	print("rod model")
	var world := SampleData.build_world()
	var rod: RodData = SampleData.find(world["all"], "rod_basic")
	rod.model_3d = load(FIXTURE_SCENE)
	var other: RodData = SampleData.find(world["all"], "rod_sturdy")
	other.model_3d = load(NO_TIP_SCENE)
	var db := _new_db(true)
	_check(db.load_records(world["all"]), "world with models loads")
	var model: Node3D = db.instantiate_rod_model("rod_basic")
	_check(model != null, "instantiate rod model")
	var tip: Node3D = db.find_line_tip(model) if model != null else null
	_check(tip != null and tip.name == "LineTip", "LineTip found")
	if model != null:
		model.free()
	var no_tip: Node3D = db.instantiate_rod_model("rod_sturdy")
	_check(no_tip != null and db.find_line_tip(no_tip) == null, "model without tip: find_line_tip is null")
	if no_tip != null:
		no_tip.free()
	_check(db.instantiate_rod_model("rod_heavy") == null, "rod without model: null")
	_check(db.instantiate_rod_model("rod_nope") == null, "unknown rod: null")
	db.free()


# -----------------------------------------------------------------------------
# Validation: each case breaks one thing in a fresh world
# -----------------------------------------------------------------------------

func _test_validation_rules() -> void:
	print("validation")
	_expect_error("empty id", "id must not be empty", func(w): _fish(w, "fish_bass").id = "")
	_expect_error("bad prefix", "must be lowercase snake_case and start with 'fish_'", func(w): _fish(w, "fish_bass").id = "bass")
	_expect_error("uppercase id", "must be lowercase snake_case and start with 'fish_'", func(w): _fish(w, "fish_bass").id = "fish_Bass")
	_expect_error("empty name", "display_name must not be empty", func(w): _fish(w, "fish_bass").display_name = "")
	_expect_error("empty scientific", "scientific_name must not be empty", func(w): _fish(w, "fish_bass").scientific_name = "")
	_expect_error("bad class", "size_class 'huge' is not one of", func(w): _fish(w, "fish_bass").size_class = "huge")
	_expect_error("min > max", "min_size (", func(w): _fish(w, "fish_bass").min_size = 99.0)
	_expect_error("avg out of range", "avg_size (", func(w): _fish(w, "fish_bass").avg_size = 99.0)
	_expect_error("zero avg size", "avg_size must be greater than 0", func(w):
		var f := _fish(w, "fish_bass"); f.min_size = 0.0; f.avg_size = 0.0)
	_expect_error("zero avg weight", "avg_weight must be greater than 0", func(w): _fish(w, "fish_bass").avg_weight = 0.0)
	_expect_error("zero grid width", "grid_width is 0 but must be at least 1", func(w): _fish(w, "fish_bass").grid_width = 0)
	_expect_error("bait enables nothing", "enables_fish must not be empty", func(w): _bait(w, "bait_worm").enables_fish.clear())
	_expect_error("boost not enabled", "boosted fish 'fish_carp' must also be listed in enables_fish", func(w):
		_add_boost(_bait(w, "bait_worm"), _fish(w, "fish_carp"), 2.0))
	_expect_error("boost twice", "is boosted twice", func(w):
		_add_boost(_bait(w, "bait_worm"), _fish(w, "fish_bluegill"), 2.0))
	_expect_error("boost zero", "multiplier must be greater than 0", func(w): _bait(w, "bait_worm").boosts[0].multiplier = 0.0)
	_expect_error("rod sum", "the chances add up to", func(w): _rod(w, "rod_basic").chance_small = 0.5)
	_expect_error("rod chance range", "a chance must be between 0 and 1", func(w):
		var r := _rod(w, "rod_basic"); r.chance_small = 1.5; r.chance_medium = -0.5)
	_expect_error("empty pool", "fish_pool must not be empty", func(w): _location(w, "location_kawit").fish_pool.clear())
	_expect_error("duplicate pool fish", "is listed twice in this pool", func(w):
		var l := _location(w, "location_kawit"); l.fish_pool.append(l.fish_pool[0]))
	_expect_error("bad flag", "must be lowercase snake_case", func(w): _location(w, "location_dock").unlock_flag = "Unlock Dock")
	_expect_error("modifier no condition", "needs at least one of time_of_day, weather, season", func(w):
		_location(w, "location_kawit").fish_pool[1].modifiers[0].season.clear())
	_expect_error("bad weather value", "'hail' is not a valid weather value", func(w):
		_location(w, "location_dock").fish_pool[1].modifiers[0].weather.assign(["hail"]))
	_expect_error("repeated condition", "lists 'wet' more than once", func(w):
		_location(w, "location_kawit").fish_pool[1].modifiers[0].season.assign(["wet", "wet"]))
	_expect_error("modifier multiplier", "multiplier must be greater than 0", func(w):
		_location(w, "location_kawit").fish_pool[1].modifiers[0].multiplier = 0.0)
	_expect_error("duplicate id", "duplicate id", func(w): _fish(w, "fish_perch").id = "fish_bluegill")
	_expect_error("null pool fish", "fish", func(w): _location(w, "location_kawit").fish_pool[0].fish = null)
	_expect_error("fish not in database", "that is not in the database", func(w):
		w["all"].erase(_fish(w, "fish_carp")))
	_expect_error("no records", "no database records found", func(w): w["all"].clear())


# -----------------------------------------------------------------------------
# Fight stats (DECISIONS.md GameDatabase list, items 1-2) and the new-player rules (items 4-5)
# -----------------------------------------------------------------------------

func _test_fight_stats() -> void:
	print("fight stats")
	# A stat of 0 or less is an ERROR for every stat.
	_expect_error("pull_strength 0", "pull_strength must be greater than 0", func(w): _fish(w, "fish_bass").pull_strength = 0.0)
	_expect_error("stamina 0", "stamina must be greater than 0", func(w): _fish(w, "fish_bass").stamina = -1.0)
	_expect_error("line_strength 0", "line_strength must be greater than 0", func(w): _rod(w, "rod_basic").line_strength = 0.0)
	_expect_error("reel_speed 0", "reel_speed must be greater than 0", func(w): _rod(w, "rod_basic").reel_speed = 0.0)
	_expect_error("max_cast_distance 0", "max_cast_distance must be greater than 0", func(w): _rod(w, "rod_basic").max_cast_distance = 0.0)
	_expect_error("control 0", "control must be greater than 0", func(w): _rod(w, "rod_basic").control = 0.0)
	# Outside the suggested range is only a WARNING: the load still succeeds.
	var world := SampleData.build_world()
	_fish(world, "fish_bass").pull_strength = 9.0
	_rod(world, "rod_heavy").max_cast_distance = 50.0
	var db := _new_db(true)
	_check(db.load_records(world["all"]), "out-of-range stats still load: %s" % [db.load_errors])
	_check(_any(db.load_warnings, "pull_strength (9.0) is outside the suggested range"), "pull_strength warns: %s" % [db.load_warnings])
	_check(_any(db.load_warnings, "max_cast_distance (50.0) is outside the suggested range"), "max_cast_distance warns")
	db.free()
	# The defaults of a freshly made record are inside the suggested ranges (so old .tres files without
	# the new fields load without warnings).
	var fish := FishData.new()
	var rod := RodData.new()
	_check(fish.pull_strength == 4.0 and fish.stamina == 20.0, "fish defaults 4 / 20")
	_check(rod.line_strength == 10.0 and rod.reel_speed == 1.0 and rod.max_cast_distance == 20.0 and rod.control == 1.0, "rod defaults")
	var real := _loaded()
	_check(is_equal_approx(real.get_fish("fish_carp").pull_strength, 7.5) and is_equal_approx(real.get_rod("rod_heavy").line_strength, 18.0),
		"authored stats are read from the .tres files")
	real.free()


func _test_new_player_and_grid() -> void:
	print("new player / grid")
	var db := _loaded()
	# D10 + section 4: a brand-new player (no flags) with the free starter rod and the starter bait can fish.
	var starter: Dictionary = db.get_catch_odds("location_kawit", "bait_worm", "rod_basic", {"unlocked": []})
	_check(not starter.is_empty(), "new player: Kawit + worm + basic rod has odds")
	_check(db.get_unlock_flag("location_kawit") == "" and db.get_rod("rod_basic").rod_price == 0, "starting spot open, starter rod free")
	# INV-R7: every fish and bait fits its container (fish_box 6x8, tackle_box 8x6), either orientation.
	for fish in db.get_all_fish():
		_check(_fits(fish, Vector2i(6, 8)), "%s %s fits the fish box" % [fish.id, fish.get_grid_size()])
		_check(fish.max_stack == 1, "%s never stacks" % fish.id)
	for bait in db.get_all_bait():
		_check(_fits(bait, Vector2i(8, 6)), "%s fits the tackle box" % bait.id)
	db.free()


# True if the item fits inside the container as placed or rotated by 90 degrees.
func _fits(item: ItemData, box: Vector2i) -> bool:
	var size := item.get_grid_size()
	return (size.x <= box.x and size.y <= box.y) or (size.y <= box.x and size.x <= box.y)


# -----------------------------------------------------------------------------
# DECISIONS v3.1: unlimited bait (D12), Compost Pit worms (D13), the dock (section 4)
# -----------------------------------------------------------------------------

func _test_unlimited_compost_dock() -> void:
	print("unlimited / compost / dock")
	var db := _loaded()
	# D12: bait_worm is unlimited, nothing else is.
	_check(db.get_bait("bait_worm").unlimited, "bait_worm is unlimited")
	var unlimited_ids: Array = []
	for bait in db.get_all_bait():
		if bait.unlimited:
			unlimited_ids.append(bait.id)
	_check(unlimited_ids == ["bait_worm"], "only bait_worm is unlimited (got %s)" % [unlimited_ids])
	_check(not BaitData.new().unlimited, "default is not unlimited")

	# D13: compost weights. Worm 0; red worm 3; night crawler 1; every pit bait is NOT unlimited.
	_check(db.get_bait("bait_worm").compost_weight == 0.0, "worm is never made by the pit")
	_check(db.get_bait("bait_red_worm").compost_weight == 3.0 and db.get_bait("bait_night_crawler").compost_weight == 1.0, "pit weights 3 and 1")
	_check(BaitData.new().compost_weight == 0.0, "default compost_weight is 0")
	var pool: Array = []
	for bait in db.get_all_bait():
		if bait.compost_weight > 0.0:
			pool.append(bait.id)
			_check(not bait.unlimited, "%s (compost_weight > 0) is not unlimited" % bait.id)
			_check(bait.max_stack == 99 and not bait.enables_fish.is_empty() and not bait.boosts.is_empty(),
				"%s: stack 99, enables fish, has a boost" % bait.id)
			# Each fish the pit bait enables must be reachable at some location.
			for fish in bait.enables_fish:
				var reachable := false
				for location in db.get_all_locations():
					if location.find_entry(fish) != null:
						reachable = true
				_check(reachable, "%s: enabled fish %s is offered by a location" % [bait.id, fish.id])
	pool.sort()
	_check(pool == ["bait_night_crawler", "bait_red_worm"], "pit pool is the two worms (got %s)" % [pool])
	_expect_error("negative compost weight", "compost_weight must not be below 0", func(w): _bait(w, "bait_red_worm").compost_weight = -1.0)

	# Dock: closed without the flag, open with it; has a dock-only fish and a fish the worm enables.
	var flagged := {"unlocked": ["unlock_dock"]}
	_check(db.get_unlock_flag("location_dock") == "unlock_dock", "dock needs unlock_dock")
	_check(db.get_catch_odds("location_dock", "bait_worm", "rod_basic", {}).is_empty(), "dock, no flags: {}")
	_check(db.get_catch_odds("location_dock", "bait_worm", "rod_basic", {"unlocked": []}).is_empty(), "dock, empty flag list: {}")
	_check(db.get_catch_odds("location_dock", "bait_worm", "rod_basic", {"unlocked": ["other_flag"]}).is_empty(), "dock, wrong flag: {}")
	_check_odds(db.get_catch_odds("location_dock", "bait_worm", "rod_basic", flagged), {"fish_perch": 1.0}, "dock + flag + worm + basic rod: perch only")
	_check_odds(db.get_catch_odds("location_dock", "bait_red_worm", "rod_basic", flagged),
		{"fish_perch": 2.0 / 3.0, "fish_smelt": 1.0 / 3.0}, "dock + red worm: boosted perch, dock-only smelt")
	var dock_only: Array = db.get_location_fish_pool("location_dock").filter(func(e): return db.get_location_weight_multiplier("location_kawit", e.fish.id) == 0.0)
	_check(dock_only.size() == 1 and dock_only[0].fish.id == "fish_smelt", "exactly one dock-only fish: smelt")
	var worm_dock: Array = db.get_catchable_fish_ids("location_dock", "bait_worm", flagged)
	_check(worm_dock.size() >= 1, "the worm enables at least one dock fish: %s" % [worm_dock])
	db.free()


# -----------------------------------------------------------------------------
# Cascades, lenient mode, warnings
# -----------------------------------------------------------------------------

func _test_cascade_and_modes() -> void:
	print("cascade / modes")
	# A rejected fish: exactly ONE error, and nothing downstream reports it again.
	var world := SampleData.build_world()
	_fish(world, "fish_bass").size_class = "huge"
	var db := _new_db(true)
	_check(not db.load_records(world["all"]), "strict: fails")
	_check(db.load_errors.size() == 1, "one cause, one error (got %d: %s)" % [db.load_errors.size(), db.load_errors])
	db.free()

	# Lenient: bad record skipped, the rest keeps working, and nothing dangling remains.
	world = SampleData.build_world()
	_fish(world, "fish_bass").size_class = "huge"
	var lenient := _new_db(false)
	_check(lenient.load_records(world["all"]), "lenient: loads")
	_check(not lenient.has_fish("fish_bass") and lenient.has_fish("fish_perch"), "lenient: bad fish skipped, others kept")
	_check(not lenient.load_errors.is_empty(), "lenient: error still reported")
	var odds: Dictionary = lenient.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", {})
	_check(not odds.has("fish_bass") and not odds.is_empty(), "lenient: odds ignore the skipped fish")
	_check(lenient.get_bait_enabled_fish("bait_worm").size() == 2, "lenient: bait no longer lists the skipped fish")
	lenient.free()

	# Empty database is fatal even in lenient mode.
	var empty := _new_db(false)
	_check(not empty.load_records([]), "lenient: empty database is fatal")
	empty.free()

	# Non-records are warnings, not errors.
	world = SampleData.build_world()
	var all: Array = world["all"].duplicate()
	all.append(Resource.new())
	var odd := _new_db(true)
	_check(odd.load_records(all), "stray object does not fail the load")
	_check(_any(odd.load_warnings, "not a database record"), "stray object warns: %s" % [odd.load_warnings])
	odd.free()


# -----------------------------------------------------------------------------
# Disk: round trip, subfolders, broken files, reload
# -----------------------------------------------------------------------------

func _test_disk() -> void:
	print("disk")
	_wipe(TMP_DIR)
	var dir := TMP_DIR + "round/"
	_save_world(SampleData.build_world(), dir, true)
	# Drop every in-memory reference so the loader really reads the files (the resource cache is weak).
	var db := _new_db(true)
	_check(db.load_all(dir), "round trip loads from disk: %s" % [db.load_errors])
	_check(db.get_all_fish().size() == 6 and db.get_all_locations().size() == 2, "round trip: counts")
	_check_odds(db.get_catch_odds("location_kawit", "bait_worm", "rod_sturdy", _ctx("day", "clear", "dry")),
		{"fish_bluegill": 0.375, "fish_perch": 0.125, "fish_bass": 0.5}, "round trip: same odds")
	_check(db.get_bait("bait_worm").enables_fish[0] == db.get_fish("fish_bluegill"), "bait links to the SAME fish object")
	db.free()

	# Subfolders are scanned; a mismatched file name only warns; a missing directory is fatal.
	var sub := TMP_DIR + "sub/"
	var world := SampleData.build_world()
	_save_world(world, sub, false, {"fish_perch": "deep/wrong_name"})
	var db2 := _new_db(true)
	_check(db2.load_all(sub), "subfolders are scanned: %s" % [db2.load_errors])
	_check(db2.has_fish("fish_perch"), "fish found in subfolder")
	_check(_any(db2.load_warnings, "does not match the id"), "file-name mismatch warns: %s" % [db2.load_warnings])
	db2.free()
	var missing := _new_db(true)
	_check(not missing.load_all(TMP_DIR + "does_not_exist/"), "missing directory is fatal")
	missing.free()

	# A file that is not a valid resource: error in strict mode, skipped in lenient.
	var broken := TMP_DIR + "broken/"
	_save_world(SampleData.build_world(), broken, false)
	var f := FileAccess.open(broken + "fish/fish_garbage.tres", FileAccess.WRITE)
	f.store_string("this is not a resource")
	f.close()
	var strict := _new_db(true)
	_check(not strict.load_all(broken), "broken file: strict fails")
	strict.free()
	var lenient := _new_db(false)
	_check(lenient.load_all(broken) and lenient.has_fish("fish_bass"), "broken file: lenient skips it")
	lenient.free()

	# reload() sees a changed file and keeps working.
	var live := TMP_DIR + "live/"
	_save_world(SampleData.build_world(), live, false)
	var rdb := _new_db(true)
	_check(rdb.load_all(live), "reload: first load")
	_check(rdb.get_fish("fish_bass").base_price == 30, "reload: original price")
	var path := live + "fish/fish_bass.tres"
	var text := FileAccess.get_file_as_string(path).replace("base_price = 30", "base_price = 77")
	var wf := FileAccess.open(path, FileAccess.WRITE)
	wf.store_string(text)
	wf.close()
	_check(rdb.reload(live), "reload: loads again: %s" % [rdb.load_errors])
	_check(rdb.get_fish("fish_bass").base_price == 77, "reload: sees the edited price")
	rdb.free()
	_wipe(TMP_DIR)


# Saves a world as .tres files like the generator does. [param drop] frees the in-memory records.
func _save_world(world: Dictionary, dir: String, _drop: bool, renames: Dictionary = {}) -> void:
	var folders := {"fish": "fish/", "bait": "bait/", "rods": "rods/", "locations": "locations/"}
	for kind in ["fish", "bait", "rods", "locations"]:
		DirAccess.make_dir_recursive_absolute(dir + folders[kind])
		for record in world[kind]:
			var path: String = dir + folders[kind] + record.id + ".tres"
			if renames.has(record.id):
				path = dir + folders[kind] + renames[record.id] + ".tres"
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var err := ResourceSaver.save(record, path, ResourceSaver.FLAG_CHANGE_PATH)
			_check(err == OK, "saved " + path)
			record.take_over_path(path)
	# Forget the in-memory copies: Godot's cache holds only weak references, so the next load reads the files.
	world.clear()


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _check_odds(actual: Dictionary, expected: Dictionary, label: String) -> void:
	var ok := actual.size() == expected.size()
	var total := 0.0
	for fish_id in expected:
		if not actual.has(fish_id) or absf(actual[fish_id] - expected[fish_id]) > 0.0001:
			ok = false
	for fish_id in actual:
		total += actual[fish_id]
	_check(ok and absf(total - 1.0) < 0.0001, "%s (expected %s, got %s)" % [label, expected, actual])


func _ctx(time_of_day: String, weather: String, season: String, unlocked: Array = []) -> Dictionary:
	return {"time_of_day": time_of_day, "weather": weather, "season": season, "unlocked": unlocked}


func _new_db(strict: bool) -> Node:
	var db := DatabaseScript.new()
	db.strict_mode = strict
	db.quiet = true
	return db


func _loaded() -> Node:
	var db := _new_db(true)
	db.load_all(REAL_DATA_DIR)
	return db


func _fish(world: Dictionary, id: String) -> FishData: return SampleData.find(world["all"], id)
func _bait(world: Dictionary, id: String) -> BaitData: return SampleData.find(world["all"], id)
func _rod(world: Dictionary, id: String) -> RodData: return SampleData.find(world["all"], id)
func _location(world: Dictionary, id: String) -> LocationData: return SampleData.find(world["all"], id)


func _add_boost(bait: BaitData, fish: FishData, multiplier: float) -> void:
	var boost := BaitBoost.new()
	boost.fish = fish
	boost.multiplier = multiplier
	bait.boosts.append(boost)


func _any(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if needle in message:
			return true
	return false


# Builds a fresh world, lets [param mutate] break it, loads it strictly, and expects a failure whose
# error text contains [param needle].
func _expect_error(case_name: String, needle: String, mutate: Callable) -> void:
	var world := SampleData.build_world()
	mutate.call(world)
	var db := _new_db(true)
	var loaded: bool = db.load_records(world["all"])
	_check(not loaded, "%s: strict load fails" % case_name)
	_check(_any(db.load_errors, needle), "%s: error mentions '%s' (got %s)" % [case_name, needle, db.load_errors])
	db.free()


func _wipe(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(abs_path):
		OS.move_to_trash(abs_path) if false else _rm_rf(abs_path)


func _rm_rf(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_rm_rf(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
