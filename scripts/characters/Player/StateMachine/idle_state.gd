extends State
class_name IdleState

const DECELERATION : float = 100.0

# Store the last movement direction to preserve facing when stopping
var last_facing_direction: float = 0.0


func enter():
	pass
	

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
	
	if not player.is_on_floor():
		change_to("FallingState") 
		
	if Input.is_action_just_pressed("jump") and not player.ignore_next_jump:
		change_to("JumpingState") 
		
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		if Input.is_action_pressed("run"):
			change_to("RunningState")
		else:
			change_to("WalkingState")
		return
	
	# On ice: keep gliding with the shared momentum model (no input = slow glide)
	if player.is_on_ice:
		player.apply_ice_movement(delta, Vector3.ZERO, 0.0)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, DECELERATION * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, DECELERATION * delta)
	
	player.move_and_slide()
