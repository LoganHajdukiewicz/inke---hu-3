extends State
class_name WallSlidingState

# Wall sliding configuration
@export var slide_speed: float = -1.2  # Slow downward slide (much slower than falling)
@export var min_slide_speed: float = -3.5  # Maximum slide speed
@export var grab_deceleration: float = 40.0  # How hard the wall grabs you on entry (units/s^2)
@export var wall_check_distance: float = 1.2  # How far to check for walls (generous so near-misses still count)
@export var wall_stick_force: float = 4.0  # Gentle pull toward the wall - makes the wall "sticky"
@export var detach_hold_time: float = 0.25  # Hold away from wall this long to deliberately detach

@export_category("Dust Effect")
@export var dust_enabled: bool = true
@export var dust_color: Color = Color(0.9, 0.88, 0.82, 0.75)   # Same as the landing puff
@export var dust_amount: int = 48
@export var puff_interval: float = 0.09    # Seconds between scrape puffs

# Internal state
var wall_normal: Vector3 = Vector3.ZERO
var is_sliding: bool = false
var away_hold_timer: float = 0.0  # How long the stick has been held away from the wall
var _dust: GPUParticles3D = null
var _puff_timer: float = 0.0
var _grab_settled: bool = false   # Finished decelerating into the slide?

func enter():
	
	# Find the wall we're sliding on
	wall_normal = detect_wall()
	
	if wall_normal == Vector3.ZERO:
		change_to("FallingState")
		return
	
	is_sliding = true
	away_hold_timer = 0.0
	_puff_timer = 0.0
	_grab_settled = player.velocity.y >= slide_speed
	
	# Kill horizontal speed - we're stuck to the wall now
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	
	# Face the wall
	var target_rotation = atan2(-wall_normal.x, -wall_normal.z)
	player.rotation.y = target_rotation
	
	if dust_enabled:
		_create_dust()
		_spawn_scrape_puff(1.2)   # Grab burst so the catch reads instantly

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
	
	# Slide physics. Two phases:
	# 1) GRAB: if we came in falling fast, decelerate HARD toward slide
	#    speed (this is the friction-catch that makes sliding visibly
	#    slower than falling - snapping instantly read as a teleport,
	#    not clamping at all read as "same speed as falling")
	# 2) SLIDE: gentle gravity ramp from slide_speed to min_slide_speed
	if not _grab_settled:
		player.velocity.y = move_toward(player.velocity.y, slide_speed, grab_deceleration * delta)
		if player.velocity.y >= slide_speed - 0.01:
			_grab_settled = true
	else:
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
	
	# Scrape puffs - same dust-ball style as landing on the ground, so the
	# slide visibly kicks up dust the whole way down
	if dust_enabled and player.velocity.y < -0.5:
		_puff_timer -= delta
		if _puff_timer <= 0.0:
			_puff_timer = puff_interval
			_spawn_scrape_puff(0.5)
	
	player.move_and_slide()

func _spawn_scrape_puff(strength: float):
	"""Dust balls at the wall contact point - same look as the landing puff
	(unshaded spheres that scatter and fade), so the effect matches."""
	var parent = player.get_parent()
	if not parent:
		return
	var contact = player.global_position + Vector3(0, 0.9, 0) - wall_normal * 0.4
	var along = Vector3.UP.cross(wall_normal).normalized()
	var count = 2 if strength < 1.0 else 5
	for i in range(count):
		var puff = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		var size = randf_range(0.09, 0.2) * strength
		sphere.radius = size
		sphere.height = size * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		puff.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = dust_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = mat
		parent.add_child(puff)
		puff.global_position = contact + along * randf_range(-0.3, 0.3) + Vector3(0, randf_range(-0.2, 0.2), 0)
		# Puffs kick UP and slightly off the wall as you scrape down
		var target = puff.global_position \
			+ wall_normal * randf_range(0.15, 0.45) \
			+ along * randf_range(-0.4, 0.4) \
			+ Vector3(0, randf_range(0.4, 0.9), 0)
		var tween = puff.create_tween()
		tween.set_parallel(true)
		tween.tween_property(puff, "global_position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector3(0.1, 0.1, 0.1), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tween.chain().tween_callback(puff.queue_free)

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
