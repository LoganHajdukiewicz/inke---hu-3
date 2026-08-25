class_name SpinningFloor
extends FloorTypeHandler

## Rotates continuously around Y and carries players standing on it,
## transferring tangential momentum when they jump off.


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(0.9, 0.6, 1.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()


func process(delta: float) -> void:
	var rotation_amount = owner_floor.spin_speed * delta
	
	var rotation_radians = deg_to_rad(rotation_amount)
	if owner_floor.spin_direction == Floor.SpinDirection.LEFT:
		rotation_radians = -rotation_radians
	
	owner_floor.rotate_y(rotation_radians)
	
	spin_players_with_floor(rotation_radians)


func spin_players_with_floor(rotation_radians: float) -> void:
	"""Move players to follow the floor's rotation"""
	if owner_floor.players_on_floor.size() == 0:
		return
	
	var center = owner_floor.global_position
	var players_to_remove = []
	
	for player in owner_floor.players_on_floor:
		if player and is_instance_valid(player):
			if not player.is_on_floor() and player.velocity.y > 0:
				players_to_remove.append(player)
				continue
			
			var player_pos = player.global_position
			var relative_pos = player_pos - center
			
			var rotated_x = relative_pos.x * cos(rotation_radians) + relative_pos.z * sin(rotation_radians)
			var rotated_z = -relative_pos.x * sin(rotation_radians) + relative_pos.z * cos(rotation_radians)
			
			player.global_position = center + Vector3(rotated_x, relative_pos.y, rotated_z)
	
	for player in players_to_remove:
		owner_floor.players_on_floor.erase(player)
		if owner_floor.enable_momentum_transfer:
			transfer_rotational_momentum(player)


func transfer_rotational_momentum(player: CharacterBody3D) -> void:
	"""Transfer rotational momentum to a player leaving the floor"""
	if not player or not is_instance_valid(player):
		return
	if not (player.velocity.y > 0 or not player.is_on_floor()):
		return
	
	var center = owner_floor.global_position
	var player_relative_pos = player.global_position - center
	
	var radius = Vector2(player_relative_pos.x, player_relative_pos.z).length()
	if radius < 0.01:
		return
	
	var tangential_speed = abs(owner_floor.floor_angular_velocity) * radius
	var radius_direction = Vector2(player_relative_pos.x, player_relative_pos.z).normalized()
	
	var tangent_direction_2d: Vector2
	if owner_floor.spin_direction == Floor.SpinDirection.RIGHT:
		tangent_direction_2d = Vector2(radius_direction.y, -radius_direction.x)
	else:
		tangent_direction_2d = Vector2(-radius_direction.y, radius_direction.x)
	
	var tangent_direction = Vector3(tangent_direction_2d.x, 0, tangent_direction_2d.y)
	player.velocity += tangent_direction * tangential_speed * owner_floor.momentum_transfer_strength


func on_player_exited(player: CharacterBody3D) -> void:
	if owner_floor.enable_momentum_transfer:
		transfer_rotational_momentum(player)
