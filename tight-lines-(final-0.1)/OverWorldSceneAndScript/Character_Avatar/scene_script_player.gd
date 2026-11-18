extends CharacterBody2D

const SHOP_UI_SCENE := preload("res://UIScenesAndScript/RodShopUI/ShopUI.tscn")

var character_direction : Vector2
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _shop_ui: Control = null


func _physics_process(_delta):
	var story := get_node_or_null("/root/StoryManager")
	if story != null and story.is_playing():
		velocity = Vector2.ZERO
		return

	var dir = Input.get_vector("Left", "Right", "Up", "Down")
	if dir == Vector2.ZERO and get_node_or_null("/root/InputManager") != null:
		dir = get_node_or_null("/root/InputManager").get_move_vector()

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


func _enter_fishing(scene_id: String, spot_id: String) -> void:
	var ctx := {"spot_id": spot_id}
	var rod_id := SaveManager.get_equipped_rod()
	var bait_id := SaveManager.get_equipped_bait()
	if rod_id != "":
		ctx["rod_id"] = rod_id
	if bait_id != "":
		ctx["bait_id"] = bait_id
	GameManager.change_scene(scene_id, ctx)


func _try_change_scene(scene_id: String, required_flag: String = "", locked_msg: String = "") -> void:
	if required_flag != "" and not SaveManager.has_unlock_flag(required_flag):
		var story := get_node_or_null("/root/StoryManager")
		if story != null and locked_msg != "":
			story.call("show_notice", locked_msg)
		return
	GameManager.change_scene(scene_id)


# Spawn Signals
func _on_spawn_to_fish_market_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_fish_market", "unlock_kawit", "Catch every small fish in Imus to unlock Kawit!")

func _on_spawn_to_house_1_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_house_1")

func _on_spawn_to_rice_fields_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_rice_field", "unlock_imus", "Catch every small fish in Marikina River to unlock Imus!")

func _on_spawn_to_river_park_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_river_park")

# House Signals
func _on_house_1_to_house_2_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_house_2")

func _on_house_1_to_spawn_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_spawn")

func _on_house_2_to_house_1_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_house_1")

# Rice Field Signals (Imus Fields -> location_imus)
func _on_rice_fields_to_rice_fishing_spot_1_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_rice_field", "location_imus")

func _on_rice_fields_to_rice_fishing_spot_2_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_rice_field", "location_imus")

func _on_rice_fields_to_spawn_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_spawn")

# River Park Signal (Marikina River Park -> location_marikina)
func _on_river_park_to_spawn_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_spawn")

func _on_river_park_to_river_park_fishing_spot_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_river_park", "location_marikina")

# Fish Market Signals
func _on_fish_market_to_spawn_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_spawn")

func _on_fish_market_to_fish_pens_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_fishing_pens", "unlock_fish_pens", "Catch every small fish in Kawit to unlock Noveleta!")

# Seaside Park 3D Scene (Kawit Seaside Park -> location_kawit)
func _on_seaside_park_3d_scene_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_fish_market", "location_kawit")

# Fish Pens Signals
func _on_fish_pens_to_seaside_park_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_fish_market")

func _on_fish_pen_to_salt_farm_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_salt_farm", "unlock_salt_farm", "Catch every small & medium fish in the Fishing Pen to unlock the Salt Farm!")

# Fish Pens 3D Signal (Noveleta Fish Pens -> location_fish_pens)
func _on_fish_pen_3d_scene_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_fishing_pens", "location_fish_pens")

# Salt Farm Signals
func _on_salt_farm_to_fish_pens_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_fishing_pens")

func _on_salt_farm_to_mangrove_forest_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_mangrove", "unlock_calatagan", "Catch every small & medium fish in the Salt Farm to unlock Batangas!")

# Salt Farm 3D Signal (Noveleta Salt Farm -> location_salt_farm)
func _on_salt_farm_3d_scene_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_salt_farm", "location_salt_farm")

# Mangrove Signals
func _on_mangrove_to_island_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_try_change_scene("overworld_island", "unlock_fortune_island", "Catch every fish in Calatagan Mangrove Forest to unlock Fortune Island!")

func _on_mangrove_to_salt_farm_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_salt_farm")

# Mangrove 3D Signal (Calatagan Mangrove Forest -> location_calatagan)
func _on_mangrove_3d_scene_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_mangrove", "location_calatagan")

# Island Signals
func _on_island_to_mangrove_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_mangrove")

# Island 3D Signal (Fortune Island -> location_fortune_island)
func _on_island_3d_scene_body_entered(body: Node2D) -> void:
	if body != self:
		return
	_enter_fishing("fishing_island", "location_fortune_island")

# Shop Signals
func _on_rod_shop_exit_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_spawn")

func _on_shop_ui_signal_body_entered(body: Node2D) -> void:
	if body != self:
		return
	if _shop_ui == null or not is_instance_valid(_shop_ui):
		_shop_ui = SHOP_UI_SCENE.instantiate() as Control
		$CanvasLayer.add_child(_shop_ui)
	if _shop_ui.has_method("open_shop"):
		_shop_ui.call("open_shop")
	else:
		_shop_ui.visible = true

func _on_spawn_to_rod_shop_body_entered(body: Node2D) -> void:
	if body != self:
		return
	GameManager.change_scene("overworld_rod_shop")
