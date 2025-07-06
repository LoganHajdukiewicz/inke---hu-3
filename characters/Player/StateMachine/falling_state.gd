extends State
class_name FallingState

func enter():
	print("Entered Falling State")

func physics_update(delta: float):
	# Apply gravity
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
	
	# Check for double jump input while falling
	if Input.is_action_just_pressed("jump") and player.can_perform_double_jump():
		player.perform_double_jump()
		# Transition back to jumping state for the double jump
		change_to("JumpingState")
		return
	
	# Handle horizontal movement while falling
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		# Move based on camera direction, but blend with existing momentum
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Use current horizontal speed or minimum air speed, whichever is higher
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 8.0)  # At least walking speed
		var target_velocity = direction * air_speed
		
		# ENHANCED: Increased air control factor for better midair turning
		var air_control_factor = 0.7  # Increased from 0.3 to 0.7 for much better air control
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# ENHANCED: Add player rotation while falling for visual feedback
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 12.0  # Faster rotation for more responsive turning
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# ENHANCED: If no input but we have momentum, face the direction we're moving
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:  # Only rotate if moving with some speed
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 6.0  # Slower when not inputting
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		
		# Gradually reduce horizontal movement when no input (air resistance)
		var air_resistance = 0.02  # Much less than ground friction
		player.velocity.x = lerp(player.velocity.x, 0.0, air_resistance)
		player.velocity.z = lerp(player.velocity.z, 0.0, air_resistance)
	
	# Check if we've landed
	if player.is_on_floor():
		# Determine next state based on input
		if input_dir.length() > 0.1:
			change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	player.move_and_slide()
