extends State
class_name SlidingState

const BASE_SLIDE_SPEED: float = 10.0
const SLIDE_FRICTION: float = 0.98  # REDUCED friction (was 2.0) - keeps speed better!
const MIN_SLIDE_SPEED: float = 0.5  # Minimum speed before stopping slide
const ROTATION_SPEED: float = 8.0  # Faster rotation for responsive feel
const SLIDE_CONTROL_STRENGTH: float = 0.5  # More control while sliding
const MIN_ENTRY_SPEED: float = 0.0  # Minimum speed needed to start sliding
const MAX_SLIDE_SPEED: float = 70.0  # Cap for safety (sliding floors can push higher)

# Sliding floor steering
const SLOPE_STEER_STRENGTH: float = 8.0  # How much lateral control on slopes

var slide_velocity: Vector3 = Vector3.ZERO
var slide_direction: Vector3 = Vector3.ZERO
var initial_slide_speed: float = 10.0

func enter():
	print("Entered Sliding State")
	# Get the player's current horizontal velocity
	var current_horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
	var current_speed = current_horizontal_velocity.length()
	
	# Get the player's current movement for initial slide direction
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Determine initial slide direction and speed
	if current_speed > MIN_ENTRY_SPEED:
		# Use current velocity if player is already moving
		slide_direction = current_horizontal_velocity.normalized()
		initial_slide_speed = current_speed
		print("Using current velocity - Speed: ", current_speed)
    elif sliding_floor:
		# On a sliding floor with no velocity — let the slope physics handle it
		slide_direction = Vector3.FORWARD
		initial_slide_speed = 0.0
		print("On sliding floor with no velocity - slope will accelerate")
	elif input_dir.length() > 0.1:
		# Use input direction if player is actively moving
		var camera_basis = player.get_node("CameraController").transform.basis
		slide_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		initial_slide_speed = BASE_SLIDE_SPEED
		print("Using input direction - Speed: ", initial_slide_speed)
	else:
		# Player is not moving - exit sliding immediately
		print("Not moving, exiting slide immediately")
		call_deferred("change_to", "IdleState")
		return
	
	# Set initial slide velocity - PRESERVE MOMENTUM!
	slide_velocity = slide_direction * initial_slide_speed
	
	# CRITICAL: Set player velocity to match (don't reset it!)
	player.velocity.x = slide_velocity.x
	player.velocity.z = slide_velocity.z
	
	print("Sliding! Direction: ", slide_direction, " Initial Speed: ", initial_slide_speed, " Slide Velocity: ", slide_velocity)

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
	
	# Allow grapple hook exit
	if Input.is_action_just_pressed("yoyo") and !player.is_on_floor():
		change_to("GrappleHookState")
		return
	
	# Allow dash exit
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			change_to("DodgeDashState")
			return

    # Check if we're on a SLIDING type floor
	var sliding_floor = _get_sliding_floor()
	if sliding_floor:
		_handle_sliding_floor_physics(sliding_floor, delta)
		return
	
	# NOT on a sliding floor
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Allow jump exit
	if Input.is_action_just_pressed("jump") and not player.ignore_next_jump:
		print("Jump from slide - preserving momentum: ", player.velocity)
		change_to("JumpingState")
		return

	var on_frozen = _is_on_frozen_floor()
	
	# Get player input for limited control while sliding
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Apply steering control
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Blend the slide direction with input direction
		slide_direction = slide_direction.lerp(input_direction, SLIDE_CONTROL_STRENGTH * delta).normalized()
	
	# Get current horizontal speed
	var current_horizontal = Vector2(player.velocity.x, player.velocity.z)
	var current_speed = current_horizontal.length()
	
	# Apply friction (only on frozen floors, not sliding floors!)
	current_speed = max(current_speed - SLIDE_FRICTION * delta, 0.0)
	
	# Safety cap
	if current_speed > MAX_SLIDE_SPEED:
		current_speed = MAX_SLIDE_SPEED
	
	# Stop sliding if speed gets too low AND we're not on frozen floor
	if current_speed < MIN_SLIDE_SPEED and not on_frozen:
		var stop_input_dir = Input.get_vector("left", "right", "forward", "back")
		if stop_input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Transition check for non-frozen floors
	if not on_frozen and current_speed > MIN_SLIDE_SPEED:
		var exit_input_dir = Input.get_vector("left", "right", "forward", "back")
		if exit_input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			pass
	
	# Update slide velocity
	slide_velocity = slide_direction * current_speed
	
	# Rotate player
	if slide_direction.length() > 0.1:
		var target_rotation = atan2(-slide_direction.x, -slide_direction.z)
		var rotation_factor = ROTATION_SPEED * (1.0 + current_speed / MAX_SLIDE_SPEED)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_factor * delta)
	
	# Apply slide movement
	player.velocity.x = slide_velocity.x
	player.velocity.z = slide_velocity.z
	
	player.move_and_slide()


