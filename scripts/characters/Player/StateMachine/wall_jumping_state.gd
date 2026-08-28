extends State
class_name WallJumpingState

## Wall jump, rebuilt for feel:
##  - PUNCHY: strong up + away impulse the moment you press jump
##  - STEERABLE: your stick input at jump time TILTS the launch direction
##    (up to steer_angle_degrees away from the pure wall normal), so you
##    aim wall jumps like in Celeste/Odyssey instead of being fired
##    perpendicular whether you like it or not
##  - RESPONSIVE: the input lock is short (0.12s) and control fades back
##    in quickly - the old 0.35s dead zone was the main "feels bad"
##  - CHAINABLE: jumping at another wall mid-flight re-launches instantly

@export_category("Launch")
@export var wall_jump_up_velocity: float = 11.0       # Vertical pop (regular jump is 15)
@export var wall_jump_horizontal_force: float = 9.5   # Push away from the wall
@export var steer_angle_degrees: float = 55.0         # Max stick-steering away from the wall normal
@export var steer_strength: float = 0.85              # 0 = ignore stick, 1 = full steer authority

@export_category("Control Return")
@export var momentum_lock_duration: float = 0.12  # Full lock - just enough to guarantee separation
@export var momentum_fade_duration: float = 0.18  # Control fades back over this window
@export var air_control_factor: float = 0.22      # Air control once faded in

@export_category("Wall Slide Handoff")
@export var wall_slide_check_time: float = 0.25            # Don't slide-grab instantly after jumping
@export var wall_slide_velocity_threshold: float = -2.0    # Falling this fast near a wall -> slide

var total_lock_time: float:   # kept for the debug overlay
	get: return momentum_lock_duration + momentum_fade_duration

var wall_direction: Vector3 = Vector3.ZERO
var wall_jump_timer: float = 0.0

func enter():
	_launch(wall_direction)

func setup_wall_jump(wall_normal: Vector3):
	wall_direction = wall_normal

func _launch(wall_normal: Vector3):
	"""Apply the wall jump impulse off the given wall."""
	wall_direction = wall_normal
	wall_jump_timer = 0.0
	
	# Kill any velocity INTO the wall so nothing fights the launch
	if wall_normal.length() > 0:
		var into_wall = player.velocity.dot(-wall_normal)
		if into_wall > 0:
			player.velocity -= (-wall_normal) * into_wall
	
	# Launch direction: wall normal, tilted toward the player's stick input
	var launch_dir = wall_normal.normalized() if wall_normal.length() > 0 else Vector3.UP
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.2 and wall_normal.length() > 0:
		var camera_basis = player.get_node("CameraController").transform.basis
		var wish = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		# Only steer if the input isn't pointing back INTO the wall
		if wish.dot(launch_dir) > -0.25:
			var steered = (launch_dir + wish * steer_strength).normalized()
			# Clamp the tilt to steer_angle_degrees off the pure normal
			var max_rad = deg_to_rad(steer_angle_degrees)
			var angle = launch_dir.angle_to(steered)
			if angle > max_rad:
				steered = launch_dir.slerp(steered, max_rad / angle).normalized()
			launch_dir = steered
	
	# Preserve a slice of earned horizontal speed along the launch direction
	# so chained wall jumps across a shaft keep building flow
	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var carried = clampf(h_speed * 0.35, 0.0, 6.0)
	
	player.velocity.x = launch_dir.x * (wall_jump_horizontal_force + carried)
	player.velocity.z = launch_dir.z * (wall_jump_horizontal_force + carried)
	player.velocity.y = wall_jump_up_velocity
	
	# Face the launch direction instantly - readable and snappy
	if launch_dir.length() > 0.1:
		player.rotation.y = atan2(-launch_dir.x, -launch_dir.z)
	
	# Squash-and-stretch pop for game feel
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.8, 1.25, 0.8), 0.07)
	tween.tween_property(player, "scale", Vector3.ONE, 0.12)
	
	# Allow immediate chaining
	player.wall_jump_cooldown = 0.0

func physics_update(delta: float):
	if Input.is_action_just_pressed("yoyo"):
		change_to("GrappleHookState")
		return
	
	wall_jump_timer += delta
	player.velocity += player.get_gravity() * delta
	
	# Chain onto another wall (or the same wall after separating)
	if Input.is_action_just_pressed("jump") and player.can_perform_wall_jump():
		var wall_normal = player.get_wall_jump_direction()
		if wall_normal.length() > 0 and wall_direction.angle_to(wall_normal) > 0.5:
			_launch(wall_normal)
			return
	
	# Hand off to wall slide when falling against a wall
	if wall_jump_timer > wall_slide_check_time and player.velocity.y < wall_slide_velocity_threshold:
		if is_near_wall():
			change_to("WallSlidingState")
			return
	
	_handle_air_control(delta)
	
	if player.is_on_floor():
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		change_to("WalkingState" if input_dir.length() > 0.1 else "IdleState")
		return
	
	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()

func _handle_air_control(delta: float):
	"""Short lock, quick fade, then normal air control - one code path."""
	# control_amount: 0 during the lock, eases to 1 across the fade window
	var control_amount := 0.0
	if wall_jump_timer >= momentum_lock_duration:
		var fade = (wall_jump_timer - momentum_lock_duration) / momentum_fade_duration
		control_amount = ease(clampf(fade, 0.0, 1.0), -2.0)
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1 and control_amount > 0.0:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var target_velocity = direction * max(h_speed, 6.0)
		
		var factor = air_control_factor * control_amount
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, factor)
		
		var target_rotation = atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, 8.0 * control_amount * delta)
	else:
		# Face momentum
		var h = Vector2(player.velocity.x, player.velocity.z)
		if h.length() > 1.0:
			var momentum_dir = Vector3(h.x, 0, h.y).normalized()
			var target_rotation = atan2(-momentum_dir.x, -momentum_dir.z)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, 4.0 * delta)

func is_near_wall() -> bool:
	"""Generous 8-direction wall check for the slide handoff."""
	var space_state = player.get_world_3d().direct_space_state
	var forward = -player.global_transform.basis.z
	var right = player.global_transform.basis.x
	
	for direction in [
		forward, -forward, right, -right,
		(forward + right).normalized(), (forward - right).normalized(),
		(-forward + right).normalized(), (-forward - right).normalized(),
	]:
		var ray_start = player.global_position + Vector3(0, 1.0, 0)
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_start + direction * 1.2)
		query.collision_mask = 1
		query.exclude = [player]
		if space_state.intersect_ray(query):
			return true
	return false

func exit():
	player.scale = Vector3.ONE
