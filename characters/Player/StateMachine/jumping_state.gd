extends State
class_name JumpingState

var jump_velocity : float = 5.0

func enter():
	print("Entered Jumping State")
	# Apply jump velocity while preserving horizontal momentum
	player.velocity.y = jump_velocity
	# Don't reset horizontal velocity - preserve momentum from previous state

func physics_update(delta: float):
	# Apply gravity
	player.velocity += player.get_gravity() * delta
	
	# Handle horizontal movement while jumping
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		# Move based on camera direction, but blend with existing momentum
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Use current horizontal speed or minimum air speed, whichever is higher
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 8.0)  # At least walking speed
		var target_velocity = direction * air_speed
		
		# Blend current horizontal velocity with input direction for air control
		var air_control_factor = 0.3  # Adjust this value (0.0 = no air control, 1.0 = full control)
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
	# If no input, maintain current horizontal momentum (no deceleration in air)

	# Check if we're falling (velocity going down)
	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()
