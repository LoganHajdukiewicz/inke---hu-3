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
var being_stomped := false  # NEW: Flag to prevent damage during stomp

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
	add_to_group("Enemy")
	print("Enemy added to 'Enemy' group")
	
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
	
	if mesh and mesh.material_override:
		initial_color = mesh.material_override.albedo_color
	
	if hit_box:
		hit_box.add_to_group("Enemy")
		
		# Connect body_entered signal
		if not hit_box.body_entered.is_connected(_on_hit_box_body_entered):
			hit_box.body_entered.connect(_on_hit_box_body_entered)
			print("Enemy HitBox body_entered signal connected!")
		
		if not hit_box.area_entered.is_connected(_on_hit_box_area_entered):
			hit_box.area_entered.connect(_on_hit_box_area_entered)
			print("Enemy HitBox area_entered signal connected!")
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
	"""This detects when the PLAYER'S BODY enters the enemy's hitbox"""
	if not body.is_in_group("Player"):
		return
	
	# CRITICAL: Check if being stomped - if so, don't damage player
	if being_stomped:
		print("HitBox collision BLOCKED - Being stomped!")
		return
	
	if not can_chase:
		print("HitBox collision BLOCKED - Can't chase")
		return
	
	# Check if player is above enemy and falling (head stomp scenario)
	var player_y = body.global_position.y
	var enemy_head_y = global_position.y + 0.8  # Approximate head height
	var is_above_head = player_y > enemy_head_y
	
	var player_velocity_y = 0.0
	if "velocity" in body:
		player_velocity_y = body.velocity.y
	var is_falling = player_velocity_y < 0
	
	print("HitBox collision - Player Y: ", player_y, " Enemy head Y: ", enemy_head_y, 
		  " Above head: ", is_above_head, " Falling: ", is_falling)
	
	# If player is doing a head stomp, don't damage them here
	if is_above_head and is_falling:
		print("HEAD STOMP - Not damaging player")
		return
	
	# Normal damage scenario
	print("NORMAL COLLISION - Damaging player")
	can_chase = false
	damage_player(body)
	state_machine.change_state("aiidlestate")
	await get_tree().create_timer(1.3).timeout
	if is_instance_valid(self):
		can_chase = true

func _on_hit_box_area_entered(area: Area3D) -> void:
	"""This detects when an AREA3D enters the enemy's hitbox"""
	if area.name == "AttackHitbox":
		var attack_manager = area.get_parent()
		if attack_manager and attack_manager.name == "AttackManager":
			var attacking_player = attack_manager.get_parent()
			if attacking_player and attacking_player.is_in_group("Player"):
				# Calculate knockback direction
				var knockback_direction = (global_position - attacking_player.global_position).normalized()
				knockback_direction.y = 0.2  # Add slight upward component
				
				# Note: The actual knockback is applied in AttackManager.hit_enemy()
				# This is just a fallback in case the signal path is used

func _physics_process(delta: float) -> void:
	# Get current state name for debugging
	var current_state_name = ""
	if state_machine and state_machine.current_state:
		current_state_name = state_machine.current_state.get_script().get_global_name()
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Only reset Y velocity if not in knockback state
		if current_state_name != "AIKnockbackState":
			velocity.y = 0
	
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	if state_machine:
		state_machine.update(delta)
	
	# Debug knockback
	if current_state_name == "AIKnockbackState":
		print("Enemy in knockback - velocity: ", velocity, " on_floor: ", is_on_floor())
	
	move_and_slide()

