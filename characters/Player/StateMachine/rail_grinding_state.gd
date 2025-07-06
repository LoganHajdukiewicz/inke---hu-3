extends State
class_name RailGrindingState

# Rail grinding variables
var rail_grind_node = null
var countdown_for_next_grind: float = 1.0
var countdown_for_next_grind_time_left: float = 1.0
var grind_timer_complete: bool = true
var start_grind_timer: bool = false
var detached_from_rail: bool = false

# Configuration
var jump_velocity: float = 5.0
var lerp_speed: float = 40.0
var grind_speed: float = 10.0

func enter():
	print("Entered Rail Grinding State")



func physics_update(delta: float):
	

	
	# Handle the grinding movement and physics
	if rail_grind_node:
		# Smoothly move player to rail position
		player.position = lerp(player.position, rail_grind_node.global_position, delta * lerp_speed)
		
		# CHANGE #1: Rotate player to align with rail direction
		var target_rotation = rail_grind_node.global_transform.basis.orthonormalized()
		if not rail_grind_node.forward:
			# If moving backward, flip the rotation 180 degrees
			target_rotation = target_rotation.rotated(Vector3.UP, PI)
		
		# Smoothly rotate the player to match the rail direction
		player.transform.basis = player.transform.basis.slerp(target_rotation, delta * lerp_speed).orthonormalized()
		
		# Set horizontal velocity based on rail movement direction
		var rail_velocity = Vector3.ZERO
		if rail_grind_node.forward:
			rail_velocity = rail_grind_node.transform.basis.z * grind_speed
		else:
			rail_velocity = -rail_grind_node.transform.basis.z * grind_speed
		
		player.velocity.x = rail_velocity.x
		player.velocity.z = rail_velocity.z
		player.velocity.y = 0  # No vertical movement while grinding
		
		# CHANGE #2: Check for manual jump input for mid-grind jumping
		if Input.is_action_just_pressed("jump"):
			detach_from_rail()
			return
		
		# Check for automatic detachment at rail end
		if rail_grind_node.detach:
			detach_from_rail()
			return
	else:
		# If we lost the rail node, fall
		change_to("FallingState")
		return
	
	# Update the grind timer
	grind_timer(delta)
	


func grind_timer(delta: float):
	if start_grind_timer and countdown_for_next_grind_time_left > 0:
		countdown_for_next_grind_time_left -= delta
		if countdown_for_next_grind_time_left <= 0:
			countdown_for_next_grind_time_left = countdown_for_next_grind
			grind_timer_complete = true
			start_grind_timer = false

func setup_grinding(grind_ray):
	"""Called when starting to grind - sets up the rail grinding state"""
	var grind_rail = grind_ray.get_collider().get_parent()
	
	# Disable gravity while grinding
	player.gravity = 0.0
	
	# Find the nearest rail follower node
	rail_grind_node = find_nearest_rail_follower(player.global_position, grind_rail)
	
	if rail_grind_node:
		# Set up the rail node
		rail_grind_node.chosen = true
		rail_grind_node.grinding = true
		
		# Determine grinding direction based on player facing
		if not rail_grind_node.direction_selected:
			rail_grind_node.forward = is_facing_same_direction(player, rail_grind_node)
			rail_grind_node.direction_selected = true
		
		print("Started grinding on rail, forward: ", rail_grind_node.forward)
		return true
	
	return false

func find_nearest_rail_follower(player_position: Vector3, rail_node: Node):
	var nearest_node = null
	var min_distance = INF
	
	for node in rail_node.get_children():
		if node.is_in_group("rail_follower"):
			var distance = player_position.distance_to(node.global_position)
			if distance < min_distance:
				min_distance = distance
				nearest_node = node
	
	return nearest_node

func is_facing_same_direction(player_node: CharacterBody3D, path_follow: PathFollow3D) -> bool:
	var player_forward = -player_node.global_transform.basis.z.normalized()
	var path_follow_forward = -path_follow.global_transform.basis.z.normalized()
	var dot_product = player_forward.dot(path_follow_forward)
	const THRESHOLD = 0.5
	return dot_product > THRESHOLD


func disable_grind_raycasts():
	if player.grindrays:
		for grind_ray in player.grindrays.get_children():
			if grind_ray is RayCast3D:
				grind_ray.enabled = false
		
		# Re-enable them after a short delay using a timer
		var timer = Timer.new()
		timer.wait_time = 0.3
		timer.one_shot = true
		timer.timeout.connect(enable_grind_raycasts)
		player.add_child(timer)
		timer.start()
# Add this to your rail_grinding_state.gd exit() function:

func exit():
	print("Exited Rail Grinding State")
	# Clean up when leaving the grinding state
	if rail_grind_node:
		rail_grind_node.chosen = false
		rail_grind_node.detach = false
		rail_grind_node.direction_selected = false
		rail_grind_node.grinding = false
	
	# Restore gravity
	player.gravity = player.gravity_default
	
	# Reset grind timer
	grind_timer_complete = true
	start_grind_timer = false
	
	# CHANGE #3: Disable grind raycasts to prevent immediate re-grinding
	disable_grind_raycasts()

# Also update the detach_from_rail function to handle the state transition better:
func detach_from_rail():
	print("Detaching from rail")
	
	# Give the player upward velocity
	player.velocity.y = jump_velocity
	
	# FIXED: Properly apply rail momentum to player velocity
	if rail_grind_node:
		var rail_direction = Vector3.ZERO
		if rail_grind_node.forward:
			rail_direction = -rail_grind_node.transform.basis.z  # Negative Z is forward in Godot
		else:
			rail_direction = rail_grind_node.transform.basis.z   # Positive Z is backward
		
		# Apply the full rail momentum in the correct direction
		var momentum_velocity = rail_direction * grind_speed
		player.velocity.x = momentum_velocity.x
		player.velocity.z = momentum_velocity.z
		
		print("Detaching with momentum: ", momentum_velocity)
	
	# Start the grind cooldown timer
	start_grind_timer = true
	countdown_for_next_grind_time_left = countdown_for_next_grind
	grind_timer_complete = false
	
	# CHANGE #2: Always transition to JumpingState when detaching from rail
	change_to("JumpingState")

func enable_grind_raycasts():
	if player.grindrays:
		for grind_ray in player.grindrays.get_children():
			if grind_ray is RayCast3D:
				grind_ray.enabled = true

func get_speed():
	return grind_speed
	
	
