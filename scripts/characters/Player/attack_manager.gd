extends Node
class_name AttackManager

# Attack configuration
@export var attack_damage: int = 1
@export var attack_range: float = 5
@export var attack_radius: float = 15
@export var attack_cooldown: float = 0.5
@export var knockback_force: float = 500.0

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
	print("AttackManager: Ready! Press attack button to attack.")

func setup_attack_hitbox():
	"""
	Creates an Area3D hitbox in front of the player for detecting enemies.
	
	KEY FIX: The CollisionShape needs to be at (0,0,0) relative to the Area3D,
	and we move the entire Area3D instead of just the shape!
	"""
	attack_hitbox = Area3D.new()
	attack_hitbox.name = "AttackHitbox"
	
	# Set collision layers so enemy HitBox can detect it
	attack_hitbox.collision_layer = 1   # Exists on layer 1
	attack_hitbox.collision_mask = 1    # Detect things on layer 1
	attack_hitbox.monitoring = false     # Start disabled (we enable during attack)
	attack_hitbox.monitorable = true    # Must be true so enemy can detect it!
	
	player.add_child(attack_hitbox)
	
	# Create collision shape for the hitbox
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = attack_radius
	collision_shape.shape = sphere_shape
	
	# CRITICAL FIX: CollisionShape position should be at origin (0,0,0)
	# We'll move the entire Area3D instead during the attack
	collision_shape.position = Vector3(0, 0, 0)
	attack_hitbox.add_child(collision_shape)
	
	print("Attack hitbox setup complete!")
	print("AttackHitbox collision_layer: ", attack_hitbox.collision_layer)
	print("AttackHitbox collision_mask: ", attack_hitbox.collision_mask)
	print("AttackHitbox monitoring: ", attack_hitbox.monitoring)
	print("AttackHitbox monitorable: ", attack_hitbox.monitorable)

func _physics_process(delta: float):
	# Update attack cooldown timer
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0:
			can_attack = true
	
	# Check for attack input
	check_attack_input()

func check_attack_input():
	"""
	Checks if the player pressed the attack button and initiates attack.
	"""
	# Debug: Print when attack button is pressed
	if Input.is_action_just_pressed("attack"):
		print("Attack button pressed! can_attack=", can_attack, " is_dead=", player.is_dead if player else "no player")
	
	# Check if attack button is pressed and we can attack
	if Input.is_action_just_pressed("attack") and can_attack and not player.is_dead:
		perform_attack()

func perform_attack():
	"""
	Executes the attack - enables hitbox, checks for enemies, deals damage.
	
	TEACHING: Avoiding Multiple Hits on Same Enemy
	- We track enemies we've already hit in this attack
	- This prevents hitting the same enemy through different collision areas
	- Each enemy only takes damage once per attack
	"""
	print("=== PERFORMING ATTACK ===")
	
	# Start cooldown
	can_attack = false
	attack_timer = attack_cooldown
	is_attacking = true
	
	# Position hitbox in front of player's current facing direction
	update_hitbox_position()
	
	# Enable hitbox detection
	attack_hitbox.monitoring = true
	print("AttackHitbox enabled at position: ", attack_hitbox.global_position)
	
	# Wait one physics frame for Area3D to detect overlaps
	await player.get_tree().physics_frame
	
	# Get all overlapping bodies and areas
	var hit_bodies = attack_hitbox.get_overlapping_bodies()
	var hit_areas = attack_hitbox.get_overlapping_areas()
	
	print("Hit bodies: ", hit_bodies.size())
	print("Hit areas: ", hit_areas.size())
	
	# Track which enemies we've already damaged to prevent multi-hits
	var damaged_enemies: Array = []
	
	# Process body hits first (enemies themselves)
	for body in hit_bodies:
		print("Checking body: ", body.name, " groups: ", body.get_groups())
		if body.is_in_group("Enemy") and body not in damaged_enemies:
			print("✓ Found enemy body!")
			hit_enemy(body)
			damaged_enemies.append(body)
	
	# Process area hits (enemy hitboxes)
	for area in hit_areas:
		print("Checking area: ", area.name, " groups: ", area.get_groups())
		
		# Check if the area's parent is an enemy
		if area.get_parent() and area.get_parent().is_in_group("Enemy"):
			var enemy_parent = area.get_parent()
			if enemy_parent not in damaged_enemies:
				print("✓ Found enemy via parent area!")
				hit_enemy(enemy_parent)
				damaged_enemies.append(enemy_parent)
	
	print("Total enemies damaged: ", damaged_enemies.size())
	
	# Disable hitbox after attack
	attack_hitbox.monitoring = false
	
	# Visual feedback duration
	await player.get_tree().create_timer(0.2).timeout
	is_attacking = false

func update_hitbox_position():
	"""
	Updates the hitbox position to be in front of where the player is facing.
	
	CRITICAL FIX: Use player's rotation to position attack in front
	- We need to account for where the player is FACING
	- Simply using local Z doesn't work when player rotates
	- We calculate forward direction from player's basis
	"""
	if not attack_hitbox:
		return
	
	# Get player's forward direction (negative Z in their local space)
	var forward_direction = -player.global_transform.basis.z.normalized()
	
	# Calculate position in front of player in world space
	var offset = forward_direction * attack_range
	offset.y = 0.5  # Height offset
	
	# Set the hitbox position in local space
	# Since it's a child, we convert world offset to local
	attack_hitbox.position = offset
	
	print("Player rotation: ", player.rotation.y)
	print("Forward direction: ", forward_direction)
	print("AttackHitbox local pos: ", attack_hitbox.position)
	print("AttackHitbox global pos: ", attack_hitbox.global_position)
	print("Player global pos: ", player.global_position)

func hit_enemy(enemy: Node):
	"""
	Deals damage and applies knockback to an enemy.
	"""
	if not enemy or not is_instance_valid(enemy):
		return
	
	print("=== HIT ENEMY ===")
	print("Enemy: ", enemy.name)
	print("Enemy has take_damage: ", enemy.has_method("take_damage"))
	
	# Calculate knockback direction (from player to enemy)
	var knockback_direction = (enemy.global_position - player.global_position).normalized()
	knockback_direction.y = 0  # Keep knockback horizontal
	
	# Apply knockback force
	var knockback_velocity = knockback_direction * knockback_force
	
	print("Knockback direction: ", knockback_direction)
	print("Knockback velocity: ", knockback_velocity)
	
	# Try to damage the enemy
	if enemy.has_method("take_damage"):
		enemy.take_damage(attack_damage, knockback_velocity)
		print("✓ Damage applied!")
	else:
		print("✗ Enemy doesn't have take_damage method!")

func get_is_attacking() -> bool:
	"""Returns whether the player is currently attacking"""
	return is_attacking
