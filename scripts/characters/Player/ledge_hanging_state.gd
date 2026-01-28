extends State
class_name LedgeHangingState

# Ledge hang configuration
@export var shimmy_speed: float = 3.0
@export var climb_up_duration: float = 0.5
@export var hang_offset: float = 0.8  # Distance from wall when hanging
@export var ledge_grab_height: float = 1.2  # How high above player center to check for ledge

# Internal state
var ledge_position: Vector3 = Vector3.ZERO
var ledge_normal: Vector3 = Vector3.ZERO
var is_climbing: bool = false
var shimmy_direction: float = 0.0

# Raycast references
var ledge_detection_ray: RayCast3D
var wall_check_ray: RayCast3D
var ledge_top_ray: RayCast3D

func enter():
	print("=== ENTERED LEDGE HANGING STATE ===")
	print("Ledge position: ", ledge_position)
	print("Wall normal: ", ledge_normal)
	
	# Stop all velocity when grabbing ledge
	player.velocity = Vector3.ZERO
	
	# Disable gravity while hanging
	if player.has_method("get") and player.get("gravity") != null:
		player.gravity = 0.0
	
	# Position player at the ledge
	position_at_ledge()
	
	# Visual feedback - slight squash
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.9, 1.1, 0.9), 0.1)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func position_at_ledge():
	"""Position the player at the correct hanging position"""
	if ledge_position == Vector3.ZERO or ledge_normal == Vector3.ZERO:
		print("Invalid ledge data, exiting ledge hang")
		exit_ledge_hang()
		return
	
	# Calculate hanging position (slightly away from wall, below ledge)
	var hang_pos = ledge_position - ledge_normal * hang_offset
	hang_pos.y = ledge_position.y - player.collision_shape.shape.height * 0.7
	
	player.global_position = hang_pos
	
	# Rotate player to face the wall
	var target_rotation = atan2(-ledge_normal.x, -ledge_normal.z)
	player.rotation.y = target_rotation

func physics_update(delta: float):
	if is_climbing:
		return
	
	# Check if still near ledge
	if not is_valid_ledge_position():
		print("Lost ledge contact")
		exit_ledge_hang()
		return
	
	# Handle input
	handle_ledge_input(delta)
	
	# Keep player stationary while hanging
	player.velocity = Vector3.ZERO
	player.move_and_slide()

func handle_ledge_input(delta: float):
	"""Handle player input while hanging on ledge"""
	# Check for climb up
	if Input.is_action_just_pressed("jump"):
		climb_up_ledge()
		return
	
	# Check for drop down
	if Input.is_action_just_pressed("crouch") or Input.is_action_pressed("back"):
		drop_from_ledge()
		return
	
	# Handle shimmying left/right
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if abs(input_dir.x) > 0.1:
		shimmy_along_ledge(input_dir.x, delta)
	else:
		shimmy_direction = 0.0

func shimmy_along_ledge(direction: float, delta: float):
	"""Move the player along the ledge horizontally"""
	# Calculate shimmy direction (perpendicular to wall normal)
	var right_vector = Vector3.UP.cross(ledge_normal).normalized()
	var shimmy_velocity = right_vector * direction * shimmy_speed
	
	# Store intended shimmy direction for animation
	shimmy_direction = direction
	
	# Calculate new position
	var new_position = player.global_position + shimmy_velocity * delta
	
	# Check if new position is still valid (still has ledge to grab)
	if can_shimmy_to_position(new_position):
		player.global_position = new_position
		
		# Update ledge position as we shimmy
		update_ledge_position()
	else:
		# Hit an obstacle or end of ledge
		shimmy_direction = 0.0

