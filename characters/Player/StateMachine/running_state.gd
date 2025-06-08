extends State
class_name RunningState

const SPEED : float = 15.0

func enter():
	print("Entered Running State")

func get_speed():
	return SPEED

func physics_update(delta: float):
	# Handle gravity
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Check for jump
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
		return
	
	# Get movement input
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# If no input, go to idle
	if input_dir.length() < 0.1:
		change_to("IdleState")
		return
	
	# If not holding run button, go back to walking
	if not Input.is_action_pressed("run"):
		change_to("WalkingState")
		return
	
	# Move based on camera direction
	var camera_basis = player.get_node("CameraController").transform.basis
	var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	
	player.move_and_slide()
