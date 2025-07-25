extends State
class_name WalkingState

const SPEED : float = 10.0
const ROTATION_SPEED : float = 10.0  

var should_reset_rotation: bool = false
const ROTATION_RESET_SPEED : float = 8.0

func enter():
	print("Entered Walking State")
	check_if_rotation_reset_needed()

func get_speed():
	return SPEED

func physics_update(delta: float):
	if should_reset_rotation:
		reset_player_rotation(delta)

	# Handle gravity
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Check for jump
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
		return

	# Check for running
	if Input.is_action_pressed("run"):
		change_to("RunningState")
		return
	
	# Get movement input
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# If no input, go to idle
	if input_dir.length() < 0.1:
		change_to("IdleState")
		return
	
	# Move based on camera direction
	var camera_basis = player.get_node("CameraController").transform.basis
	var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Rotate player to face movement direction
	if direction.length() > 0.1:
		var target_rotation = atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
	
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	
	player.move_and_slide()
	
func reset_player_rotation(delta: float):
	var current_transform = player.transform
	var current_basis = current_transform.basis
	
	var current_y_rotation = player.rotation.y
	
	var target_basis = Basis()
	target_basis = target_basis.rotated(Vector3.UP, current_y_rotation)
	
	var up_dot = current_basis.y.dot(Vector3.UP)
	if up_dot == 1:
		should_reset_rotation = false
		return
	
	player.transform.basis = current_basis.slerp(target_basis, ROTATION_RESET_SPEED * delta)
	
	if player.transform.basis.y.dot(Vector3.UP) == 1:
		should_reset_rotation = false

func enable_rotation_reset():
	should_reset_rotation = true

func check_if_rotation_reset_needed():
	var up_dot = player.transform.basis.y.dot(Vector3.UP)
	if up_dot < 1:
		should_reset_rotation = true
	else:
		should_reset_rotation = false
