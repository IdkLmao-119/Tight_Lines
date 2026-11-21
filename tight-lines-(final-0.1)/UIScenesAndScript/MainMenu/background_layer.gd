extends Control

@export var fish_sprites_folder: String = "res://Assets/2D/fish_sprites/"
@export var vertical_texture: Texture2D # Photo moving bottom -> top

@export_group("Spawn & Scale")
@export var horizontal_spawn_interval: float = 3.0
@export var vertical_spawn_interval: float = 3.5
@export var horizontal_scale: float = 3.0
@export var vertical_scale: float = 1.0

@export_group("Movement Speed (Pixels/Sec)")
@export var horizontal_min_speed: float = 60.0
@export var horizontal_max_speed: float = 110.0
@export var vertical_min_speed: float = 140.0
@export var vertical_max_speed: float = 220.0

var horizontal_textures: Array[Texture2D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_textures_from_folder(fish_sprites_folder)
	_start_horizontal_loop()
	_start_vertical_loop()


func _load_textures_from_folder(folder_path: String) -> void:
	var dir := DirAccess.open(folder_path)
	if not dir:
		push_warning("Could not open folder: " + folder_path)
		return

	var valid_extensions := ["png", "jpg", "jpeg", "webp", "svg"]
	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir():
			var clean_name := file_name.trim_suffix(".import")
			if clean_name.get_extension().to_lower() in valid_extensions:
				var full_path := folder_path.path_join(clean_name)
				var tex := load(full_path) as Texture2D
				if tex and not horizontal_textures.has(tex):
					horizontal_textures.append(tex)
		file_name = dir.get_next()

	dir.list_dir_end()


func _start_horizontal_loop() -> void:
	while is_inside_tree():
		_spawn_right_to_left()
		await get_tree().create_timer(horizontal_spawn_interval).timeout


func _start_vertical_loop() -> void:
	while is_inside_tree():
		_spawn_bottom_to_top()
		await get_tree().create_timer(vertical_spawn_interval).timeout


func _spawn_right_to_left() -> void:
	if horizontal_textures.is_empty():
		return

	var chosen_tex: Texture2D = horizontal_textures.pick_random()
	if not chosen_tex:
		return

	var sprite := _create_bg_sprite(chosen_tex, horizontal_scale)
	var viewport_size := get_viewport_rect().size
	var scaled_size := chosen_tex.get_size() * horizontal_scale

	# Start fully off-screen on the right, at a random Y position
	var start_x := viewport_size.x
	var end_x := -scaled_size.x
	var random_y := randf_range(0.0, maxf(0.0, viewport_size.y - scaled_size.y))

	sprite.position = Vector2(start_x, random_y)
	add_child(sprite)

	# Calculate duration from distance and speed (pixels/sec)
	var distance := absf(end_x - start_x)
	var speed := randf_range(horizontal_min_speed, horizontal_max_speed)
	var duration := distance / maxf(speed, 1.0)

	var tween := create_tween()
	tween.tween_property(sprite, "position:x", end_x, duration)
	tween.tween_callback(sprite.queue_free)


func _spawn_bottom_to_top() -> void:
	if not vertical_texture:
		return

	var sprite := _create_bg_sprite(vertical_texture, vertical_scale)
	var viewport_size := get_viewport_rect().size
	var scaled_size := vertical_texture.get_size() * vertical_scale

	# Start fully off-screen at the bottom, at a random X position
	var random_x := randf_range(0.0, maxf(0.0, viewport_size.x - scaled_size.x))
	var start_y := viewport_size.y
	var end_y := -scaled_size.y

	sprite.position = Vector2(random_x, start_y)
	add_child(sprite)

	# Calculate duration from distance and speed (pixels/sec)
	var distance := absf(end_y - start_y)
	var speed := randf_range(vertical_min_speed, vertical_max_speed)
	var duration := distance / maxf(speed, 1.0)

	var tween := create_tween()
	tween.tween_property(sprite, "position:y", end_y, duration)
	tween.tween_callback(sprite.queue_free)


func _create_bg_sprite(tex: Texture2D, scale_factor: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.scale = Vector2(scale_factor, scale_factor)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Uncomment below if using pixel art so 3x scaling stays crisp:
	# rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect
