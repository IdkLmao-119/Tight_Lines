## BaitData: one kind of bait. One .tres file per bait in [code]res://data/bait/[/code].
##
## A bait is REQUIRED to fish (no bait = no cast) and does two jobs:
## [br]1. [member enables_fish], a WHITELIST: only these fish can be caught with this bait.
## [br]2. [member boosts], optional: makes some of those fish more (or less) likely than their
##    classmates. A boost never changes how likely a whole size class is (that is the rod's job).
##
## Bait is consumed once per bite. That is a gameplay/save rule, not data, so it is not stored here.
## Whether bait is sold in shops (and for how much) is not decided yet, so there is no bait price.
## ALL VALUES IN THE SAMPLE FILES ARE PLACEHOLDERS.
class_name BaitData
extends ItemData

@export_group("Catching")

## The whitelist of fish this bait allows you to catch. Must not be empty; drag fish .tres files from
## the FileSystem dock into the array. No duplicates.
@export var enables_fish: Array[FishData] = []

## Optional odds boosts for specific fish of the whitelist.
@export var boosts: Array[BaitBoost] = []


func get_id_prefix() -> String:
	return "bait_"


## True if this bait allows catching [param fish].
func enables(fish: FishData) -> bool:
	return enables_fish.has(fish)


## The boost multiplier this bait gives [param fish]: 1.0 if the bait does not boost it.
func get_boost_for(fish: FishData) -> float:
	for boost in boosts:
		if boost != null and boost.fish == fish:
			return boost.multiplier
	return 1.0
