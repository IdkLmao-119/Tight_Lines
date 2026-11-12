## BaitBoost: one "this bait makes that fish more (or less) likely" entry inside a [BaitData].
##
## Embedded inside the bait's .tres file (created from the Inspector with "New BaitBoost"); it is
## not a file of its own. A boost only reshuffles odds INSIDE the fish's own size class: it never
## changes how likely the class itself is (that is the rod's job).
class_name BaitBoost
extends Resource

## The fish this boost applies to. It must also be listed in the bait's [code]enables_fish[/code]
## (a boost for a fish the bait cannot catch would silently do nothing), and each fish may be boosted once.
@export var fish: FishData

## Odds multiplier, above 0: 1.5 = counts 1.5x as much as an unboosted classmate, 0.5 = half as much.
@export_range(0.05, 10.0, 0.05, "or_greater") var multiplier: float = 1.0
