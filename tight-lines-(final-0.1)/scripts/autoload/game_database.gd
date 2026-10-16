## GameDatabase (autoload singleton): the game's static reference data.
##
## Scans [code]res://data/[/code] for [code].tres[/code] records ([FishData], [BaitData], [RodData],
## [LocationData]), validates them, and serves lookups to both the 2D Overworld and the 3D Fishing
## Minigame. Nothing is ever written back at runtime; anything that changes per save (inventory,
## equipped items, unlock flags) belongs to SaveManager.
##
## [b]Setup[/b]: Project Settings > Autoload, add this script as "GameDatabase" and place it ABOVE
## SaveManager in the list (autoloads initialise top to bottom, and SaveManager may want to validate saved
## ids against this database). The class definitions in [code]res://resources/[/code] must be in the
## project (Godot registers their class_name automatically when the project is opened).
##
## [b]What is a record?[/b] Every .tres file under the data folder whose script is one of the four record
## classes. The folder layout is only a convention (data/fish/, data/bait/, data/rods/, data/locations/):
## the loader scans the whole data folder, including subfolders, and sorts records by TYPE, so you may
## organise files freely (e.g. data/fish/freshwater/). Records are listed in file-path order.
##
## [b]How a catch is decided[/b] (implemented by [method get_catch_odds]):
## [codeblock]
## 1. Candidates = fish in the location's pool that the equipped bait enables
##                 (the location itself must be open).
## 2. The ROD gives a chance per fish category (size class), e.g. small 50%, medium 50%, large 0%.
##    A category the rod can catch but that has no candidates here gives its chance, equally,
##    to the other categories the rod can catch.
## 3. Inside a category the fish split that category's chance EQUALLY
##    (10 small fish at 50% => 5% each), except that bait boosts, location multipliers,
##    time/weather/season modifiers and runtime extra multipliers make chosen fish count more
##    (or less) than their classmates. They only ever boost or decrease; nothing forbids a fish.
## [/codeblock]
## The result sums to 1.0. This class never rolls dice itself; CatchRateResolver does.
##
## [b]Size, weight, price[/b]: the catch logic rolls a size (cm) between a fish's min_size and max_size.
## Weight = size x avg_weight / avg_size and sell price = base_price x size / avg_size
## (see [method FishData.get_weight_for_size_kg] and [method FishData.get_sell_price]).
##
## [b]Load pipeline[/b] (all synchronous, finished before any scene's _ready()):
## [codeblock]
## scan data folder -> load every .tres -> sort records by type
##   each record : validate (ids, ranges, probabilities, conditions...)
##   then        : cross-record check (bait / location -> fish references)
##   then        : index by id and set is_loaded = true
## [/codeblock]
##
## [b]Errors vs warnings[/b]
## [br]- ERROR: the data is wrong (bad id, duplicate id, a value out of range, a reference to a fish that is
##   not in the database...). With [member strict_mode] on (default in debug builds) any error makes the
##   whole load fail, so mistakes are caught immediately. With it off (default in release builds) bad
##   records are skipped and the rest of the game still runs.
## [br]- WARNING: suspicious but legal (file name differs from the id, a fish no location offers, a
##   .tres that is not a database record). Never fails the load.
## [br]An empty data folder (no records at all) is always fatal.
##
## [b]Records are shared objects[/b]: [method get_fish] and friends return the SAME loaded Resource every
## time, so changing one (say [code]fish.speed = 2.0[/code]) would change it for everyone until the game
## restarts. GDScript cannot mark an object read-only, so treat records as read-only (copy with
## [code]duplicate()[/code] if you need a variant). The only time the loader itself edits a record is the
## clean-up of dangling references in lenient mode, which only happens after an error was reported.
##
## Tested on Godot 4.6 (see tests/test_game_database.gd); other versions are untested.
extends Node


# =============================================================================
# SIGNALS
# =============================================================================

## Emitted after a (re)load that produced a usable database.
signal database_loaded

## Emitted after a (re)load that failed. [param errors] is the full error list
## (the same content as [member load_errors]).
signal database_load_failed(errors: PackedStringArray)


# =============================================================================
# CONSTANTS
# =============================================================================

## Folder scanned for records. Overridable per call via [method load_all] (tests use this).
const DATA_DIR := "res://data/"

## Allowed floating-point slack when checking that probabilities add up to 1.0
## (decimals like 0.3 are not exact in binary).
const PROBABILITY_TOLERANCE := 0.001

## The name a rod model's attachment point must have. Put a Marker3D with this name at the
## tip of the rod in the model's scene; the fishing line attaches there.
const LINE_TIP_NODE_NAME := "LineTip"

## The four kinds of record, in loading order. These strings are what [method get_record],
## [method has_record], [method get_ids] and [method get_all] accept as "kind".
const KINDS := ["fish", "bait", "rod", "location"]


# =============================================================================
# PUBLIC STATE
# =============================================================================

