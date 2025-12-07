extends Node
class_name AttackManager

# Attack configuration
@export var attack_damage: int = 1
@export var attack_range: float = 1.5
@export var attack_radius: float = 1.0
@export var attack_cooldown: float = 0.5
@export var knockback_force: float = 10.0

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
	
	WHY THIS APPROACH:
	- Area3D allows us to detect overlapping bodies/areas without physics collisions
	- We position it in front of the player's facing direction
	- We enable/disable it only during attacks to avoid constant detection
	"""
	attack_hitbox = Area3D.new()
	attack_hitbox.name = "AttackHitbox"
	attack_hitbox.collision_layer = 0  # Don't exist on any layer
	attack_hitbox.collision_mask = 1   # Detect things on layer 1 (default layer)
	attack_hitbox.monitoring = false    # Start disabled
	attack_hitbox.monitorable = false
	player.add_child(attack_hitbox)
	
	# Create collision shape for the hitbox
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = attack_radius
	collision_shape.shape = sphere_shape
	
	# Position the hitbox in front of the player
	collision_shape.position = Vector3(0, 0.5, -attack_range)
	attack_hitbox.add_child(collision_shape)
	
	print("Attack hitbox setup complete!")

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
	
	WHY CHECK HERE:
	- Centralized attack logic in one place
	- Easy to add conditions (like "can only attack on ground")
	- Simple to manage attack cooldown
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
	
	THE ATTACK PROCESS:
	1. Start attack cooldown (prevent spam)
	2. Enable the hitbox temporarily
	3. Position hitbox in front of player's facing direction
	4. Check for overlapping enemies
	5. Deal damage and knockback to each enemy
	6. Disable hitbox after a brief moment
	"""
	print("Performing attack!")
	
	# Start cooldown
	can_attack = false
	attack_timer = attack_cooldown
	is_attacking = true
	
	# Position hitbox in front of player's current facing direction
	update_hitbox_position()
	
	# Enable hitbox detection
	attack_hitbox.monitoring = true
	
	# Wait one physics frame for Area3D to detect overlaps
	await player.get_tree().physics_frame
	
	# Get all overlapping bodies
	var hit_bodies = attack_hitbox.get_overlapping_bodies()
	var hit_areas = attack_hitbox.get_overlapping_areas()
	
	# Process hits
	for body in hit_bodies:
		if body.is_in_group("Enemy"):
			hit_enemy(body)
	
	for area in hit_areas:
		if area.is_in_group("Enemy"):
			hit_enemy(area)
	
	# Disable hitbox after attack
	attack_hitbox.monitoring = false
	
	# Visual feedback duration
	await player.get_tree().create_timer(0.2).timeout
	is_attacking = false

func update_hitbox_position():
	"""
	Updates the hitbox position to be in front of where the player is facing.
	
	WHY UPDATE POSITION:
	- Player can rotate, so we need to update where "in front" is
	- Uses player's basis to get forward direction
	- Negative Z is forward in Godot's coordinate system
	"""
	if not attack_hitbox:
		return
	
	# Get player's forward direction (negative Z in local space)
	var forward_direction = -player.global_transform.basis.z
	
	# Position hitbox in front of player
	var hitbox_position = player.global_position + forward_direction * attack_range
	hitbox_position.y = player.global_position.y + 0.5  # Chest height
	
	attack_hitbox.global_position = hitbox_position

func hit_enemy(enemy: Node):
	"""
	Deals damage and applies knockback to an enemy.
	
	HOW IT WORKS:
	1. Check if enemy has a take_damage method (our Enemy class should have this)
	2. Calculate knockback direction (away from player)
	3. Call the enemy's take_damage method with damage and knockback
	
	WHY THIS DESIGN:
	- Enemies handle their own damage response (separation of concerns)
	- We just tell them "you got hit with X damage from Y direction"
	- This allows different enemy types to respond differently to damage
	"""
	if not enemy or not is_instance_valid(enemy):
		return
	
	print("Hit enemy: ", enemy.name)
	
	# Calculate knockback direction (from player to enemy)
	var knockback_direction = (enemy.global_position - player.global_position).normalized()
	knockback_direction.y = 0  # Keep knockback horizontal
	
	# Apply knockback force
	var knockback_velocity = knockback_direction * knockback_force
	
	# Try to damage the enemy
	if enemy.has_method("take_damage"):
		# Enemy class will handle damage, knockback, and death
		enemy.take_damage(attack_damage, knockback_velocity)
	else:
		print("Warning: Enemy doesn't have take_damage method!")

func get_is_attacking() -> bool:
	"""Returns whether the player is currently attacking"""
	return is_attacking
