## SampleData: builds the PLACEHOLDER fish, bait, rods and locations in memory.
##
## Two users:
## [br]- [code]tools/generate_sample_data.gd[/code] saves them as the .tres files in res://data/.
## [br]- [code]tests/test_game_database.gd[/code] builds a fresh copy for every test case, so a test can
##   break one value (say, a negative price) without touching the real files or any other test.
##
## Every number, name and text here is a PLACEHOLDER for exercising the loader. Replace the .tres files
## with your real content; you never need this file for that.
##
## [b]Scenario the numbers describe[/b] (used by the documentation's worked examples):
## Kawit (open from the start) offers Bluegill, Perch, Bass, Catfish and Carp; Dock (needs the
## "unlock_dock" flag) offers Bass, Catfish and Carp.
extends RefCounted


## Builds a brand-new set of records (new objects on every call, none of them saved anywhere).
## Returns {"fish": Array, "bait": Array, "rods": Array, "locations": Array, "all": Array} where "all"
## is the four lists joined in loading order, ready for [method GameDatabase.load_records].
## The records reference each other directly (a bait points at its FishData objects), exactly as the
## .tres files do through ext_resource links.
static func build_world() -> Dictionary:
	var fish := _build_fish()
	var bait := _build_bait(fish)
	var rods := _build_rods()
	var locations := _build_locations(fish)
	var all: Array = []
	all.append_array(fish)
	all.append_array(bait)
	all.append_array(rods)
	all.append_array(locations)
	return {"fish": fish, "bait": bait, "rods": rods, "locations": locations, "all": all}


## Returns the fish of [param world] with the given id (null if there is none). Handy in tests.
static func find(records: Array, id: String) -> Resource:
	for record in records:
		if record.id == id:
			return record
	return null


# -----------------------------------------------------------------------------
# Fish
# -----------------------------------------------------------------------------

static func _build_fish() -> Array:
	return [
		_fish("fish_bluegill", "Bluegill", "Lepomis macrochirus",
			"A small, round sunfish that darts around shallow weed beds and bites at almost anything.",
			"small", 10, Vector2i(1, 1), 1.0, [8.0, 15.0, 25.0], 0.15),
		_fish("fish_perch", "Yellow Perch", "Perca flavescens",
			"A striped, schooling fish that lingers near the bottom of cool, clear water.",
			"small", 12, Vector2i(1, 1), 1.2, [10.0, 20.0, 30.0], 0.2),
		_fish("fish_bass", "Largemouth Bass", "Micropterus salmoides",
			"An ambush hunter that strikes hard and fights with sudden, powerful runs.",
			"medium", 30, Vector2i(2, 1), 1.6, [25.0, 40.0, 60.0], 1.2),
		_fish("fish_catfish", "Channel Catfish", "Ictalurus punctatus",
			"A whiskered bottom-feeder, most active after dark, that pulls with slow, heavy strength.",
			"large", 60, Vector2i(3, 1), 1.2, [30.0, 55.0, 90.0], 2.5),
		_fish("fish_carp", "Common Carp", "Cyprinus carpio",
			"A wary, long-lived giant that bolts at the slightest mistake.",
			"large", 90, Vector2i(2, 2), 2.0, [40.0, 65.0, 100.0], 4.0),
	]


# sizes = [min_size, avg_size, max_size] in cm.
static func _fish(id: String, display_name: String, scientific_name: String, description: String,
		size_class: String, base_price: int, grid: Vector2i, speed: float, sizes: Array, avg_weight: float) -> FishData:
	var fish := FishData.new()
	fish.id = id
	fish.display_name = display_name
	fish.scientific_name = scientific_name
	fish.description = description
	fish.size_class = size_class
	fish.base_price = base_price
	fish.grid_width = grid.x
	fish.grid_height = grid.y
	fish.max_stack = 1
	fish.speed = speed
	fish.min_size = sizes[0]
	fish.avg_size = sizes[1]
	fish.max_size = sizes[2]
	fish.avg_weight = avg_weight
	return fish


# -----------------------------------------------------------------------------
# Bait
# -----------------------------------------------------------------------------

static func _build_bait(fish: Array) -> Array:
	return [
		_bait("bait_worm", "Worm", fish, ["fish_bluegill", "fish_perch", "fish_bass"], {"fish_bluegill": 1.5}),
		_bait("bait_minnow", "Minnow", fish, ["fish_bass", "fish_catfish"], {"fish_catfish": 2.0}),
		_bait("bait_dough", "Dough Ball", fish, ["fish_bluegill", "fish_carp"], {"fish_carp": 2.0}),
	]