func take_damage(amount: int, knockback_velocity: Vector3 = Vector3.ZERO):
	"""Reduce health and apply knockback"""
	print("=== TAKE_DAMAGE CALLED ===")
	print("Damage amount: ", amount)
	print("Knockback velocity: ", knockback_velocity)
	print("Knockback Y component: ", knockback_velocity.y)
	
	# Ignore damage if still in cooldown
	if damage_cooldown > 0:
		print("✗ DAMAGE BLOCKED - Still in cooldown!")
		return
	
	print("✓ DAMAGE ACCEPTED!")
	print("Health: ", current_health, " -> ", current_health - amount)
	
	current_health -= amount
	damage_cooldown = damage_cooldown_time
	
	# Visual feedback
	flash_color()
	
	# CRITICAL: Set the knockback BEFORE changing state
	if state_machine:
		var knockback_state = state_machine.states.get("aiknockbackstate") as AIKnockbackState
		if knockback_state:
			print("Setting knockback on state: ", knockback_velocity)
			knockback_state.set_knockback(knockback_velocity)
		else:
			print("ERROR: Could not get knockback state!")
		
		print("Changing to knockback state...")
		state_machine.change_state("aiknockbackstate")
		
		# Double-check the velocity was applied
		print("Enemy velocity after state change: ", velocity)
	
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
	if not body.is_in_group("Player"):
		return
	
	var player_velocity_y = body.velocity.y
	var is_falling_or_jumping = player_velocity_y <= 0
	var is_above_enemy = body.global_position.y > global_position.y
	
	print("HeadHurtbox hit - Player Y vel: ", player_velocity_y, " Above: ", is_above_enemy, 
		  " Falling: ", is_falling_or_jumping)
	
	if is_above_enemy and is_falling_or_jumping:
		print("=== HEAD STOMP DAMAGE ===")
		
		# CRITICAL: Set flag to prevent HitBox from damaging player
		being_stomped = true
		
		# Make player invulnerable briefly to prevent damage
		if "is_invulnerable" in body and "invulnerability_timer" in body:
			body.is_invulnerable = true
			body.invulnerability_timer = 0.5
		
		# Give player bounce FIRST
		body.velocity.y = bounce_feedback
		
		# Prevent enemy from damaging player
		can_chase = false
		
		# Damage the enemy
		take_damage(1)
		
		# Wait before re-enabling damage
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(self):
			being_stomped = false
			can_chase = true
			print("Enemy can chase again")


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
# AI KNOCKBACK STATE - FIXED VERSION
# ============================================

class AIKnockbackState extends EnemyState:
	var knockback_velocity: Vector3 = Vector3.ZERO
	var knockback_duration: float = 0.8
	var knockback_timer: float = 0.0
	var initial_upward_velocity: float = 0.0
	var min_air_time: float = 0.1  # Minimum time before we check for landing
	
	func set_knockback(new_knockback: Vector3):
		"""Set the knockback velocity from external source"""
		knockback_velocity = new_knockback
		initial_upward_velocity = new_knockback.y
		print("Knockback set to: ", knockback_velocity)
		print("Initial upward velocity: ", initial_upward_velocity)
	
	func enter():
		print("Enemy entering AI KNOCKBACK state")
		print("Initial knockback velocity: ", knockback_velocity)
		knockback_timer = 0.0
		
		# If no knockback was set externally, use default
		if knockback_velocity.length() < 0.1:
			knockback_velocity = enemy.global_transform.basis.z * -8.0
			knockback_velocity.y = 3.0
			initial_upward_velocity = 3.0
			print("Using default knockback: ", knockback_velocity)
		
		# Apply initial knockback immediately
		enemy.velocity = knockback_velocity
		print("Applied velocity to enemy: ", enemy.velocity)
	
	func update(delta: float):
		knockback_timer += delta
		
		# Use normal gravity from the enemy (9.8)
		enemy.velocity.y -= enemy.gravity * delta
		
		# Gradually reduce horizontal knockback (air resistance)
		var horizontal_decay = 0.98  # Very slight decay
		enemy.velocity.x *= horizontal_decay
		enemy.velocity.z *= horizontal_decay
		
		# Only print every 10 frames to reduce spam
		if int(knockback_timer * 60) % 10 == 0:
			print("Knockback timer: ", snappedf(knockback_timer, 0.01), 
				  " Y velocity: ", snappedf(enemy.velocity.y, 0.1),
				  " On floor: ", enemy.is_on_floor())
		
		# CRITICAL FIX: Only check for landing AFTER min_air_time has passed
		# This gives the enemy time to actually leave the ground
		if knockback_timer >= min_air_time:
			if enemy.is_on_floor() and enemy.velocity.y <= 0:
				print("Knockback complete - landed on ground")
				enemy.state_machine.change_state("aiidlestate")
		
		# Safety timeout
		if knockback_timer >= knockback_duration * 2.0:
			print("Knockback timeout - forcing end")
			enemy.state_machine.change_state("aiidlestate")
	
	func exit():
		# Reset knockback velocity for next time
		knockback_velocity = Vector3.ZERO
		initial_upward_velocity = 0.0


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
