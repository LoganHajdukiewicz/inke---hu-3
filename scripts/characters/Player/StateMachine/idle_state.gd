extends State
class_name IdleState

const DECELERATION : float = 100.0

# Store the last movement direction to preserve facing when stopping
var last_facing_direction: float = 0.0


func enter():
	print("Entered Idle State")
	
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
	
	# NEW: Slower deceleration on ice
	var decel = DECELERATION
	if player.is_on_ice:
		decel *= player.get_ice_friction_multiplier()  # Much slower decel on ice
	
	player.velocity.x = move_toward(player.velocity.x, 0, decel * delta)
	player.velocity.z = move_toward(player.velocity.z, 0, decel * delta)
	
	player.move_and_slide()
