extends State
class_name DodgeDashState

# Dodge dash configuration
@export var dash_speed: float = 100.0
@export var dash_duration: float = 0.3
@export var dash_cooldown: float = 0.1
@export var iframe_duration: float = 0.4  # Invincibility frames duration
@export var max_dash_distance: float = 15.0  # Maximum distance the dash can cover

# Internal state
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var can_dash: bool = true
var cooldown_timer: float = 0.0
var dash_start_position: Vector3 = Vector3.ZERO
var is_air_dash: bool = false

func enter():
	print("Entered Dodge Dash State")
	
	# Store whether this is an air dash
	is_air_dash = not player.is_on_floor()
	
	# Store starting position for distance limit
	dash_start_position = player.global_position
	
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
	
	# For air dashes, preserve some vertical momentum but reduce it
	if is_air_dash:
		player.velocity.y = clamp(player.velocity.y * 0.3, -5.0, 5.0)
	else:
		player.velocity.y = 0  # Keep horizontal on ground
	
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
	
	# Check if we've exceeded max dash distance
	var distance_traveled = player.global_position.distance_to(dash_start_position)
	if distance_traveled >= max_dash_distance:
		exit_dash()
		return
	
	# Maintain dash velocity with slight deceleration
	var decel_factor = 1.0 - (dash_timer / dash_duration)
	player.velocity.x = dash_direction.x * dash_speed * decel_factor
	player.velocity.z = dash_direction.z * dash_speed * decel_factor
	
	# Apply gravity differently based on air/ground dash
	if is_air_dash:
		# Light gravity for air dash
		player.velocity.y += player.get_gravity().y * delta * 0.5
	else:
		# No gravity for ground dash
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

	# If we landed during an air dash, reset the dash availability
	if is_air_dash and player.is_on_floor():
		can_dash = true
		cooldown_timer = 0.0

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
