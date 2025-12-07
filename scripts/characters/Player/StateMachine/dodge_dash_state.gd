extends State
class_name DodgeDashState

# Dodge dash configuration
@export var dash_speed: float = 100.0
@export var dash_duration: float = 0.3
@export var dash_cooldown: float = 0.1
@export var iframe_duration: float = 0.4  # Invincibility frames duration

# Internal state
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_dash: bool = true
var cooldown_timer: float = 0.0

func enter():
	print("Entered Dodge Dash State")
	
	# Get input direction for dash
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		# Dash in input direction
		var camera_basis = player.get_node("CameraController").transform.basis
		dash_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	else:
		# Dash forward if no input
		dash_direction = -player.global_transform.basis.z.normalized()
	
	# Set dash velocity
	player.velocity.x = dash_direction.x * dash_speed
	player.velocity.z = dash_direction.z * dash_speed
	player.velocity.y = 0  # Keep horizontal
	
	# Rotate player to face dash direction
	if dash_direction.length() > 0.1:
		var target_rotation = atan2(-dash_direction.x, -dash_direction.z)
		player.rotation.y = target_rotation
	
	# Reset timers
	dash_timer = 0.0
	can_dash = false
	cooldown_timer = dash_cooldown
	
	# Enable invincibility
	player.is_invulnerable = true
	player.invulnerability_timer = iframe_duration
	
	# Visual feedback - scale squash effect
	start_dash_animation()

func start_dash_animation():
	"""Create a quick squash and stretch effect for the dash"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	
	# Quick squash at start
	tween.tween_property(player, "scale", Vector3(1.3, 0.7, 1.3), 0.1)
	# Return to normal
	tween.tween_property(player, "scale", Vector3.ONE, 0.2)

func physics_update(delta: float):
	dash_timer += delta
	
	# Update cooldown
	if not can_dash:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_dash = true
	
	# Maintain dash velocity with slight deceleration
	var decel_factor = 1.0 - (dash_timer / dash_duration)
	player.velocity.x = dash_direction.x * dash_speed * decel_factor
	player.velocity.z = dash_direction.z * dash_speed * decel_factor
	
	
	
	# Apply light gravity (can dash in air)
	if not player.is_on_floor():
		player.velocity.y += player.get_gravity().y * delta * 0.3
	else:
		player.velocity.y = 0
	
	# Check for dash end
	if dash_timer >= dash_duration:
		exit_dash()
		return
	
	# Allow canceling into jump
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		exit_dash()
		change_to("JumpingState")
		return
	
	player.move_and_slide()

func exit_dash():
	"""End the dash and transition to appropriate state"""
	# Preserve some momentum
	var momentum_factor = 0.6
	player.velocity.x *= momentum_factor
	player.velocity.z *= momentum_factor

	# Transition to correct state
	if player.is_on_floor():
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			change_to("IdleState")
	else:
		change_to("FallingState")


func exit():
	# Reset scale
	player.scale = Vector3.ONE
	
	# Note: invulnerability timer will naturally expire via player's update_invulnerability()

func can_perform_dash() -> bool:
	"""Check if dash is off cooldown"""
	return can_dash
