extends State
class_name FallingState

func enter():
	print("Entered Falling State")

func physics_update(delta: float):
	# Apply gravity
	player.velocity += player.get_gravity() * delta
	
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
		
		# Blend current horizontal velocity with input direction for air control
		var air_control_factor = 0.3  # Adjust this value for desired air control
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
	else:
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
