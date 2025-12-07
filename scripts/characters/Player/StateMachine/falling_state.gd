extends State
class_name FallingState

var fall_time : float = 0.0
var initial_fall_velocity : float

func enter():
	print("Entered Falling State")
	fall_time = 0.0
	initial_fall_velocity = player.velocity.y

func physics_update(delta: float):
	fall_time += delta
	
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			change_to("DodgeDashState")
	
	# Falling - gets heavier over time
	var gravity_multiplier = get_fall_gravity_multiplier()
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
	
	# Check for coyote time jump
	if Input.is_action_just_pressed("jump") and player.can_coyote_jump():
		player.consume_coyote_time()
		change_to("JumpingState")
		return
	
	# Check for double jump input
	if Input.is_action_just_pressed("jump") and player.can_perform_double_jump():
		player.perform_double_jump()
		change_to("DoubleJumpState")
		return
	
	# Very limited air control while falling
	handle_falling_movement(delta)
	
	if player.is_on_floor():
		if Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
			change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	player.move_and_slide()

func get_fall_gravity_multiplier() -> float:
	# Progressive gravity increase for faster falling
	if fall_time < 0.1:
		# Brief initial period with normal gravity
		return 1.0
	elif fall_time < 0.3:
		# Quickly ramp up gravity
		return lerp(1.0, 2.2, (fall_time - 0.1) / 0.2)
	else:
		# Heavy gravity for fast descent
		return 2.2

func handle_falling_movement(delta: float):
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Limited air control while falling - preserve momentum
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var target_speed = max(current_horizontal_speed, 4.0)  # Conservative air speed
		var target_velocity = direction * target_speed
		
		# Moderate air control - better than jumps but still limited
		var air_control_factor = 0.25  # More control than jumping, but still limited
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Controlled rotation while falling
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 6.0  # Moderate rotation speed
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Face momentum direction when no input
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 4.0  # Slower momentum-based rotation
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

		# Minimal air resistance - preserve horizontal momentum
		var air_resistance = 0.01  # Very light resistance
		player.velocity.x *= (1.0 - air_resistance)
		player.velocity.z *= (1.0 - air_resistance)