## When true, ANY validation error fails the whole load (database stays empty and
## [member is_loaded] is false). Set in [method _ready] from [code]OS.is_debug_build()[/code]:
## strict while developing, lenient in shipped builds. Set it before calling [method load_all].
var strict_mode := true

## When true, nothing is sent to [code]push_error[/code]/[code]push_warning[/code]
## (messages are still collected in [member load_errors]/[member load_warnings]).
## Used by the unit tests so intentionally broken data doesn't spam the console.
var quiet := false

## True once a load finished with a usable database. Check this before querying
## if you can run before autoloads are ready (normally you cannot).
var is_loaded := false

## Everything that went wrong in the last load, one human-readable line each.
var load_errors := PackedStringArray()

## Everything suspicious in the last load, one human-readable line each.
var load_warnings := PackedStringArray()


# =============================================================================
# PRIVATE STATE
# =============================================================================

# kind -> { id -> record }. Dictionaries keep insertion order, so get_all*() / get_ids() return
# records in the order they were loaded (file-path order when loaded from disk).
var _tables: Dictionary = {}

# instance id of every record that failed validation or lost a duplicate-id race. A reference to such
# a record is already explained by the record's own error, so it is not reported a second time
# (one cause, one error).
var _rejected: Dictionary = {}

# Set when the load cannot possibly produce a usable database (no records at all): fatal in both modes.
var _fatal := false

# Matches lowercase snake_case identifiers: letters/digits/underscore, starting with a letter.
var _slug_regex := RegEx.new()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _init() -> void:
	_slug_regex.compile("^[a-z][a-z0-9_]*$")
	_reset()


func _ready() -> void:
	# Strict in the editor / debug builds so authoring mistakes stop the game
	# immediately; lenient in release so one bad record can't brick a shipped game.
	strict_mode = OS.is_debug_build()
	load_all()
	if OS.is_debug_build():
		print("[GameDatabase] ", get_summary())


## Scans [param data_dir] (including subfolders) for .tres records, validates them and indexes them.
## Returns true if the database is usable afterwards (same as [member is_loaded]).
## Safe to call again at runtime (see [method reload]): all state is rebuilt from scratch and
## [signal database_loaded] / [signal database_load_failed] fires.
## [param cache_mode] is how Godot's resource cache is used (the default shares already-loaded files).
func load_all(data_dir: String = DATA_DIR, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE) -> bool:
	_reset()
	_process_records(_scan_and_load(data_dir, cache_mode))
	_finalize()
	return is_loaded


## Validates and indexes records that are ALREADY in memory instead of scanning a folder. Same rules
## and results as [method load_all]. Useful for tests, tools and (later) mods that build records in code.
## [param records] is any Array of Resources; items that are not database records are ignored with a warning.
func load_records(records: Array) -> bool:
	_reset()
	_process_records(records)
	_finalize()
	return is_loaded


## Re-reads all .tres files while the game is running (same as [method load_all], but files that Godot
## already has in memory are refreshed from disk).
## Development convenience: edit a number in a .tres file, trigger this (e.g. from a debug key), and
## see the change without restarting the game. Does nothing unless you call it.
## Note: anything that stored a record before the reload may keep the OLD copy; fetch records again
## after [signal database_loaded] fires.
func reload(data_dir: String = DATA_DIR) -> bool:
	return load_all(data_dir, ResourceLoader.CACHE_MODE_REPLACE)


## One-line human-readable status, e.g. for a debug overlay or the startup log.
func get_summary() -> String:
	if not is_loaded:
		return "NOT LOADED (%d errors, %d warnings)" % [load_errors.size(), load_warnings.size()]
	return "loaded: %d fish, %d bait, %d rods, %d locations (%d warnings)" % [
		_tables["fish"].size(), _tables["bait"].size(), _tables["rod"].size(),
		_tables["location"].size(), load_warnings.size()]


# =============================================================================
# PUBLIC API: LOOKUPS
# =============================================================================
# All lookups return the SHARED record (see "Records are shared objects" above). A missing id returns
# null and logs a warning, so check has_*() when the id comes from untrusted input such as a save file.

## The record of [param kind] ("fish", "bait", "rod" or "location") with [param id], or null if unknown.
func get_record(kind: String, id: String) -> DatabaseEntry:
	return _lookup(kind, id)


## True if a record of [param kind] with [param id] exists. Never logs a warning.
func has_record(kind: String, id: String) -> bool:
	return is_loaded and _tables.has(kind) and (_tables[kind] as Dictionary).has(id)


## All ids of [param kind], in load order.
func get_ids(kind: String) -> Array:
	if not _tables.has(kind):
		push_warning("[GameDatabase] unknown record kind '%s'" % kind)
		return []
	return (_tables[kind] as Dictionary).keys()


## All records of [param kind], in load order.
func get_all(kind: String) -> Array:
	if not _tables.has(kind):
		push_warning("[GameDatabase] unknown record kind '%s'" % kind)
		return []
	return (_tables[kind] as Dictionary).values()


