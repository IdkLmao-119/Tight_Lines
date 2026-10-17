## OddsModifier: a situational odds change for one fish at one location.
##
## "When it is [time_of_day] / [weather] / [season], multiply this fish's odds by [multiplier]."
## It can only BOOST (above 1) or DECREASE (below 1) a chance; it never forbids a fish (the multiplier
## must be above 0). Embedded inside a [PoolEntry] (created from the Inspector with "New OddsModifier").
##
## [b]Conditions[/b]: each of the three lists below is optional. An EMPTY list means "no restriction on
## this one". Values inside a list are alternatives (dawn OR dusk); a modifier applies only if ALL its
## non-empty lists match (AND). At least one list must be non-empty: a modifier with nothing to match
## would apply to everything (use the pool entry's weight_multiplier for that).
##
## The words must come from FishingTerms (the dropdowns offer exactly those). The context the game
## passes in uses the same keys: {"time_of_day": "dawn", "weather": "rain", "season": "wet"}.
## A key missing from the context simply means the modifier does not apply.
class_name OddsModifier
extends Resource

@export_group("When")

## Allowed times of day (dawn OR dusk ...). Empty = any time.
@export_enum("dawn", "day", "dusk", "night") var time_of_day: Array[String] = []

## Allowed weather. Empty = any weather.
@export_enum("clear", "cloudy", "rain", "storm") var weather: Array[String] = []

## Allowed seasons. Empty = any season.
@export_enum("dry", "wet") var season: Array[String] = []

@export_group("Effect")

## Odds multiplier, above 0: 1.5 = 50% more likely than its classmates, 0.5 = half as likely.
@export_range(0.05, 10.0, 0.05, "or_greater") var multiplier: float = 1.0


## True if this modifier applies in [param context] (a dictionary with the optional keys
## "time_of_day", "weather" and "season").
func matches(context: Dictionary) -> bool:
	return _list_matches(time_of_day, context, "time_of_day") \
		and _list_matches(weather, context, "weather") \
		and _list_matches(season, context, "season")


## True if none of the three lists has an entry, i.e. the modifier has no condition at all (invalid).
func has_no_condition() -> bool:
	return time_of_day.is_empty() and weather.is_empty() and season.is_empty()


## The allowed values for one situation key ("time_of_day", "weather" or "season") as a plain array.
func get_values(key: String) -> Array:
	var values: Variant = get(key)
	return values if values is Array else []


# An empty list places no restriction. Otherwise the context must provide the key and its value must
# be in the list. str() lets the game pass either String or StringName values.
func _list_matches(allowed: Array[String], context: Dictionary, key: String) -> bool:
	if allowed.is_empty():
		return true
	return context.has(key) and allowed.has(str(context[key]))
