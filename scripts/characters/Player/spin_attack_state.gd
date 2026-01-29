extends State
class_name SpinAttackState

# Spin attack configuration
@export var spin_duration: float = 0.2  # How long the spin lasts
@export var hover_strength: float = 25.0  # Upward force during spin
@export var air_control_strength: float = 25.0  # Horizontal control during spin
@export var max_horizontal_speed: float = 15.0  # Maximum speed during spin
@export var pushback_force: float = 25.0  # Force to push enemies
@export var pushback_radius: float = 3.0  # Radius of 360° pushback
@export var damage: int = 2  # Damage dealt by spin

# Internal state
var spin_timer: float = 0.0
var is_spinning: bool = false
var hit_enemies: Array = []  # Track hit enemies to avoid multiple hits
var spin_hitbox: Area3D

# Visual
var spin_tween: Tween

func enter():
	print("Entered Spin Attack State")
	
	# Reset state
	spin_timer = 0.0
	is_spinning = true
	hit_enemies.clear()
	
	# Only apply upward force if IN THE AIR
	if not player.is_on_floor():
		# Only modify velocity when in air
		if player.velocity.y < 0:
			player.velocity.y = -1.0
		elif player.velocity.y < 5.0:
			player.velocity.y = 3.0
		
		# Reduce horizontal momentum slightly for air spin
		player.velocity.x *= 0.6
		player.velocity.z *= 0.6
	else:
		# ON GROUND: Keep velocity at zero vertically
		player.velocity.y = 0.0
		
		# DISABLE FLOOR FRICTION by setting floor_stop_on_slope to false
		# and floor_constant_speed to true
		player.floor_stop_on_slope = false
		player.floor_constant_speed = true
		player.floor_block_on_wall = false
	
	# Setup hitbox
	setup_spin_hitbox()
	
	# Start spin animation
	start_spin_animation()

func setup_spin_hitbox():
	"""Create a 360° hitbox around the player"""
	spin_hitbox = Area3D.new()
	spin_hitbox.name = "SpinHitbox"
	
	# Set collision properties
	spin_hitbox.collision_layer = 0
	spin_hitbox.collision_mask = 1  # Detect enemies
	spin_hitbox.monitoring = true
	spin_hitbox.monitorable = false
	
	player.add_child(spin_hitbox)
	
	# Create spherical collision shape
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = pushback_radius
	collision_shape.shape = sphere_shape
	collision_shape.position = Vector3(0, 1.0, 0)  # Center on player body
	spin_hitbox.add_child(collision_shape)
	
	print("Spin hitbox created with radius: ", pushback_radius)

func start_spin_animation():
	"""Create spinning visual effect"""
	if spin_tween and is_instance_valid(spin_tween):
		spin_tween.kill()
	
	spin_tween = create_tween()
	spin_tween.set_loops()
	
	var current_rotation = player.rotation.y
	spin_tween.tween_property(player, "rotation:y", current_rotation + TAU, spin_duration)

func physics_update(delta: float):
	spin_timer += delta
	
	# Check if spin duration is complete
	if spin_timer >= spin_duration:
		exit_spin()
		return
	
	# Only apply hover force when in the air
	if not player.is_on_floor():
		var hover_multiplier = 1.0 - (spin_timer / spin_duration)
		
		if player.velocity.y < -2.0:
			player.velocity.y += hover_strength * hover_multiplier * delta * 0.3
		
		player.velocity += player.get_gravity() * delta * 0.5
		
		# Air control
		var input_dir = Input.get_vector("left", "right", "forward", "back")
		
		if input_dir.length() > 0.1:
			var camera_basis = player.get_node("CameraController").transform.basis
			var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			
			var target_velocity = direction * max_horizontal_speed
			player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_strength * delta)
			player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_strength * delta)
	else:
		# On ground - just apply gravity, friction is disabled
		player.velocity += player.get_gravity() * delta
	
	# Check for enemies in range and apply pushback
	check_and_pushback_enemies()
	
	# Allow canceling into other moves
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		exit_spin()
		change_to("JumpingState")
		return
	
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			exit_spin()
			change_to("DodgeDashState")
			return
	
	player.move_and_slide()
	
	# Check for landing - exit immediately when touching ground
	if player.is_on_floor() and spin_timer > 0.05:  # Very brief ground time before exit
		exit_spin()
		return

func check_and_pushback_enemies():
	"""Check for enemies in range and push them back"""
	if not spin_hitbox:
		return
	
	var overlapping_bodies = spin_hitbox.get_overlapping_bodies()
	var overlapping_areas = spin_hitbox.get_overlapping_areas()
	
	# Process bodies
	for body in overlapping_bodies:
		if body.is_in_group("Enemy") and body not in hit_enemies:
			hit_enemy(body)
		elif body.is_in_group("Breakables") and body not in hit_enemies:
			if body.has_method("take_damage"):
				body.take_damage(damage)
				hit_enemies.append(body)
	
	# Process areas
	for area in overlapping_areas:
		var parent = area.get_parent()
		if parent and parent.is_in_group("Enemy") and parent not in hit_enemies:
			hit_enemy(parent)
		elif parent and parent.is_in_group("Breakables") and parent not in hit_enemies:
			if parent.has_method("take_damage"):
				parent.take_damage(damage)
				hit_enemies.append(parent)

func hit_enemy(enemy: Node):
	"""Deal damage and pushback to enemy"""
	if not enemy or not is_instance_valid(enemy):
		return
	
	print("Spin attack hit: ", enemy.name)
	
	# Calculate pushback direction (radial from player)
	var pushback_direction = (enemy.global_position - player.global_position).normalized()
	pushback_direction.y = 0.3  # Slight upward component
	
	# Create pushback velocity
	var pushback_velocity = pushback_direction * pushback_force
	pushback_velocity.y = 8.0  # Strong upward knockback
	
	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, pushback_velocity)
	
	# Mark as hit to avoid multiple hits
	hit_enemies.append(enemy)

func exit_spin():
	"""Exit the spin attack"""
	print("Spin attack complete")
	
	# FIXED: Kill tweens here too
	if spin_tween and is_instance_valid(spin_tween):
		spin_tween.kill()
	spin_tween = null
	
	# Preserve some horizontal momentum
	player.velocity.x *= 0.8
	player.velocity.z *= 0.8
	
	# Transition to appropriate state
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
	print("Exited Spin Attack State")
	
	# Clean up
	is_spinning = false
	
	# Re-enable floor friction
	player.floor_stop_on_slope = true
	player.floor_constant_speed = false
	player.floor_block_on_wall = true
	
	# Kill tweens
	if spin_tween and is_instance_valid(spin_tween):
		spin_tween.kill()
	spin_tween = null
	
	if spin_hitbox and is_instance_valid(spin_hitbox):
		spin_hitbox.queue_free()
	
	# Reset scale
	player.scale = Vector3.ONE
	
	# Normalize rotation
	player.rotation.y = fmod(player.rotation.y, TAU)
