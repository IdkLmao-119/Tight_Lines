extends Control
class_name InventoryGrid

@export var width: int = 10
@export var height: int = 6

# Stores references to Item objects placed on the grid coordinates
var grid: Array = []

func _init(p_width: int = 10, p_height: int = 6) -> void:
	width = p_width
	height = p_height
	clear()

func clear() -> void:
	grid = []
	for x in range(width):
		var column = []
		for y in range(height):
			column.append(null)
		grid.append(column)

func is_within_bounds(pos: Vector2i, item_dims: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and \
		   pos.x + item_dims.x <= width and \
		   pos.y + item_dims.y <= height

func check_space_available(pos: Vector2i, item_dims: Vector2i) -> bool:
	if not is_within_bounds(pos, item_dims):
		return false
	
	for x in range(item_dims.x):
		for y in range(item_dims.y):
			if grid[pos.x + x][pos.y + y] != null:
				return false
	return true

func add_fish(fish_item, pos: Vector2i) -> bool:
	if not check_space_available(pos, fish_item.data.dimensions):
		return false
		
	for x in range(fish_item.data.dimensions.x):
		for y in range(fish_item.data.dimensions.y):
			grid[pos.x + x][pos.y + y] = fish_item
	return true
