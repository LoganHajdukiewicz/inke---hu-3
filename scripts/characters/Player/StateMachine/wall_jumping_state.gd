extends State
class_name WallJumpingState

@export var wall_jump_velocity: float = 5.0
@export var wall_jump_upward_boost: float = 2.0

var wall_jump_horizontal_force: float = 12.0
var wall_direction: Vector3 = Vector3.ZERO
var wall_jump_timer: float = 0.0

# === NEW: Momentum Lock System ===
# This is the key fix - it prevents player input from canceling wall jump momentum
var momentum_lock_duration: float = 0.25  # Lock full control for this long
var momentum_fade_duration: float = 0.15  # Gradually give back control over this time
var total_lock_time: float = 0.4  # Total time before full control returns

func enter():
	print("Entered Wall Jump State")
	
	# Cancel momentum going into the wall first
	if wall_direction.length() > 0:
		var velocity_into_wall = player.velocity.dot(-wall_direction)
		if velocity_into_wall > 0:
			player.velocity -= wall_direction * velocity_into_wall
	
	# Apply wall jump velocity with boost
	player.velocity.y = wall_jump_velocity + wall_jump_upward_boost
	
	# Apply horizontal force away from the wall
	if wall_direction.length() > 0:
		var horizontal_force = wall_direction.normalized() * wall_jump_horizontal_force
		player.velocity.x = horizontal_force.x
		player.velocity.z = horizontal_force.z
		
		# Rotate player to face away from wall
		var target_rotation = atan2(-wall_direction.x, -wall_direction.z)
		player.rotation.y = target_rotation
	
	# Reset wall jump timer
	wall_jump_timer = 0.0
	
	# Clear wall jump cooldown to allow immediate chaining
	player.wall_jump_cooldown = 0.0

func physics_update(delta: float):
	wall_jump_timer += delta
	
	# Apply gravity
	player.velocity += player.get_gravity() * delta
	
	# Check for wall jump input first (highest priority)
	if Input.is_action_just_pressed("jump") and player.can_perform_wall_jump():
		var wall_normal = player.get_wall_jump_direction()
		if wall_normal.length() > 0:
			# Check if this is a different wall
			var wall_angle_difference = wall_direction.angle_to(wall_normal)
			if wall_angle_difference > 0.5:  # Different wall
				
				# Cancel momentum going into the new wall
				var velocity_into_wall = player.velocity.dot(-wall_normal)
				if velocity_into_wall > 0:
					player.velocity -= wall_normal * velocity_into_wall
				
				# Set up for new wall jump
				setup_wall_jump(wall_normal)
				wall_jump_timer = 0.0  # Reset timer for new wall jump
				
				# Apply new wall jump forces
				player.velocity.y = wall_jump_velocity + wall_jump_upward_boost
				
				# Apply horizontal force away from the new wall
				var horizontal_force = wall_normal.normalized() * wall_jump_horizontal_force
				player.velocity.x = horizontal_force.x
				player.velocity.z = horizontal_force.z
				
				# Rotate player to face away from new wall
				var target_rotation = atan2(-wall_normal.x, -wall_normal.z)
				player.rotation.y = target_rotation
				
				# Keep wall jump cooldown at 0 for infinite wall jumping
				player.wall_jump_cooldown = 0.0
				return
	
	# === NEW: Progressive Control System ===
	# This is where we fix the player input issue
	handle_wall_jump_movement(delta)
	
	# Check for landing
	if player.is_on_floor():
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Transition to falling state when moving downward
	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()

func handle_wall_jump_movement(delta: float):
	"""
	This function implements the momentum lock system that fixes the wall jump issue.
	
	WHY THIS WORKS:
	- During momentum_lock_duration (0.25s), player input is completely ignored
	- During momentum_fade_duration (0.15s), control gradually returns
	- After total_lock_time (0.4s), player has full control
	
	This prevents player input from immediately canceling the wall jump force,
	allowing the wall jump to feel responsive and natural.
	"""
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Phase 1: Full Momentum Lock
	# During this phase, the wall jump force is preserved completely
	if wall_jump_timer < momentum_lock_duration:
		# Player input is IGNORED - wall jump momentum is fully preserved
		# Only allow rotation to face movement direction if there's momentum
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 3.0  # Slower rotation during lock
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		return
	
	# Phase 2: Gradual Control Return
	# Control smoothly returns to the player over momentum_fade_duration
	elif wall_jump_timer < total_lock_time:
		# Calculate how much control to give back (0.0 to 1.0)
		var fade_progress = (wall_jump_timer - momentum_lock_duration) / momentum_fade_duration
		var control_factor = ease(fade_progress, -2.0)  # Ease out curve for smooth transition
		
		if input_dir.length() > 0.1:
			var camera_basis = player.get_node("CameraController").transform.basis
			var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			
			var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
			var air_speed = max(current_horizontal_speed, 6.0)
			var target_velocity = direction * air_speed
			
			# Gradually increase control as fade_progress increases
			var air_control_factor = 0.1 * control_factor  # Start at 0, end at 0.1
			player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
			player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
			
			# Allow rotation during fade
			if direction.length() > 0.1:
				var target_rotation = atan2(-direction.x, -direction.z)
				var rotation_speed = 5.0 * control_factor  # Rotation also fades in
				player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		else:
			# Face momentum direction when no input
			var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
			if horizontal_velocity.length() > 1.0:
				var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
				var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
				var rotation_speed = 4.0 * control_factor
				player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		return
	
	# Phase 3: Full Control
	# After total_lock_time, player has normal air control
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 6.0)
		var target_velocity = direction * air_speed
		
		# Normal air control
		var air_control_factor = 0.3
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Normal rotation
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 8.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Face movement direction when no input
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 4.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

func setup_wall_jump(wall_normal: Vector3):
	"""Set up the wall jump direction based on the wall normal"""
	wall_direction = wall_normal
