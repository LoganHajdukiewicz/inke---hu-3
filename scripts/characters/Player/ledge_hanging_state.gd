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
	
	# CRITICAL: Stop all movement immediately
	player.velocity = Vector3.ZERO
	player.set_velocity(Vector3.ZERO)
	
	# Disable gravity while hanging
	if player.has_method("set"):
		player.set("gravity", 0.0)
	
	# Position player at the ledge - do this AFTER stopping velocity
	position_at_ledge()
	
	# Visual feedback - slight squash
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.9, 1.1, 0.9), 0.1)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)
	
	print("Player velocity after ledge grab: ", player.velocity)
	print("Player position: ", player.global_position)

func position_at_ledge():
	"""Position the player at the correct hanging position"""
	if ledge_position == Vector3.ZERO or ledge_normal == Vector3.ZERO:
		print("Invalid ledge data, exiting ledge hang")
		exit_ledge_hang()
		return
	
	# Get the CollisionShape3D node to access the capsule height
	var collision_shape = player.get_node("CollisionShape3D")
	var capsule_height = 1.5  # Default height from your scene file
	
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		capsule_height = collision_shape.shape.height
	
	# CRITICAL FIX: Position player BELOW the ledge, hanging from hands
	# Calculate where the player's hands would be (top of capsule)
	var hand_height = capsule_height * 0.4  # Hands are near top of body
	
	# Position player so their "hands" are at the ledge level, body hanging below
	var hang_pos = ledge_position
	hang_pos.y = ledge_position.y - hand_height  # Body hangs down from ledge
	
	# Pull player slightly away from the wall
	hang_pos -= ledge_normal * hang_offset
	
	player.global_position = hang_pos
	
	# Rotate player to face the wall
	var target_rotation = atan2(-ledge_normal.x, -ledge_normal.z)
	player.rotation.y = target_rotation
	
	print("Positioned player at: ", hang_pos)
	print("Ledge is at: ", ledge_position)
	print("Height difference: ", ledge_position.y - hang_pos.y)

func physics_update(delta: float):
	# Debug: Print state info every few frames
	if Engine.get_physics_frames() % 30 == 0:
		print("=== LEDGE HANG PHYSICS UPDATE ===")
		print("Is climbing: ", is_climbing)
		print("Player position: ", player.global_position)
		print("Player velocity: ", player.velocity)
	
	if is_climbing:
		print("Currently climbing, skipping physics update")
		return
	
	# CRITICAL: Force velocity to zero every frame while hanging
	player.velocity = Vector3.ZERO
	
	# Check if still near ledge
	if not is_valid_ledge_position():
		print("Lost ledge contact")
		exit_ledge_hang()
		return
	
	# Handle input
	handle_ledge_input(delta)
	
	# Keep player locked in position - don't call move_and_slide unless shimmying
	# This prevents any physics from pushing the player around

func handle_ledge_input(delta: float):
	"""Handle player input while hanging on ledge"""
	# Check for climb up
	if Input.is_action_just_pressed("jump"):
		print("=== CLIMB UP INITIATED ===")
		climb_up_ledge()
		return
	
	# Check for drop down
	if Input.is_action_just_pressed("crouch") or Input.is_action_pressed("back"):
		print("=== DROP DOWN INITIATED ===")
		drop_from_ledge()
		return
	
	# Handle shimmying left/right
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if abs(input_dir.x) > 0.1:
		print("Shimmying: ", "LEFT" if input_dir.x < 0 else "RIGHT")
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
		# Directly set position for shimmying (more reliable than velocity)
		player.global_position = new_position
		
		# Update ledge position as we shimmy
		update_ledge_position()
	else:
		# Hit an obstacle or end of ledge
		shimmy_direction = 0.0
	
	# Keep velocity at zero
	player.velocity = Vector3.ZERO

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
	print("=== CLIMBING UP LEDGE ===")
	
	# Calculate target position on top of ledge
	# Player should end up standing ON the ledge surface
	var climb_target = ledge_position
	climb_target.y = ledge_position.y + 0.1  # Just slightly above the ledge surface
	
	# Move player forward from the wall so they're standing on the platform
	climb_target -= ledge_normal * 0.8  # Push away from wall
	
	print("Climbing from: ", player.global_position)
	print("Climbing to: ", climb_target)
	
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
	
	print("Climb complete, transitioning to IdleState")
	
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
	
	# Restore gravity using player's property
	if player.has_method("set") and player.has_method("get"):
		var default_gravity = player.get("gravity_default")
		if default_gravity != null:
			player.set("gravity", default_gravity)
			print("Restored gravity to: ", default_gravity)
	
	print("Final velocity on exit: ", player.velocity)
