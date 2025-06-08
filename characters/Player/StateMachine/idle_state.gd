extends State
class_name IdleState

const DECELERATION : float = 100.0

func enter():
	print("Entered Idle State")

func physics_update(delta: float):
	# Handle gravity
	if not player.is_on_floor():
		change_to("FallingState") 
		
	# Check for jump
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
	
	# Check for movement input FIRST
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		# If moving AND running, go to running state
		if Input.is_action_pressed("run"):
			change_to("RunningState")
		else:
			change_to("WalkingState")
		return
	
	# Apply deceleration
	player.velocity.x = move_toward(player.velocity.x, 0, DECELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, DECELERATION * delta)
	
	player.move_and_slide()
