class_name MobileCursorHighlight
extends Panel

@export var border_color: Color = Color(1.0, 0.85, 0.2, 1.0)
@export var border_width: int = 4
@export var corner_radius: int = 8
@export var padding: Vector2 = Vector2(3.0, 3.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	top_level = false
	visible = false

	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	add_theme_stylebox_override(&"panel", style)


func highlight(target: Control) -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		clear()
		return

	var rect := target.get_global_rect()
	visible = true
	global_position = rect.position - padding
	size = rect.size + padding * 2.0


func clear() -> void:
	visible = false
