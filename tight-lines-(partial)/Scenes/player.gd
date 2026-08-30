extends CharacterBody2D
@export var movement_speed : float = 150
var character_direction : Vector2
@onready var sprite: AnimatedSprite2D = $sprite

func _physics_process(_delta):
	character_direction.x = Input.get_axis("Move_Left", "Move_Right")
	character_direction.y = Input.get_axis("Move_Up", "Move_Down")
	
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