func can_shimmy_to_position(new_pos: Vector3) -> bool:
	"""Check if player can shimmy to the new position"""
	# Check if there's still a wall at the new position
	var wall_check_start = new_pos + Vector3(0, 0.5, 0)
	var wall_check_end = wall_check_start + ledge_normal * -1.5
	
	var space_state = player.get_world_3d().direct_space_state
	var wall_query = PhysicsRayQueryParameters3D.create(wall_check_start, wall_check_end)
	wall_query.collision_mask = 1
	wall_query.exclude = [player]
	
	var wall_result = space_state.intersect_ray(wall_query)
	if not wall_result:
		return false
	
	# Check if there's still a ledge at the new position
	var ledge_check_start = new_pos + Vector3(0, ledge_grab_height, 0) + ledge_normal * -0.3
	var ledge_check_end = ledge_check_start + Vector3(0, 0.5, 0)
	
	var ledge_query = PhysicsRayQueryParameters3D.create(ledge_check_start, ledge_check_end)
	ledge_query.collision_mask = 1
	ledge_query.exclude = [player]
	
	var ledge_result = space_state.intersect_ray(ledge_query)
	return ledge_result.size() > 0

func update_ledge_position():
	"""Update the ledge position as player shimmies"""
	var check_start = player.global_position + Vector3(0, ledge_grab_height, 0) + ledge_normal * -0.3
	var check_end = check_start + Vector3(0, 0.5, 0)
	
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(check_start, check_end)
	query.collision_mask = 1
	query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	if result:
		ledge_position = result.position

func climb_up_ledge():
	"""Climb up onto the ledge"""
	if is_climbing:
		return
	
	is_climbing = true
	print("Climbing up ledge!")
	
	# Calculate target position on top of ledge
	var climb_target = ledge_position + Vector3(0, 0.1, 0) + ledge_normal * -0.8
	
	# Create climb animation
	var tween = create_tween()
	tween.set_parallel(false)
	
	# First, move up and forward
	tween.tween_property(player, "global_position", climb_target, climb_up_duration)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	
	# Add some scale animation for polish
	var scale_tween = create_tween()
	scale_tween.set_parallel(true)
	scale_tween.tween_property(player, "scale", Vector3(1.1, 0.9, 1.1), climb_up_duration * 0.3)
	scale_tween.tween_property(player, "scale", Vector3.ONE, climb_up_duration * 0.7).set_delay(climb_up_duration * 0.3)
	
	# Wait for climb to complete
	await tween.finished
	
	# Transition to idle/walking state
	change_to("IdleState")

func drop_from_ledge():
	"""Drop down from the ledge"""
	print("Dropping from ledge")
	
	# Apply small backward velocity
	player.velocity = ledge_normal * 3.0
	player.velocity.y = -2.0
	
	# Transition to falling state
	change_to("FallingState")

func is_valid_ledge_position() -> bool:
	"""Check if player is still in a valid position to hang"""
	# Check if there's still a wall in front
	var wall_check_start = player.global_position + Vector3(0, 0.5, 0)
	var wall_check_end = wall_check_start + ledge_normal * -1.5
	
	var space_state = player.get_world_3d().direct_space_state
	var wall_query = PhysicsRayQueryParameters3D.create(wall_check_start, wall_check_end)
	wall_query.collision_mask = 1
	wall_query.exclude = [player]
	
	var wall_result = space_state.intersect_ray(wall_query)
	if not wall_result:
		return false
	
	# Check if there's still a ledge above
	var ledge_check_start = player.global_position + Vector3(0, ledge_grab_height, 0) + ledge_normal * -0.3
	var ledge_check_end = ledge_check_start + Vector3(0, 0.5, 0)
	
	var ledge_query = PhysicsRayQueryParameters3D.create(ledge_check_start, ledge_check_end)
	ledge_query.collision_mask = 1
	ledge_query.exclude = [player]
	
	var ledge_result = space_state.intersect_ray(ledge_query)
	return ledge_result.size() > 0

func exit_ledge_hang():
	"""Exit ledge hanging state"""
	# Restore normal scale
	player.scale = Vector3.ONE
	
	# Transition to falling
	change_to("FallingState")

func setup_ledge_hang(ledge_pos: Vector3, wall_normal: Vector3):
	"""Setup the ledge hang with position and normal data"""
	ledge_position = ledge_pos
	ledge_normal = wall_normal
	print("Ledge hang setup - Pos: ", ledge_position, " Normal: ", ledge_normal)

func exit():
	print("=== EXITED LEDGE HANGING STATE ===")
	is_climbing = false
	player.scale = Vector3.ONE
	
	# Restore gravity
	if player.has_method("get") and player.get("gravity_default") != null:
		player.gravity = player.gravity_default
