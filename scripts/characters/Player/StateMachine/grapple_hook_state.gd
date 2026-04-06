extends State
class_name GrappleHookState

# Grappling configuration
@export var grapple_speed: float = 30.0
@export var max_grapple_distance: float = 30.0
@export var grapple_pull_force: float = 25.0
@export var swing_control_strength: float = 8.0
@export var release_boost: float = 15.0

# Enemy grapple configuration
@export var enemy_grapple_distance: float = 15.0  # Max distance to grapple enemies
@export var enemy_grapple_speed: float = 35.0  # Speed when grappling to enemy
@export var enemy_attack_damage: int = 2  # Damage dealt on grapple attack
@export var enemy_knockback_force: float = 15.0  # Knockback applied to enemy
@export var bounce_back_force: float = 12.0  # Bounce away from enemy after attack

# Grapple state
var grapple_point: Vector3 = Vector3.ZERO
var is_grappling: bool = false
var grapple_mode: String = "pull"  # "pull", "swing", or "enemy"
var rope_length: float = 0.0
var swing_velocity: Vector3 = Vector3.ZERO

# Enemy grapple state
var grapple_target_enemy: Node3D = null
var has_attacked_enemy: bool = false

# Visual rope
var rope_line: ImmediateMesh = null
var rope_mesh_instance: MeshInstance3D = null

func enter():
	print("Entered Grappling State")
	
	# Reset enemy grapple state
	has_attacked_enemy = false
	grapple_target_enemy = null
	
	# First, try to find an enemy to grapple
	var nearest_enemy = find_nearest_enemy()
	
	if nearest_enemy:
		# Enemy grapple mode
		setup_enemy_grapple(nearest_enemy)
	else:
		# Regular grapple point mode
		var grapple_target = find_grapple_point()
		
		if not grapple_target:
			print("No grapple point or enemy found!")
			change_to("FallingState")
			return
		
		grapple_point = grapple_target
		is_grappling = true
		rope_length = player.global_position.distance_to(grapple_point)
		
		# Determine grapple mode based on initial conditions
		var to_grapple = grapple_point - player.global_position
		var angle_to_grapple = rad_to_deg(acos(to_grapple.normalized().dot(Vector3.UP)))
		
		# If grapple point is above and ahead, swing. Otherwise, pull directly
		if angle_to_grapple < 270 and to_grapple.y > 0:
			grapple_mode = "swing"
			# Preserve horizontal momentum for swinging
			swing_velocity = player.velocity
			
			# Reset double jump and air dash abilities when entering swing mode
			player.can_double_jump = true
			player.has_double_jumped = false
			player.can_air_dash = true
			player.has_air_dashed = false
			print("Swing mode - abilities reset!")
		else:
			grapple_mode = "pull"
			# Start pulling immediately
			player.velocity = Vector3.ZERO
		
		print("Grappling to point: ", grapple_point, " Mode: ", grapple_mode)
	
	# Create visual rope
	create_rope_visual()

func setup_enemy_grapple(enemy: Node3D):
	"""Setup grapple to enemy"""
	print("=== ENEMY GRAPPLE INITIATED ===")
	print("Target enemy: ", enemy.name)
	
	grapple_mode = "enemy"
	grapple_target_enemy = enemy
	grapple_point = enemy.global_position
	is_grappling = true
	has_attacked_enemy = false
	
	# Make player invulnerable during enemy grapple (no flash)
	if player.has_method("set_invulnerable_without_flash"):
		player.set_invulnerable_without_flash(2.0)  # Long duration to cover whole grapple
		print("Player invulnerable during enemy grapple")
	
	# Reset double jump and air dash abilities
	player.can_double_jump = true
	player.has_double_jumped = false
	player.can_air_dash = true
	player.has_air_dashed = false

func create_rope_visual():
	"""Create a visual line to represent the grapple rope"""
	rope_line = ImmediateMesh.new()
	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.mesh = rope_line
	
	# Create rope material - different color for enemy grapple
	var rope_material = StandardMaterial3D.new()
	if grapple_mode == "enemy":
		rope_material.albedo_color = Color(1.0, 0.3, 0.3, 1.0)  # Red for enemy grapple
	else:
		rope_material.albedo_color = Color(0.8, 0.8, 0.8, 1.0)  # Gray for normal grapple
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
	if grapple_mode == "enemy":
		handle_enemy_grapple(delta)
	elif grapple_mode == "pull":
		handle_pull_grapple(delta)
	elif grapple_mode == "swing":
		handle_swing_grapple(delta)
	
	# Update rope visual
	update_rope_visual()
	
	player.move_and_slide()

