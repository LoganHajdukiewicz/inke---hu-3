class_name MotionFloor
extends FloorTypeHandler

## Unified motion handler: MOVING (tween between two points) and SPINNING
## (continuous Y rotation) were two nearly identical scripts - both carry
## riders and transfer momentum on exit. Now one handler does either or
## BOTH: configure everything under "Motion Floor Settings" on the Floor.
## FloorType.MOVING and FloorType.SPINNING both create this handler; the
## floor type just picks which defaults are active (motion_moves/motion_spins).

var movement_tween: Tween
var is_moving: bool = false
var last_floor_position: Vector3


func setup() -> void:
	var tint = Color(0.6, 0.8, 1.0, 1) if owner_floor.motion_moves else Color(0.9, 0.6, 1.0, 1)
	var material = owner_floor.create_textured_material(tint)
	material.metallic = 0.3
	material.roughness = 0.2
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()
	
	last_floor_position = owner_floor.global_position
	
	if owner_floor.motion_moves:
		if owner_floor.movement_delay > 0:
			await owner_floor.get_tree().create_timer(owner_floor.movement_delay).timeout
			if not is_instance_valid(owner_floor):
				return
		start_moving()


func process(delta: float) -> void:
	# --- Translation: carry riders by the frame delta -----------------
	if is_moving:
		move_players_with_floor()
	
	# --- Rotation: spin and carry riders around the axis ---------------
	if owner_floor.motion_spins:
		var rotation_radians = deg_to_rad(owner_floor.spin_speed * delta)
		if owner_floor.spin_direction == Floor.SpinDirection.LEFT:
			rotation_radians = -rotation_radians
		owner_floor.rotate_y(rotation_radians)
		spin_players_with_floor(rotation_radians)


# =========================================================================
# TRANSLATION (was MovingFloor)
# =========================================================================

func start_moving() -> void:
	if is_moving:
		return
	is_moving = true
	last_floor_position = owner_floor.global_position
	
	if owner_floor.movement_repeat:
		_create_movement_cycle()
	else:
		_create_single_movement()


func stop_moving() -> void:
	if movement_tween:
		movement_tween.kill()
	is_moving = false


func _new_tween() -> Tween:
	var tween = owner_floor.create_tween()
	tween.set_trans(owner_floor.movement_transition)
	tween.set_ease(owner_floor.movement_easing)
	return tween


func _create_movement_cycle() -> void:
	if not is_moving:
		return
	movement_tween = _new_tween()
	movement_tween.tween_property(owner_floor, "global_position", owner_floor.end_position, owner_floor.movement_duration)
	movement_tween.tween_callback(func(): _handle_mid_cycle_delay())


func _handle_mid_cycle_delay() -> void:
	if owner_floor.movement_delay > 0:
		await owner_floor.get_tree().create_timer(owner_floor.movement_delay).timeout
	if not is_moving or not is_instance_valid(owner_floor):
		return
	movement_tween = _new_tween()
	movement_tween.tween_property(owner_floor, "global_position", owner_floor.start_position, owner_floor.movement_duration)
	movement_tween.tween_callback(func(): _handle_end_cycle_delay())


func _handle_end_cycle_delay() -> void:
	if owner_floor.movement_delay > 0:
		await owner_floor.get_tree().create_timer(owner_floor.movement_delay).timeout
	if not is_moving or not is_instance_valid(owner_floor):
		return
	_create_movement_cycle()


func _create_single_movement() -> void:
	movement_tween = _new_tween()
	movement_tween.tween_property(owner_floor, "global_position", owner_floor.end_position, owner_floor.movement_duration)
	movement_tween.tween_callback(func(): _handle_single_movement_delay())


func _handle_single_movement_delay() -> void:
	if owner_floor.movement_delay > 0:
		await owner_floor.get_tree().create_timer(owner_floor.movement_delay).timeout
	if not is_moving or not is_instance_valid(owner_floor):
		return
	movement_tween = _new_tween()
	movement_tween.tween_property(owner_floor, "global_position", owner_floor.start_position, owner_floor.movement_duration)
	movement_tween.tween_callback(func(): is_moving = false)


func move_players_with_floor() -> void:
	var floor_delta = owner_floor.global_position - last_floor_position
	
	if floor_delta.length() > 0.001:
		var players_to_remove = []
		for player in owner_floor.players_on_floor:
			if player and is_instance_valid(player):
				if player.is_on_floor() or player.velocity.y <= 0.1:
					player.global_position += floor_delta
				else:
					players_to_remove.append(player)
		
		for player in players_to_remove:
			owner_floor.players_on_floor.erase(player)
			if owner_floor.enable_momentum_transfer:
				transfer_linear_momentum(player)
	
	last_floor_position = owner_floor.global_position


func transfer_linear_momentum(player: CharacterBody3D) -> void:
	if not player or not is_instance_valid(player):
		return
	if not (player.velocity.y > 0 or not player.is_on_floor()):
		return
	
	player.velocity += Vector3(
		owner_floor.floor_velocity.x * owner_floor.momentum_transfer_strength,
		0,
		owner_floor.floor_velocity.z * owner_floor.momentum_transfer_strength
	)


# =========================================================================
# ROTATION (was SpinningFloor)
# =========================================================================

func spin_players_with_floor(rotation_radians: float) -> void:
	if owner_floor.players_on_floor.size() == 0:
		return
	
	var center = owner_floor.global_position
	var players_to_remove = []
	
	for player in owner_floor.players_on_floor:
		if player and is_instance_valid(player):
			if not player.is_on_floor() and player.velocity.y > 0:
				players_to_remove.append(player)
				continue
			
			var relative_pos = player.global_position - center
			var rotated_x = relative_pos.x * cos(rotation_radians) + relative_pos.z * sin(rotation_radians)
			var rotated_z = -relative_pos.x * sin(rotation_radians) + relative_pos.z * cos(rotation_radians)
			player.global_position = center + Vector3(rotated_x, relative_pos.y, rotated_z)
	
	for player in players_to_remove:
		owner_floor.players_on_floor.erase(player)
		if owner_floor.enable_momentum_transfer:
			transfer_rotational_momentum(player)


func transfer_rotational_momentum(player: CharacterBody3D) -> void:
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
	if not owner_floor.enable_momentum_transfer:
		return
	if owner_floor.motion_moves:
		transfer_linear_momentum(player)
	if owner_floor.motion_spins:
		transfer_rotational_momentum(player)
