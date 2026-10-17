## PoolEntry: one fish that can appear at a location, with that location's odds adjustments.
##
## Embedded inside the location's .tres file (created from the Inspector with "New PoolEntry").
## Both adjustments only shift odds between fish of the SAME size class at that spot, because the rod
## fixes each class's chance. A fish that is alone in its class there gets the class's whole share
## whatever its multipliers are.
class_name PoolEntry
extends Resource

## The fish that can appear here (drag its .tres file in). Each fish may appear at most once per location.
@export var fish: FishData

## Makes this fish count more (above 1) or less (below 1) than its classmates here, ALWAYS.
## 0 removes the fish from this spot. Combines (multiplies) with bait boosts and modifiers.
@export_range(0.0, 10.0, 0.05, "or_greater") var weight_multiplier: float = 1.0

## Situational odds changes (time of day / weather / season). Several matching modifiers multiply together.
@export var modifiers: Array[OddsModifier] = []


## The combined multiplier of every modifier that matches [param context]; 1.0 if none match.
func get_modifier_multiplier(context: Dictionary) -> float:
	var result := 1.0
	for modifier in modifiers:
		if modifier != null and modifier.matches(context):
			result *= modifier.multiplier
	return result
