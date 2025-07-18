extends State
class_name JumpingState

var jump_velocity : float = 10.0


func enter():
	print("Entered Jumping State")
	
	# Instant, snappy jump - no tween, just immediate velocity
	player.velocity.y = jump_velocity
	
	if player.is_on_floor():
		player.can_double_jump = true
	
	# Quick visual pop effect
	var quick_tween = create_tween()
	quick_tween.set_trans(Tween.TRANS_BACK)
	quick_tween.set_ease(Tween.EASE_OUT)
	quick_tween.tween_property(player, "scale", Vector3(1.05, 0.95, 1.05), 0.05)
	quick_tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func physics_update(delta: float):
	# Apply slightly reduced gravity for better arc
	player.velocity += player.get_gravity() * delta * quick_jump_gravity_multiplier
	
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
		return

	# Simple air control - maintains momentum from ground movement
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 8.0)  # Maintain running speed
		var target_velocity = direction * air_speed
		
		# Original air control factor for responsive but not overpowered movement
		var air_control_factor = 0.7  # Good balance of control and momentum
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Quick rotation for responsive feel
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 12.0  # Fast rotation for snappy feel
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Face movement direction when no input
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 6.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()

func exit():
	# Reset scale to normal in case it was modified
	player.scale = Vector3.ONE
