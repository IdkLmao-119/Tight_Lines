## ItemData: a database record the player can carry in the grid inventory (fish and bait).
##
## Adds the 2D icon and the inventory footprint on top of [DatabaseEntry]. Rods and locations
## are not items (rods are bought in a shop and are not inventory items), so they extend
## [DatabaseEntry] directly.
class_name ItemData
extends DatabaseEntry

## 2D icon shown in the inventory, shop and fish log. Leave empty while the art does not exist yet.
@export var icon: Texture2D

@export_group("Grid inventory")

## How many grid cells wide this item is (whole number, at least 1).
@export_range(1, 20, 1, "suffix:cells") var grid_width: int = 1

## How many grid cells tall this item is (whole number, at least 1).
@export_range(1, 20, 1, "suffix:cells") var grid_height: int = 1

## How many units fit in one stack. 1 = never stacks (fish never stack, because every fish keeps
## its own size and weight); bait stacks, e.g. 99.
@export_range(1, 999, 1) var max_stack: int = 1


## The footprint as a vector: x = width, y = height, in grid cells.
func get_grid_size() -> Vector2i:
	return Vector2i(grid_width, grid_height)
