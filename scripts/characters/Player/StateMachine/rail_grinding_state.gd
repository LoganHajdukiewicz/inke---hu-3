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
var jump_velocity: float = 10.0 # Controls the upwards movement of jumping off a rail
var grind_exit_speed: float = 15.0 # Controls the horizontal movement of jumping off a rail
var lerp_speed: float = 50.0 # Does NOT control how fast you are going

func enter():
	print("Entered Rail Grinding State")
	
	# Restore double jump and air dash abilities when starting rail grinding
	player.can_double_jump = true
	player.has_double_jumped = false
	player.can_air_dash = true
	player.has_air_dashed = false

func physics_update(delta: float):
	if Input.is_action_just_pressed("yoyo") and !player.is_on_floor():
		change_to("GrappleHookState")
		return
	# Handle the grinding movement and physics
	if rail_grind_node:
		# Smoothly move player to rail position
		player.position = lerp(player.position, rail_grind_node.global_position, delta * lerp_speed)
		
		# Rotate player to align with rail direction
		var target_rotation = rail_grind_node.global_transform.basis.orthonormalized()
		
		# If moving backward, flip the rotation 180 degrees
		if not rail_grind_node.forward:
			target_rotation = target_rotation.rotated(Vector3.UP, PI)
		
		# Smoothly rotate the player to match the rail direction
		player.transform.basis = player.transform.basis.slerp(target_rotation, delta * lerp_speed).orthonormalized()
		
		# Set velocity based on rail movement direction
		var rail_velocity = Vector3.ZERO
		if rail_grind_node.forward:
			rail_velocity = rail_grind_node.transform.basis.z * grind_exit_speed
		else:
			rail_velocity = -rail_grind_node.transform.basis.z * grind_exit_speed
		
		# CRITICAL FIX: Set the ACTUAL velocity so speed effects can detect it
		# The speed effects manager reads player.velocity to determine speed
		player.velocity = rail_velocity
		player.velocity.y = 0  # Keep it horizontal for grinding
		
		# Check for manual jump input for mid-grind jumping
		if Input.is_action_just_pressed("jump"):
			detach_from_rail()
			return
		
		# Check for automatic detachment at rail end
		if rail_grind_node.detach:
			detach_from_rail()
			return
	else:
		change_to("FallingState")
		return
	
	grind_timer(delta)

func grind_timer(delta: float):
	if start_grind_timer and countdown_for_next_grind_time_left > 0:
		countdown_for_next_grind_time_left -= delta
		if countdown_for_next_grind_time_left <= 0:
			countdown_for_next_grind_time_left = countdown_for_next_grind
			grind_timer_complete = true
			start_grind_timer = false

func setup_grinding(grind_ray):
	"""Legacy method for raycast compatibility - converts raycast to node"""
	var grind_rail = grind_ray.get_collider().get_parent()
	
	# Disable gravity while grinding
	player.gravity = 0.0
	
	# Find the nearest rail follower node
	rail_grind_node = find_nearest_rail_follower(player.global_position, grind_rail)
	
	if rail_grind_node:
		setup_rail_node(rail_grind_node)
		return true
	return false

func setup_grinding_with_node(rail_node):
	"""New method that directly accepts a rail follower node"""
	if not rail_node or not is_instance_valid(rail_node):
		return false
	
	# Disable gravity while grinding
	player.gravity = 0.0
	
	rail_grind_node = rail_node
	setup_rail_node(rail_grind_node)
	return true

func setup_rail_node(rail_node):
	"""Common setup for rail node"""
	if not rail_node:
		return
	
	# Set up the rail node
	rail_node.chosen = true
	rail_node.grinding = true
	
	# Determine grinding direction based on player facing
	if not rail_node.direction_selected:
		rail_node.forward = is_facing_same_direction(player, rail_node)
		rail_node.direction_selected = true

func find_nearest_rail_follower(player_position: Vector3, rail_node: Node):
	"""Find the nearest rail follower node from a rail parent"""
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

func disable_rail_detection():
	"""Disable rail detection area temporarily"""
	if player.rail_grind_area:
		player.rail_grind_area.monitoring = false
		player.rail_grind_area.monitorable = false
		
		# Re-enable after a short delay using a timer
		var timer = Timer.new()
		timer.wait_time = 0.3
		timer.one_shot = true
		timer.timeout.connect(enable_rail_detection)
		player.add_child(timer)
		timer.start()

func enable_rail_detection():
	"""Re-enable rail detection area"""
	if player.rail_grind_area:
		player.rail_grind_area.monitoring = true
		player.rail_grind_area.monitorable = true

func exit():
	if rail_grind_node:
		rail_grind_node.chosen = false
		rail_grind_node.detach = false
		rail_grind_node.direction_selected = false
		rail_grind_node.grinding = false
	
	player.gravity = player.gravity_default
	
	grind_timer_complete = true
	start_grind_timer = false
	
	disable_rail_detection()

func detach_from_rail():
	player.velocity.y = jump_velocity
	
	if rail_grind_node:
		var rail_direction = Vector3.ZERO
		if rail_grind_node.forward:
			rail_direction = -rail_grind_node.transform.basis.z
		else:
			rail_direction = rail_grind_node.transform.basis.z
		
		var momentum_velocity = rail_direction * grind_exit_speed
		player.velocity.x = momentum_velocity.x
		player.velocity.z = momentum_velocity.z
	
	start_grind_timer = true
	countdown_for_next_grind_time_left = countdown_for_next_grind
	grind_timer_complete = false
	
	# Always transition to JumpingState when detaching from rail
	change_to("JumpingState")

func get_speed():
	return grind_exit_speed
