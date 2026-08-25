class_name MovingFloor
extends FloorTypeHandler

## Tweens between two positions, carrying players riding it and
## transferring linear momentum when they jump off.

var movement_tween: Tween
var is_moving: bool = false
var last_floor_position: Vector3


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(0.6, 0.8, 1.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()
	
	last_floor_position = owner_floor.global_position
	
	if owner_floor.movement_delay > 0:
		await owner_floor.get_tree().create_timer(owner_floor.movement_delay).timeout
		if not is_instance_valid(owner_floor):
			return
	start_moving()


func process(_delta: float) -> void:
	if is_moving:
		move_players_with_floor()


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
	"""One complete movement cycle (start->end->start) with delays"""
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
	"""Carry players riding the floor"""
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


func on_player_exited(player: CharacterBody3D) -> void:
	if owner_floor.enable_momentum_transfer:
		transfer_linear_momentum(player)
