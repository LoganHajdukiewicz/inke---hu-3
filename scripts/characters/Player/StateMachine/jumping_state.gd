extends State
class_name JumpingState

@export var jump_velocity : float = 15.0
@export var long_jump_multiplier: float = 1.3  # Multiplier for long jump horizontal speed
var gravity_multiplier : float = 1.0
var jump_time : float = 1.0
var peak_time : float = 0.0  
var horizontal_movement_decel = 0.8  # CHANGED from 0.8 to 0.5 - less momentum preservation
var is_long_jump: bool = false  # NEW: Track if this is a long jump
var used_dash_momentum: bool = false  # NEW: Track if we used stored dash momentum

func enter():
	print("Entered Jumping State")
	
	# NEW: Check if this is a long jump
	is_long_jump = false
	used_dash_momentum = false
	
	if player.has_method("is_long_jump_available") and player.is_long_jump_available():
		is_long_jump = true
		print("=== LONG JUMP ACTIVATED! ===")
		# Consume the long jump
		if player.has_method("enable_long_jump"):
			player.can_long_jump = false
			player.long_jump_timer = 0.0
	
	# Don't override velocity if being launched by a spring
	if not player.is_being_sprung:
		player.velocity.y = jump_velocity
		jump_time = 0.0
		
		# NEW: Check for stored dash momentum
		var stored_momentum = Vector3.ZERO
		if player.has_method("get") and player.get("stored_dash_momentum") != null:
			stored_momentum = player.get("stored_dash_momentum")
			print("=== DASH JUMP DETECTED ===")
			print("Stored dash momentum: ", stored_momentum.length())
		
		# Normal momentum reduction first
		print("=== NORMAL JUMP ===")
		print("Before decel: ", player.velocity)
		
		player.velocity.x *= horizontal_movement_decel
		player.velocity.z *= horizontal_movement_decel
		
		print("After decel: ", player.velocity)
		
		# If we have stored dash momentum, apply a 1.2x boost
		if stored_momentum.length() > 0:
			# Calculate the direction from the stored momentum
			var dash_direction = stored_momentum.normalized()
			
			# Get the current horizontal speed (after deceleration)
			var current_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
			
			# Apply a 1.4x boost to the current speed in the dash direction
			var boosted_speed = current_horizontal * 0.5
			
			# Apply the boosted speed in the dash direction
			player.velocity.x = dash_direction.x * boosted_speed
			player.velocity.z = dash_direction.z * boosted_speed
			used_dash_momentum = true
			
			# Clear the stored momentum
			if player.has_method("set"):
				player.set("stored_dash_momentum", Vector3.ZERO)
			
			print("Applied dash jump 1.4x boost: ", Vector2(player.velocity.x, player.velocity.z).length())
		
		# NEW: Apply long jump boost if active (can stack with dash boost)
		if is_long_jump:
			print("Applying long jump multiplier: ", long_jump_multiplier)
			player.velocity.x *= long_jump_multiplier
			player.velocity.z *= long_jump_multiplier
			create_long_jump_effect()
		
		print("Final velocity after all boosts: ", player.velocity)
		
		# SAFETY: Cap maximum horizontal velocity on jump entry
		var horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		
		# Higher cap for dash jumps and long jumps
		var max_jump_horizontal = 50.0  # Base cap
		if used_dash_momentum:
			max_jump_horizontal = 60.0  # Cap for dash jumps
		elif is_long_jump:
			max_jump_horizontal = 55.0  # Cap for long jumps
		
		if horizontal_speed > max_jump_horizontal:
			print("!!! Jump velocity cap triggered: ", horizontal_speed, " -> ", max_jump_horizontal)
			var normalized = Vector2(player.velocity.x, player.velocity.z).normalized()
			player.velocity.x = normalized.x * max_jump_horizontal
			player.velocity.z = normalized.y * max_jump_horizontal
			print("After cap: ", player.velocity)
	else:
		# Spring is controlling the jump, just reset timer
		jump_time = 0.0
	
	if player.is_on_floor():
		player.can_double_jump = true

func create_long_jump_effect():
	"""Create a visual effect to indicate long jump"""
	# Create a quick flash/burst effect
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Quick scale pulse
	tween.tween_property(player, "scale", Vector3(1.2, 0.8, 1.2), 0.1)
	tween.tween_property(player, "scale", Vector3.ONE, 0.2).set_delay(0.1)
	
	# You could also add particle effects here if you have a particle system

func update_dash_cooldown(delta: float):
	"""Update the dash cooldown timer in the dodge dash state"""
	var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
	if dodge_dash_state:
		# Continue updating cooldown even when not in dash state
		if not dodge_dash_state.can_dash and dodge_dash_state.cooldown_timer > 0:
			dodge_dash_state.cooldown_timer -= delta
			if dodge_dash_state.cooldown_timer <= 0:
				dodge_dash_state.can_dash = true
				dodge_dash_state.cooldown_timer = 0.0
				print("Dash cooldown completed in ", get_script().get_global_name())

func physics_update(delta: float):
	update_dash_cooldown(delta)
	jump_time += delta

	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			print("=== TRANSITIONING TO AIR DASH ===")
			print("Jump state velocity before transition: ", player.velocity)
			change_to("DodgeDashState")
			return

	if Input.is_action_just_pressed("yoyo"):
		change_to("GrappleHookState")
		return

	# Jak and Daxter gravity curve - quick up, brief pause, quick down
	if jump_time < peak_time:
		gravity_multiplier = 0.15
	elif jump_time < peak_time + 0.0001:
		gravity_multiplier = 0.1
	else:
		gravity_multiplier = 3
	
	player.velocity += player.get_gravity() * delta * gravity_multiplier
	
	# Don't allow jump input if being sprung (spring floor handles this)
	if not player.is_being_sprung:
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
		
		# Check for double jump input
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
		
		# Less air control for dash jumps to preserve momentum
		var air_control_factor = 0.5  # Base control
		if used_dash_momentum:
			air_control_factor = 0.2  # Much less control for dash jumps
		
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Slower rotation - more deliberate movement
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 8.0  # Much slower rotation
			if used_dash_momentum:
				rotation_speed = 4.0  # Even slower for dash jumps
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
		if used_dash_momentum:
			air_resistance = 0.003  # Almost no resistance for dash jumps
		player.velocity.x *= (1.0 - air_resistance)
		player.velocity.z *= (1.0 - air_resistance)

	# Transition to falling when velocity goes negative
	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()

func exit():
	print("=== JUMP EXIT ===")
	print("Final velocity: ", player.velocity)
	print("Was long jump: ", is_long_jump)
	print("Used dash momentum: ", used_dash_momentum)
	
	# Reset flags
	is_long_jump = false
	used_dash_momentum = false
	
	# Reset scale to normal
	player.scale = Vector3.ONE
