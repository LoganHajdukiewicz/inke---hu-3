extends Node
class_name AttackManager

# Attack configuration
@export_group("Light Attack")
@export var light_attack_damage: int = 1
@export var light_attack_range: float = 0.1
@export var light_attack_radius: float = 10
@export var light_attack_cooldown: float = 0.3
@export var light_knockback_force: float = 40.0
@export var light_knockback_upward: float = 3.0

# Spin attack now replaces heavy attack
@export_group("Spin Attack")
@export var spin_attack_cooldown: float = 1.0

# Attack state
var can_attack: bool = true
var attack_timer: float = 0.0
var attack_hitbox: Area3D
var is_attacking: bool = false

# References
var player: CharacterBody3D
var state_machine: StateMachine

func _ready():
	player = get_parent() as CharacterBody3D
	state_machine = player.get_node("StateMachine") if player.has_node("StateMachine") else null
	setup_attack_hitbox()

func setup_attack_hitbox():
	"""Creates an Area3D hitbox in front of the player for detecting enemies."""
	attack_hitbox = Area3D.new()
	attack_hitbox.name = "AttackHitbox"
	
	# CRITICAL: Set collision layers properly
	# Layer 1 = default layer where enemies exist
	# We need to DETECT layer 1 (enemies) but not BE on layer 1 (to avoid self-collision)
	attack_hitbox.collision_layer = 0    # Don't exist on any layer
	attack_hitbox.collision_mask = 1     # Detect things on layer 1 (enemies)
	attack_hitbox.monitoring = false     # Start disabled
	attack_hitbox.monitorable = false    # We don't need to be detected
	
	player.add_child(attack_hitbox)
	
	# Create collision shape for the hitbox
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = light_attack_radius  # Start with light attack radius
	collision_shape.shape = sphere_shape
	collision_shape.position = Vector3(0, 0, 0)
	attack_hitbox.add_child(collision_shape)
	

func _physics_process(delta: float):
	# Update attack cooldown timer
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0:
			can_attack = true
	
	# Check for attack input
	check_attack_input()

func check_attack_input():
	"""Checks if the player pressed attack buttons and initiates attack."""
	# Debug: Check input state
	if Input.is_action_just_pressed("attack"):
		pass
	
	if Input.is_action_just_pressed("heavy_attack"):
		pass
	
	if not can_attack or player.is_dead:
		return
	
	# No attacking while hands are busy: on a rope Triangle/X is CLIMB UP,
	# and hanging/climbing states reposition the player directly - a spin
	# attack there breaks the attachment.
	if state_machine and state_machine.current_state:
		var state_name = state_machine.current_state.get_script().get_global_name()
		if state_name in ["RopeSwingState", "LedgeHangingState", "WallClimbingState", "BalanceBeamState"]:
			return
	
	# Spin attack (higher priority) - Check both heavy_attack action and shift+attack
	var spin_pressed = Input.is_action_just_pressed("heavy_attack") or \
						(Input.is_action_just_pressed("attack") and Input.is_key_pressed(KEY_SHIFT))
	
	if spin_pressed:
		perform_spin_attack()
	# Light attack - only if shift is NOT held
	elif Input.is_action_just_pressed("attack") and not Input.is_key_pressed(KEY_SHIFT):
		perform_attack(false)  # false = light attack

func perform_spin_attack():
	"""Transition to spin attack state instead of performing attack here"""
	if not state_machine:
		print("ERROR: No state machine found!")
		return
	
	var spin_state = state_machine.states.get("spinattackstate")
	if not spin_state:
		print("ERROR: SpinAttackState not found in state machine!")
		return
	
	# Start cooldown
	can_attack = false
	attack_timer = spin_attack_cooldown
	
	# Transition to spin attack state
	state_machine.change_state("SpinAttackState")

