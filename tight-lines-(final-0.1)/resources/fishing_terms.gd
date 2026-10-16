## FishingTerms: the shared vocabulary of the fishing database.
##
## Lists every word the database data may use for the three open-ended "situations"
## (time of day, weather, season) and for the fish size categories. Both the database
## loader and the Day/Weather system should read these lists, so the game and the data
## always agree on spelling.
##
## [b]Why the words appear twice[/b] (here AND in an [code]@export_enum(...)[/code] line):
## GDScript only accepts literal text inside [code]@export_enum[/code], so the Inspector
## dropdowns cannot read these constants. [code]tests/test_game_database.gd[/code] compares the
## two and fails if they ever differ, so a forgotten edit is caught immediately.
## [br][br]
## [b]To add or rename a word:[/b]
## [br]- time of day / weather / season: edit the list below AND the matching
##   [code]@export_enum[/code] line in [code]odds_modifier.gd[/code].
## [br]- size class: edit the list below, the [code]@export_enum[/code] line of
##   [code]FishData.size_class[/code], and add a [code]chance_<name>[/code] property to [code]RodData[/code].
## [br]Words are stored as plain text inside the .tres files, so adding or reordering words is
## safe. [b]Renaming or removing[/b] a word that existing .tres files use makes the loader report
## an error for each file that still uses it.
##
## ALL VALUES BELOW EXCEPT THE SIZE CLASSES ARE PLACEHOLDERS: replace them with the time periods,
## weather types and seasons the game really has.
class_name FishingTerms
extends RefCounted

## The fish categories. Every fish belongs to exactly one; every rod gives a chance for each.
const SIZE_CLASSES: PackedStringArray = ["small", "medium", "large"]

## Periods of the day (PLACEHOLDERS).
const TIMES_OF_DAY: PackedStringArray = ["dawn", "day", "dusk", "night"]

## Weather types (PLACEHOLDERS).
const WEATHERS: PackedStringArray = ["clear", "cloudy", "rain", "storm"]

## Seasons (PLACEHOLDERS).
const SEASONS: PackedStringArray = ["dry", "wet"]

## The three situation keys. The same names are used as property names on [OddsModifier]
## and as keys of the runtime context dictionary the game passes to [GameDatabase].
const CONDITION_KEYS: PackedStringArray = ["time_of_day", "weather", "season"]


## The allowed words for one situation key ("time_of_day", "weather" or "season").
## Returns an empty array for any other key.
static func values_for(key: String) -> PackedStringArray:
	match key:
		"time_of_day":
			return TIMES_OF_DAY
		"weather":
			return WEATHERS
		"season":
			return SEASONS
	return PackedStringArray()
