extends CharacterBody3D
class_name Enemy

# Health system
@export var max_health: int = 3
@export var current_health: int = 3

# Behavior parameters
@export var detection_range: float = 15.0
@export var chase_speed: float = 8.0
@export var wander_speed: float = 3.0
@export var damage_to_player: int = 1
@export var bounce_feedback: int = 9
var can_chase := true

# Physics
var gravity: float = 9.8

# Damage cooldown
var damage_cooldown: float = 0.0
var damage_cooldown_time: float = 0.5

# State machine
var state_machine: EnemyStateMachine
var player: CharacterBody3D = null

# Animation/Visual
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hit_box: Area3D = $HitBox
var initial_color: Color

func _ready():
	# Add enemy to the "Enemy" group so AttackManager can find it
	add_to_group("Enemy")
	print("Enemy added to 'Enemy' group")
	
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
	
	if mesh and mesh.material_override:
		initial_color = mesh.material_override.albedo_color
	
	# CRITICAL FIX: Connect the area_entered signal for detecting attack hitboxes
	if hit_box:
		# Add HitBox to Enemy group as well (backup detection method)
		hit_box.add_to_group("Enemy")
		
		# Connect area signal
		if not hit_box.area_entered.is_connected(_on_hit_box_area_entered):
			hit_box.area_entered.connect(_on_hit_box_area_entered)
			print("Enemy HitBox area_entered signal connected!")
		
		# Print collision layer info for debugging
		print("Enemy collision_layer: ", collision_layer)
		print("Enemy collision_mask: ", collision_mask)
		print("HitBox collision_layer: ", hit_box.collision_layer)
		print("HitBox collision_mask: ", hit_box.collision_mask)
		print("HitBox monitoring: ", hit_box.monitoring)
		print("HitBox monitorable: ", hit_box.monitorable)
	else:
		print("ERROR: HitBox not found on enemy!")
	
	state_machine = EnemyStateMachine.new()
	state_machine.enemy = self
	add_child(state_machine)
	state_machine.initialize_states()

func damage_player(player_body: Node3D):
	"""Apply damage and knockback to the player"""
	if not player_body.has_method("take_damage"):
		return
	
	var knockback_direction = (player_body.global_position - global_position).normalized()
	knockback_direction.y = 0
	
	player_body.take_damage(damage_to_player, knockback_direction)

func _on_hit_box_body_entered(body: Node) -> void:
	"""
	This detects when the PLAYER'S BODY enters the enemy's hitbox
	Used for damaging the player when they touch the enemy
	"""
	if body.is_in_group("Player") and can_chase:
		can_chase = false
		damage_player(body)
		state_machine.change_state("aiidlestate")
		await get_tree().create_timer(1.3).timeout
		can_chase = true

func _on_hit_box_area_entered(area: Area3D) -> void:
	"""
	NEW FUNCTION: This detects when an AREA3D enters the enemy's hitbox
	This is crucial for detecting the AttackManager's attack hitbox!
	"""
	print("=== ENEMY HITBOX AREA ENTERED ===")
	print("Area name: ", area.name)
	print("Area parent: ", area.get_parent().name if area.get_parent() else "NO PARENT")
	print("Area groups: ", area.get_groups())
	
	# Check if this is the player's attack hitbox
	if area.name == "AttackHitbox":
		print("✓ Detected AttackHitbox!")
		
		# Get the player (attack hitbox's grandparent)
		var attack_manager = area.get_parent()
		if attack_manager and attack_manager.name == "AttackManager":
			print("✓ Found AttackManager")
			var attacking_player = attack_manager.get_parent()
			if attacking_player and attacking_player.is_in_group("Player"):
				print("✓ Found Player - APPLYING DAMAGE!")
				
				# Calculate knockback direction (away from player)
				var knockback_direction = (global_position - attacking_player.global_position).normalized()
				knockback_direction.y = 0.2
				
				# Apply damage with knockback
				var knockback_velocity = knockback_direction * 10.0
				take_damage(1, knockback_velocity)
			else:
				print("✗ Could not find Player or Player not in group")
		else:
			print("✗ Could not find AttackManager")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	if state_machine:
		state_machine.update(delta)
	
	move_and_slide()

func take_damage(amount: int, knockback_velocity: Vector3 = Vector3.ZERO):
	"""
	Reduce health and show hit feedback
	Now accepts optional knockback parameter for attack-based damage
	"""
	print("=== TAKE_DAMAGE CALLED ===")
	print("Damage amount: ", amount)
	print("Knockback: ", knockback_velocity)
	print("Current cooldown: ", damage_cooldown)
	
	# Ignore damage if still in cooldown
	if damage_cooldown > 0:
		print("✗ DAMAGE BLOCKED - Still in cooldown!")
		return
	
	print("✓ DAMAGE ACCEPTED!")
	print("Health: ", current_health, " -> ", current_health - amount)
	
	current_health -= amount
	damage_cooldown = damage_cooldown_time
	
	# Visual feedback when hit
	flash_color()
	
	# Apply knockback if provided
	if knockback_velocity.length() > 0:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		velocity.y = knockback_velocity.y
		print("Knockback applied: ", velocity)
	
	# Transition to knockback state
	if state_machine:
		state_machine.change_state("aiknockbackstate")
	
	# Check for death
	if current_health <= 0:
		die()