## Fish with [param id], or null if unknown.
func get_fish(id: String) -> FishData: return _lookup("fish", id) as FishData
## Bait with [param id], or null if unknown.
func get_bait(id: String) -> BaitData: return _lookup("bait", id) as BaitData
## Rod with [param id], or null if unknown.
func get_rod(id: String) -> RodData: return _lookup("rod", id) as RodData
## Location with [param id], or null if unknown.
func get_location(id: String) -> LocationData: return _lookup("location", id) as LocationData

## True if a fish with [param id] exists.
func has_fish(id: String) -> bool: return has_record("fish", id)
## True if a bait with [param id] exists.
func has_bait(id: String) -> bool: return has_record("bait", id)
## True if a rod with [param id] exists.
func has_rod(id: String) -> bool: return has_record("rod", id)
## True if a location with [param id] exists.
func has_location(id: String) -> bool: return has_record("location", id)


## Every fish, in load order.
func get_all_fish() -> Array[FishData]:
	var result: Array[FishData] = []
	result.assign(_tables["fish"].values())
	return result


## Every bait, in load order.
func get_all_bait() -> Array[BaitData]:
	var result: Array[BaitData] = []
	result.assign(_tables["bait"].values())
	return result


## Every rod, in load order.
func get_all_rods() -> Array[RodData]:
	var result: Array[RodData] = []
	result.assign(_tables["rod"].values())
	return result


## Every location, in load order.
func get_all_locations() -> Array[LocationData]:
	var result: Array[LocationData] = []
	result.assign(_tables["location"].values())
	return result


# =============================================================================
# PUBLIC API: CONTEXT AND AVAILABILITY
# =============================================================================
# A "context" is a plain Dictionary describing the world RIGHT NOW. The game builds it (from a weather
# system, a clock, SaveManager...) and passes it in:
#   {
#     "time_of_day": "dawn",                 # one of FishingTerms.TIMES_OF_DAY
#     "weather":     "rain",                 # one of FishingTerms.WEATHERS
#     "season":      "wet",                  # one of FishingTerms.SEASONS
#     "unlocked":    ["unlock_dock"],        # unlock flags the player has earned
#   }
# Every key is optional. A modifier that looks at a key the context does not provide simply does not
# apply (the fish keeps its normal odds), so forgetting the weather never hides a fish.

## True if the location exists and is open: it has no unlock flag, or the player has that flag
## (listed in [code]context["unlocked"][/code]). Check this before letting the player start fishing there.
func is_location_available(location_id: String, context: Dictionary) -> bool:
	if not has_location(location_id):
		return false
	var location := _tables["location"][location_id] as LocationData
	return location.is_open_for(context.get("unlocked", []))


## The unlock flag a location needs ("" if it is open from the start, or if the location is unknown).
## Lets the NPC that opens a spot grant the right flag without hardcoding its name.
func get_unlock_flag(location_id: String) -> String:
	var location := get_location(location_id)
	return location.unlock_flag if location != null else ""


## The allowed words for one situation key ("time_of_day", "weather" or "season"), straight from
## [FishingTerms]. Handy for building debug menus or validating game state.
func get_condition_values(key: String) -> PackedStringArray:
	return FishingTerms.values_for(key)


# =============================================================================
# PUBLIC API: RELATIONAL QUERIES
# =============================================================================

## The location's complete fish pool, in the order authored. Empty if the location is unknown.
func get_location_fish_pool(location_id: String) -> Array[PoolEntry]:
	var location := get_location(location_id)
	var pool: Array[PoolEntry] = []
	if location != null:
		pool.assign(location.fish_pool)
	return pool


## The fish this bait enables (its whitelist). Empty if the bait is unknown.
func get_bait_enabled_fish(bait_id: String) -> Array[FishData]:
	var bait := get_bait(bait_id)
	var fish: Array[FishData] = []
	if bait != null:
		fish.assign(bait.enables_fish)
	return fish


## True if bait [param bait_id] is allowed to catch fish [param fish_id].
func bait_enables_fish(bait_id: String, fish_id: String) -> bool:
	var bait := get_bait(bait_id)
	var fish := get_fish(fish_id)
	return bait != null and fish != null and bait.enables(fish)


## Fish ids that can be caught at [param location_id] with [param bait_id]: the location must be
## available, and the fish must be in the pool, enabled by the bait and not removed by a
## weight_multiplier of 0. Pool order. Modifiers never remove a fish, so time/weather/season do not
## change this list. (The rod is not considered here; it only changes how likely each category is.
## See [method get_catch_odds].)
func get_catchable_fish_ids(location_id: String, bait_id: String, context: Dictionary) -> Array:
	var result: Array = []
	var bait := get_bait(bait_id)
	if bait == null or not is_location_available(location_id, context):
		return result
	for entry in get_location_fish_pool(location_id):
		if bait.enables(entry.fish) and entry.weight_multiplier > 0.0:
			result.append(entry.fish.id)
	return result


