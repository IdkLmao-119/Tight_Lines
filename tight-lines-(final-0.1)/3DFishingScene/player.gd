extends Node3D

@export var rotation_speed: float = 1.5
@export var throw_strength: float = 10.0
@export var throw_upward: float = 0.4 # adds a bit of arc
@export var bobber_radius: float = 0.1

var current_bobber: RigidBody3D


func _process(delta: float) -> void:
	var direction := Input.get_axis("PanRight", "PanLeft")
	rotate_y(direction * rotation_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		throw_bobber()


func throw_bobber() -> void:
	# Only keep one bobber in the world at a time.
	if is_instance_valid(current_bobber):
		current_bobber.queue_free()

	var bobber := RigidBody3D.new()

	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = bobber_radius
	sphere_mesh.height = bobber_radius * 2.0
	mesh_instance.mesh = sphere_mesh
	bobber.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = bobber_radius
	collision.shape = sphere_shape
	bobber.add_child(collision)

	get_tree().current_scene.add_child(bobber)

	# -Z is forward; global_basis accounts for your -180° Y rotation.
	var forward := -global_basis.z
	bobber.global_position = global_position + forward * 1.0

	var throw_direction := (forward + Vector3.UP * throw_upward).normalized()
	bobber.apply_central_impulse(throw_direction * throw_strength)

	current_bobber = bobber