# enabled = fish ids the bait enables; boosts = {fish_id: multiplier}.
static func _bait(id: String, display_name: String, fish: Array, enabled: Array, boosts: Dictionary) -> BaitData:
	var bait := BaitData.new()
	bait.id = id
	bait.display_name = display_name
	bait.grid_width = 1
	bait.grid_height = 1
	bait.max_stack = 99
	for fish_id in enabled:
		bait.enables_fish.append(find(fish, fish_id))
	for fish_id in boosts:
		var boost := BaitBoost.new()
		boost.fish = find(fish, fish_id)
		boost.multiplier = boosts[fish_id]
		bait.boosts.append(boost)
	return bait


# -----------------------------------------------------------------------------
# Rods
# -----------------------------------------------------------------------------

static func _build_rods() -> Array:
	return [
		_rod("rod_basic", "Basic Rod", 0, [1.0, 0.0, 0.0]),
		_rod("rod_sturdy", "Sturdy Rod", 150, [0.5, 0.5, 0.0]),
		_rod("rod_heavy", "Heavy Rod", 500, [0.2, 0.3, 0.5]),
	]


# chances = [small, medium, large].
static func _rod(id: String, display_name: String, price: int, chances: Array) -> RodData:
	var rod := RodData.new()
	rod.id = id
	rod.display_name = display_name
	rod.rod_price = price
	rod.chance_small = chances[0]
	rod.chance_medium = chances[1]
	rod.chance_large = chances[2]
	return rod


# -----------------------------------------------------------------------------
# Locations
# -----------------------------------------------------------------------------

static func _build_locations(fish: Array) -> Array:
	# Kawit: open from the start. Perch is more common in the wet season and rarer in the dry season,
	# catfish bite more at night, carp (rarer here) mostly at dawn and dusk.
	var kawit := _location("location_kawit", "Kawit", "")
	kawit.fish_pool.append(_entry(find(fish, "fish_bluegill")))
	kawit.fish_pool.append(_entry(find(fish, "fish_perch"), 1.0, [
		_modifier({"season": ["wet"]}, 1.5),
		_modifier({"season": ["dry"]}, 0.5)]))
	kawit.fish_pool.append(_entry(find(fish, "fish_bass")))
	kawit.fish_pool.append(_entry(find(fish, "fish_catfish"), 1.0, [_modifier({"time_of_day": ["night"]}, 2.0)]))
	kawit.fish_pool.append(_entry(find(fish, "fish_carp"), 0.5, [_modifier({"time_of_day": ["dawn", "dusk"]}, 3.0)]))

	# Dock: closed until the player has the "unlock_dock" flag (granted by talking to an NPC).
	var dock := _location("location_dock", "Dock", "unlock_dock")
	dock.fish_pool.append(_entry(find(fish, "fish_bass"), 1.2))
	dock.fish_pool.append(_entry(find(fish, "fish_catfish"), 1.0, [_modifier({"weather": ["rain", "storm"]}, 1.5)]))
	dock.fish_pool.append(_entry(find(fish, "fish_carp"), 1.0, [_modifier({"weather": ["clear"]}, 1.5)]))
	return [kawit, dock]


static func _location(id: String, display_name: String, unlock_flag: String) -> LocationData:
	var location := LocationData.new()
	location.id = id
	location.display_name = display_name
	location.unlock_flag = unlock_flag
	return location


static func _entry(fish: FishData, weight_multiplier: float = 1.0, modifiers: Array = []) -> PoolEntry:
	var entry := PoolEntry.new()
	entry.fish = fish
	entry.weight_multiplier = weight_multiplier
	for modifier in modifiers:
		entry.modifiers.append(modifier)
	return entry


# when = {"time_of_day": [...], "weather": [...], "season": [...]} (any subset of the keys).
static func _modifier(when: Dictionary, multiplier: float) -> OddsModifier:
	var modifier := OddsModifier.new()
	if when.has("time_of_day"):
		modifier.time_of_day.assign(when["time_of_day"])
	if when.has("weather"):
		modifier.weather.assign(when["weather"])
	if when.has("season"):
		modifier.season.assign(when["season"])
	modifier.multiplier = multiplier
	return modifier
