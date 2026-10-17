## RodData: one fishing rod. One .tres file per rod in [code]res://data/rods/[/code].
##
## In the catch, a rod does ONE thing: it decides which fish CATEGORIES (size classes) can be caught
## and how likely each category is. It does not change how big an individual fish is.
## Example: chance_small 0.5, chance_medium 0.5, chance_large 0.0 = half of the catches come from
## small fish, half from medium fish, never large. Inside a class the fish share that class's chance
## equally (before bait boosts and modifiers): 10 small fish at 0.5 => 0.05 each. If the spot has no
## fish for a class the rod favours, that share is split equally among the other classes the rod can
## catch (see docs, section "How a catch is decided").
##
## Rods are bought in a shop with currency and are not inventory items. ALL VALUES IN THE SAMPLE FILES
## ARE PLACEHOLDERS.
class_name RodData
extends DatabaseEntry

@export_group("Appearance")

## 2D icon (shop, equipment screen). Leave empty while the art does not exist yet.
@export var icon: Texture2D

## 3D-style icon (an image). Leave empty while it does not exist yet.
@export var icon_3d: Texture2D

## The in-minigame rod model: a scene whose root is a Node3D and that contains a Marker3D named
## "LineTip" at the rod's tip, where the fishing line attaches. Leave empty until the model exists.
## Use [method GameDB.instantiate_rod_model] and [method GameDB.find_line_tip].
@export var model_3d: PackedScene

@export_group("Shop")

## Shop price in currency (whole number, at least 0; 0 = free / starter rod).
@export_range(0, 1000000, 1, "or_greater") var rod_price: int = 0

@export_group("Catch chances by fish class")

## Chance that a bite comes from a SMALL fish. The three chances must add up to 1.0.
@export_range(0.0, 1.0, 0.01) var chance_small: float = 1.0

## Chance that a bite comes from a MEDIUM fish.
@export_range(0.0, 1.0, 0.01) var chance_medium: float = 0.0

## Chance that a bite comes from a LARGE fish.
@export_range(0.0, 1.0, 0.01) var chance_large: float = 0.0


@export_group("Fight stats (TEMPORARY ranges, to be tuned with FishingManager)")

## How much pull the line survives before it snaps. Compared with the fish's pull_strength by the
## minigame. Suggested range 5 to 20; must be above 0.
@export_range(1.0, 100.0, 0.5, "or_greater") var line_strength: float = 10.0

## How fast the reel takes in line (1.0 = baseline). Suggested range 0.5 to 2.0; must be above 0.
@export_range(0.1, 10.0, 0.05, "or_greater") var reel_speed: float = 1.0

## The farthest cast the rod allows, in metres. Suggested range 10 to 40; must be above 0.
@export_range(1.0, 200.0, 0.5, "or_greater", "suffix:m") var max_cast_distance: float = 20.0

## How precisely the player steers the reel bar (1.0 = baseline, higher = easier). Suggested range
## 0.5 to 2.0; must be above 0.
@export_range(0.1, 10.0, 0.05, "or_greater") var control: float = 1.0


func get_id_prefix() -> String:
	return "rod_"


## The chance for one fish category ("small", "medium" or "large"); 0.0 for an unknown class name.
## Reads the property named "chance_<size_class>", so a class added to FishingTerms.SIZE_CLASSES
## only needs a matching chance_<name> property here.
func get_chance(size_class: String) -> float:
	var value: Variant = get("chance_" + size_class)
	return float(value) if value != null else 0.0


## The chance of every size class as {class_name: probability}, in FishingTerms.SIZE_CLASSES order.
## The values add up to 1.0 in any record the loader accepts.
func get_chances() -> Dictionary:
	var result := {}
	for size_class in FishingTerms.SIZE_CLASSES:
		result[size_class] = get_chance(size_class)
	return result
