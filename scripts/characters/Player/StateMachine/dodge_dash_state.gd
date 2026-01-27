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
var first_frame: bool = true  # Track if this is the first physics frame

func enter():
	print("Entered Dodge Dash State")
	
	# CRITICAL: If we're entering but cooldown isn't ready, exit immediately
	if not can_dash:
		print("ERROR: Entered dash state while cooldown active! Exiting immediately.")
		exit_dash()
		return
	
	# Store whether this is an air dash
	is_air_dash = not player.is_on_floor()
	
	# If this is an air dash, consume the air dash ability
	if is_air_dash:
		player.has_air_dashed = true
		print("Air dash used - has_air_dashed set to true")
	
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
	
	# FIX #1: COMPLETELY RESET horizontal velocity before setting dash velocity
	# This prevents momentum accumulation from previous dashes/jumps
	player.velocity.x = 0
	player.velocity.z = 0
	
	# Now set the dash velocity on a clean slate
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
	
	# Reset timers - mark dash as used
	dash_timer = 0.0
	can_dash = false
	cooldown_timer = dash_cooldown
	first_frame = true  # Mark that next physics_update is first frame
	
	# Enable invincibility without flash (for dashing)
	if player.has_method("set_invulnerable_without_flash"):
		player.set_invulnerable_without_flash(iframe_duration)
	else:
		player.is_invulnerable = true
		player.invulnerability_timer = iframe_duration
	
	# Visual feedback - scale squash effect
	start_dash_animation()
	
	# DEBUG: Print velocity for debugging
	print("=== DASH ENTER ===")
	print("Dash velocity set to: ", player.velocity)
	print("Is air dash: ", is_air_dash)

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
	# Update cooldown FIRST before anything else
	if not can_dash:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_dash = true
			print("Dash cooldown complete - can dash again")
	
	# FIX #2: CRITICAL - Force reset velocity on first frame to handle race conditions
	# This catches any velocity that might have persisted from move_and_slide() timing
	if first_frame:
		print("=== FIRST FRAME VELOCITY CHECK ===")
		print("Before reset: ", player.velocity)
		
		# Check if horizontal velocity is higher than expected
		var current_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
		var expected_horizontal = dash_speed
		
		if current_horizontal > expected_horizontal * 1.1:  # 10% tolerance
			print("!!! VELOCITY ANOMALY DETECTED !!!")
			print("Current: ", current_horizontal, " Expected: ", expected_horizontal)
			print("Forcing reset...")
			
			# Force reset to exact dash velocity
			player.velocity.x = dash_direction.x * dash_speed
			player.velocity.z = dash_direction.z * dash_speed
			
			if is_air_dash:
				player.velocity.y = clamp(player.velocity.y * 0.3, -5.0, 5.0)
			else:
				player.velocity.y = 0
		
		print("After reset: ", player.velocity)
		first_frame = false
	
	dash_timer += delta
	
	# Check if dash duration has completed FIRST (priority check)
	if dash_timer >= dash_duration:
		print("Dash duration complete")
		exit_dash()
		return
	
	# Check if we've exceeded max dash distance (secondary check)
	var distance_traveled = player.global_position.distance_to(dash_start_position)
	if distance_traveled >= max_dash_distance:
		print("Max dash distance reached: ", distance_traveled)
		exit_dash()
		return
	
	# FIX #3: Maintain EXACT dash velocity - completely override each frame
	# This prevents ANY accumulation from collision responses or other sources
	var decel_factor = 1.0 - (dash_timer / dash_duration)
	var target_speed = dash_speed * decel_factor
	
	# FORCE set velocity to exact values - ignore any external modifications
	player.velocity.x = dash_direction.x * target_speed
	player.velocity.z = dash_direction.z * target_speed
	
	# FIX #4: Add safety cap to catch any remaining edge cases
	var actual_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
	if actual_horizontal > dash_speed * 1.5:  # 150% of dash speed
		print("!!! EMERGENCY VELOCITY CAP !!!")
		print("Capping from ", actual_horizontal, " to ", dash_speed)
		var normalized = Vector2(player.velocity.x, player.velocity.z).normalized()
		player.velocity.x = normalized.x * dash_speed
		player.velocity.z = normalized.y * dash_speed
	
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
	
	if Input.is_action_just_pressed("yoyo"):
		change_to("GrappleHookState")
		return
	
	# Allow canceling into jump
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		exit_dash()
		change_to("JumpingState")
		return
	
	player.move_and_slide()
	
	# DEBUG: Monitor velocity after move_and_slide
	var post_slide_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
	if post_slide_horizontal > target_speed * 1.2:  # 20% tolerance
		print("!!! Post-slide velocity spike detected: ", post_slide_horizontal, " vs expected ", target_speed)

func exit_dash():
	print("=== DASH EXIT ===")
	print("Pre-exit velocity: ", player.velocity)
	
	# FIX #5: More conservative momentum preservation to prevent accumulation
	# Reduce from 0.6 to 0.3 for even safer transitions
	var momentum_factor = 0.3
	player.velocity.x *= momentum_factor
	player.velocity.z *= momentum_factor
	
	# Cap maximum exit velocity to prevent mega-launches
	var horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var max_exit_speed = dash_speed * 0.4  # Cap at 40% of dash speed
	
	if horizontal_speed > max_exit_speed:
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z).normalized()
		player.velocity.x = horizontal_velocity.x * max_exit_speed
		player.velocity.z = horizontal_velocity.y * max_exit_speed
		print("Capped exit velocity from ", horizontal_speed, " to ", max_exit_speed)
	
	print("Post-exit velocity: ", player.velocity)

	# CRITICAL FIX: Always ensure cooldown continues after exit
	if cooldown_timer <= 0:
		can_dash = true
		print("Cooldown already complete - dash enabled")
	elif is_air_dash and player.is_on_floor():
		can_dash = true
		cooldown_timer = 0.0
		print("Air dash landed - dash enabled immediately")
	else:
		print("Cooldown still running - dash will enable in ", cooldown_timer, " seconds")

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
	
	print("Can dash after exit: ", can_dash)


func exit():
	print("=== DASH STATE EXIT ===")
	print("Final can_dash value: ", can_dash)
	print("Final velocity: ", player.velocity)
	
	# Reset scale
	player.scale = Vector3.ONE
	
	# Note: invulnerability timer will naturally expire via player's update_invulnerability()

func can_perform_dash() -> bool:
	"""Check if dash is off cooldown AND air dash is available if in air"""
	# If on ground, just check cooldown
	if player.is_on_floor():
		return can_dash
	
	# If in air, check both cooldown AND if we haven't used air dash yet
	var result = can_dash and not player.has_air_dashed
	print("can_perform_dash() - In air: can_dash=", can_dash, " has_air_dashed=", player.has_air_dashed, " result=", result)
	return result