func perform_attack(_is_heavy: bool):
	"""Executes the attack with specified parameters."""
	
	# Get attack parameters based on type
	var damage = light_attack_damage
	var attack_range = light_attack_range
	var attack_radius = light_attack_radius
	var cooldown = light_attack_cooldown
	var knockback_horizontal = light_knockback_force
	var knockback_vertical = light_knockback_upward
	
	
	# Start cooldown
	can_attack = false
	attack_timer = cooldown
	is_attacking = true
	
	# Update hitbox size for this attack
	var collision_shape = attack_hitbox.get_child(0) as CollisionShape3D
	if collision_shape:
		var sphere_shape = collision_shape.shape as SphereShape3D
		sphere_shape.radius = attack_radius
	
	# Position hitbox in front of player
	update_hitbox_position(attack_range)
	
	# Enable hitbox detection
	attack_hitbox.monitoring = true
	
	# Wait one physics frame for Area3D to detect overlaps
	await player.get_tree().physics_frame
	
	# Get all overlapping bodies and areas
	var hit_bodies = attack_hitbox.get_overlapping_bodies()
	var hit_areas = attack_hitbox.get_overlapping_areas()
	
	
	# DEBUG: Print what we hit
	for body in hit_bodies:
		pass
	for area in hit_areas:
		if area.get_parent():
			pass
	
	# Track which entities we've already damaged
	var damaged_entities: Array = []
	
	# Process body hits
	for body in hit_bodies:
		# Check for breakable objects (like boxes)
		if body.is_in_group("Breakables") and body not in damaged_entities:
			if body.has_method("take_damage"):
				body.take_damage(damage)
				damaged_entities.append(body)
		
		# Check for enemies
		elif body.is_in_group("Enemy") and body not in damaged_entities:
			hit_enemy(body, damage, knockback_horizontal, knockback_vertical)
			damaged_entities.append(body)
	
	# Process area hits
	for area in hit_areas:
		
		# Check if the area itself is breakable
		if area.is_in_group("Breakables") and area not in damaged_entities:
			if area.has_method("take_damage"):
				area.take_damage(damage)
				damaged_entities.append(area)
		
		# Check if the area's parent is breakable or an enemy
		if area.get_parent():
			var parent = area.get_parent()
			
			# Check for breakable parent (like a box with a DamageDetection area)
			if parent.is_in_group("Breakables") and parent not in damaged_entities:
				if parent.has_method("take_damage"):
					parent.take_damage(damage)
					damaged_entities.append(parent)
			
			# Check for enemy parent
			elif parent.is_in_group("Enemy") and parent not in damaged_entities:
				hit_enemy(parent, damage, knockback_horizontal, knockback_vertical)
				damaged_entities.append(parent)
	
	
	# Disable hitbox after attack
	attack_hitbox.monitoring = false
	
	# Visual feedback duration
	await player.get_tree().create_timer(0.2).timeout
	is_attacking = false

func update_hitbox_position(attack_range: float):
	"""Updates the hitbox position to be in front of where the player is facing."""
	if not attack_hitbox:
		return
	
	# Get player's forward direction
	var forward_direction = -player.global_transform.basis.z.normalized()
	
	# Calculate position in front of player
	var offset = forward_direction * attack_range
	offset.y = 0.5  # Height offset
	
	# Set the hitbox position
	attack_hitbox.position = offset
	

func hit_enemy(enemy: Node, damage: int, knockback_horizontal: float, knockback_vertical: float):
	"""Deals damage and applies knockback to an enemy."""
	if not enemy or not is_instance_valid(enemy):
		return
	
	
	# Calculate knockback direction (from player to enemy)
	var knockback_direction = (enemy.global_position - player.global_position).normalized()
	knockback_direction.y = 0  # Keep horizontal component only
	
	# Create knockback velocity with both horizontal and vertical components
	var knockback_velocity = knockback_direction * knockback_horizontal
	knockback_velocity.y = knockback_vertical  # Add upward force
	
	
	# Apply damage with knockback
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, knockback_velocity)
	else:
		print("✗ Enemy doesn't have take_damage method!")

func get_is_attacking() -> bool:
	"""Returns whether the player is currently attacking"""
	return is_attacking
