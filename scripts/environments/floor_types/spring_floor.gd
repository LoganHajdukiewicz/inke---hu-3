class_name SpringFloor
extends FloorTypeHandler

## Bounces players upward (or along the floor's tilted "up" axis when
## use_directional_bounce is enabled).

var cooldown_timer: float = 0.0


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(1.0, 0.8, 0.4, 1))
	material.metallic = 0.2
	material.roughness = 0.3
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()


func process(delta: float) -> void:
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	if owner_floor.players_on_floor.size() > 0:
		activate_spring()


func activate_spring() -> void:
	"""Activate the spring effect for all players on the floor"""
	for player in owner_floor.players_on_floor:
		if player and is_instance_valid(player):
			apply_spring_effect(player)
	
	cooldown_timer = owner_floor.spring_cooldown


func apply_spring_effect(player: CharacterBody3D) -> void:
	"""Bounce a player. Tilted floors bounce along their up-axis when
	use_directional_bounce is on; otherwise straight up."""
	if not player:
		return
	
	# Reset double jump ability when bouncing
	if player.get("has_double_jumped") != null:
		player.has_double_jumped = false
		player.can_double_jump = true
	
	var bounce_direction: Vector3
	if owner_floor.use_directional_bounce:
		bounce_direction = owner_floor.global_transform.basis.y.normalized()
	else:
		bounce_direction = Vector3.UP
	
	var tween = owner_floor.create_tween()
	tween.set_parallel(true)
	
	var original_y = player.global_position.y
	
	# Visual bounce effect (small upward bump)
	tween.tween_method(
		func(pos_y): _set_player_y_position(player, pos_y),
		original_y,
		original_y + 0.3,
		owner_floor.spring_tween_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	_apply_spring_velocity(player, bounce_direction)
	
	tween.tween_callback(func(): _apply_spring_velocity(player, bounce_direction)).set_delay(owner_floor.spring_tween_duration)


func _set_player_y_position(player: CharacterBody3D, y_pos: float) -> void:
	if player and is_instance_valid(player):
		player.global_position.y = y_pos


func _apply_spring_velocity(player: CharacterBody3D, direction: Vector3) -> void:
	if player and is_instance_valid(player):
		player.velocity = direction * owner_floor.spring_force
		
		# Transition to jumping state
		var state_machine = player.get("state_machine")
		if state_machine and state_machine.has_method("change_state"):
			state_machine.change_state("JumpingState")
		
		player.move_and_slide()
