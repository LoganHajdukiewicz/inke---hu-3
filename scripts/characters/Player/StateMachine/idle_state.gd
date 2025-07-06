extends State
class_name IdleState

const DECELERATION : float = 100.0
const ROTATION_RESET_SPEED : float = 8.0

# Store the last movement direction to preserve facing when stopping
var last_facing_direction: float = 0.0
var should_reset_rotation: bool = false

func enter():
	print("Entered Idle State")
	# Check if we need to reset rotation based on the player's current tilt
	check_if_rotation_reset_needed()

func physics_update(delta: float):
	# Only reset rotation if we need to (e.g., after rail grinding)
	if should_reset_rotation:
		reset_player_rotation(delta)
	
	# Handle gravity
	if not player.is_on_floor():
		change_to("FallingState") 
		
	# Check for jump
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
	
	# Check for movement input FIRST
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		if Input.is_action_pressed("run"):
			change_to("RunningState")
		else:
			change_to("WalkingState")
		return
	
	# Apply deceleration
	player.velocity.x = move_toward(player.velocity.x, 0, DECELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, DECELERATION * delta)
	
	player.move_and_slide()

func reset_player_rotation(delta: float):
	# Only reset the tilt (X and Z rotation), preserve the Y rotation (facing direction)
	var current_transform = player.transform
	var current_basis = current_transform.basis
	
	# Extract the current Y rotation (yaw)
	var current_y_rotation = player.rotation.y
	
	# Create target rotation with only Y rotation preserved
	var target_basis = Basis()
	target_basis = target_basis.rotated(Vector3.UP, current_y_rotation)
	
	# Check if we actually need to reset (if there's significant tilt)
	var up_dot = current_basis.y.dot(Vector3.UP)
	if up_dot == 1:  # If we're already mostly upright, don't reset
		should_reset_rotation = false
		return
	
	# Smoothly interpolate to upright position
	player.transform.basis = current_basis.slerp(target_basis, ROTATION_RESET_SPEED * delta)
	
	# Stop resetting when we're close enough to upright
	if player.transform.basis.y.dot(Vector3.UP) == 1:
		should_reset_rotation = false

# Call this function when transitioning FROM rail grinding or other tilting states
func enable_rotation_reset():
	should_reset_rotation = true


func check_if_rotation_reset_needed():
	var up_dot = player.transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.99:  # If significantly tilted from upright
		should_reset_rotation = true
		print("Player is tilted, enabling rotation reset. Up dot: ", up_dot)
	else:
		should_reset_rotation = false
