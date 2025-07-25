extends State
class_name IdleState

const DECELERATION : float = 100.0
const ROTATION_RESET_SPEED : float = 8.0

# Store the last movement direction to preserve facing when stopping
var last_facing_direction: float = 0.0
var should_reset_rotation: bool = false

func enter():
	print("Entered Idle State")
	check_if_rotation_reset_needed()

func physics_update(delta: float):
	# Only reset rotation if we are tilted
	if should_reset_rotation:
		reset_player_rotation(delta)
	
	if not player.is_on_floor():
		change_to("FallingState") 
		
	if Input.is_action_just_pressed("jump"):
		change_to("JumpingState")
		
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		if Input.is_action_pressed("run"):
			change_to("RunningState")
		else:
			change_to("WalkingState")
		return
	
	player.velocity.x = move_toward(player.velocity.x, 0, DECELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, DECELERATION * delta)
	
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
