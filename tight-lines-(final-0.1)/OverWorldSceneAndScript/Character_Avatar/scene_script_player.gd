extends CharacterBody2D

var character_direction : Vector2
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _physics_process(_delta):
	var dir = Input.get_vector("Left", "Right", "Up", "Down")

	velocity = dir * 200.0
	move_and_slide()

	if dir != Vector2.ZERO:
		if abs(dir.x) > abs(dir.y):
			if dir.x > 0:
				sprite.play("walking_right")
			else:
				sprite.play("walking_left")
		else:
			if dir.y > 0:
				sprite.play("walking_front")
			else:
				sprite.play("walking_back")
	else:
		match sprite.animation:
			"walking_front", "idle_front":
				sprite.play("idle_front")
			"walking_back", "idle_back":
				sprite.play("idle_back")
			"walking_left", "idle_left":
				sprite.play("idle_left")
			"walking_right", "idle_right":
				sprite.play("idle_right")
			_:
				sprite.play("idle_front")
	
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
	
#Seaside Park 3D Scene

func _on_seaside_park_3d_scene_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_fish_market")

# Fish Pens Signals
func _on_fish_pens_to_seaside_park_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fish_market")
func _on_fish_pen_to_salt_farm_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_salt_farm")
	
# Fish Pens 3D Signal
func _on_fish_pen_3d_scene_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_fishing_pens")

# Salt Farm Signals
func _on_salt_farm_to_fish_pens_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_fishing_pens")
func _on_salt_farm_to_mangrove_forest_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_mangrove")
	
# Salt Farm 3D Signal
func _on_salt_farm_3d_scene_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_salt_farm")
	
# Mangrove Signals
func _on_mangrove_to_island_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_island")
func _on_mangrove_to_salt_farm_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_salt_farm")
	
# Mangrove 3D Signal
func _on_mangrove_3d_scene_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_mangrove")

# Island Signals
func _on_island_to_mangrove_body_entered(body: Node2D) -> void:
	GameManager.change_scene("overworld_mangrove")

#Island 3D Signal

func _on_island_3d_scene_body_entered(body: Node2D) -> void:
	GameManager.change_scene("fishing_island")
