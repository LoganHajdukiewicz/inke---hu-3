extends State
class_name JumpingState

var jump_velocity : float = 15.0  # Same upward speed
var gravity_multiplier : float = 1.0
var jump_time : float = 1.0
var peak_time : float = 0.0  # Even shorter for lower jump

func enter():
	print("Entered Jumping State")
	
	
	player.velocity.y = jump_velocity
	jump_time = 0.0
	
	
	player.velocity.x *= 0.8
	player.velocity.z *= 0.8
	
	if player.is_on_floor():
		player.can_double_jump = true
		

	


func physics_update(delta: float):
	jump_time += delta
	
	# Jak and Daxter gravity curve - quick up, brief pause, quick down
	if jump_time < peak_time:
		# Ascending - reduced gravity for quick rise
		gravity_multiplier = 0.15
	elif jump_time < peak_time + 0.0001:
		# Very brief hang time at peak (even shorter)
		gravity_multiplier = 0.1
	else:
		# Falling - increased gravity for quick descent
		gravity_multiplier = 3
	
	player.velocity += player.get_gravity() * delta * gravity_multiplier
	
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
	
	# Check for double jump input - transition to the fancy double jump state
	if Input.is_action_just_pressed("jump") and player.can_perform_double_jump():
		player.perform_double_jump()
		change_to("DoubleJumpState")
		return

	# Minimal air control - preserve horizontal momentum, don't add much
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Very limited horizontal control during jump
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var target_speed = max(current_horizontal_speed, 6.0)  # Much lower air speed
		var target_velocity = direction * target_speed
		
		# Minimal air control - mostly preserve momentum
		var air_control_factor = 0.5  # Even less control
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Slower rotation - more deliberate movement
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 8.0  # Much slower rotation
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Preserve momentum direction with minimal drift
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 3.0  # Slow momentum-based rotation
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		
		# Minimal air resistance - preserve horizontal momentum
		var air_resistance = 0.005  # Very low resistance
		player.velocity.x *= (1.0 - air_resistance)
		player.velocity.z *= (1.0 - air_resistance)

	# Transition to falling when velocity goes negative
	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()

func exit():
	# Reset scale to normal
	player.scale = Vector3.ONE