## The location's weight multiplier for [param fish_id] (1.0 unless the pool says otherwise).
## Returns 0.0 if the fish is not in that location's pool at all.
func get_location_weight_multiplier(location_id: String, fish_id: String) -> float:
	for entry in get_location_fish_pool(location_id):
		if entry.fish.id == fish_id:
			return entry.weight_multiplier
	return 0.0


## The bait's boost multiplier for [param fish_id], 1.0 if the bait does not boost it.
func get_bait_boost(bait_id: String, fish_id: String) -> float:
	var bait := get_bait(bait_id)
	var fish := get_fish(fish_id)
	return bait.get_boost_for(fish) if bait != null and fish != null else 1.0


# =============================================================================
# PUBLIC API: CATCH ODDS
# =============================================================================

## The chance of catching each fish on one bite.
## Returns [code]{fish_id: probability}[/code] (probabilities sum to 1.0; {} if nothing can be caught).
## [codeblock]
## weight(fish) = location weight_multiplier x bait boost x matching modifiers x extra_multipliers
##                (each defaults to 1.0)
## rod chance per class, e.g. small 0.2 / medium 0.3 / large 0.5
## a class the rod can catch but with no candidate fish here is "lost": its chance is split
##   EQUALLY among the classes that the rod can catch AND that have candidates
## class_share(c) = rod chance of c + lost / number of those receiving classes
## odds(fish)     = class_share(its class) x weight(fish) / sum of weights in its class
## [/codeblock]
## Worked example: rod {small 0.5, medium 0.5, large 0}, candidates = 10 small + 5 medium fish,
## no multipliers => each small fish 0.05, each medium fish 0.10.
## Redistribution example: rod {small 0.2, medium 0.3, large 0.5} but the spot has no large fish:
## the lost 0.5 is split equally, so small becomes 0.2 + 0.25 = 0.45 and medium 0.3 + 0.25 = 0.55.
## A class whose rod chance is 0 never receives anything: that rod simply cannot catch it.
## [br][br]
## [param extra_multipliers] is optional {fish_id: multiplier} for runtime effects (quests, buffs...).
## They work exactly like bait boosts, so the result still sums to 1.0. Multipliers <= 0 remove the fish.
func get_catch_odds(location_id: String, bait_id: String, rod_id: String,
		context: Dictionary, extra_multipliers: Dictionary = {}) -> Dictionary:
	var odds := {}
	var bait := get_bait(bait_id)
	var rod := get_rod(rod_id)
	if bait == null or rod == null or not is_location_available(location_id, context):
		return odds

	# Step 1: candidates grouped by class, each with its weight.
	# class_weights = { class_name: { fish_id: weight } }
	var class_weights := {}
	for entry in get_location_fish_pool(location_id):
		var fish := entry.fish
		if not bait.enables(fish):
			continue
		var weight: float = entry.weight_multiplier
		weight *= bait.get_boost_for(fish)
		weight *= entry.get_modifier_multiplier(context)
		weight *= float(extra_multipliers.get(fish.id, 1.0))
		if weight <= 0.0:
			continue
		if not class_weights.has(fish.size_class):
			class_weights[fish.size_class] = {}
		class_weights[fish.size_class][fish.id] = weight

	# Step 2: the rod's chance per class. Classes the rod can catch but that have no candidates
	# here "lose" their chance; it goes equally to the classes that can receive it.
	var receiving: Array = []
	var lost := 0.0
	for size_class in FishingTerms.SIZE_CLASSES:
		var chance := rod.get_chance(size_class)
		if chance <= 0.0:
			continue  # this rod cannot catch the class at all
		if class_weights.has(size_class):
			receiving.append(size_class)
		else:
			lost += chance
	if receiving.is_empty():
		return odds  # nothing catchable: no candidate belongs to a class this rod can catch
	var bonus: float = lost / receiving.size()

	# Step 3: split each receiving class's share among its fish by weight.
	for size_class in receiving:
		var class_share: float = rod.get_chance(size_class) + bonus
		var weights: Dictionary = class_weights[size_class]
		var weight_sum := 0.0
		for fish_id in weights:
			weight_sum += weights[fish_id]
		for fish_id in weights:
			odds[fish_id] = class_share * weights[fish_id] / weight_sum
	return odds


# =============================================================================
# PUBLIC API: SIZE, WEIGHT AND PRICE
# =============================================================================
# A fish's category (size_class) is a design label chosen in its record. The actual size (cm) of each
# caught fish is randomised between the fish's min_size and max_size by the catch logic; weight and sell
# price are then derived from it (FishData has the formulas; the id-based helpers below are shortcuts for
# code that only has a fish id, such as an inventory entry read from a save).

## The fish categories in order, e.g. ["small", "medium", "large"].
func get_size_class_ids() -> PackedStringArray:
	return FishingTerms.SIZE_CLASSES


