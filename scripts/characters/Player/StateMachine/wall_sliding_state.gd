extends State
class_name WallSlidingState

# Wall sliding configuration
@export var slide_speed: float = -2.0  # Slow downward slide
@export var min_slide_speed: float = -5.0  # Maximum slide speed
@export var slide_friction: float = 0.95  # How much to slow down vertical velocity
@export var wall_check_distance: float = 0.8  # How far to check for walls
@export var input_required: bool = true  # Whether player needs to hold towards wall

# Internal state
var wall_normal: Vector3 = Vector3.ZERO
var is_sliding: bool = false

func enter():
	print("Entered Wall Sliding State")
	
	# Find the wall we're sliding on
	wall_normal = detect_wall()
	
	if wall_normal == Vector3.ZERO:
		print("No wall found, exiting wall slide")
		change_to("FallingState")
		return
	
	is_sliding = true
	
	# Reduce velocity for slide
	player.velocity.y = max(player.velocity.y * slide_friction, slide_speed)
	
	# Face the wall
	var target_rotation = atan2(-wall_normal.x, -wall_normal.z)
	player.rotation.y = target_rotation

func physics_update(delta: float):
	# Check if still against wall
	if not is_against_wall():
		print("Lost wall contact")
		change_to("FallingState")
		return
	
	# Check if player is moving away from wall
	if input_required:
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			var camera_basis = player.get_node("CameraController").transform.basis
			var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			
			# If moving away from wall, stop sliding
			var dot_product = input_direction.dot(-wall_normal)
			if dot_product < 0.3:  # Not holding towards wall
				change_to("FallingState")
				return
	
	# Apply slide speed
	player.velocity.y = max(player.velocity.y + player.get_gravity().y * delta * 0.3, min_slide_speed)
	
	# Clamp to slide speed
	if player.velocity.y < slide_speed:
		player.velocity.y = slide_speed
	
	# Minimal horizontal control while sliding
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Only allow movement along the wall (perpendicular to normal)
		var right_vector = Vector3.UP.cross(wall_normal).normalized()
		var along_wall = direction.dot(right_vector)
		
		player.velocity.x = lerp(player.velocity.x, right_vector.x * along_wall * 3.0, 5.0 * delta)
		player.velocity.z = lerp(player.velocity.z, right_vector.z * along_wall * 3.0, 5.0 * delta)
	
	# Check for jump input
	if Input.is_action_just_pressed("jump"):
		# Wall jump off the wall
		var wall_jump_state = player.state_machine.states.get("walljumpingstate")
		if wall_jump_state:
			wall_jump_state.setup_wall_jump(wall_normal)
			change_to("WallJumpingState")
			return
	
	# Check for landing
	if player.is_on_floor():
		change_to("IdleState")
		return
	
	player.move_and_slide()

func detect_wall() -> Vector3:
	"""Detect which wall we're against"""
	var player_forward = -player.global_transform.basis.z
	var space_state = player.get_world_3d().direct_space_state
	
	# Check multiple directions around the player
	var check_directions = [
		player_forward,
		-player_forward,
		player.global_transform.basis.x,
		-player.global_transform.basis.x
	]
	
	for direction in check_directions:
		var ray_start = player.global_position + Vector3(0, 1.0, 0)
		var ray_end = ray_start + direction * wall_check_distance
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = [player]
		
		var result = space_state.intersect_ray(query)
		if result:
			return result.normal
	
	return Vector3.ZERO

func is_against_wall() -> bool:
	"""Check if still against a wall"""
	return detect_wall() != Vector3.ZERO

func exit():
	print("Exited Wall Sliding State")
	is_sliding = false
	wall_normal = Vector3.ZERO
