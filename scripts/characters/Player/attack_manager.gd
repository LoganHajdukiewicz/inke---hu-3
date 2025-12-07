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

@export_group("Heavy Attack")
@export var heavy_attack_damage: int = 3
@export var heavy_attack_range: float = 0.1
@export var heavy_attack_radius: float = 10
@export var heavy_attack_cooldown: float = 1.0
@export var heavy_knockback_force: float = 60.0
@export var heavy_knockback_upward: float = 20.0

# Attack state
var can_attack: bool = true
var attack_timer: float = 0.0
var attack_hitbox: Area3D
var is_attacking: bool = false

# References
var player: CharacterBody3D
var state_machine: StateMachine

func _ready():
	print("AttackManager: Initializing...")
	player = get_parent() as CharacterBody3D
	state_machine = player.get_node("StateMachine") if player.has_node("StateMachine") else null
	setup_attack_hitbox()
	print("AttackManager: Ready! Light attack: attack button, Heavy attack: heavy_attack button")

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
	
	print("Attack hitbox setup complete!")
	print("  collision_layer: ", attack_hitbox.collision_layer)
	print("  collision_mask: ", attack_hitbox.collision_mask)

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
		print("Attack button pressed!")
		print("Shift held: ", Input.is_key_pressed(KEY_SHIFT))
		print("Can attack: ", can_attack)
		print("Is dead: ", player.is_dead if player else "no player")
	
	if Input.is_action_just_pressed("heavy_attack"):
		print("Heavy attack button pressed!")
	
	if not can_attack or player.is_dead:
		return
	
	# Heavy attack (higher priority) - Check both heavy_attack action and shift+attack
	var heavy_pressed = Input.is_action_just_pressed("heavy_attack") or \
						(Input.is_action_just_pressed("attack") and Input.is_key_pressed(KEY_SHIFT))
	
	if heavy_pressed:
		perform_attack(true)  # true = heavy attack
		print("=== HEAVY ATTACK TRIGGERED ===")
	# Light attack - only if shift is NOT held
	elif Input.is_action_just_pressed("attack") and not Input.is_key_pressed(KEY_SHIFT):
		perform_attack(false)  # false = light attack
		print("=== LIGHT ATTACK TRIGGERED ===")

func perform_attack(is_heavy: bool):
	"""Executes the attack with specified parameters."""
	print("=== PERFORMING ", "HEAVY" if is_heavy else "LIGHT", " ATTACK ===")
	
	# Get attack parameters based on type
	var damage = heavy_attack_damage if is_heavy else light_attack_damage
	var attack_range = heavy_attack_range if is_heavy else light_attack_range
	var attack_radius = heavy_attack_radius if is_heavy else light_attack_radius
	var cooldown = heavy_attack_cooldown if is_heavy else light_attack_cooldown
	var knockback_horizontal = heavy_knockback_force if is_heavy else light_knockback_force
	var knockback_vertical = heavy_knockback_upward if is_heavy else light_knockback_upward
	
	print("Attack params - Damage: ", damage, " Knockback H: ", knockback_horizontal, " V: ", knockback_vertical)
	
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
	
	print("Hit bodies: ", hit_bodies.size(), " Hit areas: ", hit_areas.size())
	
	# DEBUG: Print what we hit
	for body in hit_bodies:
		print("  Body: ", body.name, " Groups: ", body.get_groups(), " Is Enemy: ", body.is_in_group("Enemy"))
	for area in hit_areas:
		print("  Area: ", area.name, " Groups: ", area.get_groups())
		if area.get_parent():
			print("    Parent: ", area.get_parent().name, " Groups: ", area.get_parent().get_groups())
	
	# Track which enemies we've already damaged
	var damaged_enemies: Array = []
	
	# Process body hits
	for body in hit_bodies:
		print("Checking body: ", body.name, " is_in_group(Enemy): ", body.is_in_group("Enemy"))
		if body.is_in_group("Enemy") and body not in damaged_enemies:
			print("  -> Hitting enemy body!")
			hit_enemy(body, damage, knockback_horizontal, knockback_vertical)
			damaged_enemies.append(body)
	
	# Process area hits
	for area in hit_areas:
		print("Checking area: ", area.name)
		if area.get_parent():
			print("  Parent: ", area.get_parent().name, " is_in_group(Enemy): ", area.get_parent().is_in_group("Enemy"))
			if area.get_parent().is_in_group("Enemy"):
				var enemy_parent = area.get_parent()
				if enemy_parent not in damaged_enemies:
					print("  -> Hitting enemy via area parent!")
					hit_enemy(enemy_parent, damage, knockback_horizontal, knockback_vertical)
					damaged_enemies.append(enemy_parent)
	
	print("Total enemies damaged: ", damaged_enemies.size())
	
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
	
	print("Hitbox positioned at: ", attack_hitbox.position)
	print("Hitbox global position: ", attack_hitbox.global_position)
	print("Player global position: ", player.global_position)

func hit_enemy(enemy: Node, damage: int, knockback_horizontal: float, knockback_vertical: float):
	"""Deals damage and applies knockback to an enemy."""
	if not enemy or not is_instance_valid(enemy):
		return
	
	print("=== HIT ENEMY ===")
	print("Enemy: ", enemy.name)
	print("Damage: ", damage)
	print("Knockback H: ", knockback_horizontal, " V: ", knockback_vertical)
	
	# Calculate knockback direction (from player to enemy)
	var knockback_direction = (enemy.global_position - player.global_position).normalized()
	knockback_direction.y = 0  # Keep horizontal component only
	
	# Create knockback velocity with both horizontal and vertical components
	var knockback_velocity = knockback_direction * knockback_horizontal
	knockback_velocity.y = knockback_vertical  # Add upward force
	
	print("Final knockback velocity: ", knockback_velocity)
	
	# Apply damage with knockback
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, knockback_velocity)
		print("✓ Damage and knockback applied!")
	else:
		print("✗ Enemy doesn't have take_damage method!")

func get_is_attacking() -> bool:
	"""Returns whether the player is currently attacking"""
	return is_attacking
