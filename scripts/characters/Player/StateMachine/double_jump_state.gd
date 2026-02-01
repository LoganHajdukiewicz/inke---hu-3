extends State
class_name DoubleJumpState

# Exported variables for designer control
@export var jump_height : float = 12.0  # Higher for more dramatic effect
@export var jump_duration : float = 0.4  # Shorter duration for snappier feel
@export var ascent_time : float = 0.15   # Very quick ascent
@export var peak_time : float = 0.05     # Brief hang time
@export var descent_multiplier : float = 3.0  # Fast descent

var jump_velocity : float = 16.0  # Strong initial velocity
var jump_elapsed_time : float = 0.0
var scale_tween : Tween

func enter():
	print("Entered Double Jump State")
	
	player.velocity.y = jump_velocity
	jump_elapsed_time = 0.0
	
	# More dramatic visual effect for double jump
	start_scale_effect()

func start_scale_effect():
	if scale_tween:
		scale_tween.kill()
	
	scale_tween = create_tween()
	scale_tween.set_trans(Tween.TRANS_BACK)
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(player, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	scale_tween.tween_property(player, "scale", Vector3(0.95, 1.1, 0.95), 0.12)
	scale_tween.tween_property(player, "scale", Vector3.ONE, 0.15)

func physics_update(delta: float):
	jump_elapsed_time += delta
	
	# Gravity progression for double jump
	var gravity_multiplier = get_gravity_multiplier()
	player.velocity += player.get_gravity() * delta * gravity_multiplier

	if Input.is_action_just_pressed("yoyo"):
		change_to("GrapplingState")
		return
		
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			change_to("DodgeDashState")
		
	# Check for wall jump input first
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

	# Very limited air control for double jump - focus on vertical movement
	handle_minimal_air_movement(delta)

	# Quick transition to falling
	if player.velocity.y <= 0:
		cleanup_tween()
		change_to("FallingState")
		return
	
	player.move_and_slide()

func get_gravity_multiplier() -> float:
	# Setting up the double jump curve
	if jump_elapsed_time < ascent_time:
		# Quick ascent phase - minimal gravity
		return 0.2
	elif jump_elapsed_time < ascent_time + peak_time:
		# Brief hang time at peak
		return 0.1
	else:
		# Fast descent phase - heavy gravity
		return descent_multiplier

func handle_minimal_air_movement(delta: float):
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Extremely limited horizontal control during double jump
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var max_air_speed = max(current_horizontal_speed, 3.0)  # Very conservative
		var target_velocity = direction * max_air_speed
		
		# Minimal air control - double jump is mostly vertical
		var air_control_factor = 0.08  # Very low control
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)
		
		# Very slow rotation during double jump
		if direction.length() > 0.1:
			var target_rotation = atan2(-direction.x, -direction.z)
			var rotation_speed = 2.0  # Very slow rotation
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Preserve current momentum with minimal changes
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 1.0:
			var momentum_direction = Vector3(horizontal_velocity.x, 0, horizontal_velocity.y).normalized()
			var target_rotation = atan2(-momentum_direction.x, -momentum_direction.z)
			var rotation_speed = 1.5  # Very slow momentum rotation
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_speed * delta)
		
		# Almost no horizontal deceleration - preserve momentum
		var horizontal_deceleration = 0.998  # Minimal deceleration
		player.velocity.x *= horizontal_deceleration
		player.velocity.z *= horizontal_deceleration

func cleanup_tween():
	if scale_tween:
		scale_tween.kill()
		scale_tween = null

func exit():
	cleanup_tween()
	# Reset scale to normal
	player.scale = Vector3.ONE
