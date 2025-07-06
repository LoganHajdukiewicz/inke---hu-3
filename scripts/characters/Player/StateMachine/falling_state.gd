extends State
class_name FallingState

func enter():
	print("Entered Falling State")

func physics_update(delta: float):
	player.velocity += player.get_gravity() * delta
	
	# Check for wall jump input first (highest priority)
	if Input.is_action_just_pressed("jump") and player.can_perform_wall_jump():
		var wall_normal = player.get_wall_jump_direction()
		if wall_normal.length() > 0:
			var wall_jump_state = player.state_machine.states.get("walljumpingstate")
			if wall_jump_state:
				wall_jump_state.setup_wall_jump(wall_normal)
				change_to("WallJumpingState")
				player.wall_jump_cooldown = player.wall_jump_cooldown_time
				return
	
	if Input.is_action_just_pressed("jump") and player.can_perform_double_jump():
		player.perform_double_jump()
		change_to("JumpingState")
		return
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 8.0) 
		var target_velocity = direction * air_speed
		
		# Better Midair Turns
		var air_control_factor = 0.7  
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Turn the Character model when moving midair
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 12.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 6.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

		var air_resistance = 0.02
		player.velocity.x = lerp(player.velocity.x, 0.0, air_resistance)
		player.velocity.z = lerp(player.velocity.z, 0.0, air_resistance)
	
	if player.is_on_floor():
		if input_dir.length() > 0.1:
			change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	player.move_and_slide()
