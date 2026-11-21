## BaitData: one kind of bait. One .tres file per bait in [code]res://data/bait/[/code].
##
## A bait is REQUIRED to fish (no bait = no cast) and does two jobs:
## [br]1. [member enables_fish], a WHITELIST: only these fish can be caught with this bait.
## [br]2. [member boosts], optional: makes some of those fish more (or less) likely than their
##    classmates. A boost never changes how likely a whole size class is (that is the rod's job).
##
## Bait is consumed once per cast (DECISIONS D5); unlimited bait (see [member unlimited], D12) is never
## consumed. Consumption is a gameplay/save rule, so only the "unlimited" flag is stored here.
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


@export_group("Supply")

## Unlimited bait (D12): never spent on a cast, never stored in the Tackle Box, always offered in the
## bait picker. Code must check this flag, never a specific id. More than one unlimited bait is allowed.
## Combining it with a max_stack above 1 is harmless.
@export var unlimited: bool = false

## Compost Pit weight (D13, DECISIONS section 4B): 0 = the pit never makes this bait; above 0 = the
## chance weight when the pit picks a random bait on each tick (weight 3 is picked three times as often
## as weight 1). Must not be below 0. A bait the pit makes should not be unlimited (a test checks it).
@export_range(0.0, 100.0, 0.5, "or_greater") var compost_weight: float = 0.0


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
