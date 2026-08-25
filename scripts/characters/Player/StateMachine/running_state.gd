extends State
class_name RunningState

# Speed/turn rate are tuned on Inke's Inspector (Ground Movement group)


func enter():
	pass


func get_speed():
	return player.run_speed

func physics_update(delta: float):
	# for Merchant UI 
	if player.controls_disabled:
		return

	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			change_to("DodgeDashState")

	if Input.is_action_just_pressed("yoyo"):
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
	
	# On ice: momentum-based sliding (shared model on the player)
	if player.is_on_ice:
		player.apply_ice_movement(delta, direction, player.run_speed)
	else:
		# Normal movement
		# Rotate player to face movement direction
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, player.run_rotation_speed * delta)
		
		player.velocity.x = direction.x * player.run_speed
		player.velocity.z = direction.z * player.run_speed
	
	player.move_and_slide()
