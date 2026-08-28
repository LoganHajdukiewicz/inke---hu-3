extends State
class_name WallSlidingState

# Wall sliding configuration
@export var slide_speed: float = -1.5  # Slow downward slide (much slower than falling)
@export var min_slide_speed: float = -4.0  # Maximum slide speed
@export var slide_friction: float = 0.95  # How much to slow down vertical velocity
@export var wall_check_distance: float = 1.2  # How far to check for walls (generous so near-misses still count)
@export var wall_stick_force: float = 4.0  # Gentle pull toward the wall - makes the wall "sticky"
@export var detach_hold_time: float = 0.25  # Hold away from wall this long to deliberately detach

@export_category("Dust Effect")
@export var dust_enabled: bool = true
@export var dust_color: Color = Color(0.75, 0.72, 0.68, 0.85)
@export var dust_amount: int = 48

# Internal state
var wall_normal: Vector3 = Vector3.ZERO
var is_sliding: bool = false
var away_hold_timer: float = 0.0  # How long the stick has been held away from the wall
var _dust: GPUParticles3D = null

func enter():
	
	# Find the wall we're sliding on
	wall_normal = detect_wall()
	
	if wall_normal == Vector3.ZERO:
		change_to("FallingState")
		return
	
	is_sliding = true
	away_hold_timer = 0.0
	
	# Reduce velocity for slide
	player.velocity.y = max(player.velocity.y * slide_friction, slide_speed)
	
	# Face the wall
	var target_rotation = atan2(-wall_normal.x, -wall_normal.z)
	player.rotation.y = target_rotation
	
	if dust_enabled:
		_create_dust()

func physics_update(delta: float):
	# Refresh the wall normal each frame (walls can curve / we can drift)
	var detected_normal = detect_wall()
	if detected_normal != Vector3.ZERO:
		wall_normal = detected_normal
	else:
		# No wall found at all - nothing to slide on
		change_to("FallingState")
		return
	
	# STICKY WALL: pressing away from the wall does NOT instantly detach.
	# You stay stuck unless you hold firmly away for detach_hold_time,
	# jump off, or the wall ends. This prevents accidental drop-offs when
	# adjusting the stick mid-slide.
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.5:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Holding firmly AWAY from the wall (in the direction of its normal)
		if input_direction.dot(wall_normal) > 0.6:
			away_hold_timer += delta
			if away_hold_timer >= detach_hold_time:
				# Deliberate detach: small push off the wall
				player.velocity += wall_normal * 3.0
				change_to("FallingState")
				return
		else:
			away_hold_timer = 0.0
	else:
		away_hold_timer = 0.0
	
	# Gentle pull toward the wall keeps us glued even when the collision
	# margin would otherwise drift us out of raycast range
	player.velocity += -wall_normal * wall_stick_force * delta
	
	# Slide physics: heavily damped gravity, ramping from slide_speed down
	# to min_slide_speed. Much slower than vanilla falling - the wall has
	# friction. (The old code had two contradictory clamps that pinned the
	# speed at slide_speed forever.)
	player.velocity.y += player.get_gravity().y * delta * 0.25
	player.velocity.y = clampf(player.velocity.y, min_slide_speed, slide_speed)
	
	# Minimal horizontal control while sliding
	var move_input = Input.get_vector("left", "right", "forward", "back")
	if move_input.length() > 0.1:
		var move_camera_basis = player.get_node("CameraController").transform.basis
		var direction: Vector3 = (move_camera_basis * Vector3(move_input.x, 0, move_input.y)).normalized()
		
		# Only allow movement along the wall (perpendicular to normal)
		var right_vector = Vector3.UP.cross(wall_normal).normalized()
		var along_wall = direction.dot(right_vector)
		
		player.velocity.x = lerp(player.velocity.x, right_vector.x * along_wall * 3.0, 5.0 * delta)
		player.velocity.z = lerp(player.velocity.z, right_vector.z * along_wall * 3.0, 5.0 * delta)
	
	# Check for jump input
	if Input.is_action_just_pressed("jump"):
		# Wall jump off the wall
		var wall_jump_state = player.state_machine.states.get("walljumpingstate")
		if wall_jump_state:
			wall_jump_state.setup_wall_jump(wall_normal)
			change_to("WallJumpingState")
			return
	
	# Check for landing
	if player.is_on_floor():
		change_to("IdleState")
		return
	
	# Keep the dust pinned to the wall contact point, scaled with slide speed
	if _dust and is_instance_valid(_dust):
		_dust.global_position = player.global_position + Vector3(0, 0.9, 0) - wall_normal * 0.45
		_dust.emitting = player.velocity.y < -0.5
	
	player.move_and_slide()

func _create_dust():
	"""Little dust cloud kicked up at the hand/wall contact point."""
	_dust = GPUParticles3D.new()
	_dust.amount = dust_amount
	_dust.lifetime = 0.7
	_dust.local_coords = false
	_dust.emitting = true
	
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 50.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.4
	mat.gravity = Vector3(0, 1.5, 0)          # Dust drifts UP as you scrape down
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.25
	mat.color = dust_color
	
	var curve = Curve.new()                    # Shrink to nothing over lifetime
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	_dust.process_material = mat
	
	var mesh = SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = dust_color
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	_dust.draw_pass_1 = mesh
	
	player.get_parent().add_child(_dust)
	_dust.global_position = player.global_position + Vector3(0, 0.9, 0) - wall_normal * 0.45

func detect_wall() -> Vector3:
	"""Detect which wall we're against (8 directions for reliability)"""
	var player_forward = -player.global_transform.basis.z
	var player_right = player.global_transform.basis.x
	var space_state = player.get_world_3d().direct_space_state
	
	# Check 8 directions around the player so glancing angles still register
	var check_directions = [
		player_forward,
		-player_forward,
		player_right,
		-player_right,
		(player_forward + player_right).normalized(),
		(player_forward - player_right).normalized(),
		(-player_forward + player_right).normalized(),
		(-player_forward - player_right).normalized(),
	]
	
	for direction in check_directions:
		var ray_start = player.global_position + Vector3(0, 1.0, 0)
		var ray_end = ray_start + direction * wall_check_distance
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = [player]
		
		var result = space_state.intersect_ray(query)
		if result:
			return result.normal
	
	return Vector3.ZERO

func is_against_wall() -> bool:
	"""Check if still against a wall"""
	return detect_wall() != Vector3.ZERO

func exit():
	is_sliding = false
	wall_normal = Vector3.ZERO
	if _dust and is_instance_valid(_dust):
		# Let live particles finish, then clean up
		_dust.emitting = false
		var d = _dust
		player.get_tree().create_timer(0.7).timeout.connect(func():
			if is_instance_valid(d):
				d.queue_free())
		_dust = null
