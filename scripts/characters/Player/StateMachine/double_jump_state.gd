extends State
class_name DoubleJumpState

# Exported variables for designer control
@export var jump_height : float = 8.0
@export var jump_duration : float = 0.6
@export var jump_tween_type : Tween.TransitionType = Tween.TRANS_QUART
@export var jump_ease_type : Tween.EaseType = Tween.EASE_OUT

var jump_velocity : float = 5.0
var jump_tween : Tween
var initial_y_position : float
var jump_elapsed_time : float = 0.0
var is_tweening : bool = false

func enter():
	print("Entered Double Jump State")
	
	# Store initial position
	initial_y_position = player.global_position.y
	
	# Start the double jump
	start_jump()

func start_jump():
	# Calculate the upward velocity needed for the jump arc
	var upward_velocity = (jump_height * 2.0) / jump_duration
	player.velocity.y = upward_velocity
	
	# Reset timing
	jump_elapsed_time = 0.0
	is_tweening = true
	
	# Add a subtle scale effect for extra juice
	if jump_tween:
		jump_tween.kill()
	
	jump_tween = create_tween()
	jump_tween.set_trans(Tween.TRANS_BACK)
	jump_tween.set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(player, "scale", Vector3(1.1, 0.9, 1.1), 0.1)
	jump_tween.tween_property(player, "scale", Vector3.ONE, 0.2)

func physics_update(delta: float):
	# Update jump timing
	jump_elapsed_time += delta
	
	# Apply gravity with custom curve based on tween type
	var gravity_multiplier = get_gravity_multiplier()
	player.velocity += player.get_gravity() * delta * gravity_multiplier
	
	# Check for wall jump input first (highest priority)
	if Input.is_action_just_pressed("jump") and player.can_perform_wall_jump():
		var wall_normal = player.get_wall_jump_direction()
		if wall_normal.length() > 0:
			cleanup_tween()
			var wall_jump_state = player.state_machine.states.get("walljumpingstate")
			if wall_jump_state:
				wall_jump_state.setup_wall_jump(wall_normal)
				change_to("WallJumpingState")
				player.wall_jump_cooldown = player.wall_jump_cooldown_time
				return

	# Enhanced air control for double jump
	handle_air_movement(delta)

	# Check if we should transition to falling
	if player.velocity.y <= 0:
		cleanup_tween()
		change_to("FallingState")
		return
	
	player.move_and_slide()

func get_gravity_multiplier() -> float:
	# Adjust gravity based on jump progress for more natural arc
	var progress = get_jump_progress()
	
	match jump_tween_type:
		Tween.TRANS_QUART:
			# Jak and Daxter style - quick up, smooth down
			return 0.4 if progress < 0.3 else lerp(0.4, 1.4, (progress - 0.3) / 0.7)
		Tween.TRANS_BACK:
			# Bouncy feel
			return 0.6 if progress < 0.4 else lerp(0.6, 1.2, (progress - 0.4) / 0.6)
		Tween.TRANS_ELASTIC:
			# Very bouncy
			return 0.3 if progress < 0.5 else lerp(0.3, 1.6, (progress - 0.5) / 0.5)
		_:
			# Default smooth
			return lerp(0.6, 1.2, progress)

func get_jump_progress() -> float:
	# Calculate how far through the jump we are (0.0 to 1.0)
	return clamp(jump_elapsed_time / jump_duration, 0.0, 1.0)

func handle_air_movement(delta: float):
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Set a reasonable max air speed instead of using current speed
		var max_air_speed = 6.0  # Cap the horizontal speed during jumps
		var target_velocity = direction * max_air_speed
		
		# Reduced air control - more manageable during jump
		var air_control_factor = 0.4  # Reduced from 0.8 to 0.4 for more reasonable control
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Slower player rotation for more controlled feel
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 8.0  # Reduced from 15.0 to 8.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Gradually slow down horizontal movement when no input
		var horizontal_deceleration = 0.95  # Gradually reduce speed
		player.velocity.x *= horizontal_deceleration
		player.velocity.z *= horizontal_deceleration
		
		# Face movement direction when no input
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 6.0  # Reduced from 8.0 to 6.0
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)

func cleanup_tween():
	if jump_tween:
		jump_tween.kill()
		jump_tween = null
	is_tweening = false

func exit():
	cleanup_tween()
	# Reset scale to normal in case it was modified
	player.scale = Vector3.ONE