func die():
	"""Enemy dies and is removed from scene"""
	print("=== ENEMY DIED ===")
	queue_free()

func flash_color():
	"""Flash white when hit"""
	if mesh and mesh.material_override:
		var material = mesh.material_override.duplicate()
		material.albedo_color = Color.WHITE
		mesh.material_override = material
		
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			material.albedo_color = initial_color

func _on_head_hurtbox_body_entered(body: Node3D):
	"""Handle player jumping on enemy head"""
	if body.is_in_group("Player"):
		var player_velocity_y = body.velocity.y
		var is_falling_or_jumping = player_velocity_y < 0 or player_velocity_y == 0
		var is_above_enemy = body.global_position.y > global_position.y
		
		if is_above_enemy and is_falling_or_jumping:
			print("=== HEAD STOMP DAMAGE ===")
			take_damage(1)
			body.velocity.y = bounce_feedback


# ============================================
# BASE STATE CLASS
# ============================================

class EnemyState extends Node:
	var enemy: Enemy
	
	func enter():
		pass
	
	func exit():
		pass
	
	func update(delta: float):
		pass


# ============================================
# AI IDLE STATE
# ============================================

class AIIdleState extends EnemyState:
	var wander_timer: float = 0.0
	var wander_interval: float = 2.0
	var current_direction: Vector3 = Vector3.ZERO
	
	func enter():
		print("Enemy entering AI IDLE state")
		wander_timer = 0.0
		pick_wander_direction()
	
	func pick_wander_direction():
		var random_angle = randf() * TAU
		current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()
	
	func update(delta: float):
		if enemy.player and enemy.player.is_inside_tree() and enemy.can_chase:
			var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
			if distance_to_player < enemy.detection_range:
				enemy.state_machine.change_state("aichasestate")
				return
		
		enemy.velocity.x = current_direction.x * enemy.wander_speed
		enemy.velocity.z = current_direction.z * enemy.wander_speed
		
		wander_timer += delta
		if wander_timer >= wander_interval:
			pick_wander_direction()
			wander_timer = 0.0


# ============================================
# AI CHASE STATE
# ============================================

class AIChaseState extends EnemyState:
	var chase_timeout: float = 0.0
	var max_chase_time: float = 4.0
	
	func enter():
		print("Enemy entering AI CHASE state")
		chase_timeout = 0.0
	
	func update(delta: float):
		if not enemy.player or not enemy.player.is_inside_tree():
			enemy.state_machine.change_state("aiidlestate")
			return
		
		var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
		
		if distance_to_player > enemy.detection_range * 1.5:
			chase_timeout += delta
			if chase_timeout > max_chase_time:
				enemy.state_machine.change_state("aiidlestate")
				return
		else:
			chase_timeout = 0.0
		
		var direction_to_player = (enemy.player.global_position - enemy.global_position).normalized()
		
		enemy.velocity.x = direction_to_player.x * enemy.chase_speed
		enemy.velocity.z = direction_to_player.z * enemy.chase_speed
		
		var target_rotation = atan2(-direction_to_player.x, -direction_to_player.z)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target_rotation, delta * 5.0)


# ============================================
# AI KNOCKBACK STATE
# ============================================

class AIKnockbackState extends EnemyState:
	var knockback_velocity: Vector3 = Vector3.ZERO
	var knockback_duration: float = 0.15
	var knockback_timer: float = 0.0
	
	func enter():
		print("Enemy entering AI KNOCKBACK state")
		knockback_timer = 0.0
		knockback_velocity = enemy.global_transform.basis.z * -3.0
		knockback_velocity.y = 2.0
	
	func update(delta: float):
		knockback_timer += delta
		
		enemy.velocity.x = knockback_velocity.x
		enemy.velocity.z = knockback_velocity.z
		enemy.velocity.y = knockback_velocity.y
		
		var decay_factor = 1.0 - (knockback_timer / knockback_duration)
		knockback_velocity *= decay_factor
		
		if knockback_timer >= knockback_duration:
			enemy.state_machine.change_state("aiidlestate")


# ============================================
# ENEMY STATE MACHINE
# ============================================

class EnemyStateMachine extends Node:
	var enemy: Enemy
	var current_state: EnemyState
	var states: Dictionary = {}
	
	func initialize_states():
		var idle_state = AIIdleState.new()
		states["aiidlestate"] = idle_state
		
		var chase_state = AIChaseState.new()
		states["aichasestate"] = chase_state
		
		var knockback_state = AIKnockbackState.new()
		states["aiknockbackstate"] = knockback_state
		
		change_state("aiidlestate")
	
	func change_state(state_name: String):
		if current_state:
			current_state.exit()
		
		current_state = states.get(state_name.to_lower())
		if current_state:
			current_state.enemy = enemy
			current_state.enter()
	
	func update(delta: float):
		if current_state:
			current_state.update(delta)
