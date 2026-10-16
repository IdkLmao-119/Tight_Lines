## FishData: one fish species. One .tres file per species in [code]res://data/fish/[/code].
##
## A caught fish is NOT a FishData: the catch logic rolls a size (cm) between [member min_size] and
## [member max_size], and the weight and sell price are derived from that size (see
## [method get_weight_for_size_kg] and [method get_sell_price]). The save stores the fish id plus
## its rolled size, so every fish keeps its own size, weight and value.
##
## ALL VALUES IN THE SAMPLE FILES ARE PLACEHOLDERS.
class_name FishData
extends ItemData

@export_group("Identity")

## The scientific (Latin) name, e.g. "Lepomis macrochirus".
@export var scientific_name: String = ""

## Short text for the fish log / bestiary.
@export_multiline var description: String = ""

## 3D-style icon (an image), e.g. shown in the catch result panel. Leave empty while it does not exist.
@export var icon_3d: Texture2D

@export_group("Category")

## The fish's CATEGORY: small, medium or large (list: FishingTerms.SIZE_CLASSES). A rod decides which
## categories it can catch and how likely each is. This is a design choice, NOT computed from the
## centimetres below, so the size ranges of different categories may overlap.
@export_enum("small", "medium", "large") var size_class: String = "small"

@export_group("Economy")

## Sell price of a fish of exactly [member avg_size], in currency (whole number, at least 0).
## Bigger fish sell for more: price = base_price x size / avg_size (see [method get_sell_price]).
@export_range(0, 100000, 1, "or_greater") var base_price: int = 0

@export_group("Fishing")

## How hard the fish is to catch: 1.0 = baseline, higher = harder. Scales the reel-bar drift and the
## tension rise in the minigame. It does NOT change the bite window.
@export_range(0.0, 10.0, 0.05, "or_greater") var speed: float = 1.0

@export_group("Size and weight")

## Smallest possible size in centimetres (the catch logic rolls between min_size and max_size).
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:cm") var min_size: float = 10.0

## The "normal" size in centimetres. Must lie between min_size and max_size and be above 0.
## Weight and price are proportional to size relative to this.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:cm") var avg_size: float = 20.0

## Largest possible size in centimetres.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:cm") var max_size: float = 30.0

## Weight in kilograms of a fish of exactly [member avg_size] (must be above 0).
@export_range(0.0, 1000.0, 0.01, "or_greater", "suffix:kg") var avg_weight: float = 0.5


func get_id_prefix() -> String:
	return "fish_"


## The weight in kg of a fish that is [param size_cm] long: size x avg_weight / avg_size, i.e. weight is
## proportional to size. Not clamped to min/max (the caller supplies a real size); a negative size
## counts as 0. Returns 0.0 if avg_size is not above 0 (the loader rejects such fish).
func get_weight_for_size_kg(size_cm: float) -> float:
	if avg_size <= 0.0:
		return 0.0
	return maxf(size_cm, 0.0) * avg_weight / avg_size


## The weights in kg of the smallest and largest possible catch: x = at min_size, y = at max_size.
## Derived from the size range, e.g. for a "recorded range" display in the fish log.
func get_weight_range_kg() -> Vector2:
	return Vector2(get_weight_for_size_kg(min_size), get_weight_for_size_kg(max_size))


## How much the sell price is scaled for a fish of [param size_cm]: size / avg_size
## (1.0 for an average fish). Returns 0.0 if avg_size is not above 0.
func get_price_multiplier(size_cm: float) -> float:
	if avg_size <= 0.0:
		return 0.0
	return maxf(size_cm, 0.0) / avg_size


## The sell price of a fish that is [param size_cm] long: base_price x size / avg_size, rounded to the
## nearest whole currency unit.
func get_sell_price(size_cm: float) -> int:
	return roundi(base_price * get_price_multiplier(size_cm))
