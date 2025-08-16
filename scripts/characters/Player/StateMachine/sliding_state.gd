extends State
class_name SlidingState

const BASE_SLIDE_SPEED: float = 8.0
const SLIDE_FRICTION: float = 0.5  # How quickly sliding slows down
const MIN_SLIDE_SPEED: float = 0.0  # Minimum speed before stopping slide
const ROTATION_SPEED: float = 5.0  # Slower rotation while sliding
const SLIDE_CONTROL_STRENGTH: float = 0.3  # How much control player has while sliding

var slide_velocity: Vector3 = Vector3.ZERO
var slide_direction: Vector3 = Vector3.ZERO
var initial_slide_speed: float = 20.0

func enter():
	print("Entered Sliding State")
	
	# Get the player's current movement for initial slide direction
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		# Use input direction if player is actively moving
		var camera_basis = player.get_node("CameraController").transform.basis
		slide_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		initial_slide_speed = BASE_SLIDE_SPEED
	else:
		# Use current velocity direction if no input
		var current_horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
		if current_horizontal_velocity.length() > 0.1:
			slide_direction = current_horizontal_velocity.normalized()
			initial_slide_speed = max(current_horizontal_velocity.length(), BASE_SLIDE_SPEED * 0.5)
		else:
			# Default forward direction if no movement
			slide_direction = -player.transform.basis.z
			initial_slide_speed = BASE_SLIDE_SPEED * 0.3
	
	# Set initial slide velocity
	slide_velocity = slide_direction * initial_slide_speed

func physics_update(delta: float):
	# Handle gravity
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Check if we're still on a frozen floor
	if not _is_on_frozen_floor():
		# Not on frozen floor anymore, transition to appropriate state
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Check for jump (can still jump while sliding)
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
		return
	
	# Get player input for limited control while sliding
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Apply limited steering control
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Blend the slide direction with input direction
		slide_direction = slide_direction.lerp(input_direction, SLIDE_CONTROL_STRENGTH * delta).normalized()
	
	# Apply friction to slide velocity
	var current_speed = slide_velocity.length()
	current_speed = max(current_speed - SLIDE_FRICTION * delta, 0.0)
	
	# Stop sliding if speed gets too low
	if current_speed < MIN_SLIDE_SPEED:
		var input_dir_check = Input.get_vector("left", "right", "forward", "back")
		if input_dir_check.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Update slide velocity
	slide_velocity = slide_direction * current_speed
	
	# Rotate player to face slide direction (slower than normal movement)
	if slide_direction.length() > 0.1:
		var target_rotation = atan2(-slide_direction.x, -slide_direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
	
	# Apply slide movement
	player.velocity.x = slide_velocity.x
	player.velocity.z = slide_velocity.z
	
	player.move_and_slide()

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
	# Clear slide velocity when exiting
	slide_velocity = Vector3.ZERO
