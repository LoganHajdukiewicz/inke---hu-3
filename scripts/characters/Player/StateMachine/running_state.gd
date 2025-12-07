extends State
class_name RunningState

const SPEED : float = 15.0
const ROTATION_SPEED : float = 12.0


func enter():
	print("Entered Running State")


func get_speed():
	return SPEED

func update_dash_cooldown(delta: float):
	"""Update the dash cooldown timer in the dodge dash state"""
	var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
	if dodge_dash_state:
		# Continue updating cooldown even when not in dash state
		if not dodge_dash_state.can_dash and dodge_dash_state.cooldown_timer > 0:
			dodge_dash_state.cooldown_timer -= delta
			if dodge_dash_state.cooldown_timer <= 0:
				dodge_dash_state.can_dash = true
				dodge_dash_state.cooldown_timer = 0.0
				print("Dash cooldown completed in ", get_script().get_global_name())

func physics_update(delta: float):
	update_dash_cooldown(delta)
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			change_to("DodgeDashState")

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
	
	# Rotate player to face movement direction
	if direction.length() > 0.1:
		var target_rotation = atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
	
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	
	player.move_and_slide()
