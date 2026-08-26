extends State
class_name BalanceBeamState

## Walking a balance beam:
##  - camera swings around BEHIND the player automatically
##  - movement is slowed to 80% of walk speed (beam_speed_multiplier on Inke)
##  - trying to RUN makes you lose your footing and fall off the side
##  - a subtle wobble sells the balancing act

@export var wobble_amount: float = 0.06     # Roll wobble while balancing
@export var wobble_speed: float = 5.0
@export var rotation_speed: float = 6.0

var wobble_time: float = 0.0

func enter():
	wobble_time = 0.0

func get_speed() -> float:
	return player.walk_speed * player.beam_speed_multiplier

func physics_update(delta: float):
	if player.controls_disabled:
		return
	
	# Off the beam? Return to normal ground movement
	if not player.is_on_balance_beam:
		player.rotation.z = 0.0
		var check_input = Input.get_vector("left", "right", "forward", "back")
		if not player.is_on_floor():
			change_to("FallingState")
		elif check_input.length() > 0.1:
			change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Gravity / airborne check
	if not player.is_on_floor():
		player.rotation.z = 0.0
		player.velocity += player.get_gravity() * delta
		change_to("FallingState")
		return
	
	# Jumping off the beam is allowed (careful hops)
	if Input.is_action_just_pressed("jump") and not player.ignore_next_jump:
		player.rotation.z = 0.0
		change_to("JumpingState")
		return
	
	# RUNNING on a beam = losing your footing!
	if Input.is_action_pressed("run"):
		player.rotation.z = 0.0
		player.trip_off_beam()
		change_to("FallingState")
		return
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	var beam_speed = player.walk_speed * player.beam_speed_multiplier
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var target_rotation = atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		
		player.velocity.x = direction.x * beam_speed
		player.velocity.z = direction.z * beam_speed
		
		# Balancing wobble - only while moving
		wobble_time += delta
		player.rotation.z = sin(wobble_time * wobble_speed) * wobble_amount
	else:
		# Careful stop
		player.velocity.x = move_toward(player.velocity.x, 0, player.idle_deceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, player.idle_deceleration * delta)
		player.rotation.z = lerp_angle(player.rotation.z, 0.0, 8.0 * delta)
	
	player.move_and_slide()

func exit():
	player.rotation.z = 0.0
