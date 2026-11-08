extends CharacterBody2D
@export var movement_speed : float = 300

var character_direction : Vector2
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _physics_process(_delta):
	# Keyboard through YOUR Input Map actions (so your own key mapping still
	# works) PLUS the phone: InputManager.get_move_vector() turns each phone
	# swipe into a short move pulse (PHONE_MOVE_PULSE_SEC in InputManager.gd).
	# InputManager returns zero unless the context is OVERWORLD and the game is
	# not paused, so this also stays still in menus and the pause screen.
	var keyboard := Vector2(Input.get_axis("Left", "Right"), Input.get_axis("Up", "Down"))
	character_direction = (keyboard + InputManager.get_move_vector(1)).limit_length(1.0)
	
	if character_direction.x > 0:
		sprite.flip_h = false
	elif character_direction.x < 0:
		sprite.flip_h = true
	
	if character_direction:
		velocity = character_direction * movement_speed
		if sprite.animation != "walking":
			sprite.animation = "walking"
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed)
		if sprite.animation != "idle":
			sprite.animation = "idle"
	
	move_and_slide()
	
# Spawn Signals
func _on_spawn_to_fish_market_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fish_market")
func _on_spawn_to_house_1_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_house_1")
func _on_spawn_to_rice_fields_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_rice_field")
func _on_spawn_to_river_park_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_river_park")

# House Signals
func _on_house_1_to_house_2_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_house_2")
func _on_house_1_to_spawn_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_spawn")
func _on_house_2_to_house_1_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_house_1")

# Rice Field Signals
func _on_rice_fields_to_rice_fishing_spot_1_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_rice_field")
func _on_rice_fields_to_rice_fishing_spot_2_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_rice_field")
func _on_rice_fields_to_spawn_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_spawn")

# River Park Signal
func _on_river_park_to_spawn_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_spawn")
func _on_river_park_to_river_park_fishing_spot_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_river_park")

# Fish Market Signals

func _on_fish_market_to_spawn_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_spawn")
func _on_fish_market_to_fish_pens_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fishing_pens")