## The rod's chance for every fish category as {class_name: probability} (sums to 1.0).
## Empty if the rod is unknown.
func get_rod_size_probabilities(rod_id: String) -> Dictionary:
	var rod := get_rod(rod_id)
	return rod.get_chances() if rod != null else {}


## Ids of the fish in category [param size_class], in load order.
func get_fish_ids_in_class(size_class: String) -> Array:
	var ids: Array = []
	for fish in get_all_fish():
		if fish.size_class == size_class:
			ids.append(fish.id)
	return ids


## The weight in kg of a fish [param fish_id] that is [param size_cm] long. Returns 0.0 (and warns) for an
## unknown fish. See [method FishData.get_weight_for_size_kg].
func get_weight_for_size_kg(fish_id: String, size_cm: float) -> float:
	var fish := get_fish(fish_id)
	return fish.get_weight_for_size_kg(size_cm) if fish != null else 0.0


## The sell price of a fish [param fish_id] that is [param size_cm] long. Returns 0 (and warns) for an
## unknown fish. See [method FishData.get_sell_price].
func get_sell_price(fish_id: String, size_cm: float) -> int:
	var fish := get_fish(fish_id)
	return fish.get_sell_price(size_cm) if fish != null else 0


# =============================================================================
# PUBLIC API: ROD MODELS
# =============================================================================

## Builds a ready-to-use instance of the rod's [code]model_3d[/code] scene, or null if the rod is unknown,
## has no model yet, or the scene's root is not a Node3D. Add the result to the scene yourself (e.g. under
## RodRig) and free it when done. Use [method find_line_tip] to get the line attachment point.
func instantiate_rod_model(rod_id: String) -> Node3D:
	var rod := get_rod(rod_id)
	if rod == null or rod.model_3d == null:
		return null
	var instance := rod.model_3d.instantiate()
	if instance is Node3D:
		return instance
	push_warning("[GameDatabase] the model_3d scene of '%s' must have a Node3D as its root" % rod_id)
	instance.free()
	return null


## The [code]LineTip[/code] node inside an instantiated rod model, or null (with a warning) if the
## model has none. See [constant LINE_TIP_NODE_NAME].
func find_line_tip(model: Node) -> Node3D:
	var tip := model.find_child(LINE_TIP_NODE_NAME, true, false) as Node3D
	if tip == null:
		push_warning("[GameDatabase] rod model '%s' has no Marker3D named '%s'" % [model.name, LINE_TIP_NODE_NAME])
	return tip


# =============================================================================
# INTERNAL: LOADING
# =============================================================================

# Clears all state ready for a (re)load.
func _reset() -> void:
	is_loaded = false
	load_errors = PackedStringArray()
	load_warnings = PackedStringArray()
	_rejected = {}
	_fatal = false
	_tables = {}
	for kind in KINDS:
		_tables[kind] = {}


func _err(message: String) -> void:
	load_errors.append(message)


func _warn(message: String) -> void:
	load_warnings.append(message)


# Finds every .tres/.res under [param data_dir] (recursively, sorted by path) and loads it. Returns the
# loaded resources; files that fail to load are reported and skipped.
func _scan_and_load(data_dir: String, cache_mode: ResourceLoader.CacheMode) -> Array:
	var records: Array = []
	if not DirAccess.dir_exists_absolute(data_dir):
		_err("data folder not found: %s" % data_dir)
		_fatal = true
		return records
	var paths: Array[String] = []
	_collect_paths(data_dir, paths)
	paths.sort()
	for path in paths:
		var resource := ResourceLoader.load(path, "", cache_mode)
		if resource == null:
			_err("%s: could not be loaded (see Godot's own message in the Output panel: a syntax error in the file, a missing script, or a missing file it refers to)" % path)
			continue
		records.append(resource)
	return records


# Appends the path of every resource file under [param dir] to [param out]. ResourceLoader.list_directory
# (Godot 4.4+) is used instead of DirAccess because it also works in an exported game, where .tres files
# are stored under different names.
func _collect_paths(dir: String, out: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			_collect_paths(dir.path_join(entry), out)
		elif entry.get_extension() in ["tres", "res"]:
			out.append(dir.path_join(entry))


# Which table a record belongs to: "fish", "bait", "rod", "location", or "" if it is not a database record.
func _kind_of(record: Resource) -> String:
	if record is FishData:
		return "fish"
	if record is BaitData:
		return "bait"
	if record is RodData:
		return "rod"
	if record is LocationData:
		return "location"
	return ""


# A short location string for error messages: "<file path> (<id>)", e.g.
# "res://data/fish/fish_bass.tres (fish_bass)". Records built in code have no path.
func _ctx(record: Resource) -> String:
	var where := record.resource_path if not record.resource_path.is_empty() else "(in memory)"
	var id: String = record.id if record is DatabaseEntry and not (record as DatabaseEntry).id.is_empty() else "no id"
	return "%s (%s)" % [where, id]


# Validates every record, indexes the valid ones by id, then checks the references between them.
func _process_records(records: Array) -> void:
	if records.is_empty():
		_err("no database records found (an empty or wrong data folder?)")
		_fatal = true
		return

	for item in records:
		var record := item as Resource
		if record == null:
			_err("a null entry was passed in instead of a record")
			continue
		var kind := _kind_of(record)
		if kind.is_empty():
			_warn("%s: not a database record (FishData, BaitData, RodData or LocationData); ignored" % record.resource_path)
			continue

		var entry := record as DatabaseEntry
		var ctx := _ctx(entry)
		var errors_before := load_errors.size()
		_validate_entry(entry, ctx)
		match kind:
			"fish": _validate_fish(entry as FishData, ctx)
			"bait": _validate_bait(entry as BaitData, ctx)
			"rod": _validate_rod(entry as RodData, ctx)
			"location": _validate_location(entry as LocationData, ctx)
		if load_errors.size() > errors_before:
			_rejected[entry.get_instance_id()] = true
			continue

		var table: Dictionary = _tables[kind]
		if table.has(entry.id):
			_err("%s: duplicate id '%s' (already used by %s)" % [ctx, entry.id, _ctx(table[entry.id])])
			_rejected[entry.get_instance_id()] = true
			continue
		table[entry.id] = entry

	for kind in KINDS:
		if _tables[kind].is_empty() and not records.is_empty():
			_warn("no valid %s records were loaded" % kind)
	_validate_references()


# Final step of every load: log, then either accept the data (success) or throw it away (failure) so a
# half-loaded database can never be used by accident.
func _finalize() -> void:
	var any_valid := false
	for kind in KINDS:
		any_valid = any_valid or not (_tables[kind] as Dictionary).is_empty()
	if not any_valid and not _fatal:
		_err("no valid records were left after validation")
		_fatal = true
	var usable := not _fatal and (load_errors.is_empty() or not strict_mode)

	if not quiet:
		for message in load_errors:
			push_error("[GameDatabase] " + message)
		for message in load_warnings:
			push_warning("[GameDatabase] " + message)

	if usable:
		is_loaded = true
		database_loaded.emit()
	else:
		var errors := load_errors
		_tables = {}
		for kind in KINDS:
			_tables[kind] = {}
		is_loaded = false
		database_load_failed.emit(errors)


# Shared body of the get_*() lookups.
func _lookup(kind: String, id: String) -> DatabaseEntry:
	if not is_loaded:
		push_error("[GameDatabase] queried before a successful load (is_loaded == false)")
		return null
	var table: Dictionary = _tables.get(kind, {})
	if not table.has(id):
		push_warning("[GameDatabase] unknown %s id '%s'" % [kind, id])
		return null
	return table[id]


# =============================================================================
# INTERNAL: RECORD VALIDATORS
# =============================================================================
# Each validator records errors via _err(). The caller decides the record is bad if the error count grew
# while the validators ran. Inspector hints (ranges, dropdowns) are only suggestions, and files can be
# edited by hand, so every rule is checked here again.

# Rules shared by all four kinds: a well-formed id and a display name.
func _validate_entry(record: DatabaseEntry, ctx: String) -> void:
	var id := record.id
	var prefix := record.get_id_prefix()
	if id.is_empty():
		_err("%s: id must not be empty" % ctx)
	elif not id.begins_with(prefix) or id.length() == prefix.length() or _slug_regex.search(id) == null:
		_err("%s: id '%s' must be lowercase snake_case and start with '%s' (e.g. '%sexample')" % [ctx, id, prefix, prefix])
	elif not record.resource_path.is_empty() and record.resource_path.get_file().get_basename() != id:
		# Only a warning: the id is what saves use, the file name is just a convenience.
		_warn("%s: file name '%s' does not match the id '%s' (convention: name the file like its id)" % [
			ctx, record.resource_path.get_file(), id])
	if record.display_name.strip_edges().is_empty():
		_err("%s: display_name must not be empty" % ctx)


# Rules for anything that goes in the grid inventory (fish and bait).
func _validate_item(item: ItemData, ctx: String) -> void:
	_check_min_int(item.grid_width, 1, "grid_width", ctx)
	_check_min_int(item.grid_height, 1, "grid_height", ctx)
	_check_min_int(item.max_stack, 1, "max_stack", ctx)


func _validate_fish(fish: FishData, ctx: String) -> void:
	_validate_item(fish, ctx)
	if fish.scientific_name.strip_edges().is_empty():
		_err("%s: scientific_name must not be empty" % ctx)
	if not FishingTerms.SIZE_CLASSES.has(fish.size_class):
		_err("%s: size_class '%s' is not one of: %s" % [ctx, fish.size_class, ", ".join(FishingTerms.SIZE_CLASSES)])
	_check_min_int(fish.base_price, 0, "base_price", ctx)
	_check_min_float(fish.speed, 0.0, "speed", ctx)
	_check_min_float(fish.min_size, 0.0, "min_size", ctx)
	if fish.min_size > fish.max_size:
		_err("%s: min_size (%s) must be <= max_size (%s)" % [ctx, str(fish.min_size), str(fish.max_size)])
	# avg_size and avg_weight drive weight (size x avg_weight / avg_size) and price (size / avg_size),
	# so both must be above 0, and avg_size must lie between min_size and max_size.
	if fish.avg_size <= 0.0:
		_err("%s: avg_size must be greater than 0 (weight is size x avg_weight / avg_size)" % ctx)
	elif fish.avg_size < fish.min_size or fish.avg_size > fish.max_size:
		_err("%s: avg_size (%s) must be between min_size (%s) and max_size (%s)" % [
			ctx, str(fish.avg_size), str(fish.min_size), str(fish.max_size)])
	if fish.avg_weight <= 0.0:
		_err("%s: avg_weight must be greater than 0" % ctx)


# Checks the shape of a bait record. Whether the fish are actually in the database is checked later in
# _validate_references(), once every record is known.
func _validate_bait(bait: BaitData, ctx: String) -> void:
	_validate_item(bait, ctx)
	if bait.enables_fish.is_empty():
		_err("%s: enables_fish must not be empty (a bait that enables nothing is useless)" % ctx)
	var enabled := {}
	for i in bait.enables_fish.size():
		var fish := bait.enables_fish[i]
		if fish == null:
			_err("%s.enables_fish[%d]: no fish assigned (empty slot)" % [ctx, i])
		elif enabled.has(fish.get_instance_id()):
			_err("%s.enables_fish[%d]: fish '%s' is listed more than once" % [ctx, i, fish.id])
		else:
			enabled[fish.get_instance_id()] = true

	var boosted := {}
	for i in bait.boosts.size():
		var boost := bait.boosts[i]
		var boost_ctx := "%s.boosts[%d]" % [ctx, i]
		if boost == null:
			_err("%s: empty slot (no BaitBoost)" % boost_ctx)
			continue
		if boost.fish == null:
			_err("%s: no fish assigned" % boost_ctx)
		else:
			if boosted.has(boost.fish.get_instance_id()):
				_err("%s: fish '%s' is boosted twice" % [boost_ctx, boost.fish.id])
			boosted[boost.fish.get_instance_id()] = true
			if not enabled.has(boost.fish.get_instance_id()):
				_err("%s: boosted fish '%s' must also be listed in enables_fish" % [boost_ctx, boost.fish.id])
		if boost.multiplier <= 0.0:
			_err("%s: multiplier must be greater than 0 (use a value below 1 to make a fish less likely)" % boost_ctx)


func _validate_rod(rod: RodData, ctx: String) -> void:
	_check_min_int(rod.rod_price, 0, "rod_price", ctx)
	var total := 0.0
	var shape_ok := true
	for size_class in FishingTerms.SIZE_CLASSES:
		var value: Variant = rod.get("chance_" + size_class)
		if value == null:
			_err("%s: RodData has no chance_%s property, but FishingTerms lists the class '%s'" % [ctx, size_class, size_class])
			shape_ok = false
		elif float(value) < 0.0 or float(value) > 1.0:
			_err("%s: chance_%s is %s but a chance must be between 0 and 1" % [ctx, size_class, str(value)])
			shape_ok = false
		else:
			total += float(value)
	if shape_ok and absf(total - 1.0) > PROBABILITY_TOLERANCE:
		_err("%s: the chances add up to %s but must add up to 1.0" % [ctx, str(total)])


func _validate_location(location: LocationData, ctx: String) -> void:
	if not location.unlock_flag.is_empty() and _slug_regex.search(location.unlock_flag) == null:
		_err("%s: unlock_flag '%s' must be lowercase snake_case (or empty)" % [ctx, location.unlock_flag])
	if location.fish_pool.is_empty():
		_err("%s: fish_pool must not be empty" % ctx)
	var seen := {}
	for i in location.fish_pool.size():
		var entry := location.fish_pool[i]
		var entry_ctx := "%s.fish_pool[%d]" % [ctx, i]
		if entry == null:
			_err("%s: empty slot (no PoolEntry)" % entry_ctx)
			continue
		if entry.fish == null:
			_err("%s: no fish assigned" % entry_ctx)
		else:
			if seen.has(entry.fish.get_instance_id()):
				_err("%s: fish '%s' is listed twice in this pool" % [entry_ctx, entry.fish.id])
			seen[entry.fish.get_instance_id()] = true
		_check_min_float(entry.weight_multiplier, 0.0, "weight_multiplier", entry_ctx)
		for j in entry.modifiers.size():
			_validate_modifier(entry.modifiers[j], "%s.modifiers[%d]" % [entry_ctx, j])


# A modifier needs a multiplier above 0, at least one condition list, and only words from FishingTerms.
func _validate_modifier(modifier: OddsModifier, ctx: String) -> void:
	if modifier == null:
		_err("%s: empty slot (no OddsModifier)" % ctx)
		return
	if modifier.multiplier <= 0.0:
		_err("%s: multiplier must be greater than 0 (modifiers only boost or decrease a chance; use a value below 1 to decrease)" % ctx)
	if modifier.has_no_condition():
		_err("%s: needs at least one of %s (a modifier with nothing to match would apply to everything: use weight_multiplier instead)" % [
			ctx, ", ".join(FishingTerms.CONDITION_KEYS)])
	for key in FishingTerms.CONDITION_KEYS:
		var allowed := FishingTerms.values_for(key)
		var seen := {}
		for value in modifier.get_values(key):
			if not allowed.has(value):
				_err("%s: '%s' is not a valid %s value (allowed: %s)" % [ctx, str(value), key, ", ".join(allowed)])
			elif seen.has(value):
				_err("%s: %s lists '%s' more than once" % [ctx, key, str(value)])
			seen[value] = true


# Cross-record checks that need every record known first. A reference to a fish that is not in the
# database is an ERROR (the fish may live outside the data folder, or be a private copy embedded in the
# bait/location file). The offending reference is removed so lenient mode keeps sane data, and a record
# left with nothing valid is dropped entirely.
func _validate_references() -> void:
	var fish_table: Dictionary = _tables["fish"]
	var baits: Dictionary = _tables["bait"]
	var locations: Dictionary = _tables["location"]
	var enabled_by_some_bait := {}
	var offered_by_some_location := {}

	for bait_id in baits.keys():
		var bait := baits[bait_id] as BaitData
		var kept: Array[FishData] = []
		var unexplained := 0
		for fish in bait.enables_fish:
			if _is_indexed_fish(fish):
				kept.append(fish)
				enabled_by_some_bait[fish.id] = true
			elif not _rejected.has(fish.get_instance_id()):
				unexplained += 1
				_err("%s: enables_fish references fish '%s' that is not in the database (is its .tres file inside the data folder?)" % [_ctx(bait), fish.id])
		if kept.is_empty():
			_drop_record(baits, bait_id, _ctx(bait), "enables_fish", unexplained)
		elif kept.size() != bait.enables_fish.size():
			# Lenient-mode clean-up: keep only valid fish, and the boosts that still make sense.
			bait.enables_fish = kept
			var kept_boosts: Array[BaitBoost] = []
			for boost in bait.boosts:
				if kept.has(boost.fish):
					kept_boosts.append(boost)
			bait.boosts = kept_boosts

	for location_id in locations.keys():
		var location := locations[location_id] as LocationData
		var kept_entries: Array[PoolEntry] = []
		var unexplained := 0
		for entry in location.fish_pool:
			if _is_indexed_fish(entry.fish):
				kept_entries.append(entry)
				offered_by_some_location[entry.fish.id] = true
			elif not _rejected.has(entry.fish.get_instance_id()):
				unexplained += 1
				_err("%s: fish_pool references fish '%s' that is not in the database (is its .tres file inside the data folder?)" % [_ctx(location), entry.fish.id])
		if kept_entries.is_empty():
			_drop_record(locations, location_id, _ctx(location), "fish_pool", unexplained)
		elif kept_entries.size() != location.fish_pool.size():
			location.fish_pool = kept_entries

	# Reachability warnings: a fish nobody can catch is almost always an authoring oversight.
	for fish_id in fish_table.keys():
		var fish := fish_table[fish_id] as FishData
		if not locations.is_empty() and not offered_by_some_location.has(fish_id):
			_warn("%s: not in any location's fish_pool, so it can never be caught" % _ctx(fish))
		if not baits.is_empty() and not enabled_by_some_bait.has(fish_id):
			_warn("%s: not enabled by any bait, so it can never be caught" % _ctx(fish))


# True if [param fish] is one of the records indexed by this load (the very same object, not a copy).
func _is_indexed_fish(fish: FishData) -> bool:
	return (_tables["fish"] as Dictionary).get(fish.id) == fish


# Removes a bait/location that has no valid fish left. If a reference was genuinely dangling
# (unexplained > 0) that error was already recorded; otherwise the cause was an earlier fish error, so
# only a warning is added to say why the record vanished.
func _drop_record(table: Dictionary, id: String, ctx: String, field: String, unexplained: int) -> void:
	if unexplained > 0:
		_err("%s: no valid fish left in %s; record dropped" % [ctx, field])
	else:
		_warn("%s: dropped because every fish in %s failed to load (see earlier errors)" % [ctx, field])
	table.erase(id)


# =============================================================================
# INTERNAL: FIELD CHECK HELPERS
# =============================================================================

func _check_min_int(value: int, min_value: int, field: String, ctx: String) -> void:
	if value < min_value:
		_err("%s: %s is %d but must be at least %d" % [ctx, field, value, min_value])


func _check_min_float(value: float, min_value: float, field: String, ctx: String) -> void:
	if value < min_value:
		_err("%s: %s is %s but must be at least %s" % [ctx, field, str(value), str(min_value)])
