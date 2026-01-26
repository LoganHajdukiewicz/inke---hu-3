extends State
class_name GrappleHookState

# Grappling configuration
@export var grapple_speed: float = 30.0
@export var max_grapple_distance: float = 20.0
@export var grapple_pull_force: float = 25.0
@export var swing_control_strength: float = 8.0
@export var release_boost: float = 15.0

# Grapple state
var grapple_point: Vector3 = Vector3.ZERO
var is_grappling: bool = false
var grapple_mode: String = "pull"  # "pull" or "swing"
var rope_length: float = 0.0
var swing_velocity: Vector3 = Vector3.ZERO

# Visual rope
var rope_line: ImmediateMesh = null
var rope_mesh_instance: MeshInstance3D = null

func enter():
	print("Entered Grappling State")
	
	# Find nearest grapple point
	var grapple_target = find_grapple_point()
	
	if not grapple_target:
		print("No grapple point found!")
		change_to("FallingState")
		return
	
	grapple_point = grapple_target
	is_grappling = true
	rope_length = player.global_position.distance_to(grapple_point)
	
	# Determine grapple mode based on initial conditions
	var to_grapple = grapple_point - player.global_position
	var angle_to_grapple = rad_to_deg(acos(to_grapple.normalized().dot(Vector3.UP)))
	
	# If grapple point is above and ahead, swing. Otherwise, pull directly
	if angle_to_grapple < 60 and to_grapple.y > 0:
		grapple_mode = "swing"
		# Preserve horizontal momentum for swinging
		swing_velocity = player.velocity
	else:
		grapple_mode = "pull"
		# Start pulling immediately
		player.velocity = Vector3.ZERO
	
	print("Grappling to: ", grapple_point, " Mode: ", grapple_mode)
	
	# Create visual rope
	create_rope_visual()

func create_rope_visual():
	"""Create a visual line to represent the grapple rope"""
	rope_line = ImmediateMesh.new()
	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.mesh = rope_line
	
	# Create rope material
	var rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
	rope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mesh_instance.material_override = rope_material
	
	# Add to scene
	player.get_parent().add_child(rope_mesh_instance)

func physics_update(delta: float):
	if not is_grappling:
		exit_grapple()
		return
	
	# Check for release input
	if Input.is_action_just_pressed("yoyo") or Input.is_action_just_pressed("jump"):
		release_grapple()
		return
	
	# Update based on grapple mode
	if grapple_mode == "pull":
		handle_pull_grapple(delta)
	elif grapple_mode == "swing":
		handle_swing_grapple(delta)
	
	# Update rope visual
	update_rope_visual()
	
	# Check if reached grapple point
	if player.global_position.distance_to(grapple_point) < 1.0:
		if grapple_mode == "pull":
			release_grapple()
	
	player.move_and_slide()

func handle_pull_grapple(delta: float):
	"""Pull player directly to grapple point"""
	var to_grapple = (grapple_point - player.global_position).normalized()
	
	# Apply pull force
	player.velocity = to_grapple * grapple_pull_force
	
	# Light gravity for smoother pull
	player.velocity += player.get_gravity() * delta * 0.3
	
	# Rotate to face grapple point
	if to_grapple.length() > 0.1:
		var target_rotation = atan2(-to_grapple.x, -to_grapple.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, 10.0 * delta)

func handle_swing_grapple(delta: float):
	"""Swing player like a pendulum"""
	var to_grapple = grapple_point - player.global_position
	var distance = to_grapple.length()
	
	# Apply gravity
	player.velocity += player.get_gravity() * delta
	
	# Player input for swing control
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Apply swing control perpendicular to rope
		var rope_direction = to_grapple.normalized()
		var perpendicular = input_direction - rope_direction * input_direction.dot(rope_direction)
		player.velocity += perpendicular * swing_control_strength * delta
	
	# Constrain to rope length (pendulum physics)
	var current_direction = to_grapple.normalized()
	var radial_velocity = player.velocity.dot(current_direction)
	
	# If moving away from grapple point and exceeding rope length, apply tension
	if distance >= rope_length and radial_velocity < 0:
		# Remove radial component (tension force)
		player.velocity -= current_direction * radial_velocity
		
		# Apply slight pull to maintain rope length
		var excess = distance - rope_length
		if excess > 0:
			player.velocity += current_direction * excess * 10.0

func find_grapple_point() -> Vector3:
	"""Find the nearest grapple point within range"""
	var grapple_points = get_tree().get_nodes_in_group("GrapplePoint")
	
	if grapple_points.is_empty():
		return Vector3.ZERO
	
	# Get camera forward direction for aiming
	var camera_forward = player.get_node("CameraController").get_camera_forward()
	
	var best_point: Node3D = null
	var best_score: float = -INF
	
	for point in grapple_points:
		if not is_instance_valid(point) or not point is Node3D:
			continue
		
		var to_point = point.global_position - player.global_position
		var distance = to_point.length()
		
		# Check if within range
		if distance > max_grapple_distance:
			continue
		
		# Calculate how well aligned with camera
		var alignment = to_point.normalized().dot(camera_forward)
		
		# Score based on alignment and distance (favor closer and more aligned)
		var score = alignment * 2.0 - (distance / max_grapple_distance)
		
		if score > best_score:
			best_score = score
			best_point = point
	
	return best_point.global_position if best_point else Vector3.ZERO

func update_rope_visual():
	"""Update the visual rope connecting player to grapple point"""
	if not rope_line or not rope_mesh_instance:
		return
	
	rope_line.clear_surfaces()
	rope_line.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Draw line from player to grapple point
	var player_pos = player.global_position + Vector3(0, 1.0, 0)  # Offset to hand height
	
	rope_line.surface_add_vertex(player_pos)
	rope_line.surface_add_vertex(grapple_point)
	
	rope_line.surface_end()

func release_grapple():
	"""Release the grapple and apply momentum boost"""
	print("Releasing grapple!")
	
	# Apply release boost in current velocity direction
	if player.velocity.length() > 0.1:
		var boost_direction = player.velocity.normalized()
		player.velocity += boost_direction * release_boost
	
	exit_grapple()

func exit_grapple():
	"""Exit grappling state"""
	is_grappling = false
	
	# Transition to appropriate state
	if player.is_on_floor():
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			change_to("WalkingState")
		else:
			change_to("IdleState")
	else:
		change_to("FallingState")

func exit():
	print("Exited Grappling State")
	
	# Clean up rope visual
	if rope_mesh_instance and is_instance_valid(rope_mesh_instance):
		rope_mesh_instance.queue_free()
	
	is_grappling = false