func handle_enemy_grapple(delta: float):
	"""Pull player toward enemy and attack on contact"""
	# Check if enemy is still valid
	if not grapple_target_enemy or not is_instance_valid(grapple_target_enemy):
		print("Enemy grapple target lost")
		release_grapple()
		return
	
	# Update grapple point to enemy's current position
	grapple_point = grapple_target_enemy.global_position + Vector3(0, 0.5, 0)  # Aim for center
	
	var to_enemy = (grapple_point - player.global_position).normalized()
	var distance = player.global_position.distance_to(grapple_point)
	
	# Pull toward enemy at high speed
	player.velocity = to_enemy * enemy_grapple_speed
	
	# Rotate to face enemy
	if to_enemy.length() > 0.1:
		var target_rotation = atan2(-to_enemy.x, -to_enemy.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, 15.0 * delta)
	
	# Check if close enough to attack
	if distance < 1.5 and not has_attacked_enemy:
		attack_grappled_enemy()

func attack_grappled_enemy():
	"""Attack the enemy we grappled to"""
	if not grapple_target_enemy or not is_instance_valid(grapple_target_enemy):
		return
	
	print("=== GRAPPLE ATTACK! ===")
	has_attacked_enemy = true
	
	# Calculate knockback direction (away from player)
	var knockback_direction = (grapple_target_enemy.global_position - player.global_position).normalized()
	knockback_direction.y = 0.3  # Slight upward component
	
	# Create knockback velocity
	var knockback_velocity = knockback_direction * enemy_knockback_force
	knockback_velocity.y = 5.0  # Upward boost
	
	# Deal damage to enemy
	if grapple_target_enemy.has_method("take_damage"):
		grapple_target_enemy.take_damage(enemy_attack_damage, knockback_velocity)
		print("Dealt ", enemy_attack_damage, " damage to ", grapple_target_enemy.name)
	
	# Bounce player away from enemy
	var bounce_direction = -knockback_direction
	bounce_direction.y = 0.5  # Upward bounce
	player.velocity = bounce_direction * bounce_back_force
	
	# Visual feedback - quick flash/pulse
	create_attack_flash()
	
	# Exit grapple after short delay
	await player.get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and is_grappling:
		release_grapple()

func create_attack_flash():
	"""Create visual feedback for grapple attack"""
	# Scale pulse
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(player, "scale", Vector3(1.3, 0.7, 1.3), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.15).set_delay(0.08)

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
	
	# Check if reached grapple point
	if player.global_position.distance_to(grapple_point) < 1.0:
		release_grapple()

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

func find_nearest_enemy() -> Node3D:
	"""Find the nearest enemy within grapple range"""
	var enemies = get_tree().get_nodes_in_group("Enemy")
	if enemies.is_empty():
		return null
	
	# Get camera forward direction for aiming
	var camera_forward = player.get_node("CameraController").get_camera_forward()
	
	var best_enemy: Node3D = null
	var best_score: float = -INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		
		var to_enemy = enemy.global_position - player.global_position
		var distance = to_enemy.length()
		
		# Check if within range
		if distance > enemy_grapple_distance:
			continue
		
		# Calculate how well aligned with camera
		var alignment = to_enemy.normalized().dot(camera_forward)
		
		# Score based on alignment and distance (favor closer and more aligned)
		var score = alignment * 2.0 - (distance / enemy_grapple_distance)
		
		if score > best_score:
			best_score = score
			best_enemy = enemy
	
	if best_enemy:
		print("Found enemy to grapple: ", best_enemy.name, " at distance: ", player.global_position.distance_to(best_enemy.global_position))
	
	return best_enemy

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
	
	# Only apply release boost for non-enemy grapples (enemy grapple already has bounce)
	if grapple_mode != "enemy":
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
	grapple_target_enemy = null
	has_attacked_enemy = false
