extends State
class_name RunningState

const SPEED : float = 20.0
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

	if Input.is_action_just_pressed("yoyo") and !player.is_on_floor():
		change_to("GrappleHookState")
		return
	# Handle gravity
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Check for jump
	if Input.is_action_just_pressed("jump") and not player.ignore_next_jump:
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
	
	# NEW: Get ice friction multiplier
	var _ice_control = player.get_ice_friction_multiplier()
	
	# NEW: On ice, fast acceleration but limited turning
	if player.is_on_ice:
		var target_velocity = direction * SPEED
		# Fast acceleration: use normal lerp speed for forward movement
		# But use 0.5 control for direction changes (instead of ice_control which is 0.01)
		var current_direction = Vector2(player.velocity.x, player.velocity.z).normalized()
		var target_direction = Vector2(target_velocity.x, target_velocity.z).normalized()
		var direction_similarity = current_direction.dot(target_direction)
		
		# If moving in a similar direction, accelerate quickly
		# If changing direction drastically, use 0.5 control (50% effectiveness)
		var accel_factor = lerp(0.5, 1.0, max(0.0, direction_similarity))
		
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, accel_factor * delta * 10.0)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, accel_factor * delta * 10.0)
		
		# Use 0.5 rotation speed on ice (instead of very slow ice_control)
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * 0.5 * delta)
	else:
		# Normal movement
		# Rotate player to face movement direction
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
		
		player.velocity.x = direction.x * SPEED
		player.velocity.z = direction.z * SPEED
	
	player.move_and_slide()