# === SLIDING FLOOR PHYSICS (Mario 64-style) ===
func _handle_sliding_floor_physics(floor_obj: Node, delta: float):
	# Prevent Godot's built-in slope deceleration
	player.floor_stop_on_slope = false
	player.floor_constant_speed = true
	
	# Allow jump
	if Input.is_action_just_pressed("jump") and player.is_on_floor() and not player.ignore_next_jump:
		print("Jump from sliding floor! Momentum: ", player.velocity)
		player.velocity.y = player.jump_velocity
		change_to("JumpingState")
		return
	
	# Get slope info from the floor's transform
	var floor_normal = floor_obj.global_transform.basis.y.normalized()
	var tilt_factor = 1.0 - floor_normal.dot(Vector3.UP)
	if tilt_factor < 0.01:
	# Flat floor — just move, no downhill force
		player.move_and_slide()
		return
	
	# Calculate downhill direction: project gravity onto the slope surface
	var gravity_dir = Vector3.DOWN
	var downhill = (gravity_dir - floor_normal * gravity_dir.dot(floor_normal)).normalized()
	
	# Get current speed along the downhill axis
	var current_downhill_speed = player.velocity.dot(downhill)
	
	# Apply gravity-based acceleration — steeper slopes accelerate faster
	var accel = floor_obj.slide_acceleration * tilt_factor
	var new_speed = current_downhill_speed + accel * delta
	
	# Cap at max speed
	new_speed = min(new_speed, floor_obj.slide_max_speed)
	
	# Block uphill movement — can't overcome gravity on the slope
	if new_speed < 0.0:
		new_speed = 0.0
	
	# Build velocity along the 3D downhill direction (includes Y component for slope)
	var new_velocity = downhill * new_speed
	
	# Allow limited lateral steering perpendicular to the slope
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_world = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Project input onto the plane perpendicular to the downhill direction
		var lateral = (input_world - downhill * input_world.dot(downhill))
\		new_velocity += lateral * SLOPE_STEER_STRENGTH
	
	player.velocity = new_velocity
	
	# Rotate player to face movement direction
	var move_dir = Vector2(player.velocity.x, player.velocity.z)
	if floor_obj.auto_rotate_to_slope and move_dir.length() > 0.5:
		var target_rot = atan2(-player.velocity.x, -player.velocity.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rot, 8.0 * delta)

	player.move_and_slide()
	# If briefly off the floor (small bumps on the slope), pull back down
	
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta

# === HELPER FUNCTIONS ===

func _get_sliding_floor() -> Node:
"""Get the sliding floor object the player is on, or null."""
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position,
		player.global_position + Vector3(0, -1.1, 0)
	)
	query.collision_mask = 1
	query.exclude = [player]
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider and collider.has_method("get") and collider.get("floor_type") != null:
			# FloorType.SLIDING = 7
			if collider.floor_type == 7:
				return collider
			return null

func _is_on_sliding_floor() -> bool:
	"""Check if the player is currently on a SLIDING type floor"""
	return _get_sliding_floor() != null

func _is_on_frozen_floor() -> bool:
	"""Check if the player is currently on a frozen floor"""
	# Cast a ray downward to check what we're standing on
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position,
		player.global_position + Vector3(0, -1.1, 0)
	)
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider and collider.has_method("get") and collider.get("floor_type") != null:
			return collider.floor_type == Floor.FloorType.FROZEN
	
	return false

func get_speed() -> float:
	return slide_velocity.length()

func exit():
	# Restore floor physics properties
	player.floor_stop_on_slope = true
	player.floor_constant_speed = false
	# DON'T clear slide velocity - preserve momentum!
	print("Exited Sliding State - Preserving momentum: ", slide_velocity.length())