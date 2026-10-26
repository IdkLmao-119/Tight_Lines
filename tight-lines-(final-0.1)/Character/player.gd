extends CharacterBody2D
@export var movement_speed : float = 300

var character_direction : Vector2
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _physics_process(_delta):
	character_direction.x = Input.get_axis("Left", "Right")
	character_direction.y = Input.get_axis("Up", "Down")
	
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

func _on_area_2_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fish_market")

func _on_house_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("House1")

func _on_area_1_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("MainArea")

func _on_house_2_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("House2")

func _on_rice_fields_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_rice_field")

func _on_rice_fishing_spot_1_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("3DFishRiceFields")

func _on_rice_fishing_spot_2_gateway_body_entered(body: Node2D) -> void:
	GameManager.change_scene("3DFishRiceFields")


func _on_river_park_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_river_park")


func _on_main_area_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_spawn")


func _on_fish_pens_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fishing_pens")
